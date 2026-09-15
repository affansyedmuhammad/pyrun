class EmailVerificationsController < ApplicationController
  allow_unverified_access
  layout "auth"

  rate_limit to: 3, within: 15.minutes, only: :create, by: -> { Current.user.id }, with: :rate_limited

  def pending
    redirect_to root_path if Current.user.verified?
  end

  # Resend.
  def create
    UserMailer.email_verification(Current.user).deliver_later unless Current.user.verified?
    redirect_to pending_email_verification_path, notice: t(".sent", email: Current.user.email_address)
  end

  # The link. It only works for the signed-in owner, which closes the case where
  # someone signs up with a coworker's address and the coworker clicks the mail.
  def show
    user = User.find_by_token_for(:email_verification, params[:token])

    if user.nil?
      redirect_to pending_email_verification_path, alert: t(".expired")
    elsif user != Current.user
      render :wrong_account
    else
      user.verify!
      Rails.logger.info "auth.verified user=#{user.id}"
      redirect_to root_path, notice: t(".verified")
    end
  end
end
