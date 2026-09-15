import { Controller } from "@hotwired/stimulus"
import { EditorState } from "@codemirror/state"
import {
  EditorView, keymap, lineNumbers, drawSelection, highlightActiveLine,
  highlightActiveLineGutter, highlightSpecialChars, rectangularSelection, crosshairCursor
} from "@codemirror/view"
import { defaultKeymap, history, historyKeymap, indentWithTab } from "@codemirror/commands"
import { bracketMatching, indentOnInput, indentUnit, syntaxHighlighting } from "@codemirror/language"
import { closeBrackets, closeBracketsKeymap } from "@codemirror/autocomplete"
import { python } from "@codemirror/lang-python"
import { classHighlighter } from "@lezer/highlight"

// Upgrades the code textarea to a CodeMirror editor: Python highlighting, line
// numbers, bracket matching, indentation after a colon, Tab to indent, and
// Ctrl/Cmd+Enter to run. The textarea stays in the form (hidden) and is kept in
// sync, so submission and the no-JavaScript path are unchanged.
export default class extends Controller {
  connect() {
    this.textarea = this.element
    this.wrapper = document.createElement("div")
    this.wrapper.className = "editor"
    this.textarea.insertAdjacentElement("afterend", this.wrapper)

    // The document enforces the nonce it was loaded with; Turbo swaps the meta
    // tag on every visit, so read it from the importmap script that came with
    // the original page instead.
    const nonce = document.querySelector("script[type=importmap]")?.nonce || document.querySelector("meta[name=csp-nonce]")?.content
    this.view = new EditorView({
      doc: this.textarea.value,
      parent: this.wrapper,
      extensions: [
        lineNumbers(), highlightActiveLineGutter(), highlightSpecialChars(), history(),
        drawSelection(), rectangularSelection(), crosshairCursor(), highlightActiveLine(),
        EditorState.allowMultipleSelections.of(true),
        indentOnInput(), bracketMatching(), closeBrackets(),
        python(), syntaxHighlighting(classHighlighter), indentUnit.of("    "),
        keymap.of([
          { key: "Mod-Enter", run: () => { this.submit(); return true } },
          indentWithTab, ...closeBracketsKeymap, ...defaultKeymap, ...historyKeymap
        ]),
        EditorView.updateListener.of(update => {
          if (update.docChanged) this.textarea.value = update.state.doc.toString()
        }),
        EditorView.contentAttributes.of({ "aria-label": "Code", spellcheck: "false", autocapitalize: "off" }),
        ...(nonce ? [EditorView.cspNonce.of(nonce)] : [])
      ]
    })

    this.textarea.hidden = true
    if (this.textarea.autofocus) this.view.focus()

    // Turbo snapshots the page for its cache; hand it back the plain textarea.
    this.teardown = () => this.disconnect()
    document.addEventListener("turbo:before-cache", this.teardown, { once: true })
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.teardown)
    this.view?.destroy()
    this.view = null
    this.wrapper?.remove()
    this.wrapper = null
    if (this.textarea) this.textarea.hidden = false
  }

  submit() {
    this.textarea.form?.requestSubmit()
  }
}
