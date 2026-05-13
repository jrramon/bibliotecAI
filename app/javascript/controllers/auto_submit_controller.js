import { Controller } from "@hotwired/stimulus"

// Submits the closest form when the element fires its change/input event.
// Wire as: data-controller="auto-submit" data-action="change->auto-submit#submit"
export default class extends Controller {
  submit() {
    const form = this.element.form || this.element.closest("form")
    form?.requestSubmit()
  }
}
