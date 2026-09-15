class Session < ApplicationRecord
  LOGIN_METHODS = %w[password google].freeze

  belongs_to :user

  validates :login_method, inclusion: { in: LOGIN_METHODS }
end
