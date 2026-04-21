require "json"
require "open3"
require "fileutils"
require "timeout"

# Asks the host Claude CLI to identify a single book from a photo of its
# cover. Returns a flat hash with the metadata fields we pre-fill into the
# add-book modal form. Same shell-out mechanics as ClaudeBookIdentifier
# (image written to tmp/cover_photos/, `--add-dir`, chdir Rails.root) —
# only the prompt and return shape differ.
class ClaudeCoverIdentifier
  Error = Class.new(StandardError)
  CLAUDE_TIMEOUT = 120

  PROMPT_TEMPLATE = <<~PROMPT
    Look at the photograph of a single book cover at the absolute path:
    %<image_path>s

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
  PROMPT

  def self.call(...) = new(...).call

  def initialize(cover_photo, claude_bin: ENV.fetch("CLAUDE_BIN", "claude"))
    @cover_photo = cover_photo
    @claude_bin = claude_bin
  end

  def call
    base = Rails.root.join("tmp/cover_photos")
    FileUtils.mkdir_p(base)
    image_path = base.join("#{@cover_photo.id}-#{@cover_photo.image.filename}").to_s
    File.binwrite(image_path, @cover_photo.image.download)

    prompt = format(PROMPT_TEMPLATE, image_path: image_path)
    stdout, stderr, status = nil

    Timeout.timeout(CLAUDE_TIMEOUT) do
      stdout, stderr, status = Open3.capture3(
        @claude_bin, "-p", prompt,
        "--output-format", "json",
        "--add-dir", base.to_s,
        chdir: Rails.root.to_s
      )
    end

    raise Error, "claude exited #{status.exitstatus}: #{stderr}" unless status.success?

    parse(stdout)
  ensure
    File.delete(image_path) if defined?(image_path) && File.exist?(image_path.to_s)
  end

  private

  def parse(stdout)
    envelope = JSON.parse(stdout)
    inner = (envelope.is_a?(Hash) && envelope["result"].is_a?(String)) ? envelope["result"] : stdout
    JSON.parse(strip_fences(inner))
  rescue JSON::ParserError => e
    raise Error, "claude returned non-JSON output: #{e.message}\n--- raw ---\n#{stdout.to_s.truncate(800)}"
  end

  def strip_fences(text)
    text.to_s.strip.sub(/\A```(?:json)?\s*/, "").sub(/```\s*\z/, "")
  end
end
