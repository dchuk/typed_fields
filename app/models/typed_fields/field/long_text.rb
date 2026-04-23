# frozen_string_literal: true

module TypedFields
  module Field
    class LongText < Base
      value_column :text_value

      store_accessor :options, :min_length, :max_length

      def cast_value(raw)
        raw&.to_s
      end
    end
  end
end
