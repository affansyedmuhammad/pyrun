class RunsController < ApplicationController
  include Pagy::Backend

  before_action :throttle_submissions, only: :create

  def index
    @status = Run::STATUSES.include?(params[:status]) ? params[:status] : nil
    scope = Current.user.runs.recent
    scope = scope.where(status: @status) if @status
    @pagy, @runs = pagy(scope)
  end

  def new
    @run = Run.new(code: params[:code])
  end

  def create
    result = Runs::Submit.call(user: Current.user, code: run_params[:code], runtime: run_params[:runtime] || Sandbox::Runtime.default.key)

    case result.status
    when :created
      redirect_to run_path(result.run)
    when :invalid
      @run = result.run
      render :new, status: :unprocessable_content
    when :rejected
      @run = Run.new(code: run_params[:code])
      flash.now[:alert] = result.error
      render :new, status: :unprocessable_content
    end
  end

  def show
    @run = Current.user.visible_runs.find(params[:id])
    Rails.logger.info "admin.run_view admin=#{Current.user.id} run=#{@run.id}" if @run.user_id != Current.user.id
  end

  private
    def run_params
      params.expect(run: [ :code, :runtime ])
    end

    # Reads the limit from config at request time, like every other cap.
    def throttle_submissions
      config = Pyrun.config
      count = Rails.cache.increment("rate-limit:runs:#{Current.user.id}", 1, expires_in: config.run_rate_limit_period)
      rate_limited if count && count > config.run_rate_limit_count
    end
end
