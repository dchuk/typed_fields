# frozen_string_literal: true

require "uri"

module TypedFields
  module Field
    class Url < Base
      value_column :string_value

      store_accessor :options, :min_length, :max_length, :pattern
      validate :validate_pattern_syntax

      URL_FORMAT = /\A#{URI::DEFAULT_PARSER.make_regexp(%w[http https])}\z/

      def cast_value(raw)
        raw&.to_s&.strip
      end

      def url_format_valid?(val)
        URL_FORMAT.match?(val)
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
