# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
#
# Beyond the usual credentials/tokens, we also filter user-generated
# text that's PII-ish even when not technically secret: Telegram
# message bodies, the bot's reply (which may quote private library
# data back), per-user notes on books and wishlist items, and book
# synopses. Filtering these keeps logs free of content that lives
# under different access controls than the DB.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  :text, :bot_reply, :note, :synopsis
]
