class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  layout "auth"

  rate_limit to: 10, within: 15.minutes, only: :create, with: :rate_limited

  def new
    return redirect_to root_path if authenticated?
    @user = User.new
  end

  def create
    result = Users::Register.call(**registration_params)

    case result.status
    when :created
      start_new_session_for result.user
      UserMailer.email_verification(result.user).deliver_later
      Rails.logger.info "auth.signup user=#{result.user.id} ip=#{request.remote_ip}"
      redirect_to_check_inbox
    when :existing
      # Same destination as a fresh signup, so the form never reveals whether an address is registered.
      UserMailer.existing_account(result.user).deliver_later
      redirect_to_check_inbox
    when :invalid
      @user = result.user
      render :new, status: :unprocessable_content
    when :rejected
      Rails.logger.info "auth.signup_rejected email=#{registration_params[:email_address].inspect} ip=#{request.remote_ip}"
      @user = User.new(registration_params)
      @user.errors.add(:email_address, result.error)
      render :new, status: :unprocessable_content
    when :limited
      @user = User.new(registration_params)
      flash.now[:alert] = result.error
      render :new, status: :too_many_requests
    end
  end

  def check_inbox
    @email_address = flash[:signup_email_address]
  end

  private
    def redirect_to_check_inbox
      flash[:signup_email_address] = email_address
      redirect_to check_inbox_path, status: :see_other
    end

    def registration_params
      params.expect(user: [ :email_address, :password, :password_confirmation ]).to_h.symbolize_keys
    end

    # The address as it was normalized and mailed to, not as it was typed.
    def email_address
      params.dig(:user, :email_address).to_s.strip.downcase
    end
end
