class AddLastSignedInAtToUsers < ActiveRecord::Migration[8.1]
  def change
    # Shown on the admin users page. Sessions are deleted on sign-out, so the
    # last sign-in has to be remembered on the user.
    add_column :users, :last_signed_in_at, :datetime
  end
end
