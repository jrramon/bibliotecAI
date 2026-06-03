require "net/http"
require "json"
require "base64"

module Llm
  module Providers
    # OpenAI-compatible HTTP provider (NaN.builders). Uses stdlib net/http,
    # mirroring Langfuse::Client. Images are sent inline as base64 data URLs.
    class NanApi
      DEFAULT_TIMEOUT = 120
      OPEN_TIMEOUT = 10
      MAX_ATTEMPTS = 2 # retry once on HTTP 429

      def initialize(api_key: Llm::Config::NAN_API_KEY, base_url: Llm::Config::NAN_BASE_URL)
        @api_key = api_key
        @base_url = base_url.to_s.chomp("/")
      end

      def complete(request)
        raise Llm::Error, "NAN_API_KEY is not set" if @api_key.blank?

        body = {
          model: request.model,
          messages: [{role: "user", content: content_blocks(request)}],
          temperature: 0
        }
        body[:response_format] = {type: "json_object"} if request.response_format == :json

        data = post("/chat/completions", body, timeout: request.timeout || DEFAULT_TIMEOUT)
        text = data.dig("choices", 0, "message", "content").to_s
        Llm::Response.new(text: text, usage_envelope: usage_envelope(data["usage"]))
      end

      private

      def content_blocks(request)
        blocks = [{type: "text", text: request.prompt}]
        Array(request.image_paths).each do |path|
          blocks << {type: "image_url", image_url: {url: data_url(path)}}
        end
        blocks
      end

      def data_url(path)
        "data:#{mime_for(path)};base64,#{Base64.strict_encode64(File.binread(path))}"
      end

      def mime_for(path)
        case File.extname(path).downcase
        when ".png" then "image/png"
        when ".webp" then "image/webp"
        when ".gif" then "image/gif"
        else "image/jpeg"
        end
      end

      # OpenAI usage -> claude-shaped envelope so the Langfuse + budget code
      # downstream needs no change. NaN returns no cost (added in a later slice).
      def usage_envelope(usage)
        return nil unless usage.is_a?(Hash)
        {
          "usage" => {
            "input_tokens" => usage["prompt_tokens"],
            "output_tokens" => usage["completion_tokens"]
          }.compact
        }
      end

      def post(path, body, timeout:)
        uri = URI("#{@base_url}#{path}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = timeout

        req = Net::HTTP::Post.new(uri)
        req["Authorization"] = "Bearer #{@api_key}"
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(body)

        response = request_with_retry(http, req)
        unless response.is_a?(Net::HTTPSuccess)
          raise Llm::Error, "NaN API #{response.code}: #{response.body.to_s.truncate(500)}"
        end
        JSON.parse(response.body)
      rescue JSON::ParserError => e
        raise Llm::Error, "NaN API returned non-JSON: #{e.message}"
      end

      def request_with_retry(http, req)
        attempt = 0
        loop do
          attempt += 1
          response = http.request(req)
          return response unless response.is_a?(Net::HTTPTooManyRequests) && attempt < MAX_ATTEMPTS
          sleep(0.5 * attempt)
        end
      end
    end
  end
end
