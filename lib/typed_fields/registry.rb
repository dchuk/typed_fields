# frozen_string_literal: true

module TypedFields
  class Registry
    include Singleton

    def initialize
      @entities = {}
    end

    # Register an entity type with optional type restrictions
    def register(entity_type, types: nil)
      @entities[entity_type] = { types: types }
    end

    # All registered entity type names
    def entity_types
      @entities.keys
    end

    # Which field type names are allowed for a given entity
    def allowed_types_for(entity_type)
      entry = @entities[entity_type]
      return nil unless entry
      entry[:types]
    end

    # Check if a field type is allowed for an entity
    def type_allowed?(entity_type, field_type_class)
      allowed = allowed_types_for(entity_type)
      return true if allowed.nil? # nil means all types allowed

      type_name = field_type_class.name.demodulize.underscore.to_sym
      allowed.include?(type_name)
    end

    def reset!
      @entities.clear
    end
  end
end
