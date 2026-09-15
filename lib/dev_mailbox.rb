# The development inbox. Every mail the app sends is written as one .eml file
# under tmp/dev_mailbox and shown at /dev/mail in the app's own design. Never
# used in production: the delivery method is registered and the routes are
# drawn only outside it.
module DevMailbox
  NotFound = Class.new(StandardError)
  ID_FORMAT = /\A[\w-]+\z/

  class << self
    attr_writer :location

    def location
      @location ||= Rails.root.join("tmp/dev_mailbox")
    end

    def messages
      return [] unless location.directory?
      location.glob("*.eml").map { |path| Message.new(path) }.sort_by(&:id).reverse
    end

    def find(id)
      raise NotFound, "not a mailbox id: #{id.inspect}" unless id.to_s.match?(ID_FORMAT)
      path = location.join("#{id}.eml")
      raise NotFound, "no message #{id}" unless path.file?
      Message.new(path)
    end

    def clear
      location.glob("*.eml").each(&:delete)
    end
  end
end
