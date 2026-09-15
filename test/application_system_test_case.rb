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
end
