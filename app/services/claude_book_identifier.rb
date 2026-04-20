require "json"
require "open3"
require "tempfile"
require "timeout"

class ClaudeBookIdentifier
  Result = Struct.new(:books, :unidentified, :raw, :image_width, :image_height, keyword_init: true)
  Error = Class.new(StandardError)

  CLAUDE_TIMEOUT = 180 # seconds
  PROMPT_TEMPLATE = <<~PROMPT
    Look at the bookshelf photograph at the absolute path:
    %<image_path>s

    Identify every book whose spine is readable. Return a SINGLE JSON object,
    no prose, no markdown fences, with this exact schema:

    {
      "image_width": <integer pixels>,
      "image_height": <integer pixels>,
      "books": [
        {"title": "...", "author": "...", "confidence": 0.0-1.0}
      ],
      "unidentified": [
        {"x1": <int>, "y1": <int>, "x2": <int>, "y2": <int>, "reason": "..."}
      ]
    }

    Rules:
    - Use the original image's pixel coordinates for bounding boxes (top-left origin).
    - Only include `unidentified` boxes around spines you tried to read but could not — not for blank shelf space.
    - `author` may be empty string if the spine only shows the title.
    - `confidence` reflects how sure you are about title + author together.
    - If you can't see any books, return empty arrays — never invent titles.
  PROMPT

  def self.call(...) = new(...).call

  def initialize(shelf_photo, claude_bin: ENV.fetch("CLAUDE_BIN", "claude"))
    @shelf_photo = shelf_photo
    @claude_bin = claude_bin
  end

  def call
    # Write to a project-local tmp dir so the claude CLI (which sandboxes file
    # access to its working directory by default) can read the image.
    base = Rails.root.join("tmp/shelf_photos")
    FileUtils.mkdir_p(base)
    image_path = base.join("#{@shelf_photo.id}-#{@shelf_photo.image.filename}").to_s
    File.binwrite(image_path, @shelf_photo.image.download)

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

    payload = parse(stdout)
    Result.new(
      books: Array(payload["books"]),
      unidentified: Array(payload["unidentified"]),
      raw: payload,
      image_width: payload["image_width"]&.to_i,
      image_height: payload["image_height"]&.to_i
    )
  ensure
    File.delete(image_path) if defined?(image_path) && File.exist?(image_path.to_s)
  end

  private

  # Claude's `-p --output-format json` wraps the assistant output as a string in
  # `{"result": "<assistant text>"}`; we still need to parse the inner JSON.
  def parse(stdout)
    envelope = JSON.parse(stdout)
    inner = (envelope.is_a?(Hash) && envelope["result"].is_a?(String)) ? envelope["result"] : stdout
    JSON.parse(strip_fences(inner))
  rescue JSON::ParserError => e
    raise Error, "claude returned non-JSON output: #{e.message}\n--- raw ---\n#{stdout.truncate(800)}"
  end

  def strip_fences(text)
    text.to_s.strip.sub(/\A```(?:json)?\s*/, "").sub(/```\s*\z/, "")
  end
end
