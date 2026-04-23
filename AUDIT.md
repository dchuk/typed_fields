# TypedFields Adversarial Audit Report

**Date:** 2026-04-07
**Scope:** Full codebase analysis covering Rails conventions, bugs/logic errors, performance, security, and API design.

---

## CRITICAL — Must Fix

### 1. DecimalArray silently loses precision

**`app/models/typed_fields/field/types.rb:166`**

`cast_value` converts to `.to_f` instead of keeping `BigDecimal`. A value like `"0.123456789012345"` loses trailing digits.

```ruby
# Current (broken)
Array(raw).filter_map { |v| BigDecimal(v.to_s, exception: false)&.to_f }

# Fix
Array(raw).filter_map { |v| BigDecimal(v.to_s, exception: false) }
```

**Impact:** Silent data loss on precision-sensitive decimal values.

---

### 2. Silent data mutation in array casting

**`app/models/typed_fields/field/types.rb:150-153`**

`filter_map` silently drops elements that fail to parse. Input `[1, "abc", 3]` becomes `[1, 3]` with no validation error. Users won't know data was discarded.

```ruby
# Example
field = create(:integer_array_field)
value.value = [10, "invalid", 20]
value.value  # => [10, 20] — silently dropped "invalid"
value.valid?  # => true — no validation error
```

**Impact:** Data silently modified without user awareness. Should either reject invalid elements with a validation error or document the behavior explicitly.

---

### 3. Invalid input indistinguishable from nil

**`app/models/typed_fields/field/types.rb` (Integer, Date, DateTime)**

Casting `"not_a_number"` returns `nil`. A required field then fails with "can't be blank" rather than "is invalid". The system can't tell "user left it empty" from "user submitted garbage."

```ruby
field = create(:integer_field, required: true)
value.value = "not_a_number"
value.valid?  # => false, but error says "can't be blank" instead of "is not a valid integer"
```

**Impact:** Confusing error messages for end users. Should track whether nil came from blank input vs. failed casting.

---

### 4. Empty array bypasses required validation

**`app/models/typed_fields/field/types.rb:150-153`**

`IntegerArray.cast_value([])` returns `[]`, which is truthy, so `required: true` passes. A required array field can be saved with zero elements.

```ruby
field = create(:integer_array_field, required: true)
value.value = []
value.save!  # => succeeds — should fail
```

**Impact:** Required constraint on array fields is ineffective against empty arrays.

---

### 5. ReDoS via user-supplied regex patterns

**`app/models/typed_fields/value.rb:115`**

`Regexp.new(opts[:pattern]).match?(val.to_s)` compiles arbitrary regex at validation time. A malicious pattern like `(a+)+b` causes catastrophic backtracking.

```ruby
# Current (vulnerable)
return if Regexp.new(opts[:pattern]).match?(val.to_s)
```

**Impact:** Denial of service via CPU exhaustion during validation. Pattern syntax should be validated and timeout-guarded at field creation time, not at value validation time.

**Remediation:**
- Validate regex syntax when field is created/updated
- Add `Timeout.timeout` around regex matching
- Consider limiting pattern length or complexity

---

### 6. Silent validation bypass on malformed field config

**`app/models/typed_fields/value.rb:114-119, 130-150`**

If a field's `pattern`, `min_date`, or `min_datetime` option contains invalid data, the `rescue` block silently skips the entire constraint check. Values that should fail validation pass without any warning.

```ruby
# Current — silent skip
def validate_pattern(val, opts)
  return if Regexp.new(opts[:pattern]).match?(val.to_s)
  errors.add(:value, :invalid)
rescue RegexpError
  # Invalid pattern in field config — skip validation entirely
end
```

```ruby
# Example
field = create(:date_field, options: { "min_date" => "invalid-date" })
value.value = Date.new(1900, 1, 1)  # Way in the past
value.valid?  # => true — constraint silently disabled
```

**Impact:** Misconfigured field options silently disable validation. Should validate option values at field creation time.

---

### 7. Foreign key mismatch between migration and model

**`db/migrate/20260330000000_create_typed_fields_tables.rb:31`**

`section_id` FK defaults to `ON DELETE RESTRICT`, but `Section` model declares `dependent: :nullify`. Deleting a section with associated fields will raise a database constraint error instead of nullifying.

```ruby
# Current (migration)
t.references :section, foreign_key: { to_table: :typed_field_sections }

# Fix
t.references :section, foreign_key: { to_table: :typed_field_sections, on_delete: :set_null }
```

**Impact:** Runtime `ActiveRecord::InvalidForeignKey` error when deleting sections that have fields.

---

### 8. Missing polymorphic index on values table

**`db/migrate/20260330000000_create_typed_fields_tables.rb:66`**

```ruby
t.references :entity, polymorphic: true, null: false, index: false
```

Loading an entity's typed values (`contact.typed_values`) requires a full table scan on `typed_field_values`. This is the most common access pattern and has no index.

```ruby
# Fix
t.references :entity, polymorphic: true, null: false, index: true
```

**Impact:** Every `entity.typed_values` call is a sequential scan. At 1M+ values, this is a significant performance bottleneck.

---

## HIGH — Should Fix Before Release

### 9. Mass assignment bypasses type restrictions

**`lib/typed_fields/has_typed_fields.rb:161-189`**

`typed_fields_attributes=` looks up fields by name but never checks whether the field's type is in the entity's `allowed_typed_field_types`. A model with `has_typed_fields types: [:text]` can still have values assigned to integer fields through nested attributes.

**Remediation:** Add type validation in the setter:

```ruby
allowed_types = self.class.allowed_typed_field_types
if allowed_types && !allowed_types.include?(field.field_type_name.to_sym)
  next # or raise
end
```

---

### 10. QueryBuilder doesn't validate supported operators

**`lib/typed_fields/query_builder.rb:31-75`**

`filter()` accepts any operator for any field type. Calling `with_field("is_active", :gt, true)` on a boolean field generates nonsensical SQL. Should check `field.class.supported_operators` and raise a clear error.

```ruby
# Suggested fix
unless field.class.supported_operators.include?(operator)
  supported = field.class.supported_operators.join(", ")
  raise ArgumentError, "Operator :#{operator} not supported for #{field.class.name}. Supported: #{supported}"
end
```

---

### 11. N+1 in `typed_field_value` and `set_typed_field_value`

**`lib/typed_fields/has_typed_fields.rb:194-210`**

Both use `typed_values.detect { |v| v.field.name == ... }` which loads all values into memory and then accesses each value's field association without eager loading.

```ruby
# Current (N+1)
def typed_field_value(name)
  val = typed_values.detect { |v| v.field.name == name.to_s }
  val&.value
end
```

**Remediation:** Use `includes(:field)` or a single query with a join.

---

### 12. Option validation queries on every save

**`app/models/typed_fields/value.rb:152-161`**

`validate_option_inclusion` calls `field.field_options.exists?(value: val)` hitting the DB on every validation. For select/multi-select fields saved in bulk, this is O(n) queries.

```ruby
# Fix: cache allowed values on the field
class TypedFields::Field::Base
  def allowed_option_values
    @allowed_option_values ||= field_options.pluck(:value).freeze
  end
end
```

---

### 13. Email and URL fields have no format validation

**`app/models/typed_fields/field/types.rb:202-216`**

Email field only downcases/strips. URL field only strips. Both accept any string. `"not-an-email"` is a valid email value.

```ruby
# Current
class Email < Base
  value_column :string_value
  def cast_value(raw)
    raw&.to_s&.strip&.downcase  # Only normalization, no validation
  end
end
```

**Remediation:** Add format validation, either always-on or opt-in via field options.

---

### 14. XSS risk in scaffold helper

**`lib/generators/typed_fields/scaffold/templates/helpers/typed_fields_helper.rb:13`**

`.join.html_safe` marks joined partial output as safe.

```ruby
# Current (risky)
end.join.html_safe

# Fix
safe_join(rendered_partials)
```

---

### 15. No authorization in scaffold controller

**Generated `typed_fields_controller.rb`**

No authorization checks. Any authenticated user can CRUD all field definitions across all entity types and scopes. The generated controller lists all fields globally:

```ruby
TypedFields::Field::Base.order(:entity_type, :scope, :sort_order, :name)
```

**Remediation:** Add prominent warning comments and ideally a hook for authorization integration. Document in README that authorization must be added before production use.

---

## MEDIUM — Should Address

### 16. Multi-filter queries use chained subqueries

**`lib/typed_fields/has_typed_fields.rb:89-101`**

Each filter in `where_typed_fields` adds a separate `WHERE id IN (subquery)`. Three filters = three separate scans of the values table.

```sql
-- Generated SQL for 3 filters
WHERE id IN (SELECT DISTINCT entity_id FROM typed_field_values WHERE field_id=1 AND integer_value > 21)
  AND id IN (SELECT DISTINCT entity_id FROM typed_field_values WHERE field_id=2 AND string_value = 'active')
  AND id IN (SELECT DISTINCT entity_id FROM typed_field_values WHERE field_id=3 AND ...)
```

**Impact:** At scale, a single JOIN with GROUP BY/HAVING would be significantly faster.

---

### 17. No trigram index for substring searches

**`lib/typed_fields/query_builder.rb:54-55`**

`:contains` uses `ILIKE '%value%'` which cannot use the `text_pattern_ops` B-tree index. Only `:starts_with` benefits from the existing index.

**Remediation:** Consider a `pg_trgm` GIN index or document the limitation clearly.

---

### 18. `initialize_typed_values` uses `map` instead of `pluck`

**`lib/typed_fields/has_typed_fields.rb:143`**

```ruby
# Current — instantiates all Value objects just to extract IDs
existing_field_ids = typed_values.map(&:field_id)

# Fix — single-column query, no object allocation
existing_field_ids = typed_values.pluck(:field_id)
```

---

### 19. Default values not validated at field creation

**`app/models/typed_fields/field/base.rb:49-55`**

`default_value=` stores raw values in `default_value_meta` without casting or validating. An integer field can have `default_value: "hello"` which only fails when a value is later initialized.

**Remediation:** Add a validation callback on Field::Base that casts and validates the default value against the field's own constraints.

---

### 20. Decimal `precision_scale` option not enforced

**`app/models/typed_fields/field/types.rb:53-64`**

The `precision_scale` store accessor exists but is never used in `cast_value` or validation. A field configured with `precision_scale: 2` still accepts `3.14159`.

---

### 21. Unbounded JSON payload size

**`db/migrate/20260330000000_create_typed_fields_tables.rb:77`**

`json_value` column has no size limit. Array fields and JSON fields can store arbitrarily large payloads with no validation guard.

**Remediation:** Add a byte-size validation on JSON values:

```ruby
validate :validate_json_payload_size

def validate_json_payload_size
  return unless json_value.present?
  if json_value.to_json.bytesize > 1_000_000
    errors.add(:value, "is too large")
  end
end
```

---

### 22. Scope leakage in multi-tenant mode

**`app/models/typed_fields/field/base.rb:37-40`**

`for_entity` includes both scoped AND `nil`-scoped (global) fields. Without application-level authorization, a tenant can read/modify global field definitions that affect all tenants.

```ruby
scope :for_entity, ->(entity_type, scope: nil) {
  scopes = [scope, nil].uniq  # Returns BOTH scoped and global
  where(entity_type: entity_type, scope: scopes)
}
```

**Remediation:** Document this behavior clearly. Add a "Security Considerations" section to README with authorization guidance.

---

### 23. Redundant index on `typed_fields.entity_type`

**`db/migrate/20260330000000_create_typed_fields_tables.rb:45`**

Single-column index on `entity_type` is redundant with the composite unique index `(name, entity_type, scope)` which already covers `entity_type`-leading queries. Wastes disk and write overhead.

---

## LOW — Nice to Fix

| # | Issue | Location |
|---|-------|----------|
| 24 | No reserved field name validation (`type`, `id`, `class` could shadow AR attributes) | `field/base.rb` |
| 25 | Regex compiled on every validation instead of cached | `value.rb:115` |
| 26 | Redundant value assignment in `typed_fields_attributes=` (sets `existing.value` then passes same value through nested attributes) | `has_typed_fields.rb:180` |
| 27 | `option_keys_for` uses bare `rescue` swallowing all exceptions | scaffold controller:100-105 |
| 28 | STI loading uses `Dir[]` glob instead of Zeitwerk-friendly approach | `engine.rb:20-25` |
| 29 | Missing covering indexes (`INCLUDE entity_id, entity_type`) on typed column indexes | migration |
| 30 | No partial indexes for NULL filtering on typed columns | migration |
| 31 | Inconsistent query API parameter names (`:n`/`:name`, `:v`/`:value`) underdocumented | `has_typed_fields.rb:81` |
| 32 | `dependent: :destroy` on `typed_values` may be slow with many values; consider `delete_all` | `has_typed_fields.rb:55` |
| 33 | `typed_fields_hash` N+1 when called on collections without preloading | `has_typed_fields.rb:213-216` |
| 34 | `with_field` method signature is ambiguous with 2 vs 3 arguments | `has_typed_fields.rb:111` |
| 35 | No `inverse_of` on some associations (minor; Rails 7+ auto-infers most) | various models |

---

## Recommended Priority

### Immediate (before any public release)

1. Fix DecimalArray `.to_f` — keep BigDecimal (#1)
2. Add polymorphic index on values table (#8)
3. Fix FK mismatch — add `on_delete: :set_null` (#7)
4. Add operator validation in QueryBuilder (#10)
5. Validate regex patterns at field creation, add timeout (#5)
6. Distinguish invalid input from nil in casting (#3)

### Before production use

7. Add type restriction enforcement in nested attributes (#9)
8. Add email/URL format validation (#13)
9. Fix `html_safe` to `safe_join` (#14)
10. Cache option values for select validation (#12)
11. Replace `map` with `pluck` in `initialize_typed_values` (#18)
12. Validate default values at field creation (#19)

### Before scale (1M+ values)

13. Rewrite multi-filter to JOIN-based approach (#16)
14. Add trigram index or document substring search cost (#17)
15. Add JSON payload size limits (#21)
16. Add covering indexes (#29)

---

## Summary

| Severity | Count |
|----------|-------|
| Critical | 8 |
| High | 7 |
| Medium | 8 |
| Low | 12 |
| **Total** | **35** |

The engine is well-architected overall — the typed-column approach to EAV is sound and the public API is clean. The critical issues center on three themes: **silent data loss/mutation** (casting bugs), **validation bypasses** (empty arrays, malformed config, ReDoS), and **missing database constraints** (FK mismatch, missing index). Addressing the "Immediate" tier resolves the most impactful issues with relatively low effort.
