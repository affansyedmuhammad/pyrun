import { Controller } from "@hotwired/stimulus"

// Counts up from the server-rendered elapsed seconds and fills the bar toward
// the run's own limit. Starts from the server's number so a skewed browser
// clock never shows a wrong time.
export default class extends Controller {
  static targets = ["time", "bar"]
  static values = { elapsed: Number, limit: Number, mode: String }

  connect() {
    this.startedCounting = Date.now()
    this.tick()
    this.timer = setInterval(() => this.tick(), 1000)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  // A Turbo refresh may morph new server values into this element.
  elapsedValueChanged() {
    this.startedCounting = Date.now()
  }

  tick() {
    const seconds = this.elapsedValue + Math.floor((Date.now() - this.startedCounting) / 1000)
    this.timeTarget.textContent = this.format(seconds)

    if (this.modeValue === "running" && this.hasBarTarget) {
      const percent = Math.min(100, (seconds / this.limitValue) * 100)
      this.barTarget.style.width = `${percent}%`
      this.element.querySelector("[role=progressbar]")?.setAttribute("aria-valuenow", String(seconds))
    }
  }

  format(seconds) {
    const minutes = Math.floor(seconds / 60)
    const rest = seconds % 60
    return `${minutes}:${String(rest).padStart(2, "0")}`
  }
}
