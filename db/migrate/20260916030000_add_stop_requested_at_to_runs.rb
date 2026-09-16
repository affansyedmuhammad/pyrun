class AddStopRequestedAtToRuns < ActiveRecord::Migration[8.1]
  def change
    # Set when the owner (or an admin) asks a run to stop before its limit. The
    # worker checks it about once a second and kills the sandbox.
    add_column :runs, :stop_requested_at, :datetime
  end
end
