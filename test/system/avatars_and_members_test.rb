require "application_system_test_case"

class AvatarsAndMembersTest < ApplicationSystemTestCase
  setup do
    @alice = create(:user, email: "alice@bibliotecai.test", password: "supersecret123")
    @bob = create(:user, email: "bob@bibliotecai.test", password: "supersecret123")
    @carol = create(:user, email: "carol@bibliotecai.test", password: "supersecret123")
    @library = create(:library, owner: @alice, name: "Mi casa")
    @library.memberships.create!(user: @bob, role: :member)
    @library.memberships.create!(user: @carol, role: :member)
  end

  test "sidebar members widget shows library members on library-scoped pages" do
    sign_in_as(@alice)
    visit library_path(@library)

    within ".members-widget" do
      assert_selector ".avatar", minimum: 3
      assert_text "Nadie leyendo ahora mismo"
    end
  end

  test "sidebar members widget is hidden on pages without a library in scope" do
    sign_in_as(@alice)
    visit libraries_path
    assert_no_selector ".members-widget"
  end

  test "members widget mentions who is currently reading" do
    book = create(:book, library: @library, added_by_user: @alice, title: "Quiet")
    create(:reading_status, user: @bob, book: book, state: :reading)

    sign_in_as(@alice)
    visit library_path(@library)

    within ".members-widget" do
      assert_text "bob está leyendo ahora"
    end
  end

  test "book detail shows Leído por with avatars of past readers" do
    book = create(:book, library: @library, added_by_user: @alice, title: "Sanshiro")
    create(:reading_status, user: @alice, book: book, state: :read, finished_at: 1.week.ago)
    create(:reading_status, user: @bob, book: book, state: :read, finished_at: 2.days.ago)

    sign_in_as(@carol)
    visit library_book_path(@library, book)

    within ".read-by" do
      assert_selector ".label", text: "LEÍDO POR"
      assert_selector ".avatar", count: 2
    end
  end

  test "book detail does not render Leído por when no one has finished it" do
    book = create(:book, library: @library, added_by_user: @alice, title: "Unread")
    sign_in_as(@alice)
    visit library_book_path(@library, book)
    assert_no_selector ".read-by"
  end
end
