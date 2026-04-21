import { Controller } from "@hotwired/stimulus"

// After the "Shelved" celebration card appears in the add-book modal,
// wait a beat and navigate to `href`. The delay is part of the UX —
// it gives the user a half-second to register the kanji before the
// page changes under them.
export default class extends Controller {
  static values = { href: String, delayMs: { type: Number, default: 1400 } }

  connect() {
    this.timeout = setTimeout(() => {
      window.location.href = this.hrefValue || window.location.href
    }, this.delayMsValue)
  }

  disconnect() {
    clearTimeout(this.timeout)
  }
}
