require "net/http"
require "json"

module Langfuse
  # Thin wrapper over Langfuse's Datasets / Dataset Items REST API.
  #
  # A *dataset* is the "golden set" used for evals — a collection of
  # *items*, each `{input, expectedOutput}`. The actual experiments run
  # in our code; we just store the inputs and what we expect.
  #
  # Both create operations are designed to be idempotent so re-running
  # the seed task is safe: `ensure` swallows the 409 you get when the
  # name already exists, and `upsert_item` lets Langfuse upsert on the
  # caller-supplied id.
  module Dataset
    OPEN_TIMEOUT = 2
    READ_TIMEOUT = 10

    module_function

    # POST /api/public/v2/datasets. Returns true on success or when the
    # dataset already exists.
    def ensure(name:, description: nil, metadata: nil)
      return false unless Langfuse::Config.configured?

      response = post(
        "/api/public/v2/datasets",
        {name: name, description: description, metadata: metadata}.compact
      )
      code = response&.code.to_i
      return true if (200..299).cover?(code) || code == 409
      Rails.logger.warn("[Langfuse::Dataset] ensure '#{name}' HTTP #{code}: #{response&.body.to_s.truncate(200)}")
      false
    end

    # POST /api/public/dataset-items. Pass a stable `id` and re-running
    # the seed updates the item in place instead of creating duplicates.
    def upsert_item(dataset_name:, id:, input:, expected_output: nil, metadata: nil)
      return false unless Langfuse::Config.configured?

      response = post(
        "/api/public/dataset-items",
        {
          datasetName: dataset_name,
          id: id,
          input: input,
          expectedOutput: expected_output,
          metadata: metadata
        }.compact
      )
      code = response&.code.to_i
      return true if (200..299).cover?(code)
      Rails.logger.warn("[Langfuse::Dataset] upsert_item '#{id}' HTTP #{code}: #{response&.body.to_s.truncate(200)}")
      false
    end

    # POST /api/public/dataset-run-items. Links a dataset item to the trace
    # produced when our code ran that item, tagged with a `runName` that
    # identifies the experiment (typically the model under test). All run
    # items sharing the same `runName` show up as one "run" in the
    # Langfuse UI — the run is auto-created by name on first POST (no
    # separate dataset-runs endpoint exists). The endpoint does NOT
    # accept a `datasetName` key — the dataset is derived from the item.
    # `dataset_name` is kept on the signature so callers stay readable;
    # we just don't send it. Returns the response on success so callers
    # can log helpful diagnostics, false on failure.
    def link_run_item(dataset_name:, dataset_item_id:, trace_id:, run_name:,
      run_description: nil, metadata: nil)
      return false unless Langfuse::Config.configured?

      response = post(
        "/api/public/dataset-run-items",
        {
          datasetItemId: dataset_item_id,
          traceId: trace_id,
          runName: run_name,
          runDescription: run_description,
          metadata: metadata
        }.compact
      )
      code = response&.code.to_i
      return true if (200..299).cover?(code)
      Rails.logger.warn("[Langfuse::Dataset] link_run_item dataset='#{dataset_name}' run='#{run_name}' item='#{dataset_item_id}' HTTP #{code}: #{response&.body.to_s.truncate(300)}")
      false
    end

    def post(path, body)
      uri = URI.join(Langfuse::Config::HOST, path)
      request = Net::HTTP::Post.new(uri)
      request.basic_auth(Langfuse::Config::PUBLIC_KEY, Langfuse::Config::SECRET_KEY)
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(body)

      Net::HTTP.start(uri.host, uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        http.request(request)
      end
    rescue => e
      Rails.logger.warn("[Langfuse::Dataset] #{path} failed: #{e.class}: #{e.message}")
      nil
    end
  end
end
