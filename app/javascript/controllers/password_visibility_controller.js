import { Controller } from "@hotwired/stimulus"

// The eye button on a password field: reveals or hides what was typed.
export default class extends Controller {
  static targets = ["input", "button"]

  toggle() {
    const reveal = this.inputTarget.type === "password"
    this.inputTarget.type = reveal ? "text" : "password"
    this.buttonTarget.setAttribute("aria-pressed", String(reveal))
    const label = reveal ? "Hide password" : "Show password"
    this.buttonTarget.setAttribute("aria-label", label)
    this.buttonTarget.setAttribute("title", label)
    const [eye, eyeOff] = this.buttonTarget.querySelectorAll("svg")
    eye.hidden = reveal
    eyeOff.hidden = !reveal
    this.inputTarget.focus({ preventScroll: true })
  }
}
