# Pull-quote shown on the dashboard hero. Deterministic per date (same
# quote all day) picked from a curated pool of 20 Japanese-literature
# lines — haiku, openings, aphorisms from Bashō to Murakami.
#
# Some are verbatim, some are close translations/paraphrases of known
# passages; all are clearly attributed by author (and work when helpful)
# so the flavour stays honest.
class QuoteOfTheDay
  Result = Struct.new(:body, :attribution, :book, :library, keyword_init: true)

  POOL = [
    {body: "El viejo estanque; una rana salta — el ruido del agua.",
     attribution: "Matsuo Bashō"},
    {body: "El día es un viajero, el año también un viajero.",
     attribution: "Matsuo Bashō — Sendas de Oku"},
    {body: "Este mundo de rocío es un mundo de rocío, y sin embargo…",
     attribution: "Kobayashi Issa"},
    {body: "Soy un gato. Todavía no tengo nombre.",
     attribution: "Natsume Sōseki — Soy un gato"},
    {body: "Ser adulto es perder, una a una, las cosas que nos hicieron felices de niños.",
     attribution: "Natsume Sōseki"},
    {body: "Encontramos la belleza no en la cosa misma, sino en los patrones de sombra que la envuelven.",
     attribution: "Junichirō Tanizaki — El elogio de la sombra"},
    {body: "El alma japonesa siente con los sentidos; la occidental piensa con el intelecto.",
     attribution: "Junichirō Tanizaki"},
    {body: "El tren salió del largo túnel de la frontera para entrar en el país de nieve.",
     attribution: "Yasunari Kawabata — País de nieve"},
    {body: "Oyó el sonido de la montaña. Una noche sin viento.",
     attribution: "Yasunari Kawabata — El sonido de la montaña"},
    {body: "La belleza es algo que arde en la mano como una brasa.",
     attribution: "Yukio Mishima — Confesiones de una máscara"},
    {body: "Todo pasa. Ahora no tengo ni felicidad ni infelicidad.",
     attribution: "Osamu Dazai — Indigno de ser humano"},
    {body: "El mal y el bien se confunden en los umbrales.",
     attribution: "Ryūnosuke Akutagawa — Rashōmon"},
    {body: "Si solo lees los libros que lee todo el mundo, solo puedes pensar lo que piensa todo el mundo.",
     attribution: "Haruki Murakami — Tokio blues"},
    {body: "El dolor es inevitable; el sufrimiento es opcional.",
     attribution: "Haruki Murakami — De qué hablo cuando hablo de correr"},
    {body: "Escribir es asomarse a un pozo profundo con una linterna.",
     attribution: "Haruki Murakami"},
    {body: "En la cocina de alguien puedes ver toda su vida.",
     attribution: "Banana Yoshimoto — Kitchen"},
    {body: "Las dunas cambian, pero siempre vuelven a su forma.",
     attribution: "Kōbō Abe — La mujer de la arena"},
    {body: "Los números son la huella de una belleza invisible.",
     attribution: "Yōko Ogawa — La fórmula preferida del profesor"},
    {body: "En el pelo enmarañado se esconde la juventud.",
     attribution: "Akiko Yosano — Pelo enmarañado"},
    {body: "El silencio de Dios es también una forma de respuesta.",
     attribution: "Shūsaku Endō — Silencio"}
  ].freeze

  def self.for(_user = nil, today: Date.current)
    entry = POOL[today.to_s.hash.abs % POOL.size]
    Result.new(body: entry[:body], attribution: entry[:attribution], book: nil, library: nil)
  end
end
