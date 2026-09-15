module IconsHelper
  # Inline SVG line icons (Feather, MIT). Decorative: every use sits inside a
  # control that carries its own accessible name.
  ICONS = {
    key: '<path d="M21 2l-2 2m-7.61 7.61a5.5 5.5 0 1 1-7.778 7.778 5.5 5.5 0 0 1 7.777-7.777zm0 0L15.5 7.5m0 0l3 3L22 7l-3-3m-3.5 3.5L19 4"/>',
    log_out: '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/>',
    user_x: '<path d="M16 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="8.5" cy="7" r="4"/><line x1="18" y1="8" x2="23" y2="13"/><line x1="23" y1="8" x2="18" y2="13"/>',
    user_check: '<path d="M16 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="8.5" cy="7" r="4"/><polyline points="17 11 19 13 23 9"/>',
    shield: '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>',
    shield_off: '<path d="M19.69 14a6.9 6.9 0 0 0 .31-2V5l-8-3-3.16 1.18"/><path d="M4.73 4.73L4 5v7c0 6 8 10 8 10a20.29 20.29 0 0 0 5.62-4.38"/><line x1="1" y1="1" x2="23" y2="23"/>'
  }.freeze

  # The mark: a prompt chevron and a cursor on a dark rounded square. The same
  # drawing is public/icon.svg (the favicon), so the two never drift.
  LOGO = %(<rect width="32" height="32" rx="7" fill="#18181b"/><path d="M10 10l6 6-6 6" fill="none" stroke="#ffffff" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/><path d="M17 22h6" fill="none" stroke="#34d399" stroke-width="3" stroke-linecap="round"/>).freeze

  def logo_mark(css: "logo")
    tag.svg(LOGO.html_safe, class: css, viewBox: "0 0 32 32", "aria-hidden": "true")
  end

  def icon(name, css: "icon")
    tag.svg(ICONS.fetch(name).html_safe, class: css, viewBox: "0 0 24 24", fill: "none", stroke: "currentColor",
            "stroke-width": "2", "stroke-linecap": "round", "stroke-linejoin": "round", "aria-hidden": "true")
  end

  # An icon-only button_to with an accessible name and a hover title.
  def icon_button_to(label, path, icon:, method: :post, title: label, danger: false)
    button_to path, method: method, class: "btn btn-icon#{' btn-icon-danger' if danger}", form_class: "contents",
              title: title, "aria-label": label do
      icon(icon)
    end
  end
end
