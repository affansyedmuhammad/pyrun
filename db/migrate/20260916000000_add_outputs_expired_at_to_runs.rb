class AddOutputsExpiredAtToRuns < ActiveRecord::Migration[8.1]
  def change
    # Set by ExpireRunOutputsJob when RETENTION_DAYS clears stdout and stderr,
    # so the page can say the output expired rather than that nothing was printed.
    add_column :runs, :outputs_expired_at, :datetime
  end
end
