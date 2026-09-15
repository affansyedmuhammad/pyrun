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
end
