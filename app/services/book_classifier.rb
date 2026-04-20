require "json"
require "open3"
require "timeout"

# Calls the host-installed Claude CLI to assign a CDU code + genre tags to an
# already-known (title, author) pair. Used for re-classifying books that were
# created before shelf identification started capturing cdu/genres.
class BookClassifier
  Error = Class.new(StandardError)
  CLAUDE_TIMEOUT = 60

  PROMPT = <<~PROMPT
    For the book "%<title>s" by %<author>s, return a SINGLE JSON object with
    the Spanish Clasificación Decimal Universal code and 1-4 short genre/topic
    tags in Spanish. No prose, no markdown fences, this exact schema:

    {"cdu": "<dotted numeric string, e.g. 82-31, 159.9, 330, 94(460)>", "genres": ["..."]}

    Rules:
    - cdu is a string. Empty string if unsure.
    - genres are short Spanish tags like "Novela histórica", "Management", "Ensayo".
    - Empty genres array is fine when classification is genuinely unclear.
  PROMPT

  def self.call(...) = new(...).call

  def initialize(book, claude_bin: ENV.fetch("CLAUDE_BIN", "claude"))
    @book = book
    @claude_bin = claude_bin
  end

  def call
    author = @book.author.presence || "unknown author"
    prompt = format(PROMPT, title: @book.title, author: author)

    stdout, stderr, status = nil
    Timeout.timeout(CLAUDE_TIMEOUT) do
      stdout, stderr, status = Open3.capture3(@claude_bin, "-p", prompt, "--output-format", "json")
    end
    raise Error, "claude exited #{status.exitstatus}: #{stderr}" unless status.success?

    payload = parse(stdout)
    @book.update(cdu: payload["cdu"].presence, genres: Array(payload["genres"]))
    payload
  end

  private

  def parse(stdout)
    envelope = JSON.parse(stdout)
    inner = (envelope.is_a?(Hash) && envelope["result"].is_a?(String)) ? envelope["result"] : stdout
    JSON.parse(strip_fences(inner))
  rescue JSON::ParserError => e
    raise Error, "claude returned non-JSON: #{e.message}\n--- raw ---\n#{stdout.truncate(500)}"
  end

  def strip_fences(text)
    text.to_s.strip.sub(/\A```(?:json)?\s*/, "").sub(/```\s*\z/, "")
  end
end
