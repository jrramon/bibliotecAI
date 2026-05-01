require "application_system_test_case"

class SmokeTest < ApplicationSystemTestCase
  test "guest home renders brand and hero with kanji" do
    visit root_path
    assert_selector "header.header a.brand .name", text: "BibliotecAI"
    assert_selector "header.header a.brand .kanji", text: "函"
    assert_selector ".landing-hero h1", text: "Tu biblioteca de casa"
    assert_accessible
  end
end
