require "yaml"
require "fileutils"

namespace :langfuse do
  namespace :eval do
    namespace :shelves do
      desc "Sube a Langfuse el dataset 'shelf-identification-eval' con 1 item por shelf de expected.yml (idempotente)"
      task seed: :environment do
        raise "Langfuse no está configurado" unless Langfuse::Config.configured?

        name = "shelf-identification-eval"
        yaml_path = Rails.root.join("test/fixtures/files/eval_shelves/expected.yml")
        abort "[langfuse:eval:shelves:seed] falta #{yaml_path.relative_path_from(Rails.root)} — corre antes :extract" unless File.exist?(yaml_path)

        items = YAML.safe_load_file(yaml_path)
        abort "[langfuse:eval:shelves:seed] expected.yml vacío" if items.blank?

        if Langfuse::Dataset.ensure(name: name,
          description: "Estanterías de prueba para comparar la identificación de libros entre modelos. expected_output = lista de libros gold (Opus).")
          puts "[langfuse:eval:shelves:seed] dataset '#{name}' listo"
        else
          abort "[langfuse:eval:shelves:seed] no pude asegurar el dataset"
        end

        items.each do |key, item|
          expected = item.fetch("expected")
          books = expected.fetch("books")
          ok = Langfuse::Dataset.upsert_item(
            dataset_name: name,
            id: key,
            input: {
              filename: item["image"],
              source_shelf_photo_id: item["source_shelf_photo_id"]
            },
            expected_output: {books: books},
            metadata: {
              expected_books_count: books.size,
              image_width: expected["image_width"],
              image_height: expected["image_height"],
              source_filename: item["source_filename"]
            }.compact
          )
          if ok
            puts "[langfuse:eval:shelves:seed] #{key}: creado/actualizado (#{books.size} libros)"
          else
            abort "[langfuse:eval:shelves:seed] #{key}: fallo al subir el item"
          end
        end
      end

      desc "Corre el eval: por cada (modelo × shelf) llama a Claude, puntúa, sube score+run-item a Langfuse. ENV: MODELS=a,b,c ITEMS=shelf-1,shelf-3"
      task run: :environment do
        require "securerandom"

        raise "Langfuse no está configurado" unless Langfuse::Config.configured?

        dataset_name = "shelf-identification-eval"
        default_models = ["claude-haiku-4-5", "claude-sonnet-4-6", "claude-opus-4-8", "claude-fable-5"]
        models = ENV["MODELS"].present? ? ENV["MODELS"].split(",").map(&:strip) : default_models

        yaml_path = Rails.root.join("test/fixtures/files/eval_shelves/expected.yml")
        abort "[shelves:run] falta #{yaml_path.relative_path_from(Rails.root)}" unless File.exist?(yaml_path)
        all_items = YAML.safe_load_file(yaml_path)
        item_keys = ENV["ITEMS"].present? ? ENV["ITEMS"].split(",").map(&:strip) : all_items.keys
        unknown = item_keys - all_items.keys
        abort "[shelves:run] items desconocidos: #{unknown.join(", ")}" if unknown.any?

        run_description = "Eval #{Time.now.utc.iso8601}"
        results = {}  # model => [{item:, score:, recall:, precision:}, ...]

        models.each do |model|
          puts "\n=== Modelo: #{model} ==="
          results[model] = []

          item_keys.each do |key|
            item = all_items.fetch(key)
            image_path = Rails.root.join("test/fixtures/files/eval_shelves", item.fetch("image")).to_s
            expected_books = item.fetch("expected").fetch("books")

            trace_id = SecureRandom.uuid
            fake = Eval::FakeShelfPhoto.new(id: item["source_shelf_photo_id"], image_path: image_path)

            print "  #{key} (#{expected_books.size} libros gold)… "
            $stdout.flush

            begin
              result = ClaudeBookIdentifier.call(fake, model: model, trace_id: trace_id)
              scoring = Eval::ShelfScorer.call(
                actual_books: result.books.map(&:stringify_keys),
                expected_books: expected_books
              )

              comment = "matched_full=#{scoring[:details][:matched_full].size} " \
                "title_only=#{scoring[:details][:matched_title_only].size} " \
                "missed=#{scoring[:details][:missed].size} " \
                "extra=#{scoring[:details][:extra].size} " \
                "recall=#{scoring[:details][:recall]} precision=#{scoring[:details][:precision]}"

              score_event = Langfuse::Client.score_event(
                trace_id: trace_id, name: "shelf_quality",
                value: scoring[:score], comment: comment,
                metadata: {model: model, item: key}
              )
              Langfuse::Client.ingest([score_event])
              linked = Langfuse::Dataset.link_run_item(
                dataset_name: dataset_name,
                dataset_item_id: key,
                trace_id: trace_id,
                run_name: model,
                run_description: run_description
              )
              warn "    ⚠️  link_run_item devolvió false — mira log/development.log" unless linked

              results[model] << {item: key, score: scoring[:score],
                                 recall: scoring[:details][:recall],
                                 precision: scoring[:details][:precision]}
              puts "score=#{scoring[:score]} (recall=#{scoring[:details][:recall]} precision=#{scoring[:details][:precision]})"
            rescue => e
              puts "FALLO: #{e.class}: #{e.message}"
              results[model] << {item: key, error: e.message}
            end
          end
        end

        puts "\n=== Resumen ==="
        results.each do |model, items|
          scores = items.map { _1[:score] }.compact
          avg = scores.any? ? (scores.sum / scores.size).round(4) : nil
          errors = items.count { _1[:error] }
          puts "#{model}: avg_score=#{avg || "n/a"} (#{scores.size} ok, #{errors} fallos)"
        end
        puts "\nUI: Datasets → #{dataset_name} → Runs (#{run_description})"
      end

      desc "Extrae fotos de estantería + su claude_raw_response (Opus) a test/fixtures/files/eval_shelves/. Default ids: 1,3,4,5. Override: langfuse:eval:shelves:extract[3,5]"
      task :extract, [:ids] => :environment do |_, args|
        ids = args[:ids].present? ? args[:ids].split(",").map(&:to_i) : [1, 3, 4, 5]
        dir = Rails.root.join("test/fixtures/files/eval_shelves")
        FileUtils.mkdir_p(dir)

        items = {}
        ids.each do |id|
          shelf = ShelfPhoto.find_by(id: id)
          if shelf.nil?
            puts "[langfuse:eval:shelves:extract] shelf-#{id}: no existe, skipping"
            next
          end
          unless shelf.image.attached? && shelf.claude_raw_response.present?
            puts "[langfuse:eval:shelves:extract] shelf-#{id}: sin imagen o sin resultado, skipping"
            next
          end

          key = "shelf-#{id}"
          dest = dir.join("#{key}.jpg")
          File.binwrite(dest, shelf.image.download)

          books_count = shelf.claude_raw_response["books"]&.size || 0
          items[key] = {
            "source_shelf_photo_id" => shelf.id,
            "source_filename" => shelf.image.filename.to_s,
            "image" => "#{key}.jpg",
            "expected" => shelf.claude_raw_response
          }
          puts "[langfuse:eval:shelves:extract] #{key}: #{dest.relative_path_from(Rails.root)} (#{books_count} libros)"
        end

        yaml_path = dir.join("expected.yml")
        File.write(yaml_path, items.to_yaml(line_width: -1))
        puts "[langfuse:eval:shelves:extract] escrito #{yaml_path.relative_path_from(Rails.root)} con #{items.size} items"
      end
    end

    namespace :covers do
      desc "Crea el dataset 'cover-identification-eval' con un item de muestra (idempotente)"
      task seed: :environment do
        raise "Langfuse no está configurado" unless Langfuse::Config.configured?

        name = "cover-identification-eval"

        if Langfuse::Dataset.ensure(name: name,
          description: "Portadas de prueba para comparar la identificación de Claude entre modelos.")
          puts "[langfuse:eval:covers:seed] dataset '#{name}' listo"
        else
          abort "[langfuse:eval:covers:seed] no pude asegurar el dataset"
        end

        item_id = "sample-shelf"
        ok = Langfuse::Dataset.upsert_item(
          dataset_name: name,
          id: item_id,
          input: {filename: "shelf.jpg"},
          expected_output: {
            title: "Sample title (placeholder — sustituye con una portada real)",
            author: "Sample author",
            isbn: nil
          },
          metadata: {seed: true}
        )

        if ok
          puts "[langfuse:eval:covers:seed] item '#{item_id}' creado/actualizado"
        else
          abort "[langfuse:eval:covers:seed] no pude crear el item"
        end
      end
    end

    namespace :telegram do
      desc "Sube a Langfuse el dataset 'telegram-agent-eval' (1 item por conversación curada). Idempotente."
      task seed: :environment do
        raise "Langfuse no está configurado" unless Langfuse::Config.configured?

        name = "telegram-agent-eval"
        yaml_path = Rails.root.join("test/fixtures/files/eval_telegram/conversations.yml")
        abort "[langfuse:eval:telegram:seed] falta #{yaml_path.relative_path_from(Rails.root)}" unless File.exist?(yaml_path)

        items = YAML.safe_load_file(yaml_path)
        abort "[langfuse:eval:telegram:seed] conversations.yml vacío" if items.blank?

        unless Langfuse::Dataset.ensure(name: name,
          description: "Conversaciones de Telegram para evaluar el tool-routing del agente entre modelos. expected_output = trayectoria de tools esperada (nombre + args).")
          abort "[langfuse:eval:telegram:seed] no pude asegurar el dataset"
        end
        puts "[langfuse:eval:telegram:seed] dataset '#{name}' listo"

        items.each do |key, item|
          expected = Array(item["expected_tools"])
          ok = Langfuse::Dataset.upsert_item(
            dataset_name: name,
            id: key,
            input: {
              user_message: item.fetch("user_message"),
              history: item["history"] || [],
              photo: item["photo"] || false
            },
            expected_output: {tools: expected},
            metadata: {expected_tool_count: expected.size}
          )
          if ok
            puts "[langfuse:eval:telegram:seed] #{key}: ok (#{expected.size} tool(s) esperada(s))"
          else
            abort "[langfuse:eval:telegram:seed] #{key}: fallo al subir el item"
          end
        end
      end

      desc "Corre el eval del agente: por cada (modelo × conversación) corre el agente con tools mockeadas (FixtureToolExecutor), puntúa la trayectoria, sube score + run-item. ENV: MODELS=qwen3.6,deepseek-v4-flash ITEMS=lib-list,..."
      task run: :environment do
        require "securerandom"
        raise "Langfuse no está configurado" unless Langfuse::Config.configured?

        dataset_name = "telegram-agent-eval"
        yaml_path = Rails.root.join("test/fixtures/files/eval_telegram/conversations.yml")
        abort "[telegram:run] falta #{yaml_path.relative_path_from(Rails.root)}" unless File.exist?(yaml_path)
        all_items = YAML.safe_load_file(yaml_path)

        models = ENV["MODELS"].present? ? ENV["MODELS"].split(",").map(&:strip) : %w[qwen3.6 deepseek-v4-flash]
        item_keys = ENV["ITEMS"].present? ? ENV["ITEMS"].split(",").map(&:strip) : all_items.keys
        unknown = item_keys - all_items.keys
        abort "[telegram:run] items desconocidos: #{unknown.join(", ")}" if unknown.any?

        run_description = "Eval #{Time.now.utc.iso8601}"
        results = {}
        ENV["LLM_PROVIDER_TELEGRAM"] = "openai_compatible" # fuerza el camino API para el eval

        # runName must differ across prompt versions so Langfuse keeps each run
        # as its own comparable row (same runName appends/merges items). Default
        # label = the system prompt version (so editing the prompt → new run);
        # override with RUN_LABEL for ad-hoc experiments.
        run_label = ENV["RUN_LABEL"].presence || begin
          version = Langfuse::Prompt.get("telegram-agent-system", fallback: Telegram::Agent::SYSTEM_PROMPT).version
          version ? "pv#{version}" : "local"
        end
        puts "[telegram:run] run_label=#{run_label}"

        seed_history = lambda do |user, history|
          Array(history).each do |turn|
            TelegramMessage.create!(user: user, chat_id: 1, update_id: SecureRandom.random_number(10**9),
              text: turn["user"], bot_reply: turn["bot"], status: :completed)
          end
        end

        models.each do |model|
          ENV["LLM_MODEL_TELEGRAM"] = model
          puts "\n=== Modelo: #{model} ==="
          results[model] = []

          item_keys.each do |key|
            item = all_items.fetch(key)
            print "  #{key}… "
            $stdout.flush
            trace_id = SecureRandom.uuid
            user = nil

            begin
              user = User.create!(email: "tgeval-#{SecureRandom.hex(4)}@example.test", password: "password123", name: "Eval")
              seed_history.call(user, item["history"])
              msg = TelegramMessage.create!(user: user, chat_id: 1, update_id: SecureRandom.random_number(10**9),
                text: item.fetch("user_message"), status: :pending)
              if item["photo"]
                msg.photo.attach(io: File.open(Rails.root.join("test/fixtures/files/eval_shelves/shelf-4.jpg")),
                  filename: "shelf.jpg", content_type: "image/jpeg")
              end

              fixture = Eval::FixtureToolExecutor.new
              Telegram::Agent.new(msg, tool_executor: fixture, trace_id: trace_id).call
              scoring = Eval::TrajectoryScorer.call(actual: fixture.trajectory, expected: item["expected_tools"])

              comment = "matched=#{scoring[:details][:matched]} missed=#{scoring[:details][:missed]} extra=#{scoring[:details][:extra]}"
              Langfuse::Client.ingest([Langfuse::Client.score_event(
                trace_id: trace_id, name: "trajectory", value: scoring[:score], comment: comment,
                metadata: {model: model, item: key}
              )])
              Langfuse::Dataset.link_run_item(dataset_name: dataset_name, dataset_item_id: key,
                trace_id: trace_id, run_name: "#{model} · #{run_label}", run_description: run_description)

              results[model] << {item: key, score: scoring[:score]}
              puts "score=#{scoring[:score]}  trayectoria=#{fixture.trajectory.map { _1[:tool] }.inspect}"
            rescue => e
              puts "FALLO: #{e.class}: #{e.message}"
              results[model] << {item: key, error: e.message}
            ensure
              if user
                TelegramMessage.where(user_id: user.id).destroy_all
                user.destroy
              end
            end
          end
        end

        puts "\n=== Resumen ==="
        results.each do |model, items|
          scores = items.map { _1[:score] }.compact
          avg = scores.any? ? (scores.sum / scores.size).round(4) : nil
          errors = items.count { _1[:error] }
          puts "#{model}: avg_score=#{avg || "n/a"} (#{scores.size} ok, #{errors} fallos)"
        end
        puts "\nUI: Datasets → #{dataset_name} → Runs (#{run_description})"
      end
    end
  end
end
