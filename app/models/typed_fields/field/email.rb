# frozen_string_literal: true

module TypedFields
  module Field
    class Email < Base
      value_column :string_value

      store_accessor :options, :min_length, :max_length, :pattern
      validate :validate_pattern_syntax

      EMAIL_FORMAT = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

      def cast_value(raw)
        raw&.to_s&.strip&.downcase
      end

      def email_format_valid?(val)
        EMAIL_FORMAT.match?(val)
      end

      private

      def validate_pattern_syntax
        return if pattern.blank?
        Regexp.new(pattern)
      rescue RegexpError => e
        errors.add(:pattern, "is invalid: #{e.message}")
      end
    end
  end
end
