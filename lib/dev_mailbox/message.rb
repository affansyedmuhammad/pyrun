module DevMailbox
  # One delivered mail, parsed from its file on demand.
  class Message
    URL = %r{https?://[^\s<>"']+}

    attr_reader :id, :path

    def initialize(path)
      @path = Pathname(path)
      @id = @path.basename(".eml").to_s
    end

    def subject = mail.subject.to_s
    def to = Array(mail.to)
    def from = Array(mail.from)
    def delivered_at = mail.date || @path.mtime

    def text
      part = mail.text_part || (mail.multipart? ? nil : mail)
      part ? part.decoded : ""
    end

    def html
      mail.html_part&.decoded.to_s
    end

    def links = text.scan(URL)

    private
      def mail
        @mail ||= Mail.read(@path.to_s)
      end
  end
end
