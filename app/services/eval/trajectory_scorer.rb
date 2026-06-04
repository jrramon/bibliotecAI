module Eval
  # Scores a tool-call trajectory against the gold expected tools.
  #
  #   actual:   [{tool:, arguments:}, ...]   (Eval::FixtureToolExecutor#trajectory)
  #   expected: [{"name"=>, "args_include"=>{}}, ...]   (dataset expected_tools)
  #
  # Metric (order-independent, like ShelfScorer):
  #   - each expected tool greedily matched to an unused actual call (name +
  #     every args_include constraint satisfied);
  #   - recall    = matched / expected
  #   - precision = matched / actual          (penalizes extra/wrong calls)
  #   - score     = recall × precision
  #
  # Special case — expected is EMPTY (out-of-scope / injection): the model must
  # call NO tool. score = 1.0 when actual is empty, else 0.0.
  #
  # args_include matching: string values match as accent/case-insensitive
  # substrings; non-string values (e.g. item_id) match by exact string equality.
  module TrajectoryScorer
    module_function

    def call(actual:, expected:)
      actual = Array(actual)
      expected = Array(expected)

      return empty_expected_result(actual) if expected.empty?

      used = []
      matched = []
      missed = []

      expected.each do |exp|
        idx = actual.each_index.find { |i| !used.include?(i) && tool_matches?(actual[i], exp) }
        if idx
          used << idx
          matched << exp
        else
          missed << exp
        end
      end

      extra = actual.each_index.reject { |i| used.include?(i) }.map { |i| actual[i] }
      recall = matched.size.to_f / expected.size
      precision = actual.empty? ? 0.0 : used.size.to_f / actual.size
      score = recall * precision

      {
        score: score.round(4),
        details: {recall: recall.round(4), precision: precision.round(4),
                  matched: matched.map { |e| e["name"] }, missed: missed.map { |e| e["name"] },
                  extra: extra.map { |c| c[:tool] || c["tool"] }}
      }
    end

    def empty_expected_result(actual)
      ok = actual.empty?
      {
        score: ok ? 1.0 : 0.0,
        details: {recall: 1.0, precision: ok ? 1.0 : 0.0, matched: [], missed: [],
                  extra: actual.map { |c| c[:tool] || c["tool"] }}
      }
    end

    def tool_matches?(call, expected)
      name = call[:tool] || call["tool"]
      return false unless name.to_s == expected["name"].to_s

      args = call[:arguments] || call["arguments"] || {}
      Hash(expected["args_include"]).all? { |key, want| arg_matches?(args[key.to_s], want) }
    end

    def arg_matches?(got, want)
      if want.is_a?(String)
        normalize(got).include?(normalize(want))
      else
        got.to_s == want.to_s
      end
    end

    def normalize(text)
      ActiveSupport::Inflector.transliterate(text.to_s.downcase).strip
    end
  end
end
