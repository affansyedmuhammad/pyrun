module Admin
  # Read-only view of everyone's runs for superusers. Members get a 404, so the
  # area's existence is not advertised.
  class RunsController < ApplicationController
    include Pagy::Backend

    before_action :require_admin

    def index
      @status = Run::STATUSES.include?(params[:status]) ? params[:status] : nil
      @email = params[:email].to_s.strip.downcase.presence

      scope = Run.includes(:user).recent
      scope = scope.where(status: @status) if @status
      scope = scope.joins(:user).where("users.email_address LIKE ?", "%#{Run.sanitize_sql_like(@email)}%") if @email
      @pagy, @runs = pagy(scope)
    end

    private
      def require_admin
        raise ActiveRecord::RecordNotFound unless Current.user.can_view_all_runs?
      end
  end
end
