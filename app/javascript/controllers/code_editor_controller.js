import { Controller } from "@hotwired/stimulus"

// Makes a plain textarea comfortable for code: Tab indents instead of leaving the
// field, and Ctrl/Cmd+Enter submits the form.
export default class extends Controller {
  static values = { indent: { type: String, default: "  " } }

  keydown(event) {
    if (event.key === "Tab" && !event.shiftKey) {
      event.preventDefault()
      this.insert(this.indentValue)
    } else if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
      event.preventDefault()
      this.element.form?.requestSubmit()
    }
  }

  insert(text) {
    const el = this.element
    el.setRangeText(text, el.selectionStart, el.selectionEnd, "end")
    el.dispatchEvent(new Event("input", { bubbles: true }))
  }
}
