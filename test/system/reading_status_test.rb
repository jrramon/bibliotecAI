require "application_system_test_case"

class ReadingStatusTest < ApplicationSystemTestCase
  setup do
    @alice = create(:user, email: "alice@bibliotecai.test", password: "supersecret123")
    @bob = create(:user, email: "bob@bibliotecai.test", password: "supersecret123")
    @library = create(:library, owner: @alice, name: "Mi casa")
    @library.memberships.create!(user: @bob, role: :member)
    @book = create(:book, library: @library, added_by_user: @alice, title: "Quiet")
  end

  test "user starts, finishes, and restarts a book — past cycles are preserved" do
    fast_sign_in(@alice)
    visit library_book_path(@library, @book)

    click_on "Empezar a leer"
    assert_text "Marcado como leyendo"

    click_on "Marcar como leído"
    assert_text "¡Marcado como leído!"
    assert_selector ".chip.chip-moss", text: /Le[ií]do/i

    click_on "Releer"
    assert_text "Releyendo (vez 2)"

    # One completed + one active in DB
    assert_equal 2, @book.reading_statuses.where(user: @alice).count
    assert_equal 1, @book.reading_statuses.where(user: @alice).completed.count
    assert_equal 1, @book.reading_statuses.where(user: @alice).active.count
  end

  test "stop reading marks the current attempt as dropped and keeps the row" do
    status = create(:reading_status, user: @alice, book: @book, state: :reading)
    fast_sign_in(@alice)
    visit library_book_path(@library, @book)

    click_on "Dejar de leer"
    assert_text "abandonada"
    status.reload
    assert status.dropped?
    assert_not_nil status.finished_at
  end

  test "finish reading with a past date records finished_at in the past" do
    fast_sign_in(@alice)
    visit library_book_path(@library, @book)

    click_on "Empezar a leer"
    find(".split-btn-chevron").click

    # <input type="date"> under Selenium chokes on fill_in under some locales;
    # set the value directly via JS and submit the form.
    input = find(".split-menu input[name='finished_on']")
    page.execute_script("arguments[0].value='2019-07-12'", input.native)
    within(".split-menu") { click_on "Guardar" }

    assert_text "12 de julio de 2019"
    status = @book.reading_statuses.where(user: @alice).ordered.first
    assert status.read?
    assert_equal Date.new(2019, 7, 12), status.finished_at.to_date
  end

  test "finish reading with 'Hace tiempo' stores no finished_at" do
    fast_sign_in(@alice)
    visit library_book_path(@library, @book)

    click_on "Empezar a leer"
    find(".split-btn-chevron").click
    within(".split-menu") { click_on "Hace tiempo" }

    assert_text "sin fecha"
    status = @book.reading_statuses.where(user: @alice).ordered.first
    assert status.read?
    assert_nil status.finished_at
  end

  test "three reads are each recorded and surfaced as a history" do
    fast_sign_in(@alice)
    visit library_book_path(@library, @book)

    click_on "Empezar a leer"
    click_on "Marcar como leído"
    click_on "Releer"
    click_on "Marcar como leído"
    click_on "Releer"
    click_on "Marcar como leído"

    assert_selector ".reading-history h3", text: /historial de lectura/i
    assert_selector ".reading-history h3", text: /3 veces/i
    assert_selector ".reading-log li", count: 3
    assert_equal 3, @book.reading_statuses.where(user: @alice).completed.count
  end

  test "deleting a history entry removes that reading record" do
    create(:reading_status, user: @alice, book: @book, state: :read,
      started_at: 2.years.ago, finished_at: 2.years.ago + 1.week)
    create(:reading_status, user: @alice, book: @book, state: :read,
      started_at: 1.year.ago, finished_at: 1.year.ago + 1.week)

    fast_sign_in(@alice)
    visit library_book_path(@library, @book)

    assert_selector ".reading-log li", count: 2
    accept_confirm do
      first(".reading-log-delete").click
    end
    assert_text "Entrada del historial borrada"
    assert_selector ".reading-log li", count: 1
    assert_equal 1, @book.reading_statuses.where(user: @alice).completed.count
  end

  test "leyendo ahora section on library show lists only the viewer's active reads" do
    alice_reading = create(:book, library: @library, added_by_user: @alice, title: "Alice's pick")
    bob_reading = create(:book, library: @library, added_by_user: @alice, title: "Bob's pick")
    create(:reading_status, user: @alice, book: alice_reading, state: :reading)
    create(:reading_status, user: @bob, book: bob_reading, state: :reading)

    fast_sign_in(@alice)
    visit library_path(@library)

    within ".reading-now" do
      assert_text "Leyendo ahora"
      assert_selector ".spine", text: "Alice's pick"
      assert_no_text "Bob's pick"
    end
  end

  test "leyendo ahora section is hidden when the user has no active reads in this library" do
    fast_sign_in(@bob)
    visit library_path(@library)
    assert_no_selector ".reading-now"
  end
end
