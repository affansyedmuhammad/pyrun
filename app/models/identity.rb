# An external login (Google, later others) attached to a user. Empty until one is
# linked. A user must always keep at least one way to sign in.
class Identity < ApplicationRecord
  belongs_to :user

  validates :provider, :uid, presence: true
  validates :uid, uniqueness: { scope: :provider }

  before_destroy :keep_one_login_method

  private
    def keep_one_login_method
      return if user.has_password? || user.identities.where.not(id: id).exists?
      errors.add(:base, "is the only way this account can sign in")
      throw :abort
    end
end
