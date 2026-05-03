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
