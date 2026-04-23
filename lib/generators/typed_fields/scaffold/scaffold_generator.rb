# frozen_string_literal: true

require "rails/generators"

module TypedFields
  module Generators
    class ScaffoldGenerator < ::Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Generates controller, views, helper, and Stimulus controllers for managing typed fields"

      def copy_controller
        copy_file "controllers/typed_fields_controller.rb", "app/controllers/typed_fields_controller.rb"
        copy_file "controllers/concerns/typed_fields_controller_concern.rb",
          "app/controllers/concerns/typed_fields_controller_concern.rb"
      end

      def copy_helper
        copy_file "helpers/typed_fields_helper.rb", "app/helpers/typed_fields_helper.rb"
      end

      def copy_views
        directory "views", "app/views"
      end

      def copy_javascript
        directory "javascript/controllers", "app/javascript/controllers"
      end

      def add_routes
        route <<~ROUTES
          resources :typed_fields do
            resources :field_options, controller: "typed_fields", only: [] do
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
        say "Scaffold generated. You can now manage fields at /typed_fields", :green
        say ""
        say "Next steps:", :yellow
        say ""
        say "  1. Include the concern in controllers that use typed-field",
           :yellow
        say "     search params (your host model's controller, usually):",
           :yellow
        say ""
        say "       class ProductsController < ApplicationController"
        say "         include TypedFieldsControllerConcern"
        say "         helper TypedFieldsHelper"
        say "         ..."
        say "       end"
        say ""
        say "  2. Render typed field inputs in your entity forms:", :yellow
        say ""
        say '       <%= render_typed_value_inputs(form: f, record: @record) %>'
        say ""
        say "  3. Add a search form to filter entities by typed fields:",
           :yellow
        say ""
        say '       <%= render_typed_fields_search(fields: Model.typed_field_definitions, url: search_path) %>'
        say ""
      end
    end
  end
end
