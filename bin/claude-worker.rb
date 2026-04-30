# Host-side worker that drains ShelfPhoto.pending and CoverPhoto.pending
# by invoking the identification jobs inline. Runs under `bin/rails runner`
# so all models and ActiveStorage are available; needs access to the host
# `claude` CLI, which is why it can't run inside the Rails container.
#
# Launched by `bin/shelf-photo-poller` (a thin shell wrapper). Restart the
# wrapper after editing this file — Ruby doesn't hot-reload a `rails runner`
# script.
#
# Env vars it respects:
#   INTERVAL        poll interval in seconds (default 5)
#   HEARTBEAT_EVERY emit a "still alive" log every N iterations (default 24,
#                   ie. every ~2 minutes with the 5s default)
#   STALE_AFTER     reclaim :processing records older than this (default 120s)

$stdout.sync = true
$stderr.sync = true
Rails.logger = Logger.new($stdout)
Rails.logger.level = Logger::INFO

# Run every ActiveJob inline in this process so the main poll thread never
# contends for the ActiveRecord connection pool with background :async
# workers spawned by ActiveStorage::AnalyzeJob.
ActiveJob::Base.queue_adapter = :inline

INTERVAL = Integer(ENV.fetch("INTERVAL", "5"))
HEARTBEAT_EVERY = Integer(ENV.fetch("HEARTBEAT_EVERY", "24"))
STALE_AFTER = Integer(ENV.fetch("STALE_AFTER", "120"))

PID_FILE = Rails.root.join("tmp/claude-worker.pid")

# Simple exclusive lock so two workers don't fight over the same pending
# records. If an older PID file exists but the process is gone (terminal
# closed, SIGKILL), we take over.
def acquire_lock!
  if PID_FILE.exist?
    other = PID_FILE.read.to_i
    if other > 0 && process_alive?(other)
      warn "[worker] another worker is already running (pid=#{other}). Kill it first, or wait for it to exit."
      exit 2
    else
      warn "[worker] stale PID file from pid=#{other}, taking over"
    end
  end
  PID_FILE.write(Process.pid)
  at_exit { PID_FILE.delete if PID_FILE.exist? && PID_FILE.read.to_i == Process.pid }
end

def process_alive?(pid)
  Process.kill(0, pid)
  true
rescue Errno::ESRCH, Errno::EPERM
  false
end

# Reset anything that was :processing but abandoned (poller killed
# mid-claude-call) and anything :failed (since failures are usually
# transient — missing CLI, network, one-off Claude error). Both come
# back as :pending on the next tick. If the user has a record they
# want to keep as failed, they can clear it manually via queue-status.
def reclaim!
  [ShelfPhoto, CoverPhoto].each do |klass|
    stale_processing = klass.processing.where("updated_at < ?", STALE_AFTER.seconds.ago).to_a
    stale_processing.each do |r|
      puts "[worker] reclaiming stale #{klass.name}##{r.id} (stuck in processing for > #{STALE_AFTER}s)"
      r.update(status: :pending, error_message: "reclaimed: stale processing")
    end

    klass.failed.to_a.each do |r|
      puts "[worker] retrying previously-failed #{klass.name}##{r.id} (prev err: #{r.error_message.to_s.truncate(80)})"
      r.update(status: :pending, error_message: nil)
    end
  end
end

def process_shelf(p)
  puts "[worker] shelf → #{p.id}  lib=#{p.library.name}  file=#{p.image.filename}"
  BookIdentificationJob.new.perform(p.id)
  puts "[worker] ✓ shelf #{p.id} done (status=#{p.reload.status})"
rescue => e
  warn "[worker] ! shelf #{p.id} failed: #{e.class}: #{e.message}"
  p.update(status: :failed, error_message: "#{e.class}: #{e.message}") rescue nil
end

def process_cover(p)
  puts "[worker] cover → #{p.id}  lib=#{p.library.name}  file=#{p.image.filename}"
  CoverIdentificationJob.new.perform(p.id)
  puts "[worker] ✓ cover #{p.id} done (status=#{p.reload.status})"
rescue => e
  warn "[worker] ! cover #{p.id} failed: #{e.class}: #{e.message}"
  p.update(status: :failed, error_message: "#{e.class}: #{e.message}") rescue nil
end

trap("INT")  { puts "[worker] stopping (SIGINT)";  exit 0 }
trap("TERM") { puts "[worker] stopping (SIGTERM)"; exit 0 }

acquire_lock!
puts "[worker] pid=#{Process.pid} interval=#{INTERVAL}s heartbeat_every=#{HEARTBEAT_EVERY} stale_after=#{STALE_AFTER}s"
reclaim!
puts "[worker] ready"

ticks_since_log = 0
loop do
  # Long-running Ruby processes can end up holding a stale / dropped AR
  # connection — Postgres closes idle connections, poolers cycle them,
  # and `verify!` alone has proven insufficient here. Return the current
  # connection to the pool each tick so the next query checks out a
  # fresh (and known-good) one.
  ActiveRecord::Base.connection_handler.clear_active_connections!

  shelf_pending = ShelfPhoto.pending.order(:created_at).to_a
  cover_pending = CoverPhoto.pending.order(:created_at).to_a

  if shelf_pending.any? || cover_pending.any?
    puts "[worker] tick shelf=#{shelf_pending.size} cover=#{cover_pending.size}"
    shelf_pending.each { |p| process_shelf(p) }
    cover_pending.each { |p| process_cover(p) }
    ticks_since_log = 0
  else
    ticks_since_log += 1
    if ticks_since_log >= HEARTBEAT_EVERY
      puts "[worker] heartbeat — idle, still alive (pid=#{Process.pid})"
      ticks_since_log = 0
    end
  end

  sleep INTERVAL
end
