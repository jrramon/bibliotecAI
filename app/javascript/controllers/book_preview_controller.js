import { Controller } from "@hotwired/stimulus"

// Live preview for the "Añadir libro" modal: as the user types in the form
// fields, the spine on the left side updates immediately (title, author,
// stamp, colour). No server round-trip.
export default class extends Controller {
  static targets = ["spine", "titleOut", "authorOut", "stampOut"]

  updateTitle(event) {
    const value = event.target.value.trim()
    this.titleOutTarget.textContent = value || "Título"
  }

  updateAuthor(event) {
    const value = event.target.value.trim()
    const last = value.split(/\s+/).filter(Boolean).pop() || "Autor"
    this.authorOutTarget.textContent = last
  }

  updateStamp(event) {
    const value = event.target.value.trim()
    this.stampOutTarget.textContent = value ? value.slice(0, 2) : "函"
  }

  updateSlot(event) {
    const slot = event.target.value
    const spine = this.spineTarget
    spine.classList.forEach((cls) => {
      if (cls.startsWith("spine-slot-")) spine.classList.remove(cls)
    })
    spine.classList.add(`spine-slot-${slot}`)
  }
}
