# frozen_string_literal: true

module TypedFields
  module Field
    class Color < Base
      value_column :string_value
      operators :eq, :not_eq, :is_null, :is_not_null

      def cast_value(raw)
        raw&.to_s&.strip&.downcase
      end
    end
  end
end
