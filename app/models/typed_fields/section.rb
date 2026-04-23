# frozen_string_literal: true

module TypedFields
  class Section < ApplicationRecord
    self.table_name = "typed_field_sections"

    has_many :fields,
      class_name: "TypedFields::Field::Base",
      foreign_key: :section_id,
      inverse_of: :section,
      dependent: :nullify

    validates :name, presence: true
    validates :code, presence: true, uniqueness: { scope: %i[entity_type scope] }
    validates :entity_type, presence: true

    scope :active, -> { where(active: true) }
    scope :for_entity, ->(entity_type) { where(entity_type: entity_type) }
    scope :sorted, -> { order(sort_order: :asc, name: :asc) }
  end
end
