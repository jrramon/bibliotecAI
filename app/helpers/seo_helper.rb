module SeoHelper
  # Single source of truth for the SEO defaults used when a view
  # doesn't override anything. Stays in Spanish — the audience and
  # the product are Spanish-speaking. Update here, not in the layout.
  DEFAULT_TITLE = "BibliotecAI · Tu biblioteca de casa, conversando contigo"
  DEFAULT_DESCRIPTION = "BibliotecAI organiza la biblioteca de tu casa, la comparte con quienes te importan, y te deja conversar con tus libros. Hecha con calma para amantes de los libros."
  DEFAULT_OG_IMAGE = "/social.png"
  SITE_NAME = "BibliotecAI"
  TWITTER_CARD = "summary_large_image"
  REPO_URL = "https://github.com/jrramon/bibliotecAI"

  # Plain, definitional one-liner — written to be extractable by AI search
  # engines (they quote facts, not poetry). Reused on the landing, in the
  # JSON-LD and in /llms.txt so the "what is this" story is identical everywhere.
  ABOUT = "BibliotecAI es una app open source para organizar la biblioteca de tu casa, compartirla con las personas que te importan y consultarla por Telegram. Fotografías una estantería o una portada y Claude identifica los libros y rellena sus datos. Es gratis, de código abierto (AGPL v3) y, de momento, por invitación."

  # Single source of truth for the FAQ: rendered as visible Q&A on the landing
  # AND as FAQPage JSON-LD (Google requires the structured text to match the
  # visible text). Edit here, both stay in sync.
  FAQ_ITEMS = [
    {q: "¿Es gratis?",
     a: "Sí. BibliotecAI es gratis y de código abierto (licencia AGPL v3). De momento las cuentas son por invitación: te apuntas a la lista de espera y te avisamos cuando hay hueco."},
    {q: "¿Cómo funciona el bot de Telegram?",
     a: "Vinculas tu cuenta y le escribes al bot como a un bibliotecario: «¿qué tengo de Murakami?», «apunta Kokoro en mi wishlist». También puedes mandarle la foto de una portada y la añade a tu biblioteca, o la apunta en tu wishlist si pones «wishlist» en el caption."},
    {q: "¿Cómo añado libros?",
     a: "De tres formas: a mano, fotografiando una estantería entera (Claude identifica los lomos uno a uno) o fotografiando una sola portada (Claude rellena título, autor y demás metadatos)."},
    {q: "¿En qué se diferencia de Goodreads?",
     a: "BibliotecAI es para tu biblioteca física real, compartida con un grupo pequeño (casa, pareja, club de lectura), no una red social de reseñas. Añades libros con una foto, la consultas por Telegram, y es open source y autohospedable. Tus bibliotecas y tu wishlist son privadas."},
    {q: "¿Puedo autohospedarlo?",
     a: "Sí. El código es abierto y está en GitHub; puedes desplegarlo en tu propio servidor."},
    {q: "¿Mis datos son privados?",
     a: "Sí. Tus bibliotecas y tu lista de deseos solo las ven las personas con las que compartes cada biblioteca. La wishlist tiene un enlace público opcional que tú decides activar."}
  ].freeze

  # Page-level title. Views set `content_for(:title) { "Lista de espera" }`;
  # we prepend it to the brand and keep it under ~60 chars total.
  def page_title
    custom = content_for(:title)
    return DEFAULT_TITLE if custom.blank?
    "#{custom} · #{SITE_NAME}"
  end

  def meta_description
    content_for(:description).presence || DEFAULT_DESCRIPTION
  end

  def og_image_url
    image = content_for(:og_image).presence || DEFAULT_OG_IMAGE
    image.start_with?("http") ? image : "#{request.base_url}#{image}"
  end

  def canonical_url
    content_for(:canonical).presence || request.url.split("?").first
  end

  # JSON-LD payload for the landing. Tells search engines we're an
  # open source software project so result pages can show richer cards.
  def site_json_ld
    {
      "@context" => "https://schema.org",
      "@type" => "SoftwareApplication",
      "name" => SITE_NAME,
      "description" => ABOUT,
      "url" => request.base_url + "/",
      "applicationCategory" => "BookmarksApplication",
      "operatingSystem" => "Web",
      "isAccessibleForFree" => true,
      "offers" => {"@type" => "Offer", "price" => "0", "priceCurrency" => "EUR"},
      "featureList" => [
        "Bibliotecas compartidas con varios lectores",
        "Identificación de libros por foto de estantería o de portada con Claude",
        "Asistente por Telegram para consultar y gestionar la biblioteca",
        "Lista de deseos (wishlist) privada con enlace público opcional",
        "Open source y autohospedable"
      ],
      "license" => "https://www.gnu.org/licenses/agpl-3.0.html",
      "codeRepository" => REPO_URL,
      "inLanguage" => "es"
    }.to_json.html_safe
  end

  # FAQPage structured data, built from the same FAQ_ITEMS shown on the page.
  def faq_json_ld
    {
      "@context" => "https://schema.org",
      "@type" => "FAQPage",
      "mainEntity" => FAQ_ITEMS.map do |item|
        {
          "@type" => "Question",
          "name" => item[:q],
          "acceptedAnswer" => {"@type" => "Answer", "text" => item[:a]}
        }
      end
    }.to_json.html_safe
  end
end
