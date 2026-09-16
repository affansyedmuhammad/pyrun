import { Controller } from "@hotwired/stimulus"

// Keeps a growing output box scrolled to its newest line while the run is still
// going. Scrolling up pauses following; scrolling back to the bottom resumes it.
// The server drops the controller once the run finishes, so a finished run is
// read from the top.
export default class extends Controller {
  connect() {
    this.following = true
    this.onScroll = () => { this.following = this.atBottom() }
    this.element.addEventListener("scroll", this.onScroll)
    // A Turbo refresh morphs new text into this element.
    this.observer = new MutationObserver(() => this.follow())
    this.observer.observe(this.element, { childList: true, characterData: true, subtree: true })
    this.follow()
  }

  disconnect() {
    this.observer.disconnect()
    this.element.removeEventListener("scroll", this.onScroll)
  }

  follow() {
    if (this.following) this.element.scrollTop = this.element.scrollHeight
  }

  atBottom() {
    return this.element.scrollTop + this.element.clientHeight >= this.element.scrollHeight - 4
  }
}
