# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "@codemirror/lang-python", to: "@codemirror--lang-python.js" # @6.2.1
pin "@lezer/highlight", to: "@lezer--highlight.js" # @1.2.3
pin "codemirror" # @6.0.2
pin "@codemirror/autocomplete", to: "@codemirror--autocomplete.js" # @6.20.3
pin "@codemirror/commands", to: "@codemirror--commands.js" # @6.11.0
pin "@codemirror/language", to: "@codemirror--language.js" # @6.12.4
pin "@codemirror/lint", to: "@codemirror--lint.js" # @6.9.7
pin "@codemirror/search", to: "@codemirror--search.js" # @6.7.2
pin "@codemirror/state", to: "@codemirror--state.js" # @6.7.4
pin "@codemirror/view", to: "@codemirror--view.js" # @6.43.11
pin "@lezer/common", to: "@lezer--common.js" # @1.5.2
pin "@lezer/lr", to: "@lezer--lr.js" # @1.4.10
pin "@lezer/python", to: "@lezer--python.js" # @1.1.19
pin "@marijn/find-cluster-break", to: "@marijn--find-cluster-break.js" # @1.0.3
pin "crelt" # @1.0.7
pin "style-mod" # @4.1.3
pin "w3c-keyname" # @2.2.8
