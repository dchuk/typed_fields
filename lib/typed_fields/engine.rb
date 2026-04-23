# frozen_string_literal: true

module TypedFields
  class Engine < ::Rails::Engine
    isolate_namespace TypedFields

    initializer "typed_fields.autoload" do
      require_relative "column_mapping"
      require_relative "config"
      require_relative "registry"
    end

    # Make `has_typed_fields` available on all ActiveRecord models
    initializer "typed_fields.active_record" do
      ActiveSupport.on_load(:active_record) do
        include TypedFields::HasTypedFields
      end
    end
  end
end
