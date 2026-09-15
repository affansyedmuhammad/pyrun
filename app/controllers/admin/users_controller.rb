module Admin
  # Account management for superusers: see who has an account, disable or
  # re-enable one, or end someone's sessions. Admin membership itself is
  # deployment config (ADMIN_EMAILS), so nothing here can grant it.
  class UsersController < ApplicationController
    include Pagy::Backend

    before_action :require_user_manager
    before_action :set_user, except: :index

    def index
      @status = User::ACCOUNT_STATUSES.include?(params[:status]) ? params[:status] : nil
      @email = params[:email].to_s.strip.downcase.presence

      scope = User.recent.with_account_status(@status)
      scope = scope.where("email_address LIKE ?", "%#{User.sanitize_sql_like(@email)}%") if @email
      @pagy, @users = pagy(scope)
      @run_counts = Run.where(user_id: @users.map(&:id)).group(:user_id).count
      @session_counts = Session.where(user_id: @users.map(&:id)).group(:user_id).count
    end

    def deactivate
      if @user == Current.user
        redirect_to admin_users_path, alert: t(".self"), status: :see_other
      else
        @user.deactivate!
        Rails.logger.warn "admin.user_deactivated admin=#{Current.user.id} user=#{@user.id}"
        redirect_to admin_users_path, notice: t(".done", email: @user.email_address), status: :see_other
      end
    end

    def reactivate
      @user.reactivate!
      Rails.logger.warn "admin.user_reactivated admin=#{Current.user.id} user=#{@user.id}"
      redirect_to admin_users_path, notice: t(".done", email: @user.email_address), status: :see_other
    end

    # Sends the same reset mail the person could request themselves. An admin
    # never sets or sees a password.
    def password_reset
      if @user.disabled?
        redirect_to admin_users_path, alert: t(".disabled"), status: :see_other
      else
        UserMailer.password_reset(@user).deliver_later
        Rails.logger.warn "admin.user_password_reset_sent admin=#{Current.user.id} user=#{@user.id}"
        redirect_to admin_users_path, notice: t(".done", email: @user.email_address), status: :see_other
      end
    end

    def make_admin
      @user.make_admin!
      Rails.logger.warn "admin.user_made_admin admin=#{Current.user.id} user=#{@user.id}"
      redirect_to admin_users_path, notice: t(".done", email: @user.email_address), status: :see_other
    end

    def remove_admin
      if @user == Current.user
        redirect_to admin_users_path, alert: t(".self"), status: :see_other
      elsif @user.admin_from_config?
        redirect_to admin_users_path, alert: t(".from_config", email: @user.email_address), status: :see_other
      else
        @user.remove_admin!
        Rails.logger.warn "admin.user_admin_removed admin=#{Current.user.id} user=#{@user.id}"
        redirect_to admin_users_path, notice: t(".done", email: @user.email_address), status: :see_other
      end
    end

    def sessions
      @user.sessions.destroy_all
      Rails.logger.warn "admin.user_sessions_revoked admin=#{Current.user.id} user=#{@user.id}"
      redirect_to admin_users_path, notice: t(".done", email: @user.email_address), status: :see_other
    end

    private
      def require_user_manager
        raise ActiveRecord::RecordNotFound unless Current.user.can_manage_users?
      end

      def set_user
        @user = User.find(params[:id])
      end
  end
end
