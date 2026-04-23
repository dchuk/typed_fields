# frozen_string_literal: true

module TypedFields
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
  end
end
