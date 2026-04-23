# frozen_string_literal: true

class Contact < ActiveRecord::Base
  has_typed_fields scope_method: :tenant_id
end

class Product < ActiveRecord::Base
  has_typed_fields types: %i[text integer decimal boolean]
end
