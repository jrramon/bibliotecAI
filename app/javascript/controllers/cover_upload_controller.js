import { Controller } from "@hotwired/stimulus"

// Bridges a visible "📷 Identificar desde foto" button in the book
// form with a hidden <input type="file"> that lives in a sibling form
// (because <form> elements can't nest). Clicking the button opens the
// picker; picking a file auto-submits the sibling form.
export default class extends Controller {
  static targets = ["input"]

  pick(event) {
    event.preventDefault()
    this.inputTarget.click()
  }

  submit(event) {
    if (event.target.files.length === 0) return
    event.target.form.requestSubmit()
  }
}
