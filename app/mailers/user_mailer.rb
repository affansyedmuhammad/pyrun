class UserMailer < ApplicationMailer
  def email_verification(user)
    @user = user
    @url = email_verification_url(user.generate_token_for(:email_verification))
    mail to: user.email_address, subject: t(".subject")
  end

  def password_reset(user)
    @user = user
    @url = edit_password_url(user.generate_token_for(:password_reset))
    mail to: user.email_address, subject: t(".subject")
  end

  # Sent to the owner when someone signs up with an address that already has an account.
  def existing_account(user)
    @user = user
    @url = edit_password_url(user.generate_token_for(:password_reset))
    mail to: user.email_address, subject: t(".subject")
  end
end
