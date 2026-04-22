import { Controller } from "@hotwired/stimulus"

// Tiny "Copy to clipboard" helper for the wishlist share URL. Uses the
// async Clipboard API with a fallback to document.execCommand for
// browsers that don't grant clipboard-write (e.g. non-HTTPS contexts).
export default class extends Controller {
  static targets = ["source"]

  async copy(event) {
    event.preventDefault()
    const value = this.sourceTarget.value
    try {
      await navigator.clipboard.writeText(value)
      this.#flash(event.currentTarget, "Copiado ✓")
    } catch (_) {
      this.sourceTarget.select()
      document.execCommand("copy")
      this.#flash(event.currentTarget, "Copiado ✓")
    }
  }

  #flash(button, text) {
    const original = button.textContent
    button.textContent = text
    setTimeout(() => { button.textContent = original }, 1600)
  }
}
