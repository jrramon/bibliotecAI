require "net/http"
require "json"

# Thin wrapper over the Telegram Bot HTTP API. We deliberately don't pull in
# the `telegram-bot-ruby` gem — the surface we use is small enough to
# implement with Net::HTTP, matches the "minimal deps" feel of the rest of
# the codebase, and keeps the auditable footprint tiny.
#
# This first cut exposes only `send_message` (Slice 1). Future slices add
# `send_chat_action`, `get_file`, `download_file`, `chunk` for long replies.
module Telegram
  class Client
    Error = Class.new(StandardError)

    API_HOST = "api.telegram.org"
    DEFAULT_TIMEOUT = 8

    # Sends a plain-text message back to the user. Returns the parsed
    # response on 2xx, raises Telegram::Client::Error otherwise.
    #
    # parse_mode is left at Telegram's default (none = plain text). We
    # explicitly avoid HTML/MarkdownV2 here so user-supplied content from
    # the DB never accidentally injects formatting or 400s the API on a
    # stray `<` or `_`.
    def self.send_message(chat_id:, text:, timeout: DEFAULT_TIMEOUT)
      new.send_message(chat_id: chat_id, text: text, timeout: timeout)
    end

    def send_message(chat_id:, text:, timeout: DEFAULT_TIMEOUT)
      request("sendMessage", {chat_id: chat_id, text: text}, timeout: timeout)
    end

    private

    def request(method, payload, timeout:)
      raise Error, "TELEGRAM_BOT_TOKEN missing" if Telegram::Config::BOT_TOKEN.blank?

      uri = URI("https://#{API_HOST}/bot#{Telegram::Config::BOT_TOKEN}/#{method}")
      response = Net::HTTP.start(uri.host, uri.port,
        use_ssl: true,
        open_timeout: timeout,
        read_timeout: timeout) do |http|
        req = Net::HTTP::Post.new(uri.request_uri,
          "Content-Type" => "application/json",
          "Accept" => "application/json")
        req.body = JSON.generate(payload)
        http.request(req)
      end

      parsed = parse_body(response)
      unless response.is_a?(Net::HTTPSuccess) && parsed["ok"] == true
        raise Error, "telegram #{method} failed: status=#{response.code} body=#{response.body.to_s.truncate(300)}"
      end
      parsed["result"]
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError => e
      raise Error, "telegram #{method} network: #{e.class}: #{e.message}"
    end

    def parse_body(response)
      JSON.parse(response.body.to_s)
    rescue JSON::ParserError
      {"ok" => false, "raw" => response.body.to_s}
    end
  end
end
