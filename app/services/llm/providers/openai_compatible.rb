require "net/http"
require "json"
require "base64"

module Llm
  module Providers
    # Generic OpenAI-compatible HTTP provider. Works with any endpoint that
    # speaks the /chat/completions schema (NaN.builders, OpenRouter, Together,
    # a local vLLM, …) — point LLM_API_BASE_URL + LLM_API_KEY at it. Uses stdlib
    # net/http, mirroring Langfuse::Client. Images are sent inline as base64
    # data URLs.
    class OpenaiCompatible
      DEFAULT_TIMEOUT = 120
      OPEN_TIMEOUT = 10
      MAX_ATTEMPTS = 2 # retry once on HTTP 429

      def initialize(api_key: Llm::Config::API_KEY, base_url: Llm::Config::API_BASE_URL)
        @api_key = api_key
        @base_url = base_url.to_s.chomp("/")
      end

      # Images are sent inline (base64), so the prompt must NOT point the model
      # at a file path it can't open — the service substitutes a note instead.
      def inline_images? = true

      def complete(request)
        raise Llm::Error, "LLM_API_KEY is not set" if @api_key.blank?

        body = {
          model: request.model,
          messages: [{role: "user", content: content_blocks(request)}],
          temperature: 0
        }
        body[:response_format] = {type: "json_object"} if request.response_format == :json

        data = post("/chat/completions", body, timeout: request.timeout || DEFAULT_TIMEOUT)
        text = data.dig("choices", 0, "message", "content").to_s
        Llm::Response.new(text: text, usage_envelope: usage_envelope(data["usage"], request.model))
      end

      # Multi-turn tool-calling loop. Advertises `tools` (OpenAI function
      # schemas), and on each `finish_reason: tool_calls` runs every requested
      # call through `tool_executor` and feeds the results back, until the model
      # answers in plain text or max_turns is hit.
      def run_agent(system_text:, user_text:, tools:, tool_executor:, model:, max_turns:, timeout: DEFAULT_TIMEOUT)
        raise Llm::Error, "LLM_API_KEY is not set" if @api_key.blank?

        messages = [
          {role: "system", content: system_text},
          {role: "user", content: user_text}
        ]
        totals = {input: 0, output: 0}
        tool_names = []

        max_turns.times do
          body = {model: model, messages: messages, tools: tools, tool_choice: "auto", temperature: 0}
          data = post("/chat/completions", body, timeout: timeout)
          accumulate(totals, data["usage"])

          message = data.dig("choices", 0, "message") || {}
          tool_calls = message["tool_calls"]

          if tool_calls.is_a?(Array) && tool_calls.any?
            messages << message # echo assistant turn (carries the tool_call ids)
            tool_calls.each do |tc|
              name = tc.dig("function", "name")
              args = parse_arguments(tc.dig("function", "arguments"))
              tool_names << name
              messages << {
                role: "tool",
                tool_call_id: tc["id"],
                content: tool_executor.call(name, args).to_s
              }
            end
            next
          end

          return Llm::AgentResult.new(
            ok: true,
            text: message["content"].to_s.strip,
            error: nil,
            usage_envelope: agent_usage_envelope(totals, model),
            tool_names: tool_names
          )
        end

        Llm::AgentResult.new(
          ok: false,
          text: nil,
          error: "agent hit max_turns (#{max_turns}) without a final answer",
          usage_envelope: agent_usage_envelope(totals, model),
          tool_names: tool_names
        )
      end

      private

      def parse_arguments(raw)
        return {} if raw.blank?
        JSON.parse(raw)
      rescue JSON::ParserError
        {}
      end

      def accumulate(totals, usage)
        return unless usage.is_a?(Hash)
        totals[:input] += usage["prompt_tokens"].to_i
        totals[:output] += usage["completion_tokens"].to_i
      end

      def agent_usage_envelope(totals, model)
        envelope = {"usage" => {"input_tokens" => totals[:input], "output_tokens" => totals[:output]}}
        cost = Llm::Pricing.cost_usd(model: model, input_tokens: totals[:input], output_tokens: totals[:output])
        envelope["total_cost_usd"] = cost if cost
        envelope
      end

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
      # downstream needs no change. Cost (total_cost_usd) is injected from
      # Llm::Pricing when the model's price is configured; otherwise absent
      # (the row counts as $0 against ClaudeBudget — correct for flat-rate APIs).
      def usage_envelope(usage, model)
        return nil unless usage.is_a?(Hash)

        input = usage["prompt_tokens"]
        output = usage["completion_tokens"]
        envelope = {
          "usage" => {"input_tokens" => input, "output_tokens" => output}.compact
        }
        cost = Llm::Pricing.cost_usd(model: model, input_tokens: input, output_tokens: output)
        envelope["total_cost_usd"] = cost if cost
        envelope
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
          raise Llm::Error, "LLM API #{response.code}: #{response.body.to_s.truncate(500)}"
        end
        JSON.parse(response.body)
      rescue JSON::ParserError => e
        raise Llm::Error, "LLM API returned non-JSON: #{e.message}"
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
