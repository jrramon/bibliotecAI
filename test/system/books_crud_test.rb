require "application_system_test_case"

class BooksCrudTest < ApplicationSystemTestCase
  setup do
    @user = create(:user)
    @library = create(:library, name: "Mi casa", owner: @user)
    sign_in_as(@user)
  end

  test "user adds a book, sees it in the grid, edits, and deletes it" do
    visit library_path(@library)
    click_on "Libros"

    assert_selector "h1", text: /libros/i
    assert_text "Aún no hay libros"

    click_on "＋ Añadir libro"

    fill_in "Título", with: "Línea de fuego"
    fill_in "Autor", with: "Arturo Pérez-Reverte"
    fill_in "ISBN", with: "9788420455976"
    fill_in "Notas", with: "Guerra Civil desde la trinchera."
    click_on "Añadir libro"

    assert_selector "h1", text: "Línea de fuego"
    assert_text "Arturo Pérez-Reverte"
    assert_text "9788420455976"

    click_on "Editar"
    fill_in "Autor", with: "A. Pérez-Reverte"
    click_on "Guardar cambios"

    assert_text "A. Pérez-Reverte"

    visit library_books_path(@library)
    assert_selector ".book-grid li", text: "Línea de fuego"

    click_on "Línea de fuego"
    accept_confirm { click_on "Eliminar" }

    assert_text "Aún no hay libros"
  end
end
