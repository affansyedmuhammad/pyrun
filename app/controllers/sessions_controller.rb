class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  allow_unverified_access only: :destroy
  layout "auth"

  rate_limit to: 10, within: 3.minutes, only: :create, with: :rate_limited
  # Keyed on attacker-controlled input, so deliberately loose: it slows credential
  # stuffing without letting anyone lock a coworker out.
  rate_limit to: 30, within: 15.minutes, only: :create, name: "email", with: :rate_limited,
             by: -> { params[:email_address].to_s.strip.downcase }

  def new
    redirect_to root_path if authenticated?
  end

  def create
    user = User.authenticate_by(email_address: params[:email_address].to_s, password: params[:password].to_s)

    if user && !user.disabled?
      start_new_session_for user
      redirect_to after_authentication_url
    else
      Rails.logger.info "auth.login_failed email=#{params[:email_address].to_s.inspect} ip=#{request.remote_ip}"
      @email_address = params[:email_address]
      flash.now[:alert] = t(".failed")
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    terminate_session
    redirect_to login_path, notice: t(".signed_out"), status: :see_other
  end
end
