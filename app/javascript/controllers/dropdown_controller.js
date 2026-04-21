import { Controller } from "@hotwired/stimulus"

// A tiny split-button / dropdown pattern.
//
//   <div data-controller="dropdown">
//     <button data-action="dropdown#toggle">▾</button>
//     <div data-dropdown-target="menu" hidden>…</div>
//   </div>
//
// Click on the toggle opens/closes the menu; clicking anywhere outside the
// root (or pressing Escape) closes it.
export default class extends Controller {
  static targets = ["menu"]

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
    this.menuTarget.hidden ? this.open() : this.close()
  }

  open() { this.menuTarget.hidden = false }
  close() { this.menuTarget.hidden = true }

  #closeIfOutside(event) {
    if (this.menuTarget.hidden) return
    if (!this.element.contains(event.target)) this.close()
  }
}
