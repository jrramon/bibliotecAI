# Serves the Progressive Web App manifest and service worker. No auth,
# no session touch — these endpoints are hit by the browser outside
# any user context (and often before cookies have been sent).
class PwaController < ApplicationController
  skip_before_action :touch_last_seen!, raise: false
  # Rails rejects cross-origin JS requests by default as an anti-CSRF
  # measure — but a service worker is a first-party JS asset fetched by
  # the browser with `Sec-Fetch-Site: same-origin`, so the check is
  # overcautious here. Skipping forgery protection on these two read-only,
  # asset-style endpoints is safe.
  skip_forgery_protection only: %i[manifest service_worker]

  def manifest
    render layout: false, content_type: "application/manifest+json"
  end

  def service_worker
    expires_in 0, public: false
    render layout: false, content_type: "application/javascript"
  end
end
