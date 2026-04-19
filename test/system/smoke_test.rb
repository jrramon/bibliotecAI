require "application_system_test_case"

class SmokeTest < ApplicationSystemTestCase
  test "home page renders brand + hero" do
    visit root_path
    assert_selector "header.site-header a.brand", text: "BibliotecAI"
    assert_selector "section.hero h1", text: "BibliotecAI"
    assert_accessible
  end
end
