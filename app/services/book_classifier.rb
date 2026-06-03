require "json"
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

  def initialize(book)
    @book = book
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
      provider, model = Llm::Config.resolve(:classify)
      response = provider.complete(Llm::Request.new(
        prompt: prompt,
        image_paths: [],
        model: model,
        timeout: CLAUDE_TIMEOUT,
        response_format: :json
      ))

      payload = extract_payload(response.text)
      @book.update(cdu: payload["cdu"].presence, genres: Array(payload["genres"]))
      Langfuse::Trace.record(**lf, output: payload, envelope: response.usage_envelope)
      payload
    rescue Timeout::Error => e
      Langfuse::Trace.record(**lf, error_message: e.message)
      raise
    rescue => e
      Langfuse::Trace.record(**lf, error_message: e.message)
      raise Error, e.message
    end
  end

  private

  def extract_payload(text)
    JSON.parse(ClaudeJson.extract(text))
  rescue JSON::ParserError => e
    raise Error, "model returned non-JSON: #{e.message}\n--- raw ---\n#{text.to_s.truncate(500)}"
  end
end
