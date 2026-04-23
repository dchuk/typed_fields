# frozen_string_literal: true

module TypedFields
  module Field
    class Text < Base
      value_column :string_value

      store_accessor :options, :min_length, :max_length, :pattern

      validates :min_length, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
      validates :max_length, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
      validate :max_gte_min_length
      validate :validate_pattern_syntax

      def cast_value(raw)
        raw&.to_s
      end

      private

      def max_gte_min_length
        return unless min_length && max_length
        errors.add(:max_length, "must be >= min_length") if max_length < min_length
      end

      def validate_pattern_syntax
        return if pattern.blank?
        Regexp.new(pattern)
      rescue RegexpError => e
        errors.add(:pattern, "is invalid: #{e.message}")
      end
    end
  end
end
