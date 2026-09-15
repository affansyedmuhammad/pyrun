class Run < ApplicationRecord
  STATUSES = %w[queued running succeeded failed timed_out errored].freeze
  TERMINAL_STATUSES = %w[succeeded failed timed_out errored].freeze

  belongs_to :user

  # What people run and what it printed may contain secrets they pasted; a copied
  # database file or snapshot must not reveal either.
  encrypts :code, :stdout, :stderr

  enum :status, STATUSES.index_by(&:itself), default: "queued", validate: true

  validates :code, presence: true
  validate :code_fits_the_limit, :code_has_no_nul_bytes
  validates :runtime, inclusion: { in: ->(_run) { Sandbox::Runtime.keys } }
  validates :timeout_seconds, :memory_mb, :cpus, :pids_limit, :max_output_bytes, :queued_at, presence: true

  scope :recent, -> { order(created_at: :desc, id: :desc) }
  scope :active, -> { where(status: %w[queued running]) }

  # One step through the recent order in either direction; id breaks ties.
  scope :newer_than, ->(run) {
    where("created_at > :at OR (created_at = :at AND id > :id)", at: run.created_at, id: run.id).order(created_at: :asc, id: :asc)
  }
  scope :older_than, ->(run) {
    where("created_at < :at OR (created_at = :at AND id < :id)", at: run.created_at, id: run.id).recent
  }

  # The show page subscribes to this run and re-renders when the worker updates it.
  broadcasts_refreshes

  def finished? = TERMINAL_STATUSES.include?(status)

  # The limits this run recorded at submission, which the runner uses verbatim.
  def limits
    Sandbox::Limits.new(timeout_seconds:, memory_mb:, cpus: cpus.to_f, pids_limit:, max_output_bytes:)
  end

  def runtime_definition = Sandbox::Runtime.find(runtime)

  def first_line = code.to_s.each_line.map(&:strip).find(&:present?)

  private
    def code_fits_the_limit
      max = Pyrun.config.max_code_bytes
      errors.add(:code, :too_long_bytes, count: max) if code.present? && code.bytesize > max
    end

    def code_has_no_nul_bytes
      errors.add(:code, :nul_bytes) if code&.include?("\0")
    end
end
