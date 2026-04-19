require "application_system_test_case"

class BookCommentsTest < ApplicationSystemTestCase
  setup do
    @alice = create(:user, email: "alice@bibliotecai.test", password: "supersecret123")
    @bob = create(:user, email: "bob@bibliotecai.test", password: "supersecret123")
    @library = create(:library, owner: @alice)
    @library.memberships.create!(user: @bob, role: :member)
    @book = create(:book, library: @library, added_by_user: @alice, title: "Las huellas")
  end

  test "member posts a comment and sees it in the thread" do
    sign_in_as(@alice)
    visit library_book_path(@library, @book)

    assert_selector "h3", text: "Notas y comentarios"

    within "form.comment-compose" do
      find("trix-editor").click.set("Primer apunte sobre el libro.")
      click_on "Publicar"
    end

    assert_selector ".comment .cm-body", text: "Primer apunte sobre el libro."
    assert_selector ".comment .cm-name", text: @alice.email
    assert_selector ".comment .cm-actions button", text: "Eliminar"
  end

  test "non-author cannot see delete button on another user's comment" do
    create(:comment, book: @book, user: @alice, body: "Nota de Alice.")

    sign_in_as(@bob)
    visit library_book_path(@library, @book)

    assert_selector ".comment .cm-body", text: "Nota de Alice."
    assert_selector ".comment .cm-name", text: @alice.email
    assert_no_selector ".comment .cm-actions button", text: "Eliminar"
  end
end
