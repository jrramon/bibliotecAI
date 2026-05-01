import { Controller } from "@hotwired/stimulus"

// Adds a `data-revealed` attribute to the element the first time it scrolls
// into view, so CSS can fade it up. Stagger is opt-in via
// `data-reveal-delay-value` (ms). Honors prefers-reduced-motion: when the
// user has it on, we mark every element revealed immediately and skip the
// observer entirely so nothing animates.
export default class extends Controller {
  static values = { delay: Number }

  connect() {
    if (this.#prefersReducedMotion) {
      this.#reveal()
      return
    }

    if (this.delayValue) {
      this.element.style.setProperty("--reveal-delay", `${this.delayValue}ms`)
    }

    this.observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            this.#reveal()
            this.observer.disconnect()
          }
        })
      },
      { threshold: 0.15, rootMargin: "0px 0px -8% 0px" }
    )
    this.observer.observe(this.element)
  }

  disconnect() {
    this.observer?.disconnect()
  }

  #reveal() {
    this.element.dataset.revealed = "true"
  }

  get #prefersReducedMotion() {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches
  }
}
