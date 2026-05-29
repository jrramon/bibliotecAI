require "net/http"
require "json"

module Langfuse
  # A prompt fetched from Langfuse, ready to be compiled with runtime
  # variables. Wraps two pieces of info:
  #
  # - `body`:    the template text — Mustache-style placeholders like
  #              {{image_path}} get substituted by #compile.
  # - `version`: the integer version stored in Langfuse, or nil if the
  #              prompt came from the local fallback (no Langfuse).
  #
  # The class method `get` is the entry point: it fetches by name (5-min
  # cached) and, if Langfuse is missing/down/empty, returns a Prompt built
  # from the caller's local constant. The local constant remains in the
  # service file as the safety net — the Langfuse version overrides it
  # whenever it is reachable.
  class Prompt
    CACHE_TTL = 5.minutes
    LABEL = "production".freeze
    OPEN_TIMEOUT = 2
    READ_TIMEOUT = 5

    attr_reader :name, :version, :body

    def initialize(name:, version:, body:)
      @name = name
      @version = version
      @body = body
    end

    # `fallback` is the local constant — used when Langfuse isn't
    # configured, returns nothing, or errors out. Identification never
    # breaks because the cloud is unreachable.
    def self.get(name, fallback:)
      if Langfuse::Config.configured?
        cached = Rails.cache.fetch(cache_key(name), expires_in: CACHE_TTL) do
          fetch_remote(name)
        end
        return cached if cached
      end
      new(name: name, version: nil, body: fallback)
    end

    # Substitutes {{var}} placeholders. Best-effort: unknown placeholders
    # are left alone so the caller sees them in the rendered text instead
    # of getting a silent typo. We don't implement full Mustache (no
    # sections, no partials) — Langfuse's prompts in this app don't need
    # them.
    def compile(variables = {})
      body.to_s.gsub(/\{\{\s*(\w+)\s*\}\}/) do |original|
        key = Regexp.last_match(1)
        variables[key] || variables[key.to_sym] || original
      end
    end

    # True when the prompt didn't come from Langfuse (no version stored).
    def fallback?
      version.nil?
    end

    def self.cache_key(name)
      "langfuse/prompt/#{name}/#{LABEL}"
    end

    # GET /api/public/v2/prompts/{name}?label=production. Returns a Prompt
    # on 200, nil on anything else — caller falls back to the local copy.
    def self.fetch_remote(name)
      uri = URI.join(Langfuse::Config::HOST, "/api/public/v2/prompts/#{name}?label=#{LABEL}")
      request = Net::HTTP::Get.new(uri)
      request.basic_auth(Langfuse::Config::PUBLIC_KEY, Langfuse::Config::SECRET_KEY)

      response = Net::HTTP.start(uri.host, uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        http.request(request)
      end

      return nil unless response.code.to_i == 200
      json = JSON.parse(response.body)
      new(name: json["name"] || name, version: json["version"], body: json["prompt"].to_s)
    rescue => e
      Rails.logger.warn("[Langfuse::Prompt] fetch '#{name}' failed: #{e.class}: #{e.message}")
      nil
    end
  end
end
