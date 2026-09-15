import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Left and Right arrow keys step to the newer and older run, mirroring the
// pager's links. Ignored while typing or when a modifier is held.
export default class extends Controller {
  static values = { newer: String, older: String }

  connect() {
    this.onKeydown = (event) => this.handle(event)
    document.addEventListener("keydown", this.onKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
  }

  handle(event) {
    if (event.metaKey || event.ctrlKey || event.altKey || event.shiftKey) return
    const target = event.target
    if (target.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(target.tagName)) return

    const destination = event.key === "ArrowLeft" ? this.newerValue : event.key === "ArrowRight" ? this.olderValue : ""
    if (!destination) return

    event.preventDefault()
    Turbo.visit(destination)
  }
}
