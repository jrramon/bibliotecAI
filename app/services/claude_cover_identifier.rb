require "json"
require "fileutils"
require "timeout"

# Asks the host Claude CLI to identify a single book from a photo of its
# cover. Returns a flat hash with the metadata fields we pre-fill into the
# add-book modal form. Same shell-out mechanics as ClaudeBookIdentifier
# (image written to tmp/cover_photos/, `--add-dir`, chdir Rails.root) —
# only the prompt and return shape differ.
class ClaudeCoverIdentifier
  Result = Struct.new(:data, :usage, keyword_init: true)
  Error = Class.new(StandardError)
  CLAUDE_TIMEOUT = 120
  # Substituted for {{image_path}} when the provider sends the image inline
  # (openai_compatible) — there is no file for the model to open.
  INLINE_IMAGE_NOTE = "the image attached directly to this message (there is no file path to open)"

  # Local fallback for the prompt. The "live" version lives in Langfuse
  # under the name "cover-identification" and is fetched via
  # Langfuse::Prompt.get (5-min cached). This constant is what `compile`
  # uses when Langfuse isn't configured / is unreachable. Placeholders use
  # Mustache ({{image_path}}) so the same body works in both places.
  PROMPT_TEMPLATE = <<~PROMPT
    Look at the photograph of a single book cover at the absolute path:
    {{image_path}}

    Identify the book and return a SINGLE JSON object (no prose, no markdown
    fences) with this exact schema:

    {
      "title": "...",
      "subtitle": "...",
      "author": "...",
      "publisher": "...",
      "isbn": "...",
      "published_year": <integer>,
      "page_count": <integer>,
      "language": "...",
      "synopsis": "...",
      "cdu": "...",
      "genres": ["...", "..."],
      "confidence": 0.0-1.0
    }

    Rules:
    - Every field is optional — omit or use "" / null if you're not confident.
    - `title` is required; if you genuinely cannot read any title, return
      `{"title": "", "confidence": 0}`.
    - `author` is the author name as it appears on the cover.
    - `language` is the ISO 639-1 code of the cover text (e.g. "es", "en", "ja").
    - `cdu` is the Spanish CDU (Clasificación Decimal Universal) code — a
      dotted numeric like "82-31" (novela), "159.9" (psicología), "330"
      (economía), "94(460)" (historia de España). Leave empty if unsure.
    - `genres` is 1-4 short Spanish tags like ["Novela histórica", "Guerra Civil"]
      or ["Ensayo", "Filosofía"]. Empty array if unsure.
    - `synopsis` may come from what's printed on the back cover if visible;
      otherwise leave empty. Never invent a synopsis.
    - `confidence` reflects how sure you are about title + author together.
    - Never invent ISBNs or publishers — only include them if they are
      legible on the cover.
    - CRITICAL — OUTPUT FORMAT: your entire reply must be exactly one JSON
      object and nothing else. No preamble, no explanation, no apology, no
      commentary, no markdown fences — not even when the image is not a
      book cover, is unreadable, or you were unable to do something. If you
      cannot identify the book for ANY reason, your entire reply is
      exactly: {"title": "", "confidence": 0}
  PROMPT

  def self.call(...) = new(...).call

  def initialize(cover_photo)
    @cover_photo = cover_photo
  end

  def call
    base = Rails.root.join("tmp/cover_photos")
    FileUtils.mkdir_p(base)
    image_path = base.join("#{@cover_photo.id}-#{@cover_photo.image.filename}").to_s
    File.binwrite(image_path, @cover_photo.image.download)

    provider, model = Llm::Config.resolve(:cover)
    image_ref = provider.inline_images? ? INLINE_IMAGE_NOTE : image_path

    prompt_obj = Langfuse::Prompt.get("cover-identification", fallback: PROMPT_TEMPLATE)
    prompt = prompt_obj.compile(image_path: image_ref)
    started_at = Time.now
    # Constant trace fields, splatted into the success and error calls below.
    lf = {
      trace_name: "cover-identification",
      generation_name: "claude -p (cover)",
      started_at: started_at,
      prompt: prompt,
      input: @cover_photo.image.filename.to_s,
      metadata: {cover_photo_id: @cover_photo.id, library_id: @cover_photo.library_id},
      prompt_name: prompt_obj.name,
      prompt_version: prompt_obj.version
    }

    begin
      response = provider.complete(Llm::Request.new(
        prompt: prompt,
        image_paths: [image_path],
        model: model,
        timeout: CLAUDE_TIMEOUT,
        response_format: :json
      ))

      data = extract_payload(response.text)
      usage = response.usage_envelope
      Langfuse::Trace.record(**lf, output: data, envelope: usage)
      Result.new(data: data, usage: usage)
    rescue Timeout::Error => e
      Langfuse::Trace.record(**lf, error_message: e.message)
      raise
    rescue => e
      Langfuse::Trace.record(**lf, error_message: e.message)
      raise Error, e.message
    end
  ensure
    File.delete(image_path) if defined?(image_path) && File.exist?(image_path.to_s)
  end

  private

  def extract_payload(text)
    JSON.parse(ClaudeJson.extract(text))
  rescue JSON::ParserError => e
    raise Error, "model returned non-JSON output: #{e.message}\n--- raw ---\n#{text.to_s.truncate(800)}"
  end
end
