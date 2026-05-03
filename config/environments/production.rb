require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = {"cache-control" => "public, max-age=#{1.year.to_i}"}

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [:request_id]
  config.logger = ActiveSupport::TaggedLogging.logger($stdout)

  # Change to "debug" to log everything (including potentially personally-identifiable information!)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = {database: {writing: :queue}}

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Public hostnames this deployment serves. Comma-separated so forks
  # can list multiple (apex + www, several subdomains). The first one
  # is treated as the canonical and used for mailer links + SMTP HELO.
  #
  # During `assets:precompile` (Docker build) Rails sets
  # SECRET_KEY_BASE_DUMMY=1; in that context env vars from the runtime
  # `.env.production` are not yet loaded. We tolerate APP_HOSTS being
  # absent ONLY in that build context, and require it at real boot.
  app_hosts = ENV.fetch("APP_HOSTS", "").split(",").map(&:strip).reject(&:empty?)
  building_assets = ENV["SECRET_KEY_BASE_DUMMY"].present?
  if app_hosts.empty? && !building_assets
    raise "APP_HOSTS env var must list at least one hostname (e.g. APP_HOSTS=biblio.example.org)"
  end
  primary_host = app_hosts.first || "localhost"

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = {host: primary_host}

  # Brevo SMTP
  ActionMailer::Base.smtp_settings = {
    user_name: ENV["BREVO_USERNAME"],
    password: ENV["BREVO_PASSWORD"],
    domain: primary_host,
    address: "smtp-relay.brevo.com",
    port: 587,
    authentication: :plain,
    enable_starttls_auto: true
  }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [:id]

  # DNS rebinding protection: reject requests whose `Host:` header isn't
  # one we expect. Public hostnames come from APP_HOSTS (set above);
  # "web" is the Docker service name used by the claude-worker
  # container to reach the MCP endpoint over the internal bridge
  # network — only resolvable inside that network, so nothing external
  # can spoof Host: web. The orchestrator hits /up with
  # `Host: <container-ip>` for health checks, so that path is excluded.
  config.hosts = app_hosts + ["web"] unless building_assets
  config.host_authorization = {exclude: ->(request) { request.path == "/up" }}
end
