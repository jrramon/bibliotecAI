import { Controller } from "@hotwired/stimulus"

// Floating panel that toggles palette (washi / sepia / dark) + shelf layout
// (spines / grid / list). Settings live in localStorage and are applied to
// <html> as data-theme / data-shelf-layout so the rest of the CSS can react.
//
// The stored values are also pre-applied by a small inline script in the
// layout <head> so there's no flash of unstyled content on page load.
export default class extends Controller {
  static targets = ["panel", "themeButton", "layoutButton"]
  static values = {
    storageKey: { type: String, default: "bibliotecai:tweaks" }
  }

  connect() {
    this.state = this.#load()
    this.#apply(this.state)
    this.#markActive()
  }

  open(event) {
    event?.preventDefault()
    this.panelTarget.hidden = false
  }

  close(event) {
    event?.preventDefault()
    this.panelTarget.hidden = true
  }

  setTheme(event) {
    const value = event.currentTarget.dataset.value
    this.state = { ...this.state, theme: value }
    this.#apply(this.state)
    this.#save()
    this.#markActive()
  }

  setLayout(event) {
    const value = event.currentTarget.dataset.value
    this.state = { ...this.state, layout: value }
    this.#apply(this.state)
    this.#save()
    this.#markActive()
  }

  #apply({ theme, layout }) {
    document.documentElement.setAttribute("data-theme", theme)
    document.documentElement.setAttribute("data-shelf-layout", layout)
  }

  #load() {
    try {
      const raw = localStorage.getItem(this.storageKeyValue)
      if (raw) {
        const parsed = JSON.parse(raw)
        return {
          theme: parsed.theme || "light",
          layout: parsed.layout || "grid"
        }
      }
    } catch (_) { /* ignore */ }
    return { theme: "light", layout: "grid" }
  }

  #save() {
    try { localStorage.setItem(this.storageKeyValue, JSON.stringify(this.state)) } catch (_) {}
  }

  #markActive() {
    this.themeButtonTargets.forEach(btn => {
      btn.classList.toggle("on", btn.dataset.value === this.state.theme)
    })
    this.layoutButtonTargets.forEach(btn => {
      btn.classList.toggle("on", btn.dataset.value === this.state.layout)
    })
  }
}
