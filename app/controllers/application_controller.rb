class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :touch_last_seen!

  # Throttled to one DB write per 30 min so the dashboard's "N nuevas desde
  # tu última visita" stays interesting but we don't hit the user row on
  # every request. The *previous* timestamp is snapshotted into the session
  # on the first touch of the window (and cleared when the window moves on),
  # so even subsequent requests in the same session still see the old value.
  LAST_SEEN_THROTTLE = 30.minutes

  def touch_last_seen!
    return unless user_signed_in?
    stored = current_user.last_seen_at
    fresh = stored && stored > LAST_SEEN_THROTTLE.ago
    return if fresh

    session[:previous_last_seen_at] = stored&.iso8601
    current_user.update_column(:last_seen_at, Time.current)
  end

  # Greeting/dashboard reads this to count "new since last visit".
  def previous_last_seen_at
    raw = session[:previous_last_seen_at]
    Time.iso8601(raw) if raw.present?
  rescue ArgumentError
    nil
  end
  helper_method :previous_last_seen_at
end
