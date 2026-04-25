# frozen_string_literal: true

require "rails/generators"

module TypedEAV
  module Generators
    class InstallGenerator < ::Rails::Generators::Base
      source_root File.expand_path("../../..", __dir__)

      desc "Copies TypedEAV migrations to your application"

      def copy_migrations
        rake "typed_eav:install:migrations"
      end

      def show_post_install
        say ""
        say "TypedEAV installed. Next steps:", :green
        say ""
        say "  1. Run migrations:  bin/rails db:migrate"
        say "  2. Add to a model:  has_typed_eav"
        say "  3. Generate scaffold: bin/rails generate typed_eav:scaffold"
        say ""
      end
    end
  end
end
