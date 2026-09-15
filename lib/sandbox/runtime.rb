require "yaml"

module Sandbox
  # The runtime registry, read from config/sandbox_runtimes.yml. A runtime is an
  # image plus the command that reads code from stdin. See docs/DESIGN.md §5.4.
  class Runtime
    Unknown = Class.new(StandardError)
    Definition = Data.define(:key, :label, :image, :command)

    class << self
      def registry
        @registry ||= YAML.safe_load_file(Rails.root.join("config/sandbox_runtimes.yml")).freeze
      end

      def keys = registry.keys
      def all = registry.map { |key, entry| build(key, entry) }
      def default = all.first

      def find(key)
        entry = registry[key.to_s]
        raise Unknown, "unknown runtime #{key.inspect} (known: #{keys.join(', ')})" unless entry
        build(key.to_s, entry)
      end

      private
        def build(key, entry)
          Definition.new(
            key: key,
            label: entry.fetch("label"),
            image: entry["image"] || Pyrun.config.sandbox_image,
            command: entry.fetch("command").map(&:to_s).freeze
          )
        end
    end
  end
end
