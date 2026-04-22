import { Controller } from "@hotwired/stimulus"

// Toggles the "choose library" picker next to a wishlist item so the
// user can convert it into a Book. Each library link in the picker
// drives them to `new_library_book_path(lib, wishlist_item_id: …)`
// where the add-book form arrives pre-filled.
export default class extends Controller {
  static targets = ["picker"]

  connect() {
    this.boundAway = (e) => this.#closeIfOutside(e)
    document.addEventListener("click", this.boundAway, true)
  }

  disconnect() {
    document.removeEventListener("click", this.boundAway, true)
  }

  toggle(event) {
    event.preventDefault()
    this.pickerTarget.hidden = !this.pickerTarget.hidden
  }

  #closeIfOutside(event) {
    if (this.pickerTarget.hidden) return
    if (this.element.contains(event.target)) return
    this.pickerTarget.hidden = true
  }
}
