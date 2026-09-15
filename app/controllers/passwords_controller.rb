class PasswordsController < ApplicationController
  allow_unauthenticated_access
  before_action :set_user_by_token, only: %i[edit update]
  layout "auth"

  rate_limit to: 10, within: 15.minutes, only: :create, with: :rate_limited
  rate_limit to: 5, within: 15.minutes, only: :create, name: "email", with: :rate_limited,
             by: -> { params[:email_address].to_s.strip.downcase }

  def new
  end

  def create
    user = User.find_by(email_address: params[:email_address].to_s.strip.downcase)
    UserMailer.password_reset(user).deliver_later if user && !user.disabled?

    # The same answer whether or not the address exists.
    redirect_to login_path, notice: t(".sent")
  end

  def edit
  end

  def update
    if @user.update(password_params)
      @user.sessions.destroy_all
      @user.verify! # completing a reset proves the inbox is theirs
      Rails.logger.info "auth.password_reset user=#{@user.id}"
      redirect_to login_path, notice: t(".updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  private
    def set_user_by_token
      @user = User.find_by_token_for!(:password_reset, params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
      redirect_to new_password_path, alert: t("passwords.invalid_token")
    end

    def password_params
      params.expect(user: [ :password, :password_confirmation ])
    end
end
