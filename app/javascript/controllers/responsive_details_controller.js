import { Controller } from "@hotwired/stimulus"

// Opens a <details> when a media query matches, closes it otherwise.
// Used to flatten a "+ N more" disclosure into a continuous scroll on
// narrow viewports while keeping the disclosure on wider ones.
//
//   <details data-controller="responsive-details"
//            data-responsive-details-media-value="(max-width: 640px)">
//     <summary>+ N más</summary>
//     …
//   </details>
export default class extends Controller {
  static values = { media: { type: String, default: "(max-width: 640px)" } }

  connect() {
    this.mq = window.matchMedia(this.mediaValue)
    this.handler = () => this.#sync()
    this.mq.addEventListener("change", this.handler)
    this.#sync()
  }

  disconnect() {
    this.mq?.removeEventListener("change", this.handler)
  }

  #sync() {
    this.element.open = this.mq.matches
  }
}
