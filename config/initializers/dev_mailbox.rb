# The development inbox's delivery method. Registered outside production only;
# config/environments/development.rb selects it. See lib/dev_mailbox.rb.
unless Rails.env.production?
  ActiveSupport.on_load(:action_mailer) do
    add_delivery_method :dev_mailbox, DevMailbox::DeliveryMethod
  end
end
