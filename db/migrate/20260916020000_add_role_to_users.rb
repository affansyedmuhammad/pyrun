class AddRoleToUsers < ActiveRecord::Migration[8.1]
  def change
    # Admin membership managed from the Users page. ADMIN_EMAILS still grants it
    # from config, which is how the first admin exists. See docs/DESIGN.md §4.16.
    add_column :users, :role, :string, null: false, default: "member"
    add_index :users, :role
  end
end
