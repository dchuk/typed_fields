# frozen_string_literal: true

module TypedEAVControllerConcern
  extend ActiveSupport::Concern

  included do
    helper_method :typed_eav_filter_params
  end

  # Permitted filter params for search forms.
  # Expects: params[:f] = [{ n: "field_name", op: "eq", v: "value" }, ...]
  def typed_eav_filter_params
    @typed_eav_filter_params ||=
      params.permit(f: [:n, :name, :op, :operator, :v, :value, { v: [], value: [] }])[:f] || {}
  end

  private

  # Strip leading blank element from array params (HTML multi-select quirk)
  def compact_array_param(value)
    return value unless value.is_a?(Array)
    value.first == "" ? value[1..] : value
  end
end
