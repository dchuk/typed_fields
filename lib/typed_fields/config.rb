# frozen_string_literal: true

module TypedFields
  class Config
    include Singleton

    # Map of type names to their STI class names.
    # Add custom types here via TypedFields.configure.
    BUILTIN_FIELD_TYPES = {
      text:          "TypedFields::Field::Text",
      long_text:     "TypedFields::Field::LongText",
      integer:       "TypedFields::Field::Integer",
      decimal:       "TypedFields::Field::Decimal",
      boolean:       "TypedFields::Field::Boolean",
      date:          "TypedFields::Field::Date",
      date_time:     "TypedFields::Field::DateTime",
      select:        "TypedFields::Field::Select",
      multi_select:  "TypedFields::Field::MultiSelect",
      integer_array: "TypedFields::Field::IntegerArray",
      decimal_array: "TypedFields::Field::DecimalArray",
      text_array:    "TypedFields::Field::TextArray",
      date_array:    "TypedFields::Field::DateArray",
      email:         "TypedFields::Field::Email",
      url:           "TypedFields::Field::Url",
      color:         "TypedFields::Field::Color",
      json:          "TypedFields::Field::Json",
    }.freeze

    attr_accessor :field_types

    def initialize
      @field_types = BUILTIN_FIELD_TYPES.dup
    end

    # Register a custom field type
    #
    #   TypedFields.configure do |c|
    #     c.register_field_type :phone, "MyApp::Fields::Phone"
    #   end
    def register_field_type(name, class_name)
      @field_types[name.to_sym] = class_name
    end

    # Resolve type name to class
    def field_class_for(type_name)
      class_name = @field_types[type_name.to_sym]
      raise ArgumentError, "Unknown field type: #{type_name}" unless class_name
      class_name.constantize
    end

    # All registered type names
    def type_names
      @field_types.keys
    end
  end
end
