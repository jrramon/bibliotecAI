module Eval
  # Compara la lista de libros que devolvió un modelo (`actual_books`) contra la
  # lista gold (`expected_books`, normalmente extraída con Opus) y devuelve un
  # score entre 0.0 y 1.0 más un desglose para depurar.
  #
  # Métrica (graduada con castigo por alucinación):
  #   - Por cada libro gold, busca el "mejor candidato" en actual no emparejado
  #     todavía. Greedy ordenado por gold; no usa Hungarian.
  #     - 1.0 si título y autor coinciden tras normalizar.
  #     - 0.5 si solo el título coincide.
  #     - 0.0 si nada.
  #   - recall    = suma_de_puntos / gold.size      (recall ponderado)
  #   - precision = matched_actual / actual.size    (penaliza alucinaciones)
  #   - score     = recall × precision
  #
  # Normalización:
  #   - Títulos: lowercase + sin tildes + sin puntuación + espacios colapsados.
  #   - Autores: igual, y además tokens ordenados — así "Laloux, Frédéric" y
  #     "Frédéric Laloux" se consideran equivalentes.
  module ShelfScorer
    module_function

    def call(actual_books:, expected_books:)
      actual_books = Array(actual_books)
      expected_books = Array(expected_books)

      return perfect if actual_books.empty? && expected_books.empty?
      return all_missed(expected_books) if actual_books.empty?
      return all_extra(actual_books) if expected_books.empty?

      actual_pool = (0...actual_books.size).to_a
      matched_full = []
      matched_title_only = []
      missed = []

      expected_books.each_with_index do |gold, gold_idx|
        best_full = nil
        best_title = nil

        actual_pool.each do |idx|
          actual = actual_books[idx]
          next unless titles_match?(actual["title"], gold["title"])
          if authors_match?(actual["author"], gold["author"])
            best_full = idx
            break
          else
            best_title ||= idx
          end
        end

        if best_full
          actual_pool.delete(best_full)
          matched_full << {
            gold_index: gold_idx,
            actual_index: best_full,
            title: gold["title"]
          }
        elsif best_title
          actual_pool.delete(best_title)
          matched_title_only << {
            gold_index: gold_idx,
            actual_index: best_title,
            title: gold["title"],
            expected_author: gold["author"],
            got_author: actual_books[best_title]["author"]
          }
        else
          missed << {
            gold_index: gold_idx,
            title: gold["title"],
            author: gold["author"]
          }
        end
      end

      extra = actual_pool.map do |idx|
        {
          actual_index: idx,
          title: actual_books[idx]["title"],
          author: actual_books[idx]["author"]
        }
      end

      points = matched_full.size + matched_title_only.size * 0.5
      recall = points / expected_books.size.to_f
      matched_count = matched_full.size + matched_title_only.size
      precision = matched_count / actual_books.size.to_f
      score = recall * precision

      {
        score: score.round(4),
        details: {
          recall: recall.round(4),
          precision: precision.round(4),
          matched_full: matched_full,
          matched_title_only: matched_title_only,
          missed: missed,
          extra: extra
        }
      }
    end

    def titles_match?(a, b)
      normalize_title(a) == normalize_title(b) && !normalize_title(a).empty?
    end

    def authors_match?(a, b)
      tokens_a = author_tokens(a)
      tokens_b = author_tokens(b)
      tokens_a == tokens_b
    end

    def normalize_title(text)
      return "" if text.nil?
      ActiveSupport::Inflector.transliterate(text.to_s.downcase)
        .gsub(/[[:punct:]]/, " ")
        .squeeze(" ")
        .strip
    end

    # Tokens ordenados alfabéticamente para que el orden nombre/apellido no
    # importe: "Laloux, Frédéric" → ["frederic", "laloux"]; "Frédéric Laloux"
    # → ["frederic", "laloux"] → match.
    def author_tokens(text)
      return [] if text.nil? || text.to_s.strip.empty?
      ActiveSupport::Inflector.transliterate(text.to_s.downcase)
        .gsub(/[[:punct:]]/, " ")
        .split(/\s+/)
        .reject(&:empty?)
        .sort
    end

    def perfect
      {score: 1.0, details: empty_details(recall: 1.0, precision: 1.0)}
    end

    def all_missed(expected_books)
      missed = expected_books.each_with_index.map do |b, i|
        {gold_index: i, title: b["title"], author: b["author"]}
      end
      {score: 0.0, details: empty_details.merge(missed: missed)}
    end

    def all_extra(actual_books)
      extra = actual_books.each_with_index.map do |b, i|
        {actual_index: i, title: b["title"], author: b["author"]}
      end
      {score: 0.0, details: empty_details.merge(extra: extra)}
    end

    def empty_details(recall: 0.0, precision: 0.0)
      {
        recall: recall,
        precision: precision,
        matched_full: [],
        matched_title_only: [],
        missed: [],
        extra: []
      }
    end
  end
end
