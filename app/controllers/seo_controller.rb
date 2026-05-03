# Serves robots.txt and sitemap.xml dynamically so each deployment
# (canonical or fork) emits its own hostname without anyone having to
# regenerate a static file in public/. Both endpoints derive the host
# from `request.base_url`, so they always agree with whatever the
# reverse proxy is forwarding.
class SeoController < ApplicationController
  skip_before_action :touch_last_seen!, raise: false

  def robots
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

      Sitemap: #{request.base_url}/sitemap.xml
    ROBOTS
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
