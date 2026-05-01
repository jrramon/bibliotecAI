module SeoHelper
  # Single source of truth for the SEO defaults used when a view
  # doesn't override anything. Stays in Spanish — the audience and
  # the product are Spanish-speaking. Update here, not in the layout.
  DEFAULT_TITLE = "BibliotecAI · Tu biblioteca de casa, conversando contigo"
  DEFAULT_DESCRIPTION = "BibliotecAI organiza la biblioteca de tu casa, la comparte con quienes te importan, y te deja conversar con tus libros. Hecha con calma para amantes de los libros."
  DEFAULT_OG_IMAGE = "/social.png"
  SITE_NAME = "BibliotecAI"
  TWITTER_CARD = "summary_large_image"

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
      "description" => DEFAULT_DESCRIPTION,
      "url" => request.base_url + "/",
      "applicationCategory" => "BookmarksApplication",
      "operatingSystem" => "Web",
      "offers" => {"@type" => "Offer", "price" => "0", "priceCurrency" => "EUR"},
      "license" => "https://www.gnu.org/licenses/agpl-3.0.html",
      "codeRepository" => "https://github.com/jrramon/bibliotecAI",
      "inLanguage" => "es"
    }.to_json.html_safe
  end
end
