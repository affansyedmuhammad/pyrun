class User < ApplicationRecord
  PASSWORD_MIN_LENGTH = 12
  PASSWORD_MAX_BYTES = 72 # bcrypt reads no further

  # Validations are declared explicitly below so that a missing password is a
  # deliberate state (an account that signs in through an external identity)
  # rather than an accident. See docs/DESIGN.md §4.2.
  has_secure_password validations: false

  has_many :sessions, dependent: :destroy
  has_many :identities, dependent: :destroy
  has_many :runs, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, format: { with: EmailPolicy::FORMAT }, uniqueness: true
  validates :password, length: { minimum: PASSWORD_MIN_LENGTH }, confirmation: true, allow_nil: true
  validate :password_fits_bcrypt
  validate :password_is_not_the_email_address
  validate :has_a_login_method

  # Bound to the verified-at timestamp, so verifying kills every outstanding link.
  generates_token_for :email_verification, expires_in: 24.hours do
    [ email_address, email_verified_at&.to_i ]
  end

  # Bound to the salt, so changing the password kills every outstanding link.
  generates_token_for :password_reset, expires_in: 15.minutes do
    password_salt&.last(10)
  end

  def verified? = email_verified_at.present?
  def disabled? = disabled_at.present?
  def has_password? = password_digest.present?

  def verify!
    update!(email_verified_at: Time.current) unless verified?
  end

  def admin? = AdminPolicy.admin?(email_address)

  # Views and controllers ask named permissions, never admin? directly, so a
  # third role later is a change here and nowhere else.
  def can_view_all_runs? = admin?

  # Every run lookup in every controller goes through this, so who may see what
  # is decided in exactly one place.
  def visible_runs = can_view_all_runs? ? Run.all : runs

  private
    def password_fits_bcrypt
      return if password.nil? || password.bytesize <= PASSWORD_MAX_BYTES
      errors.add(:password, :too_long_bytes, count: PASSWORD_MAX_BYTES)
    end

    def password_is_not_the_email_address
      return if password.nil? || email_address.blank?
      errors.add(:password, :is_email) if password.strip.downcase == email_address
    end

    def has_a_login_method
      return if has_password? || identities.any?
      errors.add(:base, "needs a password or an external login")
    end
end
