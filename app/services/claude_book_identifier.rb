require "json"
require "open3"
require "tempfile"
require "timeout"

class ClaudeBookIdentifier
  Result = Struct.new(:books, :unidentified, :raw, :image_width, :image_height, :usage, keyword_init: true)
  Error = Class.new(StandardError)

  CLAUDE_TIMEOUT = 180 # seconds
  # Local fallback. The live version lives in Langfuse as
  # "shelf-identification"; placeholders are Mustache so the same body
  # works in both places (see ClaudeCoverIdentifier for the pattern).
  PROMPT_TEMPLATE = <<~PROMPT
    Look at the bookshelf photograph at the absolute path:
    {{image_path}}

    Identify every book whose spine is readable. Return a SINGLE JSON object,
    no prose, no markdown fences, with this exact schema:

    {
      "image_width": <integer pixels>,
      "image_height": <integer pixels>,
      "books": [
        {
          "title": "...",
          "author": "...",
          "confidence": 0.0-1.0,
          "cdu": "...",
          "genres": ["...", "..."]
        }
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
    - `cdu` is the Clasificación Decimal Universal code (Spanish CDU, the library
      standard): a dotted numeric string like "82-31" (novela), "159.9" (psicología),
      "330" (economía), "658" (management/dirección de empresas), "94(460)"
      (historia de España). Pick the most specific code you're confident about;
      empty string if unsure.
    - `genres` is an array of 1-4 short Spanish genre/topic tags — e.g.
      ["Novela histórica", "Guerra Civil"], ["Management", "Agile"],
      ["Ensayo", "Filosofía"]. Empty array is fine for non-obvious cases.
    - If you can't see any books, return empty arrays — never invent titles.
    - CRITICAL — OUTPUT FORMAT: your entire reply must be exactly one JSON
      object and nothing else. No preamble, no explanation, no apology, no
      commentary, no markdown fences — not even when the photo is
      low-resolution, unreadable, or you were unable to crop or zoom. If
      you cannot identify any book for ANY reason, still return the object
      with "image_width" / "image_height" filled and "books": [] and
      "unidentified": [].
  PROMPT

  def self.call(...) = new(...).call

  def initialize(shelf_photo, claude_bin: ENV.fetch("CLAUDE_BIN", "claude"), model: nil, trace_id: nil)
    @shelf_photo = shelf_photo
    @claude_bin = claude_bin
    @model = model
    @trace_id = trace_id
  end

  def call
    # Write to a project-local tmp dir so the claude CLI (which sandboxes file
    # access to its working directory by default) can read the image.
    base = Rails.root.join("tmp/shelf_photos")
    FileUtils.mkdir_p(base)
    image_path = base.join("#{@shelf_photo.id}-#{@shelf_photo.image.filename}").to_s
    File.binwrite(image_path, @shelf_photo.image.download)

    prompt_obj = Langfuse::Prompt.get("shelf-identification", fallback: PROMPT_TEMPLATE)
    prompt = prompt_obj.compile(image_path: image_path)
    started_at = Time.now
    lf = {
      trace_id: @trace_id,
      trace_name: "shelf-identification",
      generation_name: "claude -p (shelf)",
      started_at: started_at,
      prompt: prompt,
      input: @shelf_photo.image.filename.to_s,
      metadata: {shelf_photo_id: @shelf_photo.id, library_id: @shelf_photo.library_id},
      prompt_name: prompt_obj.name,
      prompt_version: prompt_obj.version
    }

    begin
      stdout, stderr, status = nil

      argv = [@claude_bin, "-p", prompt, "--output-format", "json", "--add-dir", base.to_s]
      argv += ["--model", @model] if @model

      Timeout.timeout(CLAUDE_TIMEOUT) do
        stdout, stderr, status = Open3.capture3(*argv, chdir: Rails.root.to_s)
      end

      raise Error, "claude exited #{status.exitstatus}: #{stderr}" unless status.success?

      payload, usage = parse(stdout)
      Langfuse::Trace.record(**lf, output: payload, envelope: usage)
      Result.new(
        books: Array(payload["books"]),
        unidentified: Array(payload["unidentified"]),
        raw: payload,
        image_width: payload["image_width"]&.to_i,
        image_height: payload["image_height"]&.to_i,
        usage: usage
      )
    rescue => e
      Langfuse::Trace.record(**lf, error_message: e.message)
      raise
    end
  ensure
    File.delete(image_path) if defined?(image_path) && File.exist?(image_path.to_s)
  end

  private

  # Claude's `-p --output-format json` wraps the assistant output as a string in
  # `{"result": "<assistant text>", "usage": {...}, "total_cost_usd": …, …}`;
  # we need the inner JSON for the assistant output and the rest of the
  # envelope for usage telemetry.
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
    raise Error, "claude returned non-JSON output: #{e.message}\n--- raw ---\n#{stdout.truncate(800)}"
  end
end
