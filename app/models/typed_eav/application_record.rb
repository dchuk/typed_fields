# frozen_string_literal: true

module TypedEAV
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
  end
end
