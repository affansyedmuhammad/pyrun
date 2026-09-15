module ApplicationCable
  class Connection < ActionCable::Connection::Base
    SESSION_COOKIE = Authentication::SESSION_COOKIE

    identified_by :current_user

    # The same signed session cookie as the web session; anonymous sockets are refused.
    def connect
      set_current_user || reject_unauthorized_connection
    end

    private
      def set_current_user
        if (session = Session.find_by(id: cookies.signed[SESSION_COOKIE]))
          self.current_user = session.user
        end
      end
  end
end
