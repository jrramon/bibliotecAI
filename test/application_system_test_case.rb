require "test_helper"

if ENV["SELENIUM_URL"].present?
  Capybara.server_host = "0.0.0.0"
  Capybara.server_port = 3001
  Capybara.app_host = "http://web:3001"

  Capybara.register_driver :remote_chrome do |app|
    options = Selenium::WebDriver::Options.chrome
    options.add_argument("--headless=new")
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-gpu")
    options.add_argument("--window-size=1400,1400")
    Capybara::Selenium::Driver.new(
      app,
      browser: :remote,
      url: ENV["SELENIUM_URL"],
      options: options
    )
  end

  Capybara.default_driver = :remote_chrome
  Capybara.javascript_driver = :remote_chrome
end

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  if ENV["SELENIUM_URL"].blank?
    driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400]
  end

  # Force Capybara's registered driver when running against remote Selenium.
  # We skip `driven_by` because Rails' driver adapter can't express a remote browser.
  if ENV["SELENIUM_URL"].present?
    setup { Capybara.current_driver = :remote_chrome }
  end

  def sign_in_as(user, password: "supersecret123")
    user.update!(password: password) unless user.valid_password?(password)
    visit new_user_session_path
    fill_in "user_email", with: user.email
    fill_in "user_password", with: password
    click_on "Log in"
    assert_selector "header.header", text: user.email
  end

  # TODO: axe-core a11y helper — wire up once we have a real interactive page (Slice 1+).
  def assert_accessible
    # placeholder — a11y assertions arrive with Slice 1 once axe-core-capybara API is validated end-to-end.
  end
end
