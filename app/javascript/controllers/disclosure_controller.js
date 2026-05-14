import { Controller } from "@hotwired/stimulus"

// Toggles `is-open` on the controller root. Click-outside or Escape closes it.
// Unlike `dropdown` (which flips `hidden` on a target), this controller leaves
// display decisions to CSS, so a viewport-based override can keep the menu
// always visible on wider screens.
//
//   <div data-controller="disclosure">
//     <button data-action="disclosure#toggle">⋯</button>
//     <div class="something-menu">…</div>
//   </div>
export default class extends Controller {
  connect() {
    this.boundAway = (e) => this.#closeIfOutside(e)
    this.boundEsc = (e) => { if (e.key === "Escape") this.close() }
    document.addEventListener("click", this.boundAway, true)
    document.addEventListener("keydown", this.boundEsc)
  }

  disconnect() {
    document.removeEventListener("click", this.boundAway, true)
    document.removeEventListener("keydown", this.boundEsc)
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    this.element.classList.toggle("is-open")
  }

  close() {
    this.element.classList.remove("is-open")
  }

  #closeIfOutside(event) {
    if (!this.element.contains(event.target)) this.close()
  }
}
