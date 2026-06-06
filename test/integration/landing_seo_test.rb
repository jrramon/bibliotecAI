require "test_helper"

class LandingSeoTest < ActionDispatch::IntegrationTest
  test "landing shows the definitional section and FAQ (extractable by AI search)" do
    get "/"

    assert_response :ok
    assert_match(/¿Qué es BibliotecAI\?/, response.body)
    assert_match(/Preguntas frecuentes/, response.body)
    assert_match(/¿Es gratis\?/, response.body)
    assert_match(/¿En qué se diferencia de Goodreads\?/, response.body)
  end

  test "landing embeds SoftwareApplication and FAQPage JSON-LD" do
    get "/"

    assert_match(/"@type":"SoftwareApplication"/, response.body)
    assert_match(/"@type":"FAQPage"/, response.body)
    assert_match(/"@type":"Question"/, response.body)
  end
end
