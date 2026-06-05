import { Controller } from "@hotwired/stimulus"

// Pre-flight validation for multi-file shelf-photo uploads. Prevents the silent
// nginx 413 (Payload Too Large): it warns and disables submit BEFORE sending a
// POST that exceeds the server limits — 10 MB per photo (ShelfPhoto's own
// limit) and 100 MB total (kept in sync with nginx client_max_body_size).
export default class extends Controller {
  static targets = ["input", "submit", "status"]
  static values = {
    maxFileBytes: { type: Number, default: 10 * 1024 * 1024 },
    maxTotalBytes: { type: Number, default: 100 * 1024 * 1024 }
  }

  connect() {
    this.validate()
  }

  validate() {
    const files = Array.from(this.inputTarget.files || [])

    if (files.length === 0) {
      this.setStatus("", false)
      this.setValid(true)
      return
    }

    const total = files.reduce((sum, file) => sum + file.size, 0)
    const oversized = files.filter((file) => file.size > this.maxFileBytesValue)
    const summary = `${files.length} ${files.length === 1 ? "foto" : "fotos"} · ${this.mb(total)}`

    if (oversized.length > 0) {
      const names = oversized.map((file) => file.name).join(", ")
      this.setStatus(`${summary} — superan ${this.mb(this.maxFileBytesValue)} por foto: ${names}`, true)
      this.setValid(false)
    } else if (total > this.maxTotalBytesValue) {
      this.setStatus(`${summary} — supera el máximo de ${this.mb(this.maxTotalBytesValue)} en total. Sube menos fotos o más ligeras.`, true)
      this.setValid(false)
    } else {
      this.setStatus(summary, false)
      this.setValid(true)
    }
  }

  setValid(valid) {
    if (this.hasSubmitTarget) this.submitTarget.disabled = !valid
  }

  setStatus(message, isError) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = message
    this.statusTarget.classList.toggle("is-error", isError)
    this.statusTarget.hidden = message === ""
  }

  mb(bytes) {
    return `${(bytes / (1024 * 1024)).toFixed(1).replace(".", ",")} MB`
  }
}
