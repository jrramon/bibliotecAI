import { Controller } from "@hotwired/stimulus"

// Toggles a CSS class that clamps or reveals a long text block.
// Usage:
//   <div data-controller="expandable">
//     <div data-expandable-target="body" class="expandable-body">Lorem…</div>
//     <button type="button" data-action="expandable#toggle" data-expandable-target="toggle">[más]</button>
//   </div>
export default class extends Controller {
  static targets = ["body", "toggle"]
  static values  = { moreLabel: { type: String, default: "[más]" },
                     lessLabel: { type: String, default: "[menos]" } }

  connect() {
    this.expanded = false
    this.#update()
    this.#hideIfShortEnough()
  }

  toggle(event) {
    event.preventDefault()
    this.expanded = !this.expanded
    this.#update()
  }

  #update() {
    this.bodyTarget.classList.toggle("is-expanded", this.expanded)
    if (this.hasToggleTarget) {
      this.toggleTarget.textContent = this.expanded ? this.lessLabelValue : this.moreLabelValue
    }
  }

  // If the text fits in the clamped height anyway, hide the toggle entirely.
  #hideIfShortEnough() {
    if (!this.hasToggleTarget) return
    const clampedHeight = this.bodyTarget.clientHeight
    this.bodyTarget.classList.add("is-expanded")
    const fullHeight = this.bodyTarget.scrollHeight
    this.bodyTarget.classList.remove("is-expanded")
    if (fullHeight <= clampedHeight + 2) {
      this.toggleTarget.hidden = true
    }
  }
}
