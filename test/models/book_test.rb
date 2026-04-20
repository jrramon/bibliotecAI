require "test_helper"

class BookTest < ActiveSupport::TestCase
  test ".normalize collapses case, punctuation, and diacritics" do
    assert_equal "episodios nacionales primera serie", Book.normalize("Episodios Nacionales (Primera serie)")
    assert_equal "linea de fuego", Book.normalize("Línea de Fuego")
    assert_equal "becoming a minha historia", Book.normalize("Becoming — A Minha História")
    assert_equal "1984", Book.normalize("1984")
  end

  test ".normalize treats equivalent variants as equal" do
    assert_equal Book.normalize("El Asedio"), Book.normalize("el asedio")
    assert_equal Book.normalize("Un día de cólera"), Book.normalize("Un día de cólera ")
    assert_equal Book.normalize("Episodios Nacionales (Primera serie)"),
      Book.normalize("Episodios nacionales, Primera serie")
  end
end
