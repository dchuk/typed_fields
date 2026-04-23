# frozen_string_literal: true

module TypedFieldsHelper
  # ─── Value Input Rendering ───────────────────────────────────

  # Render all typed field inputs for a record's form.
  #
  #   <%= render_typed_value_inputs(form: f, record: @contact) %>
  #
  def render_typed_value_inputs(form:, record:)
    parts = record.initialize_typed_values.sort_by { |v| v.field.sort_order || 0 }.map do |typed_value|
      render_typed_value_input(form: form, typed_value: typed_value)
    end
    safe_join(parts)
  end

  # Render a single typed value input within a fields_for block.
  #
  #   <%= form.fields_for :typed_values, record.initialize_typed_values do |vf| %>
  #     <%= render_typed_value_input(form: vf, typed_value: vf.object) %>
  #   <% end %>
  #
  def render_typed_value_input(form:, typed_value:)
    field = typed_value.field
    partial_name = value_input_partial(field)

    render partial: partial_name, locals: {
      form: form,
      typed_value: typed_value,
      field: field,
    }
  end

  # Render an array field with add/remove buttons (Stimulus-powered).
  #
  #   <%= render_array_field(form: f, name: :value, value: [1,2,3],
  #         field_method: :number_field, field_opts: { min: 0 }) %>
  #
  def render_array_field(form:, name:, value:, field_method:, field_opts: {})
    render partial: "shared/array_field", locals: {
      form: form,
      name: name,
      value: value,
      field_method: field_method,
      field_opts: field_opts,
    }
  end

  # ─── Field Management Form Rendering ─────────────────────────

  # Render the field definition form (for creating/editing field definitions).
  def render_typed_field_form(field:)
    partial = field_form_partial(field)
    render partial: partial, locals: { field: field }
  end

  # ─── Search/Filter Form Rendering ───────────────────────────

  # Render a search form for filtering entities by typed fields.
  #
  #   <%= render_typed_fields_search(fields: Contact.typed_field_definitions, url: contacts_path) %>
  #
  def render_typed_fields_search(fields:, url:)
    render partial: "typed_fields/finders/form", locals: {
      fields: fields,
      url: url,
    }
  end

  # Render a single finder input for a field.
  def render_typed_field_finder_input(form:, field:, template: false, selected: {})
    partial = finder_input_partial(field)
    operators = field.class.supported_operators

    render partial: partial, locals: {
      form: form,
      field: field,
      operators: operators,
      template: template,
      selected: selected,
    }
  end

  # ─── Operator Labels ────────────────────────────────────────

  def typed_field_operator_label(operator)
    {
      eq: "equals",
      not_eq: "does not equal",
      gt: "greater than",
      gteq: "greater than or equal",
      lt: "less than",
      lteq: "less than or equal",
      between: "between",
      contains: "contains",
      not_contains: "does not contain",
      starts_with: "starts with",
      ends_with: "ends with",
      any_eq: "includes",
      all_eq: "includes all",
      is_null: "is empty",
      is_not_null: "is not empty",
    }[operator.to_sym] || operator.to_s.humanize
  end

  private

  # Resolve the value input partial for a field type.
  # Falls back to a generic text input if no specific partial exists.
  def value_input_partial(field)
    type_key = field.field_type_name
    partial = "typed_fields/values/inputs/#{type_key}"
    lookup_context.exists?(partial, [], true) ? partial : "typed_fields/values/inputs/text"
  end

  # Resolve the field definition form partial.
  def field_form_partial(field)
    type_key = field.field_type_name
    partial = "typed_fields/forms/#{type_key}"
    lookup_context.exists?(partial, [], true) ? partial : "typed_fields/forms/base"
  end

  # Resolve the finder input partial.
  def finder_input_partial(field)
    type_key = field.field_type_name
    partial = "typed_fields/finders/inputs/#{type_key}"
    lookup_context.exists?(partial, [], true) ? partial : "typed_fields/finders/inputs/text"
  end
end
