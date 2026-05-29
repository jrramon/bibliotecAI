require "json"
require "open3"
require "timeout"

# Calls the host-installed Claude CLI to assign a CDU code + genre tags to an
# already-known (title, author) pair. Used for re-classifying books that were
# created before shelf identification started capturing cdu/genres.
class BookClassifier
  Error = Class.new(StandardError)
  CLAUDE_TIMEOUT = 60

  # Local fallback for the "book-classifier" prompt in Langfuse.
  # Placeholders are Mustache so the same body serves both paths.
  PROMPT = <<~PROMPT
    For the book "{{title}}" by {{author}}, return a SINGLE JSON object with
    the Spanish Clasificación Decimal Universal code and 1-4 short genre/topic
    tags in Spanish. No prose, no markdown fences, this exact schema:

    {"cdu": "<dotted numeric string, e.g. 82-31, 159.9, 330, 94(460)>", "genres": ["..."]}

    Rules:
    - cdu is a string. Empty string if unsure.
    - genres are short Spanish tags like "Novela histórica", "Management", "Ensayo".
    - Empty genres array is fine when classification is genuinely unclear.
    - CRITICAL — OUTPUT FORMAT: your entire reply must be exactly one JSON
      object and nothing else — no preamble, no explanation, no markdown
      fences. If you cannot classify the book, your entire reply is
      exactly: {"cdu": "", "genres": []}
  PROMPT

  def self.call(...) = new(...).call

  def initialize(book, claude_bin: ENV.fetch("CLAUDE_BIN", "claude"))
    @book = book
    @claude_bin = claude_bin
  end

  def call
    author = @book.author.presence || "unknown author"
    prompt_obj = Langfuse::Prompt.get("book-classifier", fallback: PROMPT)
    prompt = prompt_obj.compile(title: @book.title, author: author)
    started_at = Time.now
    lf = {
      trace_name: "book-classification",
      generation_name: "claude -p (classify)",
      started_at: started_at,
      prompt: prompt,
      input: {title: @book.title, author: @book.author},
      metadata: {book_id: @book.id},
      prompt_name: prompt_obj.name,
      prompt_version: prompt_obj.version
    }

    begin
      stdout, stderr, status = nil
      Timeout.timeout(CLAUDE_TIMEOUT) do
        stdout, stderr, status = Open3.capture3(@claude_bin, "-p", prompt, "--output-format", "json")
      end
      raise Error, "claude exited #{status.exitstatus}: #{stderr}" unless status.success?

      payload, usage = parse(stdout)
      @book.update(cdu: payload["cdu"].presence, genres: Array(payload["genres"]))
      Langfuse::Trace.record(**lf, output: payload, envelope: usage)
      payload
    rescue => e
      Langfuse::Trace.record(**lf, error_message: e.message)
      raise
    end
  end

  private

  # Returns [parsed_inner_json, envelope_metadata_or_nil] — the envelope
  # carries the token usage and cost for Langfuse.
  def parse(stdout)
    envelope = JSON.parse(stdout)
    if envelope.is_a?(Hash) && envelope["result"].is_a?(String)
      inner = envelope["result"]
      usage = envelope.except("result")
    else
      inner = stdout
      usage = nil
    end
    [JSON.parse(ClaudeJson.extract(inner)), usage]
  rescue JSON::ParserError => e
    raise Error, "claude returned non-JSON: #{e.message}\n--- raw ---\n#{stdout.truncate(500)}"
  end
end
