# Serves robots.txt and sitemap.xml dynamically so each deployment
# (canonical or fork) emits its own hostname without anyone having to
# regenerate a static file in public/. Both endpoints derive the host
# from `request.base_url`, so they always agree with whatever the
# reverse proxy is forwarding.
class SeoController < ApplicationController
  skip_before_action :touch_last_seen!, raise: false

  # Crawlers de IA permitidos a propósito (GPTBot, ClaudeBot, PerplexityBot,
  # Google-Extended…): queremos aparecer en sus respuestas. Cada uno con su
  # bloque solo para dejar la intención explícita; todos comparten el único
  # disallow real (/w/, enlaces privados de wishlist).
  AI_CRAWLERS = %w[
    GPTBot OAI-SearchBot ChatGPT-User ClaudeBot anthropic-ai Claude-Web
    PerplexityBot Google-Extended Applebot-Extended CCBot Bytespider
  ].freeze

  def robots
    ai_blocks = AI_CRAWLERS.map { |ua| "User-agent: #{ua}\nDisallow: /w/\n" }.join("\n")

    render plain: <<~ROBOTS, content_type: "text/plain"
      # Públicas (landing, sign-up, sign-in) se indexan por defecto.
      # Las rutas auth'd devuelven 302 a /users/sign_in y los crawlers
      # las desindexan solas, así que no hace falta enumerarlas. Listar
      # rutas internas en robots.txt sirve más como mapa para curiosos
      # que como protección — la autenticación es lo que protege.
      #
      # Único disallow: /w/<token> son enlaces de wishlist privados;
      # aunque el dueño los comparta, no queremos que acaben indexados.

      User-agent: *
      Disallow: /w/

      # Crawlers de IA permitidos a propósito (para aparecer en sus respuestas).
      #{ai_blocks}
      Sitemap: #{request.base_url}/sitemap.xml
    ROBOTS
  end

  # /llms.txt — resumen del producto en texto plano para motores de IA
  # (estándar emergente, llmstxt.org). Mismo "qué es" y FAQ que la landing.
  def llms
    faq = SeoHelper::FAQ_ITEMS.map { |i| "- **#{i[:q]}** #{i[:a]}" }.join("\n")

    render plain: <<~LLMS, content_type: "text/plain"
      # BibliotecAI

      > #{SeoHelper::ABOUT}

      ## Preguntas frecuentes

      #{faq}

      ## Enlaces

      - Web: #{request.base_url}/
      - Registro (lista de espera): #{request.base_url}/users/sign_up
      - Código (open source, AGPL v3): #{SeoHelper::REPO_URL}
    LLMS
  end

  def sitemap
    urls = [
      {loc: "#{request.base_url}/", priority: "1.0"},
      {loc: "#{request.base_url}/users/sign_up", priority: "0.8"},
      {loc: "#{request.base_url}/users/sign_in", priority: "0.5"}
    ]

    body = +%(<?xml version="1.0" encoding="UTF-8"?>\n)
    body << %(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n)
    urls.each do |u|
      body << "  <url>\n"
      body << "    <loc>#{u[:loc]}</loc>\n"
      body << "    <changefreq>monthly</changefreq>\n"
      body << "    <priority>#{u[:priority]}</priority>\n"
      body << "  </url>\n"
    end
    body << "</urlset>\n"

    render xml: body
  end
end
