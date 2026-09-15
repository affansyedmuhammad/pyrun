# The one form builder. A field is a label, an input, an optional hint, and inline
# errors, with the aria wiring that makes screen readers announce the error.
class PyrunFormBuilder < ActionView::Helpers::FormBuilder
  def field(attribute, label:, as: :text, hint: nil, **options)
    id = options.delete(:id) || field_id(attribute)
    messages = error_messages(attribute)
    described_by = []
    described_by << field_id(attribute, :hint) if hint
    described_by << field_id(attribute, :error) if messages.any?

    input_options = options.merge(id: id, class: [ "field-input", options[:class] ].compact.join(" "))
    input_options[:"aria-invalid"] = true if messages.any?
    input_options[:"aria-describedby"] = described_by.join(" ") if described_by.any?

    @template.tag.div(class: "field") do
      @template.safe_join([
        label(attribute, label, class: "field-label", for: id),
        public_send(as == :textarea ? :text_area : :"#{as}_field", attribute, **input_options),
        (@template.tag.p(hint, class: "field-hint", id: field_id(attribute, :hint)) if hint),
        (@template.tag.p(messages.to_sentence.upcase_first, class: "field-error", id: field_id(attribute, :error)) if messages.any?)
      ].compact)
    end
  end

  def submit(value, variant: :primary, **options)
    classes = [ "btn btn-#{variant}", options.delete(:class) ].compact.join(" ")
    @template.tag.button(value, type: "submit", class: classes, **options)
  end

  private
    def error_messages(attribute)
      return [] unless object.respond_to?(:errors)
      object.errors.messages_for(attribute)
    end
end
