require "json"

# Aggregates `claude -p` consumption across the three models that capture it
# (ShelfPhoto, CoverPhoto, TelegramMessage) over rolling time windows.
# Real costs come from `claude_usage.total_cost_usd` (populated since S1 of
# the claude-usage plan). For rows where claude_usage is NULL (older
# completed jobs), falls back to flat per-service estimates — adjust the
# constants below once a few weeks of real data are in.
class ClaudeUsageReport
  WINDOWS = [
    ["últimas 24h", 24.hours],
    ["últimos 7d", 7.days],
    ["últimos 30d", 30.days],
    ["últimos 90d", 90.days]
  ].freeze

  # Editable estimates for pre-instrumentation rows. Update after a few real
  # measurements are visible in the "real" columns of the report.
  SHELF_ESTIMATE_USD = 0.20
  COVER_ESTIMATE_USD = 0.02
  TELEGRAM_ESTIMATE_USD = 0.05

  SERVICES = [
    {key: :shelf, label: "shelf", model: "ShelfPhoto", estimate: SHELF_ESTIMATE_USD},
    {key: :cover, label: "cover", model: "CoverPhoto", estimate: COVER_ESTIMATE_USD},
    {key: :telegram, label: "telegram", model: "TelegramMessage", estimate: TELEGRAM_ESTIMATE_USD}
  ].freeze

  def run(format: "table", io: $stdout)
    rows = WINDOWS.map { |label, duration| summarize(label, duration.ago) }
    case format.to_s
    when "json"
      io.puts JSON.pretty_generate(generated_at: Time.current.utc.iso8601, windows: rows)
    else
      render_table(rows, io: io)
    end
  end

  private

  def summarize(label, since)
    services = SERVICES.map do |svc|
      [svc[:key], stats_for(svc[:model].constantize, since, svc[:estimate])]
    end.to_h
    services.merge(window: label, totals: aggregate(services.values))
  end

  def stats_for(klass, since, estimate_usd)
    completed = klass.where(status: :completed).where("created_at >= ?", since)
    measured = completed.where.not(claude_usage: nil)
    estimated = completed.where(claude_usage: nil)

    real_cost = measured.sum("(claude_usage->>'total_cost_usd')::float").to_f
    estimated_cost = estimated.count * estimate_usd

    {
      count_total: completed.count,
      count_measured: measured.count,
      count_estimated: estimated.count,
      cost_real: real_cost.round(4),
      cost_estimated: estimated_cost.round(4),
      cost_total: (real_cost + estimated_cost).round(4)
    }
  end

  def aggregate(stats_list)
    {
      count_total: stats_list.sum { |s| s[:count_total] },
      count_measured: stats_list.sum { |s| s[:count_measured] },
      count_estimated: stats_list.sum { |s| s[:count_estimated] },
      cost_real: stats_list.sum { |s| s[:cost_real] }.round(4),
      cost_estimated: stats_list.sum { |s| s[:cost_estimated] }.round(4),
      cost_total: stats_list.sum { |s| s[:cost_total] }.round(4)
    }
  end

  def render_table(rows, io:)
    io.puts "Consumo de `claude -p` — generado #{Time.current.utc.iso8601}"
    io.puts

    rows.each do |row|
      io.puts "=== #{row[:window]} ==="
      io.puts "  servicio         n      $real       $est     $total"
      SERVICES.each do |svc|
        s = row[svc[:key]]
        io.puts format("  %-9s %8d %10.4f %10.4f %10.4f",
          svc[:label], s[:count_total], s[:cost_real], s[:cost_estimated], s[:cost_total])
      end
      t = row[:totals]
      io.puts format("  %-9s %8d %10.4f %10.4f %10.4f",
        "TOTAL", t[:count_total], t[:cost_real], t[:cost_estimated], t[:cost_total])
      io.puts
    end

    io.puts "$real: registros con claude_usage poblado (post-instrumentación)."
    io.puts "$est:  registros antiguos × constantes editables en ClaudeUsageReport."
  end
end
