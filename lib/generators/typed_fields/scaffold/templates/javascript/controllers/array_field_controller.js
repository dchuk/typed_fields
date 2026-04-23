import { Controller } from "@hotwired/stimulus"

// Manages dynamic add/remove of array field inputs.
//
// Usage:
//   <div data-controller="array-field">
//     <div data-array-field-target="template" style="display:none">
//       <input type="text" name="values[]" value="" />
//       <button data-action="click->array-field#remove">Remove</button>
//     </div>
//
//     <!-- Existing items rendered server-side -->
//     <div data-array-field-target="item">
//       <input type="text" name="values[]" value="existing" />
//       <button data-action="click->array-field#remove">Remove</button>
//     </div>
//
//     <button data-action="click->array-field#add">Add</button>
//   </div>
//
export default class extends Controller {
  static targets = ["template", "item", "container"]

  connect() {
    if (this.hasTemplateTarget) {
      this.templateTarget.style.display = "none"
    }
  }

  add(event) {
    event.preventDefault()

    if (!this.hasTemplateTarget) return

    const clone = this.templateTarget.cloneNode(true)

    // Remove the template target data attribute so it becomes a regular item
    delete clone.dataset.arrayFieldTarget
    clone.style.removeProperty("display")

    // Clear input values in the clone
    clone.querySelectorAll("input, select, textarea").forEach(input => {
      if (input.type === "checkbox" || input.type === "radio") {
        input.checked = false
      } else {
        input.value = ""
      }
    })

    // Insert before the "Add" button
    event.target.before(clone)
  }

  remove(event) {
    event.preventDefault()

    // Walk up to the nearest item wrapper div
    const item = event.target.closest("[data-array-field-target='item']") ||
                 event.target.parentElement
    if (item) {
      item.remove()
    }
  }
}
