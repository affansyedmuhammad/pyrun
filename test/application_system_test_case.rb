require "test_helper"

# System tests run a real Chromium through Playwright. The Node package pinned in
# package.json provides the driver binary; `npm install && npx playwright install chromium`
# fetches it (bin/setup does this).
Capybara.register_driver(:playwright) do |app|
  Capybara::Playwright::Driver.new(
    app,
    playwright_cli_executable_path: Rails.root.join("node_modules/.bin/playwright").to_s,
    browser_type: :chromium,
    headless: ENV["HEADLESS"] != "false",
    viewport: { width: 1280, height: 800 }
  )
end

Capybara.default_max_wait_time = 5
Capybara.save_path = Rails.root.join("tmp/screenshots")

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :playwright

  # The browser drives a real server thread; mail is delivered through Active Job,
  # so jobs perform as soon as they are enqueued for the duration of a system test.
  setup do
    queue_adapter.perform_enqueued_jobs = true
    queue_adapter.perform_enqueued_at_jobs = true
  end

  teardown do
    queue_adapter.perform_enqueued_jobs = false
    queue_adapter.perform_enqueued_at_jobs = false
  end

  private
    # The path of the first link in a delivered mail that contains +prefix+.
    def path_from_mail(mail, prefix)
      body = mail.text_part.body.to_s
      url = body[%r{https?://\S*#{Regexp.escape(prefix)}\S*}]
      assert url, "no link containing #{prefix} in:\n#{body}"
      URI.parse(url).request_uri
    end
end
