class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email_address, null: false
      # Nullable on purpose: an account that only ever signs in through an external
      # identity has no password. See docs/DESIGN.md §4.2.
      t.string :password_digest
      t.datetime :email_verified_at
      t.string :name
      t.datetime :disabled_at

      t.timestamps
    end
    add_index :users, :email_address, unique: true
  end
end
