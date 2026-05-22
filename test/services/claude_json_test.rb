require "test_helper"

class ClaudeJsonTest < ActiveSupport::TestCase
  test "returns a bare JSON object unchanged" do
    assert_equal '{"title": "Kokoro"}', ClaudeJson.extract('{"title": "Kokoro"}')
  end

  test "unwraps a fenced ```json block" do
    fenced = "```json\n{\"title\": \"Kokoro\"}\n```"
    assert_equal '{"title": "Kokoro"}', ClaudeJson.extract(fenced)
  end

  test "drops a prose preamble before the object" do
    raw = "I was unable to crop the image. Best assessment:\n\n{\"title\": \"India\"}"
    assert_equal '{"title": "India"}', ClaudeJson.extract(raw)
  end

  test "drops a prose epilogue after the object" do
    raw = "{\"title\": \"\", \"confidence\": 0}\n\nThis image is not a book cover."
    assert_equal '{"title": "", "confidence": 0}', ClaudeJson.extract(raw)
  end

  test "drops prose on both sides of a fenced block" do
    raw = "Here is my answer:\n```json\n{\"books\": []}\n```\nLet me know if you need more."
    assert_equal '{"books": []}', ClaudeJson.extract(raw)
  end

  test "keeps the outermost object when it has nested braces" do
    raw = "prefix {\"a\": {\"b\": 1}} suffix"
    assert_equal '{"a": {"b": 1}}', ClaudeJson.extract(raw)
  end

  test "the extracted slice round-trips through JSON.parse" do
    raw = "{\"title\": \"\", \"confidence\": 0}\n\nThis image is not a book cover."
    parsed = JSON.parse(ClaudeJson.extract(raw))
    assert_equal({"title" => "", "confidence" => 0}, parsed)
  end

  test "returns the input untouched when there is no object" do
    assert_equal "no json here", ClaudeJson.extract("no json here")
    assert_equal "", ClaudeJson.extract(nil)
  end
end
