require "test_helper"

class Eval::ShelfScorerTest < ActiveSupport::TestCase
  def book(title, author)
    {"title" => title, "author" => author}
  end

  # --- happy path ---

  test "perfect match: same titles + same authors → score 1.0" do
    books = [book("Reinventing Organizations", "Frédéric Laloux"),
      book("The Lean Startup", "Eric Ries")]
    result = Eval::ShelfScorer.call(actual_books: books, expected_books: books)
    assert_equal 1.0, result[:score]
    assert_equal 1.0, result[:details][:recall]
    assert_equal 1.0, result[:details][:precision]
    assert_equal 2, result[:details][:matched_full].size
    assert_empty result[:details][:matched_title_only]
    assert_empty result[:details][:missed]
    assert_empty result[:details][:extra]
  end

  test "title match but author wrong → 0.5 weight in matched_title_only" do
    expected = [book("Sapiens", "Yuval Noah Harari")]
    actual = [book("Sapiens", "Y. N. Harari")]  # mismo título, autor diferente
    result = Eval::ShelfScorer.call(actual_books: actual, expected_books: expected)
    assert_equal 0.5, result[:details][:recall]
    assert_equal 1.0, result[:details][:precision]
    assert_equal 0.5, result[:score]
    assert_equal 1, result[:details][:matched_title_only].size
  end

  # --- edge cases ---

  test "both empty → score 1.0 (perfect)" do
    result = Eval::ShelfScorer.call(actual_books: [], expected_books: [])
    assert_equal 1.0, result[:score]
  end

  test "actual empty, expected has books → score 0.0; all gold counted as missed" do
    expected = [book("Sapiens", "Harari"), book("Quijote", "Cervantes")]
    result = Eval::ShelfScorer.call(actual_books: [], expected_books: expected)
    assert_equal 0.0, result[:score]
    assert_equal 2, result[:details][:missed].size
  end

  test "expected empty, actual has books → score 0.0; all actual counted as extra" do
    actual = [book("Inventado", "Inventor")]
    result = Eval::ShelfScorer.call(actual_books: actual, expected_books: [])
    assert_equal 0.0, result[:score]
    assert_equal 1, result[:details][:extra].size
  end

  # --- normalization ---

  test "accents and case are ignored on titles" do
    expected = [book("La Casa De Los Espíritus", "Isabel Allende")]
    actual = [book("la casa de los espiritus", "isabel allende")]
    result = Eval::ShelfScorer.call(actual_books: actual, expected_books: expected)
    assert_equal 1.0, result[:score]
  end

  test "punctuation is ignored on titles" do
    expected = [book("Sapiens: A Brief History of Humankind", "Harari")]
    actual = [book("Sapiens — A Brief History of Humankind!", "Harari")]
    result = Eval::ShelfScorer.call(actual_books: actual, expected_books: expected)
    assert_equal 1.0, result[:score]
  end

  # --- author swap (paso 5) ---

  test "first/last name order does not matter for author match" do
    expected = [book("Reinventing Organizations", "Frédéric Laloux")]
    actual = [book("Reinventing Organizations", "Laloux, Frédéric")]
    result = Eval::ShelfScorer.call(actual_books: actual, expected_books: expected)
    assert_equal 1.0, result[:score], "Laloux, Frédéric ≡ Frédéric Laloux"
    assert_equal 1, result[:details][:matched_full].size
  end

  test "empty author on both sides counts as a match" do
    expected = [book("Untitled Volume", "")]
    actual = [book("Untitled Volume", "")]
    result = Eval::ShelfScorer.call(actual_books: actual, expected_books: expected)
    assert_equal 1.0, result[:score]
  end

  test "empty author on one side only is NOT a full match" do
    expected = [book("Sapiens", "Harari")]
    actual = [book("Sapiens", "")]
    result = Eval::ShelfScorer.call(actual_books: actual, expected_books: expected)
    assert_equal 0.5, result[:details][:recall], "title only"
    assert_equal 1.0, result[:details][:precision]
    assert_equal 0.5, result[:score]
  end

  # --- precision penalty (paso 3b) ---

  test "extra hallucinated books drag down precision" do
    expected = [book("Sapiens", "Harari")]
    # acierta el real + se inventa uno → recall 1.0, precision 0.5, score 0.5
    actual = [book("Sapiens", "Harari"), book("Inventado", "Fantasma")]
    result = Eval::ShelfScorer.call(actual_books: actual, expected_books: expected)
    assert_equal 1.0, result[:details][:recall]
    assert_equal 0.5, result[:details][:precision]
    assert_equal 0.5, result[:score]
    assert_equal 1, result[:details][:extra].size
  end

  test "missing books drag down recall" do
    expected = [book("A", "X"), book("B", "Y"), book("C", "Z")]
    actual = [book("A", "X")]  # solo identifica 1 de 3
    result = Eval::ShelfScorer.call(actual_books: actual, expected_books: expected)
    assert_in_delta 0.3333, result[:details][:recall], 0.001
    assert_equal 1.0, result[:details][:precision]
    assert_in_delta 0.3333, result[:score], 0.001
    assert_equal 2, result[:details][:missed].size
  end

  # --- greedy matching ---

  test "greedy never pairs the same actual book with two gold entries" do
    # Dos gold con el mismo título; el primero se queda el match exacto, el
    # segundo no encuentra candidato disponible y queda missed.
    expected = [book("Sapiens", "Harari"), book("Sapiens", "Harari")]
    actual = [book("Sapiens", "Harari")]
    result = Eval::ShelfScorer.call(actual_books: actual, expected_books: expected)
    # 1 emparejamiento full de 2 esperados → recall 0.5; precision 1.0; score 0.5
    assert_equal 0.5, result[:details][:recall]
    assert_equal 1.0, result[:details][:precision]
    assert_equal 0.5, result[:score]
    assert_equal 1, result[:details][:matched_full].size
    assert_equal 1, result[:details][:missed].size
  end

  test "title-exact-with-author-mismatch does not block a later full match" do
    # Si recorremos primero un actual con título=A pero autor distinto, no debe
    # consumirlo si después aparece otro actual con título=A y autor exacto.
    expected = [book("A", "X")]
    actual = [book("A", "Y_wrong"), book("A", "X")]
    result = Eval::ShelfScorer.call(actual_books: actual, expected_books: expected)
    assert_equal 1, result[:details][:matched_full].size, "debería preferir el full match"
    assert_equal 1, result[:details][:extra].size
    assert_equal 1.0, result[:details][:recall]
    assert_equal 0.5, result[:details][:precision]
    assert_equal 0.5, result[:score]
  end
end
