# frozen_string_literal: true

require "bundler/gem_tasks"

APP_RAKEFILE = File.expand_path("spec/dummy/Rakefile", __dir__)

begin
  require "rspec/core/rake_task"
  RSpec::Core::RakeTask.new(:spec)
  task default: :spec
rescue LoadError
  # rspec not available
end
