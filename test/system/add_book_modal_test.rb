require "application_system_test_case"

class AddBookModalTest < ApplicationSystemTestCase
  setup do
    @alice = create(:user, email: "alice@bibliotecai.test", password: "supersecret123")
    @library = create(:library, owner: @alice, name: "Mi casa")
  end

  test "opening the modal shows the dialog with the preview spine" do
    sign_in_as(@alice)
    visit library_path(@library)

    click_on "＋ Añadir libro"
    assert_selector "dialog[open] .modal-card--wide"
    assert_selector ".spine-preview"
    assert_selector ".swatch-grid .swatch", minimum: 10
  end

  test "typing in the title updates the spine preview live" do
    sign_in_as(@alice)
    visit library_path(@library)

    click_on "＋ Añadir libro"
    within("dialog[open]") do
      fill_in "book[title]", with: "Sanshiro"
    end
    assert_selector ".spine-preview [data-book-preview-target='titleOut']", text: "Sanshiro"
  end

  test "typing an author shows the surname in the preview" do
    sign_in_as(@alice)
    visit library_path(@library)

    click_on "＋ Añadir libro"
    within("dialog[open]") do
      fill_in "book[author]", with: "Natsume Soseki"
    end
    assert_selector ".spine-preview [data-book-preview-target='authorOut']", text: "SOSEKI"
  end

  test "picking a swatch changes the spine preview colour slot" do
    sign_in_as(@alice)
    visit library_path(@library)

    click_on "＋ Añadir libro"
    within("dialog[open]") do
      find("label.swatch.spine-slot-5").click
    end
    assert_selector ".spine-preview.spine-slot-5"
  end

  test "submitting creates the book and shows the Shelved celebration" do
    sign_in_as(@alice)
    visit library_path(@library)

    click_on "＋ Añadir libro"
    within("dialog[open]") do
      fill_in "book[title]", with: "Sanshiro"
      fill_in "book[author]", with: "Natsume Soseki"
      click_on "＋ Añadir a la estantería"
    end

    assert_selector ".shelved-celebration .shelved-label", text: "SHELVED"
    assert_selector ".shelved-celebration .shelved-title", text: "Sanshiro"
    assert_equal 1, @library.books.count
    assert_equal "Sanshiro", @library.books.first.title
  end

  test "submitting without a title shows the form again with an error" do
    sign_in_as(@alice)
    visit library_path(@library)

    click_on "＋ Añadir libro"
    within("dialog[open]") do
      click_on "＋ Añadir a la estantería"
    end
    assert_selector "dialog[open] .form-errors"
    assert_equal 0, @library.books.count
  end
end
