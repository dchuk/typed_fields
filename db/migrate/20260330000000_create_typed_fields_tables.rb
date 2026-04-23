# frozen_string_literal: true

class CreateTypedFieldsTables < ActiveRecord::Migration[7.1]
  def change
    # ──────────────────────────────────────────────────
    # Sections: optional UI grouping for fields
    # ──────────────────────────────────────────────────
    create_table :typed_field_sections do |t|
      t.string :name, null: false
      t.string :code, null: false
      t.string :entity_type, null: false
      t.string :scope
      t.integer :sort_order
      t.boolean :active, null: false, default: true

      t.timestamps

      t.index %i[entity_type code scope], unique: true, name: "idx_tf_sections_unique"
      t.index %i[entity_type active], name: "idx_tf_sections_entity_active"
    end

    # ──────────────────────────────────────────────────
    # Field definitions (STI via `type` column)
    # ──────────────────────────────────────────────────
    create_table :typed_fields do |t|
      t.string :name, null: false
      t.string :type, null: false           # STI: TypedFields::Field::Integer, etc.
      t.string :entity_type, null: false     # polymorphic target model name
      t.string :scope                        # optional tenant/context scoping

      t.references :section, foreign_key: { to_table: :typed_field_sections, on_delete: :nullify }

      t.boolean :required, null: false, default: false
      t.integer :sort_order

      # Field-type-specific configuration (min/max/precision/allowed_values/etc.)
      t.jsonb :options, null: false, default: {}

      # Default value stored in the matching typed column format
      t.jsonb :default_value_meta, null: false, default: {}

      t.timestamps

      t.index %i[name entity_type scope], unique: true, name: "idx_tf_fields_unique"
      t.index :entity_type
    end

    # ──────────────────────────────────────────────────
    # Options for select/enum fields
    # ──────────────────────────────────────────────────
    create_table :typed_field_options do |t|
      t.references :field, null: false, foreign_key: { to_table: :typed_fields, on_delete: :cascade }
      t.string :label, null: false
      t.string :value, null: false
      t.integer :sort_order

      t.timestamps

      t.index %i[field_id value], unique: true, name: "idx_tf_options_field_value"
    end

    # ──────────────────────────────────────────────────
    # Values: one row per entity+field, typed columns
    # ──────────────────────────────────────────────────
    create_table :typed_field_values do |t|
      t.references :entity, polymorphic: true, null: false, index: true
      t.references :field, null: false, foreign_key: { to_table: :typed_fields, on_delete: :cascade }

      # ── Typed storage columns ──
      t.text     :string_value
      t.text     :text_value
      t.boolean  :boolean_value
      t.bigint   :integer_value
      t.decimal  :decimal_value, precision: 30, scale: 10
      t.date     :date_value
      t.datetime :datetime_value
      t.jsonb    :json_value

      t.timestamps

      # Uniqueness: one value per entity per field
      t.index %i[entity_type entity_id field_id],
        unique: true,
        name: "idx_tf_values_entity_field"

      # Query performance: field + typed column indexes (covering for index-only scans)
      t.index %i[field_id integer_value],  name: "idx_tf_values_field_int",  include: %i[entity_id entity_type]
      t.index %i[field_id decimal_value],  name: "idx_tf_values_field_dec",  include: %i[entity_id entity_type]
      t.index %i[field_id date_value],     name: "idx_tf_values_field_date", include: %i[entity_id entity_type]
      t.index %i[field_id datetime_value], name: "idx_tf_values_field_dt",   include: %i[entity_id entity_type]
      t.index %i[field_id boolean_value],  name: "idx_tf_values_field_bool", include: %i[entity_id entity_type]
      t.index %i[field_id string_value],   name: "idx_tf_values_field_str",
        using: :btree, opclass: { string_value: :text_pattern_ops }, include: %i[entity_id entity_type]
    end
  end
end
