import { Controller } from "@hotwired/stimulus"

// Drives the hamburger toggle on mobile: opens/closes the sidebar as a
// slide-in drawer. On desktop the sidebar is always visible (CSS
// hides the toggle at > 880px) and this controller is a no-op.
export default class extends Controller {
  static targets = ["sidebar", "overlay"]
  static classes = ["open"]

  toggle(event) {
    event.preventDefault()
    const opening = !this.element.classList.contains(this.openClass)
    this.element.classList.toggle(this.openClass)
    document.body.style.overflow = opening ? "hidden" : ""
  }

  close() {
    this.element.classList.remove(this.openClass)
    document.body.style.overflow = ""
  }

  // Close the drawer on any link click inside — after navigation the
  // overlay would linger otherwise.
  closeOnNavigation(event) {
    if (event.target.closest("a")) this.close()
  }
}
