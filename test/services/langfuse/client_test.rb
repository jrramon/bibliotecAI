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

  test "span_event builds a well-formed span-create event" do
    t0 = Time.utc(2026, 5, 22, 10, 0, 0)
    t1 = Time.utc(2026, 5, 22, 10, 0, 1)
    event = Langfuse::Client.span_event(
      trace_id: "trace-1", name: "mcp::search_books",
      started_at: t0, ended_at: t1,
      input: {"q" => "Asimov"}, output: [{"title" => "Fundación"}]
    )

    assert_equal "span-create", event[:type]
    assert_equal "trace-1", event[:body][:traceId]
    assert_equal "mcp::search_books", event[:body][:name]
    assert_equal "2026-05-22T10:00:00.000Z", event[:body][:startTime]
    assert_equal "2026-05-22T10:00:01.000Z", event[:body][:endTime]
    assert_equal({"q" => "Asimov"}, event[:body][:input])
    assert_equal Langfuse::Config::ENVIRONMENT, event[:body][:environment]
  end

  test "span_event flags failures with level ERROR and a status message" do
    t = Time.now
    event = Langfuse::Client.span_event(
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
end
