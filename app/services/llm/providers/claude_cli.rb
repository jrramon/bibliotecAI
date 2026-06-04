require "open3"
require "timeout"

module Llm
  module Providers
    # Shells out to the `claude` Code CLI — a 1:1 extraction of the argv build
    # + envelope parsing that used to live in each Claude-calling service.
    # Behavior is identical to the pre-provider code path.
    class ClaudeCli
      def initialize(claude_bin: ENV.fetch("CLAUDE_BIN", "claude"))
        @claude_bin = claude_bin
      end

      # The CLI reads images by PATH (--add-dir), so the prompt should carry
      # the file path, not the bytes.
      def inline_images? = false

      def complete(request)
        argv = [@claude_bin, "-p", request.prompt, "--output-format", "json"]
        # The CLI reads images by PATH from a whitelisted dir (it does not get
        # the bytes); the path is already substituted into the prompt.
        Array(request.image_paths).map { |p| File.dirname(p) }.uniq.each do |dir|
          argv += ["--add-dir", dir]
        end
        argv += ["--model", request.model] if request.model.present?

        stdout, stderr, status = nil
        Timeout.timeout(request.timeout) do
          stdout, stderr, status = Open3.capture3(*argv, chdir: Rails.root.to_s)
        end
        raise Llm::Error, "claude exited #{status.exitstatus}: #{stderr}" unless status.success?

        parse_envelope(stdout)
      end

      private

      # `claude -p --output-format json` wraps the assistant output as a string
      # in {"result": "<text>", "usage": {...}, "total_cost_usd": …}. We split
      # the inner text from the rest of the envelope (used for usage telemetry).
      def parse_envelope(stdout)
        envelope = JSON.parse(stdout)
        if envelope.is_a?(Hash) && envelope["result"].is_a?(String)
          Llm::Response.new(text: envelope["result"], usage_envelope: envelope.except("result"))
        else
          Llm::Response.new(text: stdout, usage_envelope: nil)
        end
      rescue JSON::ParserError => e
        raise Llm::Error, "claude returned a non-JSON envelope: #{e.message}"
      end
    end
  end
end
