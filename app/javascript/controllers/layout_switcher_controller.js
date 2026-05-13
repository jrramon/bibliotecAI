import { Controller } from "@hotwired/stimulus"

// Inline shelf-layout switcher (spine / grid / list). Shares the same
// localStorage key as the Tweaks panel so both stay in sync across page
// loads. The <html data-shelf-layout> attribute is also pre-applied by an
// inline script in app/views/layouts/application.html.erb to avoid FOUC.
const STORAGE_KEY = "bibliotecai:tweaks"
const DEFAULT_LAYOUT = "grid"

export default class extends Controller {
  static targets = ["button"]

  connect() {
    this.layout = document.documentElement.getAttribute("data-shelf-layout") || this.#loadFromStorage() || DEFAULT_LAYOUT
    document.documentElement.setAttribute("data-shelf-layout", this.layout)
    this.#markActive()
  }

  set(event) {
    event.preventDefault()
    const value = event.currentTarget.dataset.value
    if (!value || value === this.layout) return
    this.layout = value
    document.documentElement.setAttribute("data-shelf-layout", value)
    this.#saveToStorage()
    this.#markActive()
  }

  #loadFromStorage() {
    try {
      const raw = localStorage.getItem(STORAGE_KEY)
      if (!raw) return null
      const parsed = JSON.parse(raw)
      return parsed?.layout || null
    } catch (_) {
      return null
    }
  }

  #saveToStorage() {
    try {
      const raw = localStorage.getItem(STORAGE_KEY)
      const parsed = raw ? JSON.parse(raw) : {}
      parsed.layout = this.layout
      localStorage.setItem(STORAGE_KEY, JSON.stringify(parsed))
    } catch (_) {
      // ignore
    }
  }

  #markActive() {
    this.buttonTargets.forEach(btn => {
      btn.classList.toggle("on", btn.dataset.value === this.layout)
    })
  }
}
