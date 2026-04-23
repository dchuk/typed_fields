# frozen_string_literal: true

require "uri"

module TypedFields
  module Field
    # ────────────────────────────────────────────────────
    # Scalar field types
    # ────────────────────────────────────────────────────

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

    class LongText < Base
      value_column :text_value

      store_accessor :options, :min_length, :max_length

      def cast_value(raw)
        raw&.to_s
      end
    end

    class Integer < Base
      value_column :integer_value

      store_accessor :options, :min, :max

      validates :max, comparison: { greater_than_or_equal_to: :min }, allow_nil: true, if: :min

      def cast_value(raw)
        return nil if raw.nil?
        reset_cast_state!
        str = raw.to_s.strip
        bd = BigDecimal(str, exception: false)
        if bd.nil?
          mark_cast_invalid! unless str.empty?
          return nil
        end
        # Mark invalid if input has a fractional part (not a clean integer)
        if bd.frac != 0
          mark_cast_invalid!
          return nil
        end
        bd.to_i
      end
    end

    class Decimal < Base
      value_column :decimal_value

      store_accessor :options, :min, :max, :precision_scale

      validates :max, comparison: { greater_than_or_equal_to: :min }, allow_nil: true, if: :min

      def cast_value(raw)
        return nil if raw.nil?
        reset_cast_state!
        result = BigDecimal(raw.to_s, exception: false)
        if result.nil? && !raw.to_s.strip.empty?
          mark_cast_invalid!
          return nil
        end
        return result unless result && precision_scale.present?
        scale = Integer(precision_scale, exception: false)
        return result unless scale && scale >= 0
        result.round(scale)
      end
    end

    class Boolean < Base
      value_column :boolean_value
      operators :eq, :is_null, :is_not_null

      def cast_value(raw)
        return nil if raw.nil?
        reset_cast_state!
        # Treat blank strings as nil (common from form submissions)
        return nil if raw.is_a?(String) && raw.strip.empty?
        # ActiveModel::Type::Boolean casts any non-recognized string to true.
        # Validate input is actually boolean-like before casting.
        recognized = %w[true false 1 0 t f yes no on off].freeze
        unless raw == true || raw == false || raw == 0 || raw == 1 || recognized.include?(raw.to_s.strip.downcase)
          mark_cast_invalid!
          return nil
        end
        ActiveModel::Type::Boolean.new.cast(raw)
      end
    end

    class Date < Base
      value_column :date_value

      store_accessor :options, :min_date, :max_date

      def cast_value(raw)
        return nil if raw.nil?
        reset_cast_state!
        raw.is_a?(::Date) ? raw : ::Date.parse(raw.to_s)
      rescue ::Date::Error
        mark_cast_invalid!
        nil
      end
    end

    class DateTime < Base
      value_column :datetime_value

      store_accessor :options, :min_datetime, :max_datetime

      def cast_value(raw)
        return nil if raw.nil?
        reset_cast_state!
        return raw if raw.is_a?(::Time)
        result = ::Time.zone.parse(raw.to_s)
        if result.nil? && !raw.to_s.strip.empty?
          mark_cast_invalid!
        end
        result
      rescue ArgumentError
        mark_cast_invalid!
        nil
      end
    end

    # ────────────────────────────────────────────────────
    # Choice field types (backed by typed_field_options)
    # ────────────────────────────────────────────────────

    class Select < Base
      value_column :string_value
      operators :eq, :not_eq, :is_null, :is_not_null

      def optionable? = true

      def allowed_values
        field_options.sorted.pluck(:value)
      end

      def cast_value(raw)
        raw&.to_s
      end
    end

    class MultiSelect < Base
      value_column :json_value
      operators :any_eq, :all_eq, :is_null, :is_not_null

      def optionable? = true
      def array_field? = true

      def allowed_values
        field_options.sorted.pluck(:value)
      end

      def cast_value(raw)
        return nil if raw.nil?
        Array(raw).map(&:to_s).presence
      end
    end

    # ────────────────────────────────────────────────────
    # Array field types (stored in json_value)
    # ────────────────────────────────────────────────────

    class IntegerArray < Base
      value_column :json_value
      operators :any_eq, :all_eq, :is_null, :is_not_null

      store_accessor :options, :min_size, :max_size, :min, :max

      def array_field? = true

      def cast_value(raw)
        return nil if raw.nil?
        reset_cast_state!
        elements = Array(raw)
        result = elements.filter_map { |v| BigDecimal(v.to_s, exception: false)&.to_i }
        mark_cast_invalid! if result.size < elements.size
        result.presence
      end
    end

    class DecimalArray < Base
      value_column :json_value
      operators :any_eq, :all_eq, :is_null, :is_not_null

      store_accessor :options, :min_size, :max_size

      def array_field? = true

      def cast_value(raw)
        return nil if raw.nil?
        reset_cast_state!
        elements = Array(raw)
        result = elements.filter_map { |v| BigDecimal(v.to_s, exception: false) }
        mark_cast_invalid! if result.size < elements.size
        result.presence
      end
    end

    class TextArray < Base
      value_column :json_value
      operators :any_eq, :all_eq, :contains, :is_null, :is_not_null

      store_accessor :options, :min_size, :max_size

      def array_field? = true

      def cast_value(raw)
        return nil if raw.nil?
        Array(raw).map(&:to_s).presence
      end
    end

    class DateArray < Base
      value_column :json_value
      operators :any_eq, :is_null, :is_not_null

      store_accessor :options, :min_size, :max_size

      def array_field? = true

      def cast_value(raw)
        return nil if raw.nil?
        reset_cast_state!
        elements = Array(raw)
        result = elements.filter_map { |v| ::Date.parse(v.to_s) rescue nil }
        mark_cast_invalid! if result.size < elements.size
        result.presence
      end
    end

    # ────────────────────────────────────────────────────
    # Specialty field types
    # ────────────────────────────────────────────────────

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

    class Color < Base
      value_column :string_value
      operators :eq, :not_eq, :is_null, :is_not_null

      def cast_value(raw)
        raw&.to_s&.strip&.downcase
      end
    end

    class Json < Base
      value_column :json_value
      operators :is_null, :is_not_null

      def cast_value(raw)
        raw
      end
    end
  end
end
