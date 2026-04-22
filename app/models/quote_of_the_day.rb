# Pull-quote shown on the dashboard hero. Pulls from the first two
# sentences of a random synopsis across the viewer's libraries. Falls
# back to a small pool of Japanese-literature classics when nothing
# suitable exists (blank synopses on every book, fresh install, etc.)
# so the section always has something to show.
#
# Deterministic per-day: uses `Date.current` as the seed so the quote
# stays the same until tomorrow.
class QuoteOfTheDay
  Result = Struct.new(:body, :attribution, :book, :library, keyword_init: true)

  FALLBACKS = [
    {body: "El secreto de la belleza está en la sombra.",
     attribution: "Junichirō Tanizaki — El elogio de la sombra"},
    {body: "Cada mañana resolvemos que este día será diferente; cada noche descubrimos que no lo fue.",
     attribution: "Natsume Sōseki — Kokoro"},
    {body: "El silencio, después de todo, también es una forma de palabra.",
     attribution: "Yasunari Kawabata — País de nieve"},
    {body: "La costumbre es la segunda naturaleza del corazón.",
     attribution: "Akiko Yosano — Pelo enmarañado"},
    {body: "Hay libros que se leen deprisa para llegar al final. Hay otros que leemos despacio porque no queremos que terminen.",
     attribution: "Haruki Murakami — Tokio blues"}
  ].freeze

  MIN_SYNOPSIS_LEN = 50

  def self.for(user, today: Date.current)
    new(user, today).call
  end

  def initialize(user, today)
    @user = user
    @today = today
  end

  def call
    candidate = pick_from_synopses
    return candidate if candidate
    pick_fallback
  end

  private

  def pick_from_synopses
    return nil unless @user

    books = Book
      .where(library_id: @user.libraries.select(:id))
      .where.not(synopsis: [nil, ""])
      .where("LENGTH(synopsis) >= ?", MIN_SYNOPSIS_LEN)
      .includes(:library)
      .to_a

    return nil if books.empty?

    book = books[seed % books.size]
    body = first_two_sentences(book.synopsis)
    return nil if body.blank?

    Result.new(
      body: body,
      attribution: "#{book.author.presence || "desconocido"} — #{book.title}",
      book: book,
      library: book.library
    )
  end

  def pick_fallback
    entry = FALLBACKS[seed % FALLBACKS.size]
    Result.new(body: entry[:body], attribution: entry[:attribution], book: nil, library: nil)
  end

  # Deterministic, coarse-grained so everyone sharing a library doesn't
  # see the same book every day but the pick remains stable intra-day.
  def seed
    @seed ||= @today.to_s.hash.abs
  end

  def first_two_sentences(text)
    sentences = text.to_s.strip.split(/(?<=[\.!?…])\s+/, 3)
    sentences.first(2).join(" ").strip
  end
end
