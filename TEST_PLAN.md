# TypedFields Comprehensive Test Plan

Generated: 2026-04-08

## Overview

This plan covers the full TypedFields gem with conventional Rails/RSpec tests. It is organized by spec file, with each section listing every test case needed. Tests follow Rails conventions: model specs for validations/associations/methods, lib specs for pure logic, and integration specs for cross-cutting behavior.

### Current State

**Existing spec files (6):**
- `spec/models/typed_fields/field_spec.rb` — 25 examples
- `spec/models/typed_fields/value_spec.rb` — 22 examples
- `spec/models/typed_fields/has_typed_fields_spec.rb` — 18 examples
- `spec/models/typed_fields/section_and_option_spec.rb` — 8 examples
- `spec/lib/typed_fields/query_builder_spec.rb` — 18 examples
- `spec/lib/typed_fields/config_and_registry_spec.rb` — 8 examples

**Missing factories (5):** DecimalArray, DateArray, Url, Color, Json

**Test dependencies to add:** `shoulda-matchers` (already used but undeclared)

---

## Phase 1: Factories & Test Infrastructure

### File: `spec/factories/typed_fields.rb`

Add missing factories:

```
Factory: :decimal_array_field (TypedFields::Field::DecimalArray)
Factory: :date_array_field (TypedFields::Field::DateArray)
Factory: :url_field (TypedFields::Field::Url)
Factory: :color_field (TypedFields::Field::Color)
Factory: :json_field (TypedFields::Field::Json)
```

### File: `Gemfile`

Add missing test dependency:
```
gem "shoulda-matchers" (already used in specs but not declared)
```

### File: `spec/spec_helper.rb`

Add shoulda-matchers configuration block.

---

## Phase 2: Model Specs

### File: `spec/models/typed_fields/field_spec.rb`

#### Existing (keep as-is):
- [x] associations: has_many(:values), has_many(:field_options), belongs_to(:section).optional
- [x] validates presence of name, type, entity_type
- [x] name uniqueness per entity_type and scope
- [x] STI resolution loads correct subclass
- [x] Column mapping for all 16 types
- [x] Supported operators for Integer, Boolean, Text, Select, MultiSelect
- [x] Casting: Integer (strings, non-numeric, truncation)
- [x] Casting: Decimal (strings to BigDecimal)
- [x] Casting: Boolean (true, "0", nil)
- [x] Casting: Date (string, passthrough, invalid)
- [x] Casting: Email (downcase/strip)
- [x] Casting: IntegerArray (cast elements, filter invalid)
- [x] Select: optionable?, not array_field?
- [x] MultiSelect: optionable?, array_field?

#### NEW — Reserved field names:
```
it "rejects reserved names (id, type, class, created_at, updated_at)"
  build(:text_field, name: "id") => not valid, error "is reserved"
  build(:text_field, name: "type") => not valid
  build(:text_field, name: "created_at") => not valid
```

#### NEW — Default value handling:
```
describe "#default_value and #default_value="
  it "stores and retrieves a default value cast through field type"
    field = create(:integer_field)
    field.default_value = 42
    field.save!
    expect(field.reload.default_value).to eq(42)

  it "returns nil when no default is set"
    expect(build(:text_field).default_value).to be_nil

  it "validates invalid default values"
    field = build(:integer_field)
    field.default_value_meta = { "v" => "not_a_number" }
    expect(field).not_to be_valid
    expect(field.errors[:default_value]).to be_present
```

#### NEW — field_type_name introspection:
```
describe "#field_type_name"
  it "returns underscore name for each type"
    expect(TypedFields::Field::MultiSelect.new.field_type_name).to eq("multi_select")
    expect(TypedFields::Field::IntegerArray.new.field_type_name).to eq("integer_array")
    expect(TypedFields::Field::LongText.new.field_type_name).to eq("long_text")
```

#### NEW — allowed_option_values caching:
```
describe "#allowed_option_values"
  it "returns cached option values for select fields"
    field = create(:select_field)
    expect(field.allowed_option_values).to match_array(["active", "inactive", "lead"])

  it "returns stale data after option changes (known limitation)"
    field = create(:select_field)
    field.allowed_option_values  # prime cache
    field.field_options.create!(label: "New", value: "new", sort_order: 4)
    expect(field.allowed_option_values).not_to include("new")  # stale

  it "clears cache when clear_option_cache! is called"
    field = create(:select_field)
    field.allowed_option_values  # prime cache
    field.field_options.create!(label: "New", value: "new", sort_order: 4)
    field.clear_option_cache!
    expect(field.allowed_option_values).to include("new")
```

#### NEW — Text field validations:
```
describe TypedFields::Field::Text do
  describe "option validations"
    it "validates min_length is non-negative integer"
    it "validates max_length is positive integer"
    it "validates max_length >= min_length"
      build(:text_field, options: { min_length: 10, max_length: 5 }) => not valid

    it "validates pattern syntax"
      build(:text_field, options: { pattern: "[invalid" }) => not valid, error on :pattern

    it "accepts valid regex pattern"
      build(:text_field, options: { pattern: "\\A[a-z]+\\z" }) => valid
```

#### NEW — Integer/Decimal field validations:
```
describe TypedFields::Field::Integer do
  it "validates max >= min"
    build(:integer_field, options: { min: 100, max: 10 }) => not valid

describe TypedFields::Field::Decimal do
  it "validates max >= min"
  it "applies precision_scale rounding"
    field = build(:decimal_field, options: { precision_scale: "2" })
    expect(field.cast_value("19.999")).to eq(BigDecimal("20.00"))
  it "ignores invalid precision_scale"
    field = build(:decimal_field, options: { precision_scale: "abc" })
    expect(field.cast_value("19.99")).to eq(BigDecimal("19.99"))
```

#### NEW — Untested field type casting:
```
describe TypedFields::Field::LongText do
  it "casts to string via to_s"
    expect(field.cast_value(123)).to eq("123")
  it "returns nil for nil"
    expect(field.cast_value(nil)).to be_nil
  it "maps to :text_value column"

describe TypedFields::Field::DateTime do
  it "casts valid datetime string"
    expect(field.cast_value("2025-06-15 14:30:00")).to be_a(Time)
  it "passes through Time objects"
  it "returns nil for invalid strings (Time.zone.parse returns nil)"
    expect(field.cast_value("not-a-datetime")).to be_nil
  it "does NOT mark invalid when Time.zone.parse returns nil (known bug)"
    field.cast_value("hello")
    expect(field.last_cast_invalid).to be false  # documents the bug

describe TypedFields::Field::DecimalArray do
  it "casts array elements to BigDecimal"
    expect(field.cast_value(["1.5", "2.5"])).to eq([BigDecimal("1.5"), BigDecimal("2.5")])
  it "filters out non-numeric elements and marks invalid"
    result = field.cast_value(["1.5", "abc", "3.0"])
    expect(result).to eq([BigDecimal("1.5"), BigDecimal("3.0")])
    expect(field.last_cast_invalid).to be true
  it "returns nil for nil"
  it "returns nil for empty array (via .presence)"

describe TypedFields::Field::DateArray do
  it "casts array of date strings"
    expect(field.cast_value(["2025-01-01", "2025-06-15"])).to eq([Date.new(2025,1,1), Date.new(2025,6,15)])
  it "filters out invalid dates and marks invalid"
  it "returns nil for nil"

describe TypedFields::Field::Url do
  it "strips whitespace"
    expect(field.cast_value("  https://example.com  ")).to eq("https://example.com")
  it "does not downcase (URLs are case-sensitive in path)"
  it "validates URL format"
    expect(field.url_format_valid?("https://example.com")).to be true
    expect(field.url_format_valid?("not-a-url")).to be false

describe TypedFields::Field::Color do
  it "downcases and strips"
    expect(field.cast_value("  #FF0000  ")).to eq("#ff0000")
  it "returns nil for nil"
  it "maps to :string_value column"
  it "supports only :eq, :not_eq, :is_null, :is_not_null operators"

describe TypedFields::Field::Json do
  it "passes through hash values"
    expect(field.cast_value({ "key" => "val" })).to eq({ "key" => "val" })
  it "passes through array values"
  it "passes through nil"
  it "maps to :json_value column"
  it "supports only :is_null, :is_not_null operators"
```

#### NEW — Boolean casting regression test (P0 bug):
```
describe TypedFields::Field::Boolean do
  it "REGRESSION: casts arbitrary strings to truthy (known bug)"
    expect(field.cast_value("banana")).to eq(true)  # documents the bug
  it "does not call mark_cast_invalid! for garbage input (known limitation)"
```

#### NEW — cast_value nil handling across all types:
```
describe "cast_value(nil) returns nil for all field types"
  %i[text_field long_text_field integer_field decimal_field boolean_field
     date_field datetime_field select_field multi_select_field
     integer_array_field decimal_array_field text_array_field date_array_field
     email_typed_field url_field color_field json_field].each do |factory|
    it "#{factory} returns nil for nil input"
      field = build(factory)
      expect(field.cast_value(nil)).to be_nil
```

#### NEW — Supported operators for ALL types:
```
describe "supported operators for all field types"
  it "Decimal supports numeric operators"
  it "Date supports comparison operators"
  it "DateTime supports comparison operators"
  it "LongText supports string operators"
  it "Email supports string operators (inherits from string_value defaults)"
  it "Url supports string operators"
  it "Color supports only eq/not_eq/null operators"
  it "Json supports only null operators"
  it "IntegerArray supports array operators"
  it "DecimalArray supports array operators"
  it "TextArray supports array + contains operators"
  it "DateArray supports array operators"
```

#### NEW — ColumnMapping:
```
describe TypedFields::ColumnMapping do
  it "raises NotImplementedError for field type without value_column"
    klass = Class.new(TypedFields::Field::Base)
    expect { klass.value_column }.to raise_error(NotImplementedError)

  it "returns default operators based on column type"
    expect(TypedFields::Field::Integer.supported_operators).to include(:between)
    expect(TypedFields::Field::Boolean.supported_operators).not_to include(:gt)
```

---

### File: `spec/models/typed_fields/value_spec.rb`

#### Existing (keep as-is):
- [x] associations: belongs_to entity, belongs_to field
- [x] Value storage for integer, text, boolean, decimal, date, select, multi_select, integer_array, email
- [x] Uniqueness validation (entity + field)
- [x] Entity type validation
- [x] Required field validation
- [x] Range validation (integer min/max)
- [x] Select option inclusion validation
- [x] Length validation (text min/max length)

#### NEW — Value storage for untested types:
```
context "with a long_text field"
  it "stores value in text_value column"

context "with a datetime field"
  it "stores value in datetime_value column"
  it "preserves timezone information"

context "with a decimal_array field"
  it "stores array in json_value column"
  it "round-trips BigDecimal values (documents type drift)"

context "with a date_array field"
  it "stores array of dates in json_value column"

context "with a text_array field"
  it "stores string array in json_value column"

context "with a url field"
  it "stores in string_value column"

context "with a color field"
  it "stores in string_value column"

context "with a json field"
  it "stores hash in json_value column"
  it "stores array in json_value column"
```

#### NEW — Validation: cast invalid detection:
```
describe "cast invalid detection"
  it "adds :invalid error when field marks cast as invalid"
    field = create(:integer_field, required: true)
    value = TypedFields::Value.new(entity: create(:contact), field: field)
    value.value = "not_a_number"
    expect(value).not_to be_valid
    expect(value.errors[:value]).to include(match(/invalid/))

  it "resets cast state after validation"
    field = create(:integer_field)
    value = TypedFields::Value.new(entity: create(:contact), field: field)
    value.value = "abc"
    value.valid?
    expect(field.last_cast_invalid).to be false  # reset after validation
```

#### NEW — Pattern validation:
```
describe "pattern validation"
  it "validates text value against regex pattern"
    field = create(:text_field, options: { pattern: "\\A[A-Z]" })
    value = TypedFields::Value.new(entity: create(:contact), field: field)
    value.value = "hello"
    expect(value).not_to be_valid

  it "accepts matching pattern"
    field = create(:text_field, options: { pattern: "\\A[A-Z]" })
    value = TypedFields::Value.new(entity: create(:contact), field: field)
    value.value = "Hello"
    expect(value).to be_valid

  it "handles invalid regex pattern gracefully"
    field = create(:text_field)
    field.update_column(:options, { "pattern" => "[invalid" })
    value = TypedFields::Value.new(entity: create(:contact), field: field)
    value.value = "test"
    expect(value).not_to be_valid
    expect(value.errors[:value]).to include(match(/invalid pattern/))
```

#### NEW — Email format validation:
```
describe "email format validation"
  it "rejects invalid email format"
    value.value = "not-an-email"
    expect(value).not_to be_valid
    expect(value.errors[:value]).to include(match(/email/))

  it "accepts valid email"
    value.value = "user@example.com"
    expect(value).to be_valid
```

#### NEW — URL format validation:
```
describe "url format validation"
  it "rejects invalid URL"
    value.value = "not-a-url"
    expect(value).not_to be_valid

  it "accepts valid http URL"
    value.value = "https://example.com"
    expect(value).to be_valid
```

#### NEW — Date range validation:
```
describe "date range validation"
  it "rejects date before min_date"
  it "rejects date after max_date"
  it "accepts date within range"
  it "handles invalid min/max date config gracefully"
```

#### NEW — DateTime range validation:
```
describe "datetime range validation"
  it "rejects datetime before min_datetime"
  it "rejects datetime after max_datetime"
  it "accepts datetime within range"
```

#### NEW — Multi-select option validation:
```
describe "multi-select option validation"
  it "rejects when any value is not in options list"
    value.value = ["vip", "nonexistent"]
    expect(value).not_to be_valid

  it "accepts when all values are in options list"
    value.value = ["vip", "partner"]
    expect(value).to be_valid
```

#### NEW — Array size validation:
```
describe "array size validation"
  it "rejects arrays smaller than min_size"
    field = create(:integer_array_field, options: { min_size: 2 })
    value.value = [1]
    expect(value).not_to be_valid

  it "rejects arrays larger than max_size"
    field = create(:integer_array_field, options: { max_size: 3 })
    value.value = [1, 2, 3, 4]
    expect(value).not_to be_valid

  it "accepts arrays within size range"
```

#### NEW — JSON size validation:
```
describe "json size validation"
  it "rejects JSON values exceeding 1MB"
    field = create(:json_field)
    value.value = { "data" => "x" * 1_000_001 }
    expect(value).not_to be_valid
    expect(value.errors[:value]).to include(match(/too large/))

  it "accepts JSON values under 1MB"
```

#### NEW — Decimal range validation:
```
describe "decimal range validation"
  it "rejects decimal below min"
  it "rejects decimal above max"
  it "accepts decimal within range"
```

#### NEW — Pending value mechanism:
```
describe "pending value (field assigned after value)"
  it "applies pending value after field is assigned via after_initialize"
    value = TypedFields::Value.new(field: field, value: "test")
    expect(value.value).to eq("test")
```

#### NEW — Value#value when field is nil:
```
describe "#value when field is nil"
  it "returns nil without error"
    expect(TypedFields::Value.new.value).to be_nil
```

---

### File: `spec/models/typed_fields/section_and_option_spec.rb`

#### Existing (keep as-is):
- [x] Section validations (name, code, entity_type, uniqueness)
- [x] Section associations (has many fields, nullify on destroy)
- [x] Section scopes (active, for_entity)
- [x] Option validations (label, value, uniqueness per field)
- [x] Option scopes (sorted)

#### NEW — Section:
```
describe ".sorted scope"
  it "orders by sort_order then name"

describe "default active value"
  it "defaults to true"
    expect(TypedFields::Section.new.active).to be true
```

#### NEW — Option:
```
describe "belongs_to :field"
  it "is required (non-optional)"

describe "association inverse"
  it "field.field_options returns associated options"
```

---

## Phase 3: Lib Specs

### File: `spec/lib/typed_fields/query_builder_spec.rb`

#### Existing (keep as-is):
- [x] Integer: eq, gt, lt, gteq, lteq, between, not_eq, string casting
- [x] Text: eq, contains, starts_with, ends_with, not_contains, LIKE wildcard escaping
- [x] Boolean: eq true, eq false
- [x] Date: gt, between
- [x] IntegerArray (json): any_eq, all_eq
- [x] Null checks: is_null, is_not_null
- [x] entity_ids returns relation
- [x] Unknown operator raises ArgumentError

#### FIX — Broken test:
```
describe "unknown operator" (line 226)
  FIX: Change regex from /Unknown operator/ to /not supported/
  The actual error message is "Operator :bogus is not supported for..."
```

#### NEW — Decimal field queries:
```
describe ".filter with decimal fields"
  it ":eq finds exact BigDecimal match"
  it ":gt finds greater than"
  it ":between finds within range"
```

#### NEW — DateTime field queries:
```
describe ".filter with datetime fields"
  it ":gt finds datetimes after"
  it ":between finds datetimes in range"
  it ":eq finds exact match"
```

#### NEW — Select field queries:
```
describe ".filter with select fields"
  it ":eq finds matching option value"
  it ":not_eq excludes matching and includes NULLs"
```

#### NEW — MultiSelect field queries:
```
describe ".filter with multi_select fields"
  it ":any_eq finds arrays containing element"
  it ":all_eq finds arrays containing all elements"
```

#### NEW — Null handling edge cases:
```
describe "null value handling"
  it ":eq with nil value acts as IS NULL"
  it ":not_eq with nil value acts as IS NOT NULL"
```

#### NEW — :between validation:
```
describe ":between input validation"
  it "raises ArgumentError for non-range/non-array values"
    expect { described_class.filter(field, :between, 42) }.to raise_error(ArgumentError, /between/)

  it "accepts Range input"
  it "accepts two-element Array input"
```

#### NEW — Unsupported operator per field type:
```
describe "operator validation per field type"
  it "rejects :gt on Boolean field"
    expect { described_class.filter(bool_field, :gt, true) }.to raise_error(ArgumentError, /not supported/)

  it "rejects :contains on Integer field"
  it "rejects :between on Select field"
```

#### NEW — Color field queries:
```
describe ".filter with color fields"
  it ":eq finds exact color match"
  it ":not_eq excludes color"
```

---

### File: `spec/lib/typed_fields/config_and_registry_spec.rb`

#### Existing (keep as-is):
- [x] Config: includes all builtin types, resolves type name, raises for unknown, registers custom
- [x] Registry: register, allowed_types_for, type_allowed?

#### NEW — Config:
```
it "includes :decimal_array and :date_array in type_names"
  expect(config.type_names).to include(:decimal_array, :date_array)

it "resolves all 16 builtin types to their classes"
  TypedFields::Config::BUILTIN_FIELD_TYPES.each do |name, class_name|
    expect(config.field_class_for(name)).to eq(class_name.constantize)
  end
```

#### NEW — Registry:
```
describe "#reset!"
  it "clears all registered entities"
    registry.register("Foo")
    registry.reset!
    expect(registry.entity_types).to be_empty
```

---

### File: `spec/lib/typed_fields/column_mapping_spec.rb` (NEW FILE)

```
describe TypedFields::ColumnMapping do
  describe ".value_column"
    it "raises NotImplementedError when not declared"
    it "returns declared column as symbol"

  describe ".supported_operators"
    it "returns default operators based on column type"
    it "allows override via .operators class method"

  describe ".default_operators_for"
    it "returns numeric operators for :integer_value"
    it "returns string operators for :string_value"
    it "returns boolean operators for :boolean_value"
    it "returns date operators for :date_value"
    it "returns json operators for :json_value"
    it "returns basic operators for unknown column"
```

---

## Phase 4: HasTypedFields Integration Specs

### File: `spec/models/typed_fields/has_typed_fields_spec.rb`

#### Existing (keep as-is):
- [x] has_typed_fields adds typed_values association
- [x] registers in global registry
- [x] stores scope_method and type restrictions
- [x] typed_field_definitions filters by entity_type
- [x] typed_field_definitions includes scoped fields
- [x] where_typed_fields: single field, multiple fields (AND), compact keys, default :eq, nonexistent field, chaining
- [x] with_field: short form, full form
- [x] initialize_typed_values: builds missing, no duplicates
- [x] typed_fields_attributes=: create, update, ignore unknown
- [x] typed_field_value / set_typed_field_value
- [x] typed_fields_hash
- [x] scoping: includes global+scoped, excludes other tenant

#### FIX — where_typed_fields single hash regression test (P0):
```
describe ".where_typed_fields single hash argument (REGRESSION)"
  it "REGRESSION: single hash filter is destructured incorrectly"
    # This documents the P0 bug from ANALYSIS.md 1.1
    # where_typed_fields({name: "age", op: :eq, value: 30}) breaks
    # because filters.values extracts hash values as ["age", :eq, 30]
    expect {
      Contact.where_typed_fields({name: "age", op: :gt, value: 20})
    }.to raise_error  # or produce wrong results — document current behavior
```

#### NEW — typed_fields_attributes= with _destroy:
```
describe "#typed_fields_attributes= with _destroy"
  it "destroys existing values when _destroy is truthy"
    contact.typed_fields_attributes = [{ name: "age", value: 30 }]
    contact.save!
    expect(contact.typed_field_value("age")).to eq(30)

    contact.typed_fields_attributes = [{ name: "age", _destroy: true }]
    contact.save!
    expect(contact.typed_values.count).to eq(0)

  it "handles _destroy for non-existent values gracefully"
    contact.typed_fields_attributes = [{ name: "age", _destroy: true }]
    contact.save!  # should not error
```

#### NEW — typed_fields_attributes= with type restrictions:
```
describe "#typed_fields_attributes= type restrictions"
  it "skips fields of disallowed types on restricted models"
    json_field = create(:json_field, entity_type: "Product")
    product = create(:product)
    product.typed_fields_attributes = [{ name: json_field.name, value: { key: "val" } }]
    product.save!
    expect(product.typed_values.count).to eq(0)

  it "allows fields of permitted types"
    text_field = create(:text_field, entity_type: "Product")
    product = create(:product)
    product.typed_fields_attributes = [{ name: text_field.name, value: "hello" }]
    product.save!
    expect(product.typed_values.count).to eq(1)
```

#### NEW — typed_fields_attributes= with Hash input (form params):
```
describe "#typed_fields_attributes= with Hash input"
  it "accepts hash-of-hashes (ActionController params format)"
    contact.typed_fields_attributes = {
      "0" => { name: "age", value: 30 },
      "1" => { name: "bio", value: "Hello" }
    }
    contact.save!
    expect(contact.typed_field_value("age")).to eq(30)
```

#### NEW — set_typed_field_value edge cases:
```
describe "#set_typed_field_value"
  it "returns nil for non-existent field name"
    expect(contact.set_typed_field_value("nonexistent", "value")).to be_nil

  it "updates an existing value"
    contact.set_typed_field_value("nickname", "Ace")
    contact.save!
    contact.set_typed_field_value("nickname", "Updated")
    contact.save!
    expect(contact.typed_field_value("nickname")).to eq("Updated")
```

#### NEW — initialize_typed_values with defaults:
```
describe "#initialize_typed_values with default values"
  it "populates built values with field defaults"
    field = create(:integer_field, name: "score", entity_type: "Contact",
                   default_value_meta: { "v" => 100 })
    values = contact.initialize_typed_values
    score_value = values.detect { |v| v.field.name == "score" }
    expect(score_value.value).to eq(100)
```

#### NEW — Dependent destroy:
```
describe "dependent: :destroy"
  it "destroys typed_values when entity is destroyed"
    contact.set_typed_field_value("nickname", "test")
    contact.save!
    expect { contact.destroy! }.to change(TypedFields::Value, :count).by(-1)
```

---

## Phase 5: Regression Tests for Known Bugs

### File: `spec/regressions/known_bugs_spec.rb` (NEW FILE)

These tests document known bugs from ANALYSIS.md. They should be written to FAIL against current code (pending or xfail), then pass once bugs are fixed.

```
describe "ANALYSIS 1.1: where_typed_fields single hash destructuring"
  it "should handle single hash filter correctly", pending: "P0 bug"
    # where_typed_fields({name: "age", op: :gt, value: 20}) should work

describe "ANALYSIS 1.2: Boolean casts garbage to true"
  it "should reject non-boolean strings", pending: "P0 bug"
    field = build(:boolean_field)
    # cast_value("banana") should NOT return true

describe "ANALYSIS 2.1: DecimalArray type drift through JSON"
  it "documents BigDecimal type drift on round-trip"
    field = create(:decimal_array_field, entity_type: "Contact")
    value = TypedFields::Value.create!(entity: create(:contact), field: field)
    value.value = [BigDecimal("0.1"), BigDecimal("0.2")]
    value.save!
    value.reload
    # Document: values come back as different type

describe "ANALYSIS 2.3: TextArray :contains wrong for jsonb"
  it "documents incorrect ILIKE on jsonb column", pending: "P1 bug"
    # TextArray :contains generates ILIKE on json_value which is wrong

describe "ANALYSIS 2.4: Registry type restrictions never enforced"
  it "documents that type_allowed? is never called"
    # A disallowed field type can be freely created

describe "ANALYSIS 2.5: Scope not enforced on values"
  it "documents cross-tenant value assignment possible"
    # A value can reference a field scoped to a different tenant

describe "ANALYSIS 2.6: DateTime cast doesn't mark invalid"
  it "documents Time.zone.parse returning nil without marking invalid"
    field = build(:datetime_field)
    field.cast_value("hello")
    expect(field.last_cast_invalid).to be false  # bug: should be true

describe "ANALYSIS 2.7: Silent ignore of non-existent field names"
  it "documents that typos silently return all records"
    results = Contact.where_typed_fields({ name: "nonexistent_typo", op: :eq, value: "x" })
    # returns all contacts instead of raising

describe "ANALYSIS 3.1: Integer truncates decimals silently"
  it "documents silent truncation"
    field = build(:integer_field)
    expect(field.cast_value("3.7")).to eq(3)  # truncated, no invalid flag

describe "ANALYSIS 3.2: validate_range with malformed options"
  it "documents 'abc'.to_d becoming 0"
    # min: "abc" effectively becomes min: 0
```

---

## Phase 6: Integration / End-to-End Specs

### File: `spec/integration/typed_fields_lifecycle_spec.rb` (NEW FILE)

```
describe "Full entity lifecycle"
  it "creates entity, defines fields, assigns values, queries, updates, deletes"
    # 1. Create field definitions
    age = create(:integer_field, name: "age", entity_type: "Contact")
    city = create(:text_field, name: "city", entity_type: "Contact")

    # 2. Create entity and assign values
    contact = create(:contact)
    contact.typed_fields_attributes = [
      { name: "age", value: 30 },
      { name: "city", value: "Portland" }
    ]
    contact.save!

    # 3. Read back values
    expect(contact.typed_field_value("age")).to eq(30)
    expect(contact.typed_fields_hash).to eq({ "age" => 30, "city" => "Portland" })

    # 4. Query
    expect(Contact.with_field("age", :gt, 25)).to include(contact)
    expect(Contact.with_field("city", "Portland")).to include(contact)

    # 5. Update
    contact.set_typed_field_value("age", 31)
    contact.save!
    expect(contact.typed_field_value("age")).to eq(31)

    # 6. Delete entity cascades
    expect { contact.destroy! }.to change(TypedFields::Value, :count).by(-2)

describe "Multi-field AND query"
  it "filters by multiple fields simultaneously"
    # Create 3 contacts with different age/city combos
    # Query age > 25 AND city = "Portland"
    # Verify only matching contacts returned

describe "Field definition lifecycle"
  it "field destroy cascades to values and options"
    field = create(:select_field)
    contact = create(:contact)
    TypedFields::Value.create!(entity: contact, field: field).tap { |v| v.value = "active"; v.save! }

    expect { field.destroy! }.to change(TypedFields::Value, :count).by(-1)
      .and change(TypedFields::Option, :count).by(-3)
```

---

## Phase 7: Generator Specs (optional, lower priority)

### File: `spec/generators/typed_fields/install_generator_spec.rb` (NEW FILE)

```
describe TypedFields::Generators::InstallGenerator
  it "copies migration file to host app"
```

### File: `spec/generators/typed_fields/scaffold_generator_spec.rb` (NEW FILE)

```
describe TypedFields::Generators::ScaffoldGenerator
  it "creates controller file"
  it "creates concern file"
  it "creates helper file"
  it "creates view files"
  it "injects concern into ApplicationController"
```

---

## Execution Order

| Phase | Files | Est. Test Count | Priority |
|-------|-------|-----------------|----------|
| 1 | Factories, Gemfile, spec_helper | 0 (infrastructure) | **Must do first** |
| 2 | field_spec, value_spec, section_and_option_spec | ~80 new tests | **High** |
| 3 | query_builder_spec, config_and_registry_spec, column_mapping_spec | ~25 new tests | **High** |
| 4 | has_typed_fields_spec | ~15 new tests | **High** |
| 5 | regressions/known_bugs_spec | ~12 tests | **Medium** |
| 6 | integration/lifecycle_spec | ~5 tests | **Medium** |
| 7 | generators/ | ~5 tests | **Low** |

**Total estimated new tests: ~142**
**Total after adding to existing ~99: ~241**

---

## File Structure After Implementation

```
spec/
  spec_helper.rb                              (updated: shoulda-matchers config)
  factories/typed_fields.rb                   (updated: 5 new factories)
  models/typed_fields/
    field_spec.rb                             (updated: ~55 new examples)
    value_spec.rb                             (updated: ~25 new examples)
    has_typed_fields_spec.rb                  (updated: ~15 new examples)
    section_and_option_spec.rb                (updated: ~4 new examples)
  lib/typed_fields/
    query_builder_spec.rb                     (updated: ~20 new examples, 1 fix)
    config_and_registry_spec.rb               (updated: ~5 new examples)
    column_mapping_spec.rb                    (NEW: ~10 examples)
  regressions/
    known_bugs_spec.rb                        (NEW: ~12 examples)
  integration/
    typed_fields_lifecycle_spec.rb            (NEW: ~5 examples)
  generators/typed_fields/
    install_generator_spec.rb                 (NEW: ~1 example)
    scaffold_generator_spec.rb                (NEW: ~5 examples)
```

---

## Notes

- All tests should use `transactional_fixtures` (already configured)
- Tests document known bugs via explicit expectations on current (broken) behavior, marked with comments referencing ANALYSIS.md section numbers
- Regression tests in Phase 5 can use RSpec `pending` to document bugs that should be fixed later
- Generator specs are lowest priority since generated code is templates, not runtime logic
- The `shoulda-matchers` dependency must be added to Gemfile before running specs (it's already used but undeclared)
