# frozen_string_literal: true

module TypedFields
  module Field
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
  end
end
