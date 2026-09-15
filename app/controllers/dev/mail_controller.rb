module Dev
  # The development inbox. No login: it exists so a person can find their own
  # verification link before they have an account, and the routes are only
  # drawn outside production (config/routes.rb).
  class MailController < ApplicationController
    allow_unauthenticated_access

    def index
      @messages = DevMailbox.messages
    end

    def show
      @message = DevMailbox.find(params[:id])
    rescue DevMailbox::NotFound
      raise ActiveRecord::RecordNotFound
    end

    def clear
      DevMailbox.clear
      redirect_to dev_mail_path, notice: "Inbox cleared.", status: :see_other
    end
  end
end
