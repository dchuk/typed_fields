# frozen_string_literal: true

module TypedFields
  module Field
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
  end
end
