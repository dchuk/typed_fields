# frozen_string_literal: true

class TypedFieldsController < ApplicationController
  # WARNING: This controller has NO authorization. Before using in production,
  # add authorization (e.g., Pundit, CanCanCan) to restrict who can manage
  # field definitions. Without authorization, any authenticated user can
  # create, modify, and delete field definitions for all entity types.

  before_action :set_field, only: %i[show edit update destroy]

  def index
    # NOTE: This lists ALL field definitions across all entity types and scopes.
    # In multi-tenant apps, filter by scope to prevent cross-tenant visibility:
    #   @fields = TypedFields::Field::Base.where(scope: [current_tenant_id, nil]).order(...)
    @fields = TypedFields::Field::Base.order(:entity_type, :scope, :sort_order, :name)
  end

  def show; end

  def new
    type_class = resolve_type_class(params[:type])
    @field = type_class.new
  end

  def edit; end

  def create
    type_class = resolve_type_class(params.dig(:typed_field, :field_type) || params[:type])
    @field = type_class.new(field_params(type_class, creating: true))

    if @field.save
      redirect_to edit_typed_field_path(@field), status: :see_other,
        notice: "Field created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @field.update(field_params(@field.class, creating: false))
      redirect_to edit_typed_field_path(@field), status: :see_other,
        notice: "Field updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @field.destroy!
    redirect_to typed_fields_path, status: :see_other, notice: "Field deleted."
  end

  # POST /typed_fields/:typed_field_id/field_options/add_option
  def add_option
    @field = TypedFields::Field::Base.find(params[:typed_field_id])
    @field.field_options.create!(
      label: params[:option_label],
      value: params[:option_value],
      sort_order: @field.field_options.count + 1
    )
    redirect_to edit_typed_field_path(@field), status: :see_other
  end

  # DELETE /typed_fields/:typed_field_id/field_options/remove_option
  def remove_option
    @field = TypedFields::Field::Base.find(params[:typed_field_id])
    @field.field_options.find(params[:option_id]).destroy!
    redirect_to edit_typed_field_path(@field), status: :see_other
  end

  private

  def set_field
    @field = TypedFields::Field::Base.find(params[:id])
  end

  def resolve_type_class(type_name)
    return TypedFields::Field::Text if type_name.blank?
    TypedFields.config.field_class_for(type_name)
  rescue ArgumentError
    TypedFields::Field::Text
  end

  # Data-driven permitted params based on what the field type exposes via store_accessor.
  # Much cleaner than a massive case statement per type.
  def field_params(type_class, creating:)
    base = %i[name required sort_order section_id]
    base += %i[entity_type scope] if creating

    # Collect store_accessor keys from options (min, max, min_length, etc.)
    option_keys = option_keys_for(type_class)

    # Default value is scalar for most types, array for array types
    if type_class.method_defined?(:array_field?) && type_class.allocate.array_field?
      permitted = base + option_keys + [default_value: []]
    else
      permitted = base + option_keys + %i[default_value]
    end

    params.require(:typed_field).permit(*permitted).tap do |attrs|
      attrs.transform_values! do |value|
        value.is_a?(Array) ? compact_array_param(value) : value
      end
    end
  end

  # Introspect which option keys the field type exposes
  def option_keys_for(type_class)
    return [] unless type_class.respond_to?(:stored_attributes)
    (type_class.stored_attributes[:options] || []).map(&:to_sym)
  rescue StandardError
    []
  end
end
