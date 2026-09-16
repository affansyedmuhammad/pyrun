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
    @run = Run.new(code: source_run&.code)
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
    # The list this page belongs to: the all-runs list when an admin came from
    # there (from=all) or is looking at someone else's run; otherwise their own.
    @from_all = (params[:from] == "all" && Current.user.can_view_all_runs?) || @run.user_id != Current.user.id
    list = @from_all ? Current.user.visible_runs : Current.user.runs
    @newer = list.newer_than(@run).first
    @older = list.older_than(@run).first
    Rails.logger.info "admin.run_view admin=#{Current.user.id} run=#{@run.id}" if @run.user_id != Current.user.id
  end

  private
    def run_params
      params.expect(run: [ :code, :runtime ])
    end

    # "Run again" names the run to copy; the code itself never rides in a URL. It
    # can be 64 KB, past what servers accept in a request line, and it may hold
    # pasted secrets that would land in browser history and proxy logs.
    def source_run
      Current.user.visible_runs.find(params[:run_id]) if params[:run_id].present?
    end

    # Reads the limit from config at request time, like every other cap.
    def throttle_submissions
      config = Pyrun.config
      count = Rails.cache.increment("rate-limit:runs:#{Current.user.id}", 1, expires_in: config.run_rate_limit_period)
      rate_limited if count && count > config.run_rate_limit_count
    end
end
