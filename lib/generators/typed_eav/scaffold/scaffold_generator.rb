# frozen_string_literal: true

require "rails/generators"

module TypedEAV
  module Generators
    class ScaffoldGenerator < ::Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Generates controller, views, helper, and Stimulus controllers for managing typed fields"

      def copy_controller
        copy_file "controllers/typed_eav_controller.rb", "app/controllers/typed_eav_controller.rb"
        copy_file "controllers/concerns/typed_eav_controller_concern.rb",
                  "app/controllers/concerns/typed_eav_controller_concern.rb"
      end

      def copy_initializer
        copy_file "config/initializers/typed_eav.rb", "config/initializers/typed_eav.rb"
      end

      def copy_helper
        copy_file "helpers/typed_eav_helper.rb", "app/helpers/typed_eav_helper.rb"
      end

      def copy_views
        directory "views", "app/views"
      end

      def copy_javascript
        directory "javascript/controllers", "app/javascript/controllers"
      end

      def add_routes
        route <<~ROUTES
          resources :typed_eav_fields, controller: "typed_eav" do
            resources :field_options, controller: "typed_eav", only: [] do
              collection do
                post :add_option
                delete :remove_option
              end
            end
          end
        ROUTES
      end

      def show_post_install
        say ""
        say "Scaffold generated. You can now manage fields at /typed_eav_fields", :green
        say ""
        say "Next steps:", :yellow
        say ""
        say "  1. WIRE THE ADMIN AUTH HOOK (security-critical):", :red
        say ""
        say "       Edit app/controllers/typed_eav_controller.rb and replace"
        say "       `authorize_typed_eav_admin!` with your auth check. The"
        say "       default returns `head :not_found` (fail-closed). Defining"
        say "       this method in ApplicationController does NOT override it."
        say ""
        say "         def authorize_typed_eav_admin!"
        say "           return if current_user&.admin?"
        say "           head :not_found"
        say "         end"
        say ""
        say "  2. Configure ambient scope resolution for multi-tenancy:", :yellow
        say ""
        say "       Edit config/initializers/typed_eav.rb and uncomment the"
        say "       scope_resolver pattern that matches your app (acts_as_tenant"
        say "       is auto-detected; no config needed if you use it)."
        say ""
        say "  3. Include the concern in controllers that use typed-field",
            :yellow
        say "     search params (your host model's controller, usually):",
            :yellow
        say ""
        say "       class ProductsController < ApplicationController"
        say "         include TypedEAVControllerConcern"
        say "         helper TypedEAVHelper"
        say "         ..."
        say "       end"
        say ""
        say "  4. Render typed field inputs in your entity forms:", :yellow
        say ""
        say "       <%= render_typed_value_inputs(form: f, record: @record) %>"
        say ""
        say "     Permit nested attributes in your host controller", :yellow
        say "     (the `value: []` form is required for array/multi-select):",
            :yellow
        say ""
        say "       params.require(:contact).permit("
        say "         :name,"
        say "         typed_values_attributes: ["
        say "           :id, :field_id, :_destroy, :value, { value: [] }"
        say "         ]"
        say "       )"
        say ""
        say "  5. Add a search form to filter entities by typed fields:",
            :yellow
        say ""
        say "       <%= render_typed_eav_search(fields: Model.typed_field_definitions, url: search_path) %>"
        say ""
      end
    end
  end
end
