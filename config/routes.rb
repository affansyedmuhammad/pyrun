Rails.application.routes.draw do
  root "runs#index"

  # Accounts. Every route below is private unless listed in test/controllers/route_coverage_test.rb.
  get    "signup", to: "registrations#new", as: :signup
  post   "signup", to: "registrations#create"
  get    "signup/check-inbox", to: "registrations#check_inbox", as: :check_inbox
  get    "login",  to: "sessions#new", as: :login
  post   "login",  to: "sessions#create"
  delete "logout", to: "sessions#destroy", as: :logout

  get  "verify-email",        to: "email_verifications#pending", as: :pending_email_verification
  post "verify-email",        to: "email_verifications#create",  as: :email_verifications
  get  "verify-email/:token", to: "email_verifications#show",    as: :email_verification

  resources :passwords, param: :token, only: %i[new create edit update]

  resources :runs, only: %i[index new create show]

  # Superusers only (docs/DESIGN.md §4.16). Members get a 404 here.
  namespace :admin do
    resources :runs, only: :index
    resources :users, only: :index do
      member do
        post :deactivate
        post :reactivate
        delete :sessions
      end
    end
  end

  if Rails.env.local?
    # Development inbox for every mail the app sends (lib/dev_mailbox.rb). Never in production.
    get    "dev/mail",     to: "dev/mail#index", as: :dev_mail
    get    "dev/mail/:id", to: "dev/mail#show",  as: :dev_mail_message
    delete "dev/mail",     to: "dev/mail#clear"
  end

  # Health check for load balancers and uptime monitors. Unauthenticated, says only 200.
  get "up" => "rails/health#show", as: :rails_health_check
end
