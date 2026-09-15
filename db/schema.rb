# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_16_010000) do
  create_table "identities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_at_link"
    t.datetime "last_used_at"
    t.string "provider", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["provider", "uid"], name: "index_identities_on_provider_and_uid", unique: true
    t.index ["user_id"], name: "index_identities_on_user_id"
  end

  create_table "runs", force: :cascade do |t|
    t.text "code", null: false
    t.decimal "cpus", precision: 4, scale: 2, null: false
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.string "error_message"
    t.integer "exit_code"
    t.datetime "finished_at"
    t.integer "max_output_bytes", null: false
    t.integer "memory_mb", null: false
    t.boolean "oom_killed", default: false, null: false
    t.datetime "outputs_expired_at"
    t.integer "pids_limit", null: false
    t.datetime "queued_at", null: false
    t.json "runner_metadata"
    t.string "runtime", null: false
    t.string "sandbox_image"
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.text "stderr"
    t.boolean "stderr_truncated", default: false, null: false
    t.text "stdout"
    t.boolean "stdout_truncated", default: false, null: false
    t.integer "timeout_seconds", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["status"], name: "index_runs_on_status"
    t.index ["user_id", "created_at"], name: "index_runs_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_runs_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.string "login_method", default: "password", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "disabled_at"
    t.string "email_address", null: false
    t.datetime "email_verified_at"
    t.datetime "last_signed_in_at"
    t.string "name"
    t.string "password_digest"
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "identities", "users"
  add_foreign_key "runs", "users"
  add_foreign_key "sessions", "users"
end
