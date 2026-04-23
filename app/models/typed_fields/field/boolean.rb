# frozen_string_literal: true

module TypedFields
  module Field
    class Boolean < Base
      value_column :boolean_value
      operators :eq, :is_null, :is_not_null

      def cast_value(raw)
        return nil if raw.nil?
        reset_cast_state!
        return nil if raw.is_a?(String) && raw.strip.empty?
        recognized = %w[true false 1 0 t f yes no on off].freeze
        unless raw == true || raw == false || raw == 0 || raw == 1 || recognized.include?(raw.to_s.strip.downcase)
          mark_cast_invalid!
          return nil
        end
        ActiveModel::Type::Boolean.new.cast(raw)
      end
    end
  end
end
