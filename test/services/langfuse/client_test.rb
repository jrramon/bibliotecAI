require "test_helper"

class Langfuse::ClientTest < ActiveSupport::TestCase
  test "trace_event builds a well-formed trace-create event" do
    event = Langfuse::Client.trace_event(
      id: "trace-1", name: "cover-identification",
      output: {"title" => "Kokoro"}, metadata: {cover_photo_id: 7}
    )

    assert_equal "trace-create", event[:type]
    assert event[:id].present?, "event needs its own UUID for dedup"
    assert event[:timestamp].present?
    assert_equal "trace-1", event[:body][:id]
    assert_equal "cover-identification", event[:body][:name]
    assert_equal({"title" => "Kokoro"}, event[:body][:output])
    assert_equal Langfuse::Config::ENVIRONMENT, event[:body][:environment]
  end

  test "generation_event builds a well-formed generation-create event" do
    t0 = Time.utc(2026, 5, 22, 10, 0, 0)
    t1 = Time.utc(2026, 5, 22, 10, 0, 5)
    event = Langfuse::Client.generation_event(
      trace_id: "trace-1", name: "claude -p (cover)",
      started_at: t0, ended_at: t1, input: "prompt", output: {"title" => "Kokoro"},
      usage_details: {input: 10, output: 20}, cost_details: {"total" => 0.01}
    )

    assert_equal "generation-create", event[:type]
    assert_equal "trace-1", event[:body][:traceId]
    assert_equal "2026-05-22T10:00:00.000Z", event[:body][:startTime]
    assert_equal "2026-05-22T10:00:05.000Z", event[:body][:endTime]
    assert_equal({input: 10, output: 20}, event[:body][:usageDetails])
    assert_equal({"total" => 0.01}, event[:body][:costDetails])
    assert_equal Langfuse::Config::ENVIRONMENT, event[:body][:environment]
  end

  test "generation_event records the prompt link when given prompt_name and prompt_version" do
    t = Time.now
    event = Langfuse::Client.generation_event(
      trace_id: "t", name: "g", started_at: t, ended_at: t,
      prompt_name: "cover-identification", prompt_version: 3
    )

    assert_equal "cover-identification", event[:body][:promptName]
    assert_equal 3, event[:body][:promptVersion]
  end

  test "generation_event omits the prompt link when version is nil (local fallback)" do
    t = Time.now
    event = Langfuse::Client.generation_event(
      trace_id: "t", name: "g", started_at: t, ended_at: t,
      prompt_name: "cover-identification", prompt_version: nil
    )

    assert_nil event[:body][:promptVersion], "version nil → no link to a Langfuse-stored version"
  end

  test "observation_event builds a well-formed observation-create with the given type" do
    t0 = Time.utc(2026, 5, 22, 10, 0, 0)
    t1 = Time.utc(2026, 5, 22, 10, 0, 1)
    event = Langfuse::Client.observation_event(
      type: "TOOL",
      trace_id: "trace-1", name: "mcp::search_books",
      started_at: t0, ended_at: t1,
      input: {"q" => "Asimov"}, output: [{"title" => "Fundación"}]
    )

    assert_equal "observation-create", event[:type]
    assert_equal "TOOL", event[:body][:type]
    assert_equal "trace-1", event[:body][:traceId]
    assert_equal "mcp::search_books", event[:body][:name]
    assert_equal "2026-05-22T10:00:00.000Z", event[:body][:startTime]
    assert_equal "2026-05-22T10:00:01.000Z", event[:body][:endTime]
    assert_equal({"q" => "Asimov"}, event[:body][:input])
    assert_equal Langfuse::Config::ENVIRONMENT, event[:body][:environment]
  end

  test "observation_event flags failures with level ERROR and a status message" do
    t = Time.now
    event = Langfuse::Client.observation_event(
      type: "TOOL",
      trace_id: "t", name: "mcp::boom", started_at: t, ended_at: t,
      level: "ERROR", status_message: "bad arg"
    )

    assert_equal "ERROR", event[:body][:level]
    assert_equal "bad arg", event[:body][:statusMessage]
  end

  test "generation_event flags errors with level ERROR and a status message" do
    t = Time.now
    event = Langfuse::Client.generation_event(
      trace_id: "t", name: "n", started_at: t, ended_at: t,
      level: "ERROR", status_message: "claude exited 1"
    )

    assert_equal "ERROR", event[:body][:level]
    assert_equal "claude exited 1", event[:body][:statusMessage]
  end

  test "usage_from_claude_envelope maps token counts and cost" do
    envelope = {
      "usage" => {"input_tokens" => 1200, "output_tokens" => 340, "cache_read_input_tokens" => 800},
      "total_cost_usd" => 0.0234
    }
    usage, cost = Langfuse::Client.usage_from_claude_envelope(envelope)

    assert_equal({input: 1200, output: 340, cache_read: 800}, usage)
    assert_equal({"total" => 0.0234}, cost)
  end

  test "usage_from_claude_envelope tolerates a nil or shapeless envelope" do
    assert_equal [nil, nil], Langfuse::Client.usage_from_claude_envelope(nil)
    assert_equal [nil, nil], Langfuse::Client.usage_from_claude_envelope({})
  end

  test "ingest is a no-op when Langfuse is not configured" do
    Langfuse::Config.stubs(:configured?).returns(false)
    Net::HTTP.expects(:start).never

    assert_nil Langfuse::Client.ingest([{type: "trace-create"}])
  end

  test "ingest POSTs the batch when configured" do
    Langfuse::Config.stubs(:configured?).returns(true)
    fake = mock
    fake.stubs(:code).returns("207")
    fake.stubs(:body).returns("{}")
    Net::HTTP.expects(:start).returns(fake)

    response = Langfuse::Client.ingest([Langfuse::Client.trace_event(id: "t", name: "n")])
    assert_equal "207", response.code
  end

  test "ingest swallows transport errors and never raises" do
    Langfuse::Config.stubs(:configured?).returns(true)
    Net::HTTP.stubs(:start).raises(Errno::ECONNREFUSED)

    assert_nothing_raised do
      assert_nil Langfuse::Client.ingest([{type: "trace-create"}])
    end
  end

  test "ingest skips empty batches without hitting the network" do
    Net::HTTP.expects(:start).never

    assert_nil Langfuse::Client.ingest([])
    assert_nil Langfuse::Client.ingest(nil)
  end

  test "score_event builds a well-formed score-create event" do
    event = Langfuse::Client.score_event(
      trace_id: "trace-1", name: "shelf_quality", value: 0.78,
      comment: "11/14 títulos OK"
    )

    assert_equal "score-create", event[:type]
    assert event[:id].present?
    assert_equal "trace-1", event[:body][:traceId]
    assert_equal "shelf_quality", event[:body][:name]
    assert_equal 0.78, event[:body][:value]
    assert_equal "NUMERIC", event[:body][:dataType]
    assert_equal "11/14 títulos OK", event[:body][:comment]
    assert_equal Langfuse::Config::ENVIRONMENT, event[:body][:environment]
    assert_nil event[:body][:observationId], "trace-level score: no observationId"
  end

  test "score_event attaches to a specific observation when observation_id is given" do
    event = Langfuse::Client.score_event(
      trace_id: "trace-1", observation_id: "obs-9",
      name: "shelf_quality", value: 1.0
    )

    assert_equal "obs-9", event[:body][:observationId]
  end

  test "score_event carries metadata when given (so the model shows in the Scores UI)" do
    event = Langfuse::Client.score_event(
      trace_id: "t", name: "shelf_quality", value: 0.5,
      metadata: {model: "claude-opus-4-7", item: "shelf-1"}
    )

    assert_equal({model: "claude-opus-4-7", item: "shelf-1"}, event[:body][:metadata])
  end

  test "score_event omits metadata when empty" do
    event = Langfuse::Client.score_event(
      trace_id: "t", name: "shelf_quality", value: 0.5
    )

    refute event[:body].key?(:metadata), "no debería mandarse clave metadata vacía"
  end
end
