namespace :pyrun do
  desc "Print the effective configuration (secrets redacted)"
  task config: :environment do
    width = Pyrun::Config::SETTINGS.keys.map(&:length).max
    Pyrun.config.to_h.each do |name, value|
      shown = value.is_a?(Array) ? value.join(", ") : value.to_s
      shown = "(none)" if value.nil? || (value.respond_to?(:empty?) && value.empty?)
      puts "#{name.to_s.ljust(width)}  #{shown}"
    end
  end

  desc "Queue depth, run counts by status, users and sessions"
  task stats: :environment do
    counts = Run.group(:status).count
    puts "users      #{User.count}"
    puts "sessions   #{Session.count}"
    puts "runs       #{Run.count}"
    Run::STATUSES.each { |status| puts "#{status.ljust(10)} #{counts.fetch(status, 0)}" }
  end

  desc "Disable an account and end its sessions. EMAIL=person@windbornesystems.com"
  task deactivate: :environment do
    user = user_from_env!
    user.deactivate!
    Rails.logger.warn "auth.deactivated user=#{user.id}"
    puts "Deactivated #{user.email_address} and ended their sessions."
  end

  desc "Re-enable an account. EMAIL=person@windbornesystems.com"
  task reactivate: :environment do
    user = user_from_env!
    user.reactivate!
    puts "Reactivated #{user.email_address}."
  end

  desc "Sign everyone out everywhere (incident response)"
  task revoke_sessions: :environment do
    count = Session.delete_all
    Rails.logger.warn "auth.sessions_revoked count=#{count}"
    puts "Revoked #{count} sessions."
  end

  # Operator input from the command line, not app configuration.
  def user_from_env!
    email = ENV["EMAIL"].to_s.strip.downcase
    abort "Usage: EMAIL=person@example.com bin/rails pyrun:<task>" if email.empty?
    User.find_by(email_address: email) || abort("No account for #{email}")
  end
end
