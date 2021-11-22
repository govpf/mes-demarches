require 'capybara/rspec'
require 'capybara-screenshot/rspec'
require 'capybara/email/rspec'
require 'selenium/webdriver'

Capybara.javascript_driver      = ENV.fetch('CAPYBARA_DRIVER', 'headless_chrome').to_sym
Capybara.ignore_hidden_elements = false

Capybara.register_driver :chrome do |app|
  Capybara::Selenium::Driver.new(app, browser: :chrome)
end

Capybara.register_driver :headless_chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--headless')
  options.add_argument('--window-size=1440,900')

  capabilities = Selenium::WebDriver::Remote::Capabilities.chrome(
    chromeOptions: { args: ['disable-dev-shm-usage', 'disable-software-rasterizer', 'mute-audio', 'window-size=1440,900'] }
  )

  download_path = Capybara.save_path
  # Chromedriver 77 requires setting this for headless mode on linux
  # Different versions of Chrome/selenium-webdriver require setting differently - just set them all
  options.add_preference('download.default_directory', download_path)
  options.add_preference(:download, default_directory: download_path)

  Capybara::Selenium::Driver.new(app,
    browser: :chrome,
    desired_capabilities: capabilities,
    options: options).tap do |driver|
    # Set download dir for Chrome < 77
    driver.browser.download_path = download_path
  end
end

#---- From https://gist.github.com/danwhitston/5cea26ae0861ce1520695cff3c2c3315#using-capybara-with-a-remote-selenium-server

Capybara.register_driver :wsl do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--window-size=1440,900')
  # Chromedriver 77 requires setting this for headless mode on linux
  # Different versions of Chrome/selenium-webdriver require setting differently - just set them all
  download_path = Capybara.save_path
  options.add_preference('download.default_directory', download_path)
  options.add_preference(:download, default_directory: download_path)

  capabilities = Selenium::WebDriver::Remote::Capabilities.chrome(
    chromeOptions: { args: ['disable-dev-shm-usage', 'disable-software-rasterizer', 'mute-audio', 'window-size=1440,900'] }
  )

  Capybara::Selenium::Driver.new(app,
                                 browser:              :remote,
                                 url:                  "http://localhost:4444/wd/hub",
                                 desired_capabilities: capabilities,
                                 options:              options)
end

# FIXME: remove this line when https://github.com/rspec/rspec-rails/issues/1897 has been fixed
Capybara.server = :puma, { Silent: true }

Capybara.default_max_wait_time = 2

# Save a snapshot of the HTML page when an integration test fails
Capybara::Screenshot.autosave_on_failure = true
# Keep only the screenshots generated from the last failing test suite
Capybara::Screenshot.prune_strategy = :keep_last_run
# Tell Capybara::Screenshot how to take screenshots when using the headless_chrome driver
Capybara::Screenshot.register_driver :headless_chrome do |driver, path|
  driver.browser.save_screenshot(path)
end

RSpec.configure do |config|
  # Set the user preferred language before Javascript feature specs.
  #
  # Features specs without Javascript run in a Rack stack, and respect the Accept-Language value.
  # However specs using Javascript are run into a Headless Chrome, which doesn't support setting
  # the default Accept-Language value reliably.
  # So instead we set the locale cookie explicitly before each Javascript test.
  config.before(:each, js: true) do
    visit '/' # Webdriver needs visiting a page before setting the cookie
    Capybara.current_session.driver.browser.manage.add_cookie(
      name: :locale,
      value: Rails.application.config.i18n.default_locale
    )
  end

  # Examples tagged with :capybara_ignore_server_errors will allow Capybara
  # to continue when an exception in raised by Rails.
  # This allows to test for error cases.
  config.around(:each, :capybara_ignore_server_errors) do |example|
    Capybara.raise_server_errors = false

    example.run
  ensure
    Capybara.raise_server_errors = true
  end
end
