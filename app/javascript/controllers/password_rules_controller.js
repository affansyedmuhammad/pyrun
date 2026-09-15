import { Controller } from "@hotwired/stimulus"

// Ticks the password checklist as the person types. The rules themselves are
// rendered from the model (data-pattern / data-min-length), never duplicated here.
export default class extends Controller {
  static targets = ["input", "rule"]

  connect() {
    this.check()
  }

  check() {
    const value = this.hasInputTarget ? this.inputTarget.value : ""
    for (const rule of this.ruleTargets) {
      const met = rule.dataset.minLength
        ? value.length >= Number(rule.dataset.minLength)
        : new RegExp(rule.dataset.pattern, "u").test(value)
      rule.dataset.met = String(met)
    }
  }
}
