module DevMailHelper
  # Escapes the text, then turns each URL into a link. Escaping happens first so
  # nothing in the mail can inject markup.
  def linkify(text)
    escaped = ERB::Util.html_escape(text.to_s)
    escaped.gsub(DevMailbox::Message::URL) { |url| %(<a href="#{url}" class="link">#{url}</a>) }.html_safe
  end
end
