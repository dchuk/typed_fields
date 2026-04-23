# frozen_string_literal: true

require "rails/generators"

module TypedFields
  module Generators
    class InstallGenerator < ::Rails::Generators::Base
      source_root File.expand_path("../../..", __dir__)

      desc "Copies TypedFields migrations to your application"

      def copy_migrations
        rake "typed_fields:install:migrations"
      end

      def show_post_install
        say ""
        say "TypedFields installed. Next steps:", :green
        say ""
        say "  1. Run migrations:  bin/rails db:migrate"
        say "  2. Add to a model:  has_typed_fields"
        say "  3. Generate scaffold: bin/rails generate typed_fields:scaffold"
        say ""
      end
    end
  end
end
