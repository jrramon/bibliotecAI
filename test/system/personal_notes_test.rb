require "application_system_test_case"

class PersonalNotesTest < ApplicationSystemTestCase
  setup do
    @alice = create(:user, email: "alice@bibliotecai.test", password: "supersecret123")
    @bob = create(:user, email: "bob@bibliotecai.test", password: "supersecret123")
    @library = create(:library, owner: @alice)
    @library.memberships.create!(user: @bob, role: :member)
    @book = create(:book, library: @library, added_by_user: @alice, title: "Shared Book")
  end

  test "each user sees only their own note on the same shared book" do
    sign_in_as(@alice)
    visit library_book_path(@library, @book)

    click_on "＋ Añadir mi nota personal"
    within("dialog.modal-dialog") do
      fill_in "user_book_note_body", with: "Nota secreta de Alice"
      click_on "Guardar nota"
    end
    assert_text "Nota secreta de Alice"

    # Bob opens the same book — he should NOT see Alice's note
    click_on "Cerrar sesión"
    assert_selector ".header-actions a", text: "Iniciar sesión"
    sign_in_as(@bob)
    visit library_book_path(@library, @book)

    assert_no_text "Nota secreta de Alice"
    assert_selector "button", text: "＋ Añadir mi nota personal"

    click_on "＋ Añadir mi nota personal"
    within("dialog.modal-dialog") do
      fill_in "user_book_note_body", with: "Nota de Bob"
      click_on "Guardar nota"
    end
    assert_text "Nota de Bob"
    assert_no_text "Nota secreta de Alice"
  end

  test "emptying the note removes it from view" do
    sign_in_as(@alice)
    @book.user_book_notes.create!(user: @alice, body: "Algo que ya no importa")

    visit library_book_path(@library, @book)
    assert_text "Algo que ya no importa"

    click_on "Editar nota"
    within("dialog.modal-dialog") do
      fill_in "user_book_note_body", with: ""
      click_on "Guardar nota"
    end

    assert_no_text "Algo que ya no importa"
    assert_selector "button", text: "＋ Añadir mi nota personal"
  end
end
