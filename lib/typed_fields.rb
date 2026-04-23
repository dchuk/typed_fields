# frozen_string_literal: true

require_relative "typed_fields/version"
require_relative "typed_fields/engine"

module TypedFields
  extend ActiveSupport::Autoload

  autoload :Config
  autoload :Registry
  autoload :HasTypedFields
  autoload :QueryBuilder

  class << self
    def config
      yield Config.instance if block_given?
      Config.instance
    end

    alias_method :configure, :config

    def registry = Registry.instance
  end
end
