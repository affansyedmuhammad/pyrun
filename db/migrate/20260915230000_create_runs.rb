class CreateRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :runs do |t|
      t.references :user, null: false, foreign_key: true
      t.string :status, null: false, default: "queued"

      # What was run and what came out. Encrypted at rest (see Run model).
      t.text :code, null: false
      t.text :stdout
      t.text :stderr
      t.boolean :stdout_truncated, null: false, default: false
      t.boolean :stderr_truncated, null: false, default: false
      t.integer :exit_code
      t.boolean :oom_killed, null: false, default: false
      t.string :error_message

      # Runs are self-describing: the runtime, image, and limits this run
      # actually executed under, stamped at submission. Defaults can change
      # without rewriting history. See docs/DESIGN.md §7.
      t.string :runtime, null: false
      t.string :sandbox_image
      t.integer :timeout_seconds, null: false
      t.integer :memory_mb, null: false
      t.decimal :cpus, precision: 4, scale: 2, null: false
      t.integer :pids_limit, null: false
      t.integer :max_output_bytes, null: false
      t.json :runner_metadata

      t.datetime :queued_at, null: false
      t.datetime :started_at
      t.datetime :finished_at
      t.integer :duration_ms

      t.timestamps
    end
    add_index :runs, [ :user_id, :created_at ]
    add_index :runs, :status
  end
end
