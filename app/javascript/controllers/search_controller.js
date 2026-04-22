import { Controller } from "@hotwired/stimulus"

// Global search widget for the header. Three responsibilities:
//  1. ⌘K / Ctrl+K anywhere on the page focuses the search input.
//  2. Typing debounces (150 ms) a form submission to the /search
//     endpoint via Turbo; the results frame swaps in place.
//  3. Arrow keys move between `[data-search-target="hit"]` links
//     inside the results popover, Enter activates, Escape closes.
export default class extends Controller {
  static targets = ["input", "form", "popover", "hit"]
  static values = { debounceMs: { type: Number, default: 150 } }

  connect() {
    this.boundOutside = (e) => this.#closeIfOutside(e)
    document.addEventListener("click", this.boundOutside, true)
  }

  disconnect() {
    document.removeEventListener("click", this.boundOutside, true)
    clearTimeout(this.submitTimeout)
  }

  globalShortcut(event) {
    const isK = event.key === "k" || event.key === "K"
    if (isK && (event.metaKey || event.ctrlKey)) {
      event.preventDefault()
      this.inputTarget.focus()
      this.inputTarget.select()
      this.open()
    } else if (event.key === "Escape") {
      this.close()
    }
  }

  open() { this.popoverTarget.hidden = false }
  close() {
    this.popoverTarget.hidden = true
    this.inputTarget.blur()
  }

  debouncedSubmit() {
    clearTimeout(this.submitTimeout)
    this.submitTimeout = setTimeout(() => {
      this.formTarget.requestSubmit()
      this.open()
    }, this.debounceMsValue)
  }

  navigate(event) {
    if (event.key !== "ArrowDown" && event.key !== "ArrowUp" && event.key !== "Enter") return
    const hits = this.hitTargets
    if (hits.length === 0) return
    const active = document.activeElement
    const idx = hits.indexOf(active)

    if (event.key === "Enter" && idx >= 0) {
      // Let the browser follow the focused link naturally.
      return
    }

    event.preventDefault()
    let next
    if (event.key === "ArrowDown") {
      next = idx < 0 ? 0 : Math.min(idx + 1, hits.length - 1)
    } else if (event.key === "ArrowUp") {
      if (idx <= 0) {
        this.inputTarget.focus()
        return
      }
      next = idx - 1
    }
    hits[next]?.focus()
  }

  #closeIfOutside(event) {
    if (this.popoverTarget.hidden) return
    if (this.element.contains(event.target)) return
    this.close()
  }
}
