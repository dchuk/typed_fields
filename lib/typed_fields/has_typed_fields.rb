# frozen_string_literal: true

module TypedFields
  # Include this in any ActiveRecord model to give it typed custom fields.
  #
  #   class Contact < ApplicationRecord
  #     has_typed_fields
  #   end
  #
  #   class Contact < ApplicationRecord
  #     has_typed_fields scope_method: :tenant_id
  #   end
  #
  # This gives you:
  #
  #   # Reading/writing values
  #   contact.typed_values                    # => collection
  #   contact.initialize_typed_values         # => builds missing values with defaults
  #   contact.typed_fields_attributes = [...]  # => bulk assign via nested attributes
  #
  #   # Querying (the good stuff)
  #   Contact.where_typed_fields(
  #     { name: "age", op: :gt, value: 21 },
  #     { name: "status", op: :eq, value: "active" }
  #   )
  #
  #   # Or the short form with a hash:
  #   Contact.with_field("age", :gt, 21)
  #   Contact.with_field("status", "active")  # :eq is default
  #
  module HasTypedFields
    extend ActiveSupport::Concern

    class_methods do
      # Register this model as having typed fields.
      #
      # Options:
      #   scope_method: - method name that returns a scope value (e.g. :tenant_id)
      #                   for multi-tenant field isolation
      #   types:        - restrict which field types are allowed (array of symbols)
      #                   e.g. [:text, :integer, :boolean]
      #                   default: all types
      def has_typed_fields(scope_method: nil, types: nil)
        cattr_accessor :typed_fields_scope_method, default: scope_method
        cattr_accessor :allowed_typed_field_types, default: types

        include InstanceMethods
        extend ClassQueryMethods

        has_many :typed_values,
          class_name: "TypedFields::Value",
          as: :entity,
          inverse_of: :entity,
          autosave: true,
          dependent: :destroy

        accepts_nested_attributes_for :typed_values, allow_destroy: true

        # Register with the global registry
        TypedFields.registry.register(name, types: types)
      end
    end

    # ──────────────────────────────────────────────────
    # Class-level query methods
    # ──────────────────────────────────────────────────
    module ClassQueryMethods
      # Query by custom field values. Accepts an array of filter hashes
      # or a hash of hashes (from form params).
      #
      # Each filter needs:
      #   :name or :n    - the field name
      #   :op or :operator - the operator (default: :eq)
      #   :value or :v   - the comparison value
      #
      #   Contact.where_typed_fields(
      #     { name: "age", op: :gt, value: 21 },
      #     { name: "city", value: "Portland" }   # op defaults to :eq
      #   )
      #
      def where_typed_fields(*filters, scope: nil)
        # Normalize input: accept splat args, a single array, a single filter hash,
        # a hash-of-hashes (form params), or ActionController::Parameters.
        filters = filters.map { |f| f.respond_to?(:to_unsafe_h) ? f.to_unsafe_h : f }

        if filters.size == 1
          inner = filters.first
          inner = inner.to_unsafe_h if inner.respond_to?(:to_unsafe_h)

          if inner.is_a?(Array)
            filters = inner
          elsif inner.is_a?(Hash)
            # A single filter hash has keys like :name/:n, :op, :value/:v.
            # A hash-of-hashes (form params) has values that are all hashes.
            filter_keys = %i[name n op operator value v].map(&:to_s)
            if inner.keys.any? { |k| filter_keys.include?(k.to_s) }
              filters = [inner]
            else
              filters = inner.values
            end
          end
        end

        filters = Array(filters)

        fields_by_name = typed_field_definitions(scope: scope).index_by(&:name)

        filters.inject(all) do |query, filter|
          filter = filter.to_h.with_indifferent_access

          name     = filter[:n] || filter[:name]
          operator = (filter[:op] || filter[:operator] || :eq).to_sym
          value    = filter.key?(:v) ? filter[:v] : filter[:value]

          field = fields_by_name[name.to_s]
          unless field
            raise ArgumentError, "Unknown typed field '#{name}' for #{self.name}. " \
              "Available fields: #{fields_by_name.keys.join(', ')}"
          end

          matching_ids = TypedFields::QueryBuilder.entity_ids(field, operator, value)
          query.where(id: matching_ids)
        end
      end

      # Shorthand for single-field queries.
      #
      #   Contact.with_field("age", :gt, 21)
      #   Contact.with_field("active", true)      # op defaults to :eq
      #   Contact.with_field("name", :contains, "smith")
      #
      def with_field(name, operator_or_value = nil, value = nil, scope: nil)
        if value.nil? && !operator_or_value.is_a?(Symbol)
          # Two-arg form: with_field("name", "value") implies :eq
          where_typed_fields({ name: name, op: :eq, value: operator_or_value }, scope: scope)
        else
          where_typed_fields({ name: name, op: operator_or_value, value: value }, scope: scope)
        end
      end

      # Returns field definitions for this entity type.
      def typed_field_definitions(scope: nil)
        TypedFields::Field::Base.for_entity(name, scope: scope)
      end
    end

    # ──────────────────────────────────────────────────
    # Instance methods
    # ──────────────────────────────────────────────────
    module InstanceMethods
      # The field definitions available for this record
      def typed_field_definitions
        self.class.typed_field_definitions(scope: typed_fields_scope)
      end

      # Current scope value (for multi-tenant)
      def typed_fields_scope
        return nil unless self.class.typed_fields_scope_method
        send(self.class.typed_fields_scope_method)&.to_s
      end

      # Build missing values with defaults for all available fields.
      # Useful in forms to show all fields even when no value exists yet.
      def initialize_typed_values
        existing_field_ids = typed_values.loaded? ? typed_values.map(&:field_id) : typed_values.pluck(:field_id)

        typed_field_definitions.each do |field|
          next if existing_field_ids.include?(field.id)
          typed_values.build(field: field, value: field.default_value)
        end

        typed_values
      end

      # Bulk assign values by field name.
      #
      #   record.typed_fields_attributes = [
      #     { name: "age", value: 30 },
      #     { name: "email", value: "test@example.com" },
      #     { name: "old_field", _destroy: true }
      #   ]
      #
      def typed_fields_attributes=(attributes)
        attributes = attributes.to_h if attributes.respond_to?(:permitted?)
        attributes = attributes.values if attributes.is_a?(Hash)
        attributes = Array(attributes)

        fields_by_name = typed_field_definitions.index_by(&:name)
        values_by_field_id = typed_values.index_by(&:field_id)

        nested = attributes.filter_map do |attrs|
          attrs = attrs.to_h.with_indifferent_access

          field = fields_by_name[attrs[:name]]
          next unless field

          # Enforce type restrictions
          allowed = self.class.allowed_typed_field_types
          if allowed && !allowed.map(&:to_s).include?(field.field_type_name)
            next
          end

          existing = values_by_field_id[field.id]

          if ActiveRecord::Type::Boolean.new.cast(attrs[:_destroy])
            { id: existing&.id, _destroy: true }
          elsif existing
            { id: existing.id, value: attrs[:value] }
          else
            typed_values.build(field: field, value: attrs[:value])
            nil # build already added it, skip nested_attributes
          end
        end.compact

        self.typed_values_attributes = nested if nested.any?
      end

      alias_method :typed_fields=, :typed_fields_attributes=

      # Get a specific field's value by name
      def typed_field_value(name)
        tv = typed_values.includes(:field).detect { |v| v.field.name == name.to_s }
        tv&.value
      end

      # Set a specific field's value by name
      def set_typed_field_value(name, value)
        field = typed_field_definitions.find_by(name: name.to_s)
        return unless field

        existing = typed_values.detect { |v| v.field_id == field.id }
        if existing
          existing.value = value
        else
          typed_values.build(field: field, value: value)
        end
      end

      # Hash of all field values: { "field_name" => value, ... }
      def typed_fields_hash
        typed_values.includes(:field).each_with_object({}) do |tv, hash|
          hash[tv.field.name] = tv.value
        end
      end
    end
  end
end
