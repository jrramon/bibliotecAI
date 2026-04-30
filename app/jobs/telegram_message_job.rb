# Drives a single TelegramMessage from :pending → :completed (or :failed)
# by calling Telegram::Agent and shipping the reply via Telegram::Client.
#
# Runs inline inside bin/claude-worker.rb on the host (where the `claude`
# CLI lives). The webhook controller never enqueues this directly — the
# claude-worker drains TelegramMessage.pending and calls perform_now.
#
# Lock: takes the row pessimistically to flip pending → processing in a
# single tx, so two workers (a stale one + a fresh one) can't both grab
# the same message. If we lose the race, we no-op.
#
# Errors during dev get surfaced verbatim back to the chat so we can
# debug without tailing logs. Slice 9 swaps that for a generic message.
class TelegramMessageJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound

  GENERIC_ERROR = "⚠️ Error procesando tu mensaje:\n%<details>s"

  def perform(message_id)
    message = TelegramMessage.find(message_id)

    claimed = message.with_lock do
      next false unless message.pending?
      message.update!(status: :processing, error_message: nil)
      true
    end
    return unless claimed

    result = Telegram::Agent.call(message)

    if result.ok
      Telegram::Client.send_message(chat_id: message.chat_id, text: result.text)
      message.update!(status: :completed, bot_reply: result.text)
    else
      handle_failure(message, result.error)
    end
  rescue Telegram::Client::Error => e
    handle_failure(message, "send_message failed: #{e.message}") if message
  rescue => e
    handle_failure(message, "#{e.class}: #{e.message}") if message
    raise
  end

  private

  def handle_failure(message, details)
    detail_line = details.to_s.truncate(800)
    body = format(GENERIC_ERROR, details: detail_line)

    begin
      Telegram::Client.send_message(chat_id: message.chat_id, text: body)
    rescue Telegram::Client::Error => e
      Rails.logger.error("TelegramMessageJob: could not deliver error reply: #{e.message}")
    end

    message.update!(status: :failed, error_message: detail_line, bot_reply: body)
  end
end
