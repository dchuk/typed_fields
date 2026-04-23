# TypedFields Adversarial Code Analysis

Generated: 2026-04-08
Reviewed by: Claude analysis agents (4x) + Codex GPT Code Reviewer (independent validation)

## Overview

TypedFields is a Rails Engine gem (v0.1.0) providing dynamic custom fields for ActiveRecord models using a hybrid EAV pattern with native typed database columns. This analysis covers critical bugs, performance issues, Rails convention violations, and test coverage gaps.

**Review methodology:** 4 independent Claude agents analyzed Rails conventions, bugs/correctness, performance, and test coverage. Findings were then independently validated by the Codex GPT Code Reviewer, who confirmed, disputed, or added nuance to each finding and identified additional issues.

---

## 1. CRITICAL BUGS (P0)

### 1.1 `where_typed_fields` Single Hash Arg Destructures Incorrectly

**File:** `lib/typed_fields/has_typed_fields.rb:82-85`
**Status:** Confirmed by all reviewers

```ruby
def where_typed_fields(*filters, scope: nil)
  filters = filters.first if filters.size == 1 && (filters.first.is_a?(Array) || filters.first.is_a?(Hash))
  filters = filters.values if filters.is_a?(Hash)
  filters = Array(filters)
```

When called as `where_typed_fields({name: "a", op: :eq, value: 1})`, the splat captures `[{...}]`. Line 83 unwraps to `{name: "a", op: :eq, value: 1}`. Line 84 -- `filters.is_a?(Hash)` is true, so `filters = filters.values` = `["a", :eq, 1]`. Now it iterates over `"a"`, `:eq`, and `1` as individual filters.

**Impact:** Passing a single filter hash (natural API usage) causes unpredictable errors or wrong results. This is the most clearly dangerous P0 bug.

### 1.2 Boolean Casting Persists Garbage Input as True

**File:** `app/models/typed_fields/field/types.rb:92-96`
**Status:** Confirmed P0 -- worse than initially reported

```ruby
def cast_value(raw)
  return nil if raw.nil?
  ActiveModel::Type::Boolean.new.cast(raw)
end
```

`ActiveModel::Type::Boolean.new.cast("banana")` returns `true` (not `nil` as initially reported). Arbitrary non-boolean strings are silently persisted as truthy data. No `mark_cast_invalid!` call exists, so validation cannot catch this.

**Impact:** Garbage input like `"banana"`, `"xyz"`, or `"0.5"` is silently stored as `true`. Data corruption with no error signal. This was initially listed as P1/P2 but the Codex reviewer correctly identified it as more dangerous than described.

---

## 2. HIGH-PRIORITY BUGS (P1)

### 2.1 DecimalArray Type Drift Through JSON Storage

**File:** `app/models/typed_fields/field/types.rb:194-202`
**Status:** Confirmed with nuance

`cast_value` returns BigDecimal objects stored in a `json_value` (jsonb) column. The exact serialization behavior depends on ActiveRecord version -- BigDecimal may be encoded as strings or floats. Either way, the round-trip produces type drift: values come back as a different Ruby type than what was stored. Additionally, `BigDecimal("Infinity")` and `BigDecimal("NaN")` are valid BigDecimal values but invalid JSON -- storing them causes serialization errors.

**Impact:** Type inconsistency on round-trip. Possible crashes with Infinity/NaN inputs. The "financial data corruption" framing was overstated by the initial analysis -- the real issue is type drift and edge-case crashes.

### 2.2 Silent Data Mutation in Array Casting

**File:** `app/models/typed_fields/field/types.rb` (all array types)
**Status:** Confirmed

All array field types use `filter_map` with `rescue nil` to silently drop invalid elements. Input `["1", "abc", "3"]` to IntegerArray produces `[1, 3]` with no indication that `"abc"` was dropped. DateArray uses bare `rescue nil` (no exception class), which swallows ALL exceptions including `SystemExit` and `NoMemoryError`.

**Impact:** Data loss without user awareness. Potential masking of critical system errors.

### 2.3 `TextArray` `:contains` Operator Wrong for jsonb Column

**File:** `app/models/typed_fields/field/types.rb:206`, `lib/typed_fields/query_builder.rb:63-64`
**Status:** NEW -- identified by Codex reviewer, missed by all Claude agents

`TextArray` declares `operators :any_eq, :all_eq, :contains, :is_null, :is_not_null` but `QueryBuilder` implements `:contains` with `arel_col.matches("%...%")` (ILIKE). This generates `json_value ILIKE '%text%'` which is semantically wrong for a jsonb column -- it pattern-matches against the JSON string representation, not the array contents. This likely produces incorrect results or errors on PostgreSQL.

**Impact:** `:contains` queries on TextArray fields return wrong results or fail.

### 2.4 Registry Type Restrictions Never Enforced

**File:** `lib/typed_fields/registry.rb:28`, `lib/typed_fields/has_typed_fields.rb:60`
**Status:** NEW -- identified by Codex reviewer, missed by all Claude agents

`Registry#type_allowed?` is defined but never called anywhere in the codebase. `TypedFields.registry.register(name, types: types)` stores type restrictions, but field creation and lookup via `typed_field_definitions` or `set_typed_field_value` never check them. A disallowed field type can be freely created for any entity.

**Impact:** The `types:` restriction in `has_typed_fields` is decorative -- it's stored but not enforced at the field definition level.

### 2.5 Scope Not Enforced on Values

**File:** `app/models/typed_fields/value.rb:225`
**Status:** NEW -- identified by Codex reviewer, missed by all Claude agents

`typed_fields_scope` exists on entities, but `TypedFields::Value` only validates `entity_type == field.entity_type`. There's no validation that the value's entity belongs to the same scope as the field. A record can be linked to another tenant's scoped field if code bypasses the helper methods.

**Impact:** Multi-tenant data isolation is not enforced at the model layer. Cross-tenant field value assignment possible.

### 2.6 `DateTime.cast_value` -- `Time.zone.parse` Returns nil Without Raising

**File:** `app/models/typed_fields/field/types.rb:118-126`
**Status:** Confirmed

`Time.zone.parse("hello")` returns `nil` (no exception), so `mark_cast_invalid!` is never called. Invalid input is indistinguishable from blank input. A required DateTime field with value "hello" shows "can't be blank" instead of "is invalid".

### 2.7 `where_typed_fields` Silently Ignores Non-Existent Field Names

**File:** `lib/typed_fields/has_typed_fields.rb:96-97`
**Status:** Confirmed

```ruby
field = fields_by_name[name.to_s]
next query unless field
```

A typo like `"staus"` instead of `"status"` silently skips the filter, returning ALL records instead of filtered results.

**Impact:** Typos in field names cause unfiltered queries in production.

### 2.8 `typed_field_value` Bypasses Loaded Association Cache

**File:** `lib/typed_fields/has_typed_fields.rb:199-201`
**Status:** Confirmed

`includes(:field)` on the association proxy creates a new Relation, bypassing any already-loaded cache. Every call triggers a fresh DB query. Called in a loop for N fields = N queries.

### 2.9 `:between` Operator Partial Input Validation

**File:** `lib/typed_fields/query_builder.rb:61`
**Status:** Confirmed with nuance

The code checks `value.respond_to?(:first) && value.respond_to?(:last)`, which rejects obviously wrong types. However, it still accepts malformed objects that respond to `first`/`last` (e.g., strings, hashes) producing unexpected query behavior.

### 2.10 `_destroy` With No Existing Value

**File:** `lib/typed_fields/has_typed_fields.rb:183-184`
**Status:** Confirmed, lower severity than initially stated

If `_destroy` is true but no existing value exists, produces `{ id: nil, _destroy: true }`. Rails typically ignores destroy-on-new rather than exploding, so this is a code smell more than a crash risk.

### 2.11 `last_cast_invalid` Flag -- Design Smell

**File:** `app/models/typed_fields/field/base.rb:97-109`
**Status:** Confirmed with nuance

Instance variable `@last_cast_invalid` on Field objects is set during `cast_value` and read during Value validation. The cross-thread framing is plausible but overstated -- in practice Field objects are loaded fresh per query. The real concern is the cross-object side-effect pattern using `send(:reset_cast_state!)` to call a private method on another object.

### 2.12 Generated Scaffold Controller Ships Insecure Defaults

**File:** `lib/generators/typed_fields/scaffold/templates/controllers/typed_fields_controller.rb`
**Status:** NEW -- identified by Codex reviewer

The generated controller has no authorization and lists/mutates all field definitions globally. The warning comment is honest, but the generator emits unsafe production code if copied blindly.

### ~~2.x `cattr_accessor` Shares Config Across ALL Models~~ DISPUTED

**File:** `lib/typed_fields/has_typed_fields.rb:44-45`
**Status:** DISPUTED by Codex reviewer

The Codex reviewer found that `Contact` and `Product` can hold distinct values in practice. While `class_attribute` would be more idiomatic, the `cattr_accessor` behavior described (last call overwrites all models) may not manifest as described. Needs verification with a concrete test.

### ~~2.x `:contains` Doesn't Escape SQL Wildcards~~ INVALID

**File:** `lib/typed_fields/query_builder.rb:64,127`
**Status:** INVALID -- already fixed in code

`sanitize_like` method exists at line 127 and is already used by `:contains`, `:not_contains`, `:starts_with`, and `:ends_with` operators. This finding was incorrect.

---

## 3. MEDIUM-PRIORITY BUGS (P2)

### 3.1 `Integer.cast_value("3.7")` Silently Truncates to 3

**File:** `app/models/typed_fields/field/types.rb:57-63`
**Status:** Confirmed

Decimal portion silently dropped without `mark_cast_invalid!`. User enters `3.7`, gets `3` stored.

### 3.2 `validate_range` -- `"abc".to_d` Silently Becomes 0

**File:** `app/models/typed_fields/value.rb:146-153`
**Status:** Confirmed

Malformed min/max options in JSONB become `BigDecimal(0)` instead of raising errors.

### 3.3 `allowed_option_values` Cache Never Auto-Invalidated

**File:** `app/models/typed_fields/field/base.rb:84-91`
**Status:** Confirmed

Cache exists but `clear_option_cache!` is never called automatically when options are added/removed through the association.

### 3.4 `Date.cast_value` Accepts DateTime With Timezone Issues

**File:** `app/models/typed_fields/field/types.rb:103-110`
**Status:** Confirmed, narrower than initially described

`DateTime` is a subclass of `Date`, so `is_a?(::Date)` returns true. A `DateTime` in a non-UTC timezone can be off by one day when stored in `date_value`. The Codex reviewer noted this is narrower than the initial analysis implied.

### 3.5 Pending Value Assignment Order-Dependent

**File:** `app/models/typed_fields/value.rb:39-47,57-64`
**Status:** NEW -- identified by Codex reviewer

`value=` stashes `@pending_value` when `field` is absent, but replay only happens in `after_initialize`. `TypedFields::Value.new(value: 1, field: some_field)` can silently drop the value depending on the order ActiveRecord assigns attributes internally.

### 3.6 Registry Not Thread-Safe

**File:** `lib/typed_fields/registry.rb`
**Status:** Confirmed, lower severity than initially stated

`@entities` is a plain Hash. Concurrent registration is possible but practical risk is low -- registration happens during class loading, which is typically single-threaded in production (eager load).

### ~~3.x JSON Parse Errors Silently Become nil~~ INVALID

**Status:** INVALID -- `Field::Json#cast_value` is a passthrough (`raw`), not a JSON parser. There is no `JSON.parse` call in the cast path.

### ~~3.x SQL Column Name Interpolation Without Whitelist~~ INVALID

**Status:** INVALID -- `col` comes from class metadata set by developers in field type definitions, not from user input. Not a meaningful attack vector.

---

## 4. RAILS CONVENTION VIOLATIONS

### 4.1 All 16 Field Types in Single File (Zeitwerk Violation)

**File:** `app/models/typed_fields/field/types.rb`
**Status:** Confirmed -- significant

Defines 16+ classes in one file. Zeitwerk requires one constant per file. This is why the engine needs the `require` hack in `config.to_prepare`. Each type should be in its own file (e.g., `field/text.rb`, `field/integer.rb`).

### 4.2 Engine Uses `require` Instead of Zeitwerk

**File:** `lib/typed_fields/engine.rb:20-26`
**Status:** Confirmed

`require` bypasses Zeitwerk, prevents code reloading in development, and can cause double-loading warnings.

### 4.3 Double-Loading via Autoload + require_relative

**File:** `lib/typed_fields/engine.rb:7-11` and `lib/typed_fields.rb:9-11`
**Status:** Confirmed, minor

Files are declared with `ActiveSupport::Autoload` AND loaded via `require_relative` in an initializer. Redundant but not harmful.

### 4.4 Full `rails` Dependency Instead of Components

**File:** `typed_fields.gemspec:20`
**Status:** Confirmed, packaging choice

Depends on `rails >= 7.1` but only needs `activerecord` + `railties`. Not a correctness issue.

### 4.5 PostgreSQL-Specific Features Without Declaration

**File:** `db/migrate/20260330000000_create_typed_fields_tables.rb`
**Status:** Confirmed

`include:` on indexes, `text_pattern_ops` opclass, and `jsonb` columns are PostgreSQL-only. The gemspec should declare this requirement or the README should be the authoritative source.

### 4.6 Missing STI Index on `typed_fields.type`

**Status:** Confirmed, minor performance gap

### 4.7 QueryBuilder Spec Error Regex Mismatch

**File:** spec test checks for `/Unknown operator/` but actual error message is `"Operator :bogus is not supported for..."`.
**Status:** Confirmed -- test is likely broken or testing wrong code path.

### 4.8 shoulda-matchers Used Without Dependency Declaration

Spec uses `have_many`, `belong_to` matchers but neither Gemfile nor gemspec declares `shoulda-matchers`.

### Items downgraded to non-issues by Codex review:
- **Pre-Rails 4 module pattern** -- style preference, not a defect
- **ColumnMapping in `lib/`** -- fine for engine internals
- **Migration creating 4 tables** -- preference, not a problem
- **Singleton without explicit require** -- ActiveSupport loads it
- **Test model file organization** -- test-only, not production code

---

## 5. PERFORMANCE & EFFICIENCY ISSUES

### 5.1 Missing `text_value` and `json_value` Indexes

**File:** `db/migrate/20260330000000_create_typed_fields_tables.rb`
**Status:** Confirmed (note: `string_value` IS indexed -- initial analysis was partially wrong)

`text_value` has no index (LongText queries full-scan). `json_value` has no GIN index (all array/MultiSelect `@>` queries full-scan). Other typed columns (integer, decimal, date, datetime, boolean, string) ARE properly indexed with covering indexes.

### 5.2 N+1 Queries on Collections

No mechanism for eager loading typed fields across a collection of records. Each record independently queries its values.

### 5.3 Compounding WHERE IN Subqueries

Each `with_field` filter adds a `WHERE id IN (SELECT ...)` subquery. 5 filters = 5 correlated subqueries.

### 5.4 `typed_field_definitions` Not Cached Per Request

Every call to `where_typed_fields` fires a query to load all field definitions. No memoization.

### 5.5 `Regexp.new(pattern)` Compiled Per Validation + Timeout Thread Overhead

User-configurable pattern compiled on every validation. `Timeout.timeout(1)` creates a thread per validation and is known to be unsafe in Ruby.

### 5.6 `allowed.map(&:to_s)` Allocates in Loop

`allowed_typed_field_types` converted to strings on every iteration of `typed_fields_attributes=` filter loop.

### 5.7 No Sorting Support by Typed Field Values

No mechanism to `ORDER BY` typed field values.

### 5.8 No Batch Insert Support

`initialize_typed_values` creates one AR object per missing field. 50 fields = 50 objects. No `insert_all` path.

---

## 6. TEST COVERAGE GAPS

### 6.1 Untested Field Types

5 field types have NO factory and NO tests: DecimalArray, DateArray, Url, Color, Json. DateTime and LongText casting are also untested. TextArray has a factory but no casting tests.

### 6.2 Untested Validations

- Text/Email/Url pattern validation (including Timeout and ReDoS guard)
- Date/DateTime range validation (min_date/max_date)
- Array size validation (min_size/max_size)
- JSON size validation (1MB limit)
- Reserved field name validation
- Integer/Decimal max >= min validation
- Email format validation
- URL format validation
- Multi-select partial invalid array

### 6.3 Untested Edge Cases

- `cast(nil)` for each type
- Empty string vs nil consistency
- Unicode strings
- Integer overflow / very long strings / deeply nested JSON
- `@last_cast_invalid` flag behavior and reset
- `default_value` / `default_value=` methods
- Decimal `precision_scale` rounding
- Boolean with non-boolean strings (critical given 1.2)

### 6.4 Untested Query Scenarios

- Chaining multiple `with_field` conditions
- Querying non-existent field names
- `:between` with invalid ranges
- MultiSelect containment queries
- `:eq` / `:not_eq` with nil
- Scoped `with_field` queries
- TextArray `:contains` on jsonb (2.3 -- likely broken)

### 6.5 Untested Integration Scenarios

- `_destroy` in bulk assignment
- Type restriction enforcement in `typed_fields_attributes=`
- Hash-format filter input (ActionController params)
- `dependent: :destroy` cascades (field->values, field->options, entity->values)
- Full entity lifecycle (create, assign, query, update, delete)
- Generator output (install and scaffold)
- Engine loading in host app
- Multi-tenant scope isolation (2.5)

### 6.6 Missing Negative Tests

- Creating a field with a reserved name
- Querying with unsupported operators on specific field types
- STI with non-existent type class
- Wrong value types passed to QueryBuilder
- Registry type enforcement (currently dead code -- 2.4)

---

## 7. REVISED PRIORITY MATRIX

*Updated based on Codex Code Reviewer validation. Removed invalid findings, corrected severity levels.*

| Priority | Category | Issue | Impact | Section |
|----------|----------|-------|--------|---------|
| **P0** | Bug | `where_typed_fields` single hash destructuring | Wrong query results | 1.1 |
| **P0** | Bug | Boolean casts garbage strings to `true` | Silent data corruption | 1.2 |
| **P1** | Bug | DecimalArray type drift through JSON storage | Type inconsistency, edge-case crashes | 2.1 |
| **P1** | Bug | Silent array element dropping in all array types | Data loss without awareness | 2.2 |
| **P1** | Bug | TextArray `:contains` wrong for jsonb column | Broken queries | 2.3 |
| **P1** | Bug | Registry type restrictions never enforced | `types:` option is decorative | 2.4 |
| **P1** | Bug | Multi-tenant scope not enforced on values | Cross-tenant data leakage | 2.5 |
| **P1** | Bug | DateTime cast doesn't mark invalid input | Wrong error messages | 2.6 |
| **P1** | Bug | Silent ignore of non-existent field names | Unfiltered queries on typos | 2.7 |
| **P1** | Bug | `typed_field_value` bypasses loaded cache | N+1 queries | 2.8 |
| **P1** | Bug | Scaffold controller ships without authorization | Insecure generated code | 2.12 |
| **P1** | Perf | Missing `json_value` GIN index | Full scans on array queries | 5.1 |
| **P1** | Perf | Missing `text_value` index | Full scans on LongText queries | 5.1 |
| **P1** | Conv | All field types in single file (Zeitwerk) | No code reloading in dev | 4.1 |
| **P2** | Bug | Integer truncates decimals silently | Unexpected data modification | 3.1 |
| **P2** | Bug | `validate_range` with malformed options | Silent zero comparison | 3.2 |
| **P2** | Bug | Option cache never invalidated | Stale validation | 3.3 |
| **P2** | Bug | Date accepts DateTime with timezone issues | Potential off-by-one day | 3.4 |
| **P2** | Bug | Pending value assignment order-dependent | Possible silent value drop | 3.5 |
| **P2** | Bug | `_destroy` with no existing value | No-op or minor error | 2.10 |
| **P2** | Bug | `:between` accepts malformed objects | Unexpected behavior | 2.9 |
| **P2** | Perf | N+1 on collections, no eager loading | Slow listing pages | 5.2 |
| **P2** | Conv | Full `rails` dep instead of components | Unnecessary dependencies | 4.4 |
| **P2** | Conv | `require` instead of Zeitwerk loading | Dev experience, double-loading | 4.2 |
| **P2** | Test | 5 field types completely untested | Low confidence in correctness | 6.1 |
| **P2** | Test | Most validations untested | Unknown failure modes | 6.2 |
| **P2** | Test | Broken spec (regex mismatch) | False confidence | 4.7 |

### Findings Removed (Invalid)

| Original | Reason Removed |
|----------|----------------|
| `:contains` doesn't escape SQL wildcards | `sanitize_like` already exists and is used |
| No uniqueness constraints on values table | `idx_tf_values_entity_field` unique index exists |
| No uniqueness on options table | `idx_tf_options_field_value` unique index exists |
| JSON parse errors silently become nil | `Field::Json#cast_value` is passthrough, no JSON.parse |
| SQL column interpolation risk | `col` from class metadata, not user input |
| Missing value column indexes (all) | Most columns ARE indexed; only `text_value` and `json_value` are missing |
