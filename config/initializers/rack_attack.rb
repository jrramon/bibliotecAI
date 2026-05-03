# Rate limiting for the public-facing endpoints that aren't already
# protected by their own throttle (the Telegram webhook has its own
# 60/h per-user guard inside the controller). Storage is the same
# Rails.cache used elsewhere — Solid Cache in production, MemoryStore
# in dev/test. Throttled requests get a 429 with a short retry hint.
#
# Tuning: limits are deliberately permissive. The goal is to stop
# automated abuse (brute force, mail floods, DoS), not to inconvenience
# someone reloading the page in good faith.

class Rack::Attack
  Rack::Attack.cache.store = Rails.cache

  ### LOGIN — brute-force defense ###
  # Keyed by submitted email so an attacker can't bypass by rotating IPs.
  throttle("sign_in/email", limit: 5, period: 1.minute) do |req|
    if req.path == "/users/sign_in" && req.post?
      req.params.dig("user", "email").to_s.downcase.presence
    end
  end

  ### PASSWORD RESET — email flood defense ###
  # Three sends per hour per email is plenty for someone genuinely
  # locked out and stops an attacker from spamming a user's inbox via
  # our SMTP (which is also a real cost on Brevo).
  throttle("password/email", limit: 3, period: 1.hour) do |req|
    if req.path == "/users/password" && req.post?
      req.params.dig("user", "email").to_s.downcase.presence
    end
  end

  ### WAITLIST — anti-spam ###
  throttle("waitlist/ip", limit: 5, period: 1.hour) do |req|
    req.ip if req.path == "/waitlist_requests" && req.post?
  end

  ### MCP — DoS guard on the verify path ###
  # 60/min per IP is way above what a real claude session generates
  # (typically 1-3 calls per Telegram turn) but blocks fuzzing.
  throttle("mcp/ip", limit: 60, period: 1.minute) do |req|
    req.ip if req.path == "/mcp"
  end

  ### COVER PHOTOS — cost guard for Claude calls ###
  # Authenticated user uploads. Each successful upload triggers a
  # claude run on the host worker. 30/h per user is generous (a
  # power user adding a shelf of books in one go would hit ~20).
  throttle("cover_photos/user", limit: 30, period: 1.hour) do |req|
    if req.path =~ %r{\A/libraries/[^/]+/cover_photos\z} && req.post?
      req.env["warden"]&.user&.id
    end
  end

  ### Response when throttled ###
  self.throttled_responder = ->(req) {
    match_data = req.env["rack.attack.match_data"] || {}
    retry_after = (match_data[:period] || 60).to_s
    [
      429,
      {"content-type" => "text/plain", "retry-after" => retry_after},
      ["Demasiadas peticiones. Vuelve a probar en un momento.\n"]
    ]
  }
end

# Log throttled hits so we can tell abuse from a flaky user.
ActiveSupport::Notifications.subscribe("throttle.rack_attack") do |_name, _start, _finish, _id, payload|
  req = payload[:request]
  Rails.logger.warn("[Rack::Attack] throttled rule=#{req.env["rack.attack.matched"]} ip=#{req.ip} path=#{req.path}")
end
