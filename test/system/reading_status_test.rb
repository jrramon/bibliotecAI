require "application_system_test_case"

class ReadingStatusTest < ApplicationSystemTestCase
  setup do
    @alice = create(:user, email: "alice@bibliotecai.test", password: "supersecret123")
    @bob = create(:user, email: "bob@bibliotecai.test", password: "supersecret123")
    @library = create(:library, owner: @alice, name: "Mi casa")
    @library.memberships.create!(user: @bob, role: :member)
    @book = create(:book, library: @library, added_by_user: @alice, title: "Quiet")
  end

  test "user starts, finishes, and restarts a book" do
    sign_in_as(@alice)
    visit library_book_path(@library, @book)

    click_on "Empezar a leer"
    assert_text "Marcado como leyendo"
    assert_selector "button", text: "Marcar como leído"
    assert_selector "button", text: "Dejar de leer"

    click_on "Marcar como leído"
    assert_text "¡Marcado como leído!"
    assert_selector ".chip.chip-moss", text: /Le[ií]do/i

    click_on "Releer"
    assert_text "Marcado como leyendo"
  end

  test "stop reading removes the status" do
    create(:reading_status, user: @alice, book: @book, state: :reading)
    sign_in_as(@alice)
    visit library_book_path(@library, @book)

    click_on "Dejar de leer"
    assert_text "Estado de lectura eliminado"
    assert_selector "button", text: "Empezar a leer"
  end

  test "leyendo ahora section on library show lists only the viewer's active reads" do
    alice_reading = create(:book, library: @library, added_by_user: @alice, title: "Alice's pick")
    bob_reading = create(:book, library: @library, added_by_user: @alice, title: "Bob's pick")
    create(:reading_status, user: @alice, book: alice_reading, state: :reading)
    create(:reading_status, user: @bob, book: bob_reading, state: :reading)

    sign_in_as(@alice)
    visit library_path(@library)

    within ".reading-now" do
      assert_text "Leyendo ahora"
      assert_selector ".spine", text: "Alice's pick"
      assert_no_text "Bob's pick"
    end
  end

  test "leyendo ahora section is hidden when the user has no active reads in this library" do
    sign_in_as(@bob)
    visit library_path(@library)
    assert_no_selector ".reading-now"
  end
end
