# frozen_string_literal: true

module TypedFields
  # Replaces the per-type Finder class hierarchy from active_fields.
  #
  # Because values live in native typed columns, ActiveRecord already knows
  # the column types from the schema. Arel predicates (eq, gt, lt, matches, etc.)
  # automatically go through the column's ActiveRecord::Type for casting.
  #
  # This means:
  #   where(integer_value: "42")  ->  Rails casts "42" to 42 automatically
  #   arel[:date_value].gt(value) ->  Rails casts string dates to Date objects
  #
  # No manual CAST() calls. No per-type caster classes for queries.
  # One module handles all field types.
  #
  # Usage:
  #   QueryBuilder.filter(field, :gt, 42)
  #   # => ActiveRecord::Relation scoped to matching values
  #
  #   QueryBuilder.filter(field, :contains, "hello")
  #   # => ILIKE query against the field's string_value column
  #
  class QueryBuilder
    class << self
      # Returns an ActiveRecord::Relation of TypedFields::Value records
      # matching the given field, operator, and comparison value.
      #
      # The relation is suitable for subquery use:
      #   Model.where(id: QueryBuilder.filter(field, :gt, 5).select(:entity_id))
      def filter(field, operator, value)
        col = field.class.value_column
        operator = operator.to_sym

        # Validate operator is supported by this field type
        supported = field.class.supported_operators
        unless supported.include?(operator)
          raise ArgumentError,
            "Operator :#{operator} is not supported for #{field.class.name}. " \
            "Supported operators: #{supported.map { |o| ":#{o}" }.join(', ')}"
        end

        arel_col = values_table[col]

        base = value_scope(field)

        case operator
        when :eq
          eq_predicate(base, arel_col, col, value)
        when :not_eq
          not_eq_predicate(base, arel_col, col, value)
        when :gt
          base.where(arel_col.gt(value))
        when :gteq
          base.where(arel_col.gteq(value))
        when :lt
          base.where(arel_col.lt(value))
        when :lteq
          base.where(arel_col.lteq(value))
        when :between
          raise ArgumentError, ":between expects a Range or two-element Array" unless value.respond_to?(:first) && value.respond_to?(:last)
          base.where(arel_col.between(value.first..value.last))
        when :contains
          base.where(arel_col.matches("%#{sanitize_like(value)}%"))
        when :not_contains
          base.where(arel_col.does_not_match("%#{sanitize_like(value)}%"))
        when :starts_with
          base.where(arel_col.matches("#{sanitize_like(value)}%"))
        when :ends_with
          base.where(arel_col.matches("%#{sanitize_like(value)}"))
        when :is_null
          base.where(col => nil)
        when :is_not_null
          base.where.not(col => nil)
        when :any_eq
          # For json_value arrays: contains the given element
          base.where("#{col} @> ?", [value].to_json)
        when :all_eq
          # For json_value arrays: contains all given elements
          base.where("#{col} @> ?", Array(value).to_json)
        else
          raise ArgumentError, "Unhandled operator: #{operator}"
        end
      end

      # Convenience: returns entity IDs matching the filter.
      # Useful for subqueries: Model.where(id: QueryBuilder.entity_ids(field, :gt, 5))
      def entity_ids(field, operator, value)
        filter(field, operator, value).distinct.select(:entity_id)
      end

      private

      def values_table
        TypedFields::Value.arel_table
      end

      # Base scope: values for this specific field
      def value_scope(field)
        TypedFields::Value.where(field: field)
      end

      # NULL-safe equality: `= value` for non-nil, `IS NULL` for nil,
      # `IS TRUE/FALSE` for booleans
      def eq_predicate(base, arel_col, col, value)
        if value.nil?
          base.where(col => nil)
        elsif value.is_a?(TrueClass) || value.is_a?(FalseClass)
          # Boolean columns: use IS TRUE / IS FALSE for clarity
          base.where(col => value)
        else
          base.where(col => value)
        end
      end

      # NULL-safe inequality: includes NULL rows (they're "not equal" to any value)
      def not_eq_predicate(base, arel_col, col, value)
        if value.nil?
          base.where.not(col => nil)
        else
          # NOT col = value OR col IS NULL
          # Without the OR, NULLs are excluded (SQL tri-valued logic)
          base.where(arel_col.not_eq(value).or(arel_col.eq(nil)))
        end
      end

      def sanitize_like(value)
        value.to_s.gsub(/[%_\\]/) { |m| "\\#{m}" }
      end
    end
  end
end
