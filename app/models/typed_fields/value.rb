# frozen_string_literal: true

require "timeout"

module TypedFields
  class Value < ApplicationRecord
    self.table_name = "typed_field_values"

    # ── Associations ──

    belongs_to :entity, polymorphic: true, inverse_of: :typed_values
    belongs_to :field,
      class_name: "TypedFields::Field::Base",
      foreign_key: :field_id,
      inverse_of: :values

    # ── Validations ──

    validates :field, uniqueness: { scope: %i[entity_type entity_id] }
    validate :validate_value
    validate :validate_entity_matches_field
    validate :validate_json_size

    # ── Value access ──
    #
    # The magic here is that we delegate to the correct typed column
    # based on what the field type declares. ActiveRecord handles all
    # casting through the column's type (schema-inferred).
    #
    # So `value = "42"` on an integer field writes 42 to integer_value,
    # and `value` reads it back as a Ruby Integer. No custom caster needed
    # for storage - the database column type IS the caster.

    def value
      return nil unless field
      self[value_column]
    end

    def value=(val)
      if field
        # Cast through the field type, then write to the native column.
        # Rails will further cast via the column type on save.
        self[value_column] = field.cast_value(val)
      else
        # Field not yet assigned - stash for later
        @pending_value = val
      end
    end

    # Which column this value lives in
    def value_column
      field.class.value_column
    end

    # ── Callbacks ──

    after_initialize :apply_pending_value

    private

    def apply_pending_value
      return unless @pending_value && field
      self.value = @pending_value
      @pending_value = nil
    end

    def validate_value
      return unless field

      # Check if the last cast produced an invalid result, then reset
      # to prevent flag leakage across multiple validations on the same field.
      cast_was_invalid = field.last_cast_invalid
      field.send(:reset_cast_state!) if cast_was_invalid
      if cast_was_invalid
        errors.add(:value, :invalid)
        return
      end

      val = value

      # Required check
      if field.required? && val.nil?
        errors.add(:value, :blank)
        return
      end

      return if val.nil?

      # Field-type-specific validations
      validate_constraints(val)
    end

    def validate_constraints(val)
      opts = field.options&.with_indifferent_access || {}

      case field
      when Field::Text, Field::LongText
        validate_length(val, opts)
        validate_pattern(val, opts) if opts[:pattern].present?
      when Field::Email
        validate_length(val, opts)
        validate_pattern(val, opts) if opts[:pattern].present?
        validate_email_format(val)
      when Field::Url
        validate_length(val, opts)
        validate_pattern(val, opts) if opts[:pattern].present?
        validate_url_format(val)
      when Field::Integer, Field::Decimal
        validate_range(val, opts)
      when Field::Date
        validate_date_range(val, opts)
      when Field::DateTime
        validate_datetime_range(val, opts)
      when Field::Select
        validate_option_inclusion(val)
      when Field::MultiSelect
        validate_multi_option_inclusion(val)
        validate_array_size(val, opts)
      when Field::IntegerArray, Field::DecimalArray, Field::TextArray, Field::DateArray
        validate_array_size(val, opts)
      end
    end

    def validate_length(val, opts)
      str = val.to_s
      if opts[:min_length] && str.length < opts[:min_length].to_i
        errors.add(:value, :too_short, count: opts[:min_length])
      end
      if opts[:max_length] && str.length > opts[:max_length].to_i
        errors.add(:value, :too_long, count: opts[:max_length])
      end
    end

    def validate_pattern(val, opts)
      pattern = opts[:pattern]
      return if pattern.blank?

      matched = Timeout.timeout(1) { Regexp.new(pattern).match?(val.to_s) }
      errors.add(:value, :invalid) unless matched
    rescue RegexpError
      errors.add(:value, "has an invalid pattern configured")
    rescue Timeout::Error
      errors.add(:value, "pattern validation timed out")
    end

    def validate_range(val, opts)
      if opts[:min] && val < opts[:min].to_d
        errors.add(:value, :greater_than_or_equal_to, count: opts[:min])
      end
      if opts[:max] && val > opts[:max].to_d
        errors.add(:value, :less_than_or_equal_to, count: opts[:max])
      end
    end

    def validate_date_range(val, opts)
      if opts[:min_date]
        min = ::Date.parse(opts[:min_date])
        errors.add(:value, :greater_than_or_equal_to, count: opts[:min_date]) if val < min
      end
      if opts[:max_date]
        max = ::Date.parse(opts[:max_date])
        errors.add(:value, :less_than_or_equal_to, count: opts[:max_date]) if val > max
      end
    rescue ::Date::Error
      errors.add(:base, "field has invalid date configuration")
    end

    def validate_datetime_range(val, opts)
      if opts[:min_datetime]
        min = ::Time.zone.parse(opts[:min_datetime])
        errors.add(:value, :greater_than_or_equal_to, count: opts[:min_datetime]) if val < min
      end
      if opts[:max_datetime]
        max = ::Time.zone.parse(opts[:max_datetime])
        errors.add(:value, :less_than_or_equal_to, count: opts[:max_datetime]) if val > max
      end
    rescue ArgumentError
      errors.add(:base, "field has invalid datetime configuration")
    end

    def validate_option_inclusion(val)
      return if field.allowed_option_values.include?(val&.to_s)
      errors.add(:value, :inclusion)
    end

    def validate_multi_option_inclusion(val)
      invalid = Array(val).map(&:to_s) - field.allowed_option_values
      errors.add(:value, :inclusion) if invalid.any?
    end

    def validate_array_size(val, opts)
      arr = Array(val)
      if opts[:min_size] && arr.size < opts[:min_size].to_i
        errors.add(:value, :too_short, count: opts[:min_size])
      end
      if opts[:max_size] && arr.size > opts[:max_size].to_i
        errors.add(:value, :too_long, count: opts[:max_size])
      end
    end

    def validate_email_format(val)
      return unless field.respond_to?(:email_format_valid?)
      return if field.email_format_valid?(val)
      errors.add(:value, "is not a valid email address")
    end

    def validate_url_format(val)
      return unless field.respond_to?(:url_format_valid?)
      return if field.url_format_valid?(val)
      errors.add(:value, "is not a valid URL")
    end

    MAX_JSON_BYTES = 1_000_000 # 1MB

    def validate_json_size
      return unless field && value_column == :json_value
      val = self[:json_value]
      return if val.nil?

      if val.to_json.bytesize > MAX_JSON_BYTES
        errors.add(:value, "is too large (maximum 1MB)")
      end
    end

    def validate_entity_matches_field
      return unless field && entity_type
      return if entity_type == field.entity_type

      errors.add(:entity, :invalid)
    end
  end
end
