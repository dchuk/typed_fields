# frozen_string_literal: true

module TypedEAV
  class Engine < ::Rails::Engine
    isolate_namespace TypedEAV

    initializer "typed_eav.autoload" do
      require_relative "column_mapping"
      require_relative "config"
      require_relative "registry"
    end

    # Make `has_typed_eav` available on all ActiveRecord models
    initializer "typed_eav.active_record" do
      ActiveSupport.on_load(:active_record) do
        include TypedEAV::HasTypedEAV
      end
    end
  end
end
