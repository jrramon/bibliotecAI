namespace :usage do
  desc "Resumen de invocaciones a `claude -p` por ventana (24h/7d/30d/90d). Uso: bin/rails 'usage:claude[table|json]'"
  task :claude, [:format] => :environment do |_, args|
    format = args[:format].presence || "table"
    ClaudeUsageReport.new.run(format: format)
  end
end
