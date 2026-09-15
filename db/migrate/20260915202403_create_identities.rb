class CreateIdentities < ActiveRecord::Migration[8.1]
  def change
    # External logins (Google later). Empty until one is linked, but the
    # "a user keeps at least one login method" rule is written against it now.
    create_table :identities do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :uid, null: false
      t.string :email_at_link
      t.datetime :last_used_at

      t.timestamps
    end
    add_index :identities, [ :provider, :uid ], unique: true
  end
end
