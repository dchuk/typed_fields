import { Controller } from "@hotwired/stimulus"

// Manages the typed field definition form.
// Handles dynamic scope toggling and type-specific option visibility.
//
// Usage:
//   <form data-controller="typed-eav-form">
//     <input data-typed-eav-form-target="scopeInput" />
//     <input type="checkbox" data-typed-eav-form-target="disableScopeCheckbox"
//            data-action="change->typed-eav-form#toggleScope" />
//   </form>
//
export default class extends Controller {
  static targets = ["scopeInput", "disableScopeCheckbox"]

  connect() {
    if (this.hasDisableScopeCheckboxTarget && this.hasDisableScopeCheckboxTarget) {
      this.toggleScope()
    }
  }

  toggleScope() {
    if (!this.hasScopeInputTarget || !this.hasDisableScopeCheckboxTarget) return

    const disabled = this.disableScopeCheckboxTarget.checked
    this.scopeInputTarget.disabled = disabled

    if (disabled) {
      this.scopeInputTarget.value = ""
    }
  }
}
