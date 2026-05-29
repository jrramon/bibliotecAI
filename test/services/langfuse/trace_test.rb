require "test_helper"

class Langfuse::TraceTest < ActiveSupport::TestCase
  # Captures the events Langfuse::Trace.record would ship, without touching
  # the network. Every Claude service funnels through record, so getting
  # this right covers the instrumentation across the board.
  def capture_ingest
    events = nil
    Langfuse::Client.stubs(:ingest).with { |batch| events = batch }
    yield
    events
  end

  test "record ingests a trace and a generation linked by traceId" do
    events = capture_ingest do
      Langfuse::Trace.record(
        trace_name: "cover-identification",
        generation_name: "claude -p (cover)",
        started_at: Time.now, prompt: "the prompt",
        output: {"title" => "Kokoro"},
        metadata: {cover_photo_id: 7}
      )
    end

    trace, generation = events
    assert_equal "trace-create", trace[:type]
    assert_equal "generation-create", generation[:type]
    assert_equal "cover-identification", trace[:body][:name]
    assert_equal trace[:body][:id], generation[:body][:traceId]
    assert_equal({cover_photo_id: 7}, trace[:body][:metadata])
    assert_equal "the prompt", generation[:body][:input]
    assert_equal({"title" => "Kokoro"}, generation[:body][:output])
  end

  test "record marks the generation ERROR and drops output on a failure" do
    events = capture_ingest do
      Langfuse::Trace.record(
        trace_name: "cover-identification",
        generation_name: "claude -p (cover)",
        started_at: Time.now, prompt: "the prompt",
        output: {"title" => "ignored"},
        error_message: "claude exited 1"
      )
    end

    trace, generation = events
    assert_equal "ERROR", generation[:body][:level]
    assert_equal "claude exited 1", generation[:body][:statusMessage]
    assert_nil generation[:body][:output]
    assert_nil trace[:body][:output]
  end

  test "record carries sessionId and userId for grouping conversations" do
    events = capture_ingest do
      Langfuse::Trace.record(
        trace_name: "telegram-agent-turn",
        generation_name: "claude -p (telegram)",
        started_at: Time.now, prompt: "hola", output: "¡hola!",
        user_id: "42", session_id: "1000"
      )
    end

    trace, = events
    assert_equal "42", trace[:body][:userId]
    assert_equal "1000", trace[:body][:sessionId]
  end

  test "record uses input for the trace and prompt for the generation" do
    events = capture_ingest do
      Langfuse::Trace.record(
        trace_name: "telegram-agent-turn",
        generation_name: "claude -p (telegram)",
        started_at: Time.now,
        prompt: "Eres el asistente... (system prompt + historial + user message)",
        input: "¿qué tengo de Asimov?",
        output: "Tienes 11 libros..."
      )
    end

    trace, generation = events
    assert_equal "¿qué tengo de Asimov?", trace[:body][:input]
    assert_match(/Eres el asistente/, generation[:body][:input])
    assert_equal "Tienes 11 libros...", trace[:body][:output]
  end

  test "record honours a caller-provided trace_id so spans elsewhere can link in" do
    events = capture_ingest do
      Langfuse::Trace.record(
        trace_id: "pre-minted-abc",
        trace_name: "telegram-agent-turn",
        generation_name: "claude -p (telegram)",
        started_at: Time.now, prompt: "p", output: "o"
      )
    end

    trace, generation = events
    assert_equal "pre-minted-abc", trace[:body][:id]
    assert_equal "pre-minted-abc", generation[:body][:traceId]
  end

  test "record maps the claude envelope into usage and cost on the generation" do
    events = capture_ingest do
      Langfuse::Trace.record(
        trace_name: "t", generation_name: "g",
        started_at: Time.now, prompt: "p", output: "o",
        envelope: {"usage" => {"input_tokens" => 100, "output_tokens" => 50}, "total_cost_usd" => 0.02}
      )
    end

    _, generation = events
    assert_equal({input: 100, output: 50}, generation[:body][:usageDetails])
    assert_equal({"total" => 0.02}, generation[:body][:costDetails])
  end
end
