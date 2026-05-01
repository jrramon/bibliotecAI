require "net/http"
require "json"

# Thin wrapper over the Telegram Bot HTTP API. We deliberately don't pull in
# the `telegram-bot-ruby` gem — the surface we use is small enough to
# implement with Net::HTTP, matches the "minimal deps" feel of the rest of
# the codebase, and keeps the auditable footprint tiny.
#
# Slice 1 added `send_message`; slice 4 adds `send_chat_action` so the
# webhook can show "typing…" while the claude-worker generates a reply.
# Slice 8 adds `get_file` + `download_file` so a Telegram photo can be
# pulled into the CoverPhoto pipeline.
module Telegram
  class Client
    Error = Class.new(StandardError)

    API_HOST = "api.telegram.org"
    DEFAULT_TIMEOUT = 8
    # Telegram's sendMessage caps at 4096 chars. We use a safety margin
    # so escaped chars or unexpected concatenations don't push us over.
    MAX_CHUNK_LENGTH = 4_000

    # Splits `text` into chunks Telegram will accept. Tries to break on
    # the last newline before MAX_CHUNK_LENGTH so paragraphs survive;
    # falls back to a hard cut for single lines longer than the cap.
    def self.chunk(text, max: MAX_CHUNK_LENGTH)
      text = text.to_s
      return [text] if text.length <= max

      parts = []
      remaining = text.dup
      until remaining.empty?
        if remaining.length <= max
          parts << remaining
          break
        end
        cut = remaining.rindex("\n", max) || max
        parts << remaining[0...cut].rstrip
        remaining = remaining[cut..].lstrip
      end
      parts.reject(&:empty?)
    end

    # Sends a message back to the user. Returns the parsed response on
    # 2xx, raises Telegram::Client::Error otherwise.
    #
    # parse_mode defaults to nil (plain text). When a caller passes
    # "Markdown" or "MarkdownV2" or "HTML", we send with that mode and
    # automatically retry plain-text if Telegram rejects the formatting
    # — better to deliver an unformatted reply than nothing.
    def self.send_message(chat_id:, text:, parse_mode: nil, timeout: DEFAULT_TIMEOUT)
      new.send_message(chat_id: chat_id, text: text, parse_mode: parse_mode, timeout: timeout)
    end

    def send_message(chat_id:, text:, parse_mode: nil, timeout: DEFAULT_TIMEOUT)
      payload = {chat_id: chat_id, text: text}
      payload[:parse_mode] = parse_mode if parse_mode
      request("sendMessage", payload, timeout: timeout)
    rescue Error => e
      raise unless parse_mode && parse_failure?(e)
      Rails.logger.warn("[Telegram::Client] #{parse_mode} parse failed, falling back to plain: #{e.message.truncate(160)}")
      request("sendMessage", {chat_id: chat_id, text: text}, timeout: timeout)
    end

    # Telegram shows the chat-action indicator (typing…) for ~5s. The
    # webhook fires this before persisting the message so the user gets
    # immediate feedback while the host worker spins up claude.
    def self.send_chat_action(chat_id:, action: "typing", timeout: DEFAULT_TIMEOUT)
      new.send_chat_action(chat_id: chat_id, action: action, timeout: timeout)
    end

    def send_chat_action(chat_id:, action: "typing", timeout: DEFAULT_TIMEOUT)
      request("sendChatAction", {chat_id: chat_id, action: action}, timeout: timeout)
    end

    # Two-step download. Telegram returns a `file_path` from getFile that
    # you have to fetch from a SEPARATE URL prefix that includes the bot
    # token. The path expires after about an hour — fetch immediately.
    def self.get_file(file_id:, timeout: DEFAULT_TIMEOUT)
      new.get_file(file_id: file_id, timeout: timeout)
    end

    def get_file(file_id:, timeout: DEFAULT_TIMEOUT)
      request("getFile", {file_id: file_id}, timeout: timeout)
    end

    # Pulls the bytes from https://api.telegram.org/file/bot<token>/<path>.
    # Returns the raw body. Telegram caps photo uploads at 20MB so we
    # accept whatever they send without a streaming download.
    def self.download_file(file_path:, timeout: 20)
      new.download_file(file_path: file_path, timeout: timeout)
    end

    def download_file(file_path:, timeout: 20)
      raise Error, "TELEGRAM_BOT_TOKEN missing" if Telegram::Config::BOT_TOKEN.blank?

      uri = URI("https://#{API_HOST}/file/bot#{Telegram::Config::BOT_TOKEN}/#{file_path}")
      response = Net::HTTP.start(uri.host, uri.port,
        use_ssl: true,
        open_timeout: timeout,
        read_timeout: timeout) do |http|
        http.request(Net::HTTP::Get.new(uri.request_uri))
      end

      unless response.is_a?(Net::HTTPSuccess)
        raise Error, "telegram download failed: status=#{response.code}"
      end
      response.body
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError => e
      raise Error, "telegram download network: #{e.class}: #{e.message}"
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

    # Heuristic: Telegram returns 400 with descriptions like "can't parse
    # entities" or "Can't find end of the entity" when a parse_mode'd
    # message is malformed. We look for those signatures so we only fall
    # back when it really was a formatting issue, not a network/auth
    # error or anything else.
    def parse_failure?(error)
      msg = error.message.to_s
      msg.include?("status=400") &&
        msg.match?(/can't parse entities|Can't find end of the entity|unsupported start tag|unsupported parse_mode/i)
    end
  end
end
