module NavigationHelper
  # A sidebar item; the current section is marked for both eyes and screen readers.
  def nav_link(label, path, active:)
    link_to label, path, class: [ "nav-item", ("nav-item-active" if active) ].compact.join(" "),
                         "aria-current": (active ? "page" : nil)
  end

  # Sections are path prefixes, so filters and child pages keep their item marked.
  def in_section?(prefix)
    request.path == prefix || request.path.start_with?("#{prefix}/", "#{prefix}?")
  end
end
