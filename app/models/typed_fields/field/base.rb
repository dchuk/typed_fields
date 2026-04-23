# frozen_string_literal: true

module TypedFields
  module Field
    class Base < ApplicationRecord
      self.table_name = "typed_fields"

      include TypedFields::ColumnMapping

      # ── Associations ──

      belongs_to :section,
        class_name: "TypedFields::Section",
        optional: true,
        inverse_of: :fields

      has_many :values,
        class_name: "TypedFields::Value",
        foreign_key: :field_id,
        inverse_of: :field,
        dependent: :destroy

      has_many :field_options,
        class_name: "TypedFields::Option",
        foreign_key: :field_id,
        inverse_of: :field,
        dependent: :destroy

      # ── Validations ──

      RESERVED_NAMES = %w[id type class created_at updated_at].freeze

      validates :name, presence: true, uniqueness: { scope: %i[entity_type scope] }
      validates :name, exclusion: { in: RESERVED_NAMES, message: "is reserved" }
      validates :type, presence: true
      validates :entity_type, presence: true
      validate :validate_default_value
      validate :validate_type_allowed_for_entity

      # ── Scopes ──

      scope :for_entity, ->(entity_type, scope: nil) {
        scopes = [scope, nil].uniq
        where(entity_type: entity_type, scope: scopes)
      }

      scope :sorted, -> { order(sort_order: :asc, name: :asc) }
      scope :required_fields, -> { where(required: true) }

      # ── Default value handling ──
      # Stored in default_value_meta as {"v": <raw_value>} so the jsonb
      # column can hold any type's default without an extra typed column.

      def default_value
        cast_value(default_value_meta["v"])
      end

      def default_value=(val)
        default_value_meta["v"] = val
      end

      # ── Type casting ──
      # Subclasses can override for custom casting logic.
      # For most types, Rails' column type handles it, so this is
      # just a pass-through. Override for things like enum validation.

      def cast_value(raw)
        raw
      end

      # ── Introspection ──

      def field_type_name
        self.class.name.demodulize.underscore
      end

      def array_field?
        false
      end

      def optionable?
        false
      end

      # Allowed option values for select/multi-select validation.
      # Queries fresh each time to avoid stale cache across instances.
      # For bulk validation, callers should preload field_options.
      def allowed_option_values
        field_options.pluck(:value)
      end

      # Kept for backward compatibility but now a no-op since we don't cache.
      def clear_option_cache!
        # no-op
      end

      # Track whether the last cast_value call encountered unparseable input.
      # The Value model checks this to distinguish "blank" from "invalid".
      # Thread-safe: each call to cast_value resets the flag first.
      def last_cast_invalid
        @last_cast_invalid
      end

      private

      def mark_cast_invalid!
        @last_cast_invalid = true
      end

      def reset_cast_state!
        @last_cast_invalid = false
      end

      def validate_default_value
        return if default_value_meta.blank? || !default_value_meta.key?("v")
        raw = default_value_meta["v"]
        return if raw.nil?

        cast_value(raw)
        if last_cast_invalid
          errors.add(:default_value, "is not valid for this field type")
        end
      ensure
        reset_cast_state!
      end

      # Enforces type restrictions set via `has_typed_fields types: [...]`.
      # Skips if the entity type isn't registered (e.g., in console before
      # models are loaded) — this is intentional fail-open behavior since
      # unregistered entity types have no restrictions to enforce.
      def validate_type_allowed_for_entity
        return unless entity_type.present? && type.present?
        return unless TypedFields.registry.entity_types.include?(entity_type)
        return if TypedFields.registry.type_allowed?(entity_type, self.class)

        errors.add(:type, "#{field_type_name} is not allowed for #{entity_type}")
      end
    end
  end
end
