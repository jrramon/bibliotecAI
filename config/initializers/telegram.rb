# Telegram bot config — read from ENV.
#
# - TELEGRAM_BOT_TOKEN: from @BotFather. Format "<id>:<hash>".
# - TELEGRAM_BOT_USERNAME: bot's username (without leading @). Used to build
#   the deep link `https://t.me/<username>?start=<token>` from /users/edit.
# - TELEGRAM_WEBHOOK_SECRET: random hex string. The webhook URL is
#   /telegram/webhook/<this-secret>; we constant-time-compare the path
#   segment against this value to confirm the call is from Telegram.
#
# In production all three must be set; the app boots warning loudly if not.
# In development we accept missing values so the app still boots before
# you've gone through the BotFather flow.
module Telegram
  module Config
    BOT_TOKEN = ENV["TELEGRAM_BOT_TOKEN"].to_s
    BOT_USERNAME = ENV["TELEGRAM_BOT_USERNAME"].to_s
    WEBHOOK_SECRET = ENV["TELEGRAM_WEBHOOK_SECRET"].to_s

    def self.configured?
      BOT_TOKEN.present? && WEBHOOK_SECRET.present?
    end

    def self.deep_link(start_param)
      "https://t.me/#{BOT_USERNAME}?start=#{start_param}" if BOT_USERNAME.present?
    end
  end
end

if Rails.env.production? && !Telegram::Config.configured?
  Rails.logger.warn(
    "[Telegram] missing env vars (TELEGRAM_BOT_TOKEN / TELEGRAM_WEBHOOK_SECRET). " \
    "Bot endpoints will reject all requests until they're set."
  )
end
