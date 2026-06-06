require "test_helper"

class SeoControllerTest < ActionDispatch::IntegrationTest
  test "robots.txt is rendered with the request's base url" do
    get "/robots.txt"

    assert_response :ok
    assert_equal "text/plain", response.media_type
    assert_match(/User-agent: \*/, response.body)
    assert_match(/Disallow: \/w\//, response.body)
    # The Sitemap line uses request.base_url so it adapts per deploy.
    assert_match(%r{Sitemap: https?://[^/]+/sitemap\.xml}, response.body)
  end

  test "robots.txt explicitly allows the major AI crawlers" do
    get "/robots.txt"

    assert_match(/User-agent: GPTBot/, response.body)
    assert_match(/User-agent: ClaudeBot/, response.body)
    assert_match(/User-agent: PerplexityBot/, response.body)
    assert_match(/User-agent: Google-Extended/, response.body)
  end

  test "llms.txt summarizes the product with FAQ and links" do
    get "/llms.txt"

    assert_response :ok
    assert_equal "text/plain", response.media_type
    assert_match(/# BibliotecAI/, response.body)
    assert_match(/app open source/i, response.body)
    assert_match(/¿Es gratis\?/, response.body)
    assert_match(%r{github\.com/jrramon/bibliotecAI}, response.body)
  end

  test "sitemap.xml lists the public surfaces with the request's base url" do
    get "/sitemap.xml"

    assert_response :ok
    assert_equal "application/xml", response.media_type
    assert_match(/<urlset/, response.body)
    assert_match(%r{<loc>https?://[^/]+/</loc>}, response.body)
    assert_match(%r{<loc>https?://[^/]+/users/sign_up</loc>}, response.body)
    assert_match(%r{<loc>https?://[^/]+/users/sign_in</loc>}, response.body)
  end
end
