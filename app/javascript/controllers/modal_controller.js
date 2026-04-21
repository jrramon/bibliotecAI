import { Controller } from "@hotwired/stimulus"

// Wraps a native <dialog> so we can open / close it from arbitrary buttons.
// Expected DOM:
//
//   <div data-controller="modal">
//     <button data-action="modal#open">Abrir</button>
//     <dialog data-modal-target="dialog">
//       …content…
//       <button type="button" data-action="modal#close">Cancelar</button>
//     </dialog>
//   </div>
export default class extends Controller {
  static targets = ["dialog"]

  open(event) {
    event.preventDefault()
    this.dialogTarget.showModal()
  }

  close(event) {
    event?.preventDefault()
    this.dialogTarget.close()
  }

  // Closes the dialog when the backdrop (the dialog element itself) is clicked,
  // but not when a descendant (the form, a button, etc.) is clicked.
  backdropClick(event) {
    if (event.target === this.dialogTarget) this.close()
  }
}
