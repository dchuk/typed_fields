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

    # Exclude types.rb from Zeitwerk (it defines multiple classes in one file)
    # and require it once for STI resolution.
    initializer "typed_fields.zeitwerk_ignore" do
      Rails.autoloaders.main.ignore(
        TypedFields::Engine.root.join("app/models/typed_fields/field/types.rb")
      )
    end

    config.to_prepare do
      # Eager-load field type classes so STI can resolve them.
      # types.rb is ignored by Zeitwerk (multiple classes in one file),
      # so we require it once here. `require` is idempotent and won't
      # re-execute, avoiding duplicate validators/accessors on reload.
      require TypedFields::Engine.root.join("app/models/typed_fields/field/types.rb").to_s
    end
  end
end
