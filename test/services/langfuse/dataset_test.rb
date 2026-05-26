require "test_helper"

class Langfuse::DatasetTest < ActiveSupport::TestCase
  # Helpers: stub the whole HTTP round-trip and capture the Net::HTTP::Post
  # request object so we can assert on the body. The implementation builds
  # the request inside a `Net::HTTP.start(...) { |http| http.request(req) }`
  # block, so we yield a fake http to the block, capture `req` there, and
  # return our fake response from `Net::HTTP.start`.
  def stub_http_post(code)
    fake_response = mock
    fake_response.stubs(:code).returns(code.to_s)
    fake_response.stubs(:body).returns("{}")

    @captured_request = nil
    fake_http = stub
    fake_http.stubs(:request).with do |req|
      @captured_request = req
      true
    end.returns(fake_response)

    Net::HTTP.stubs(:start).yields(fake_http).returns(fake_response)
  end

  def captured_body
    JSON.parse(@captured_request.body)
  end

  def captured_path
    @captured_request.path
  end

  test "ensure POSTs to /api/public/v2/datasets with the name and returns true on 2xx" do
    Langfuse::Config.stubs(:configured?).returns(true)
    stub_http_post(200)

    assert Langfuse::Dataset.ensure(name: "cover-identification-eval", description: "set")

    assert_equal "/api/public/v2/datasets", captured_path
    assert_equal "cover-identification-eval", captured_body["name"]
    assert_equal "set", captured_body["description"]
  end

  test "ensure treats 409 conflict as already-exists and returns true" do
    Langfuse::Config.stubs(:configured?).returns(true)
    stub_http_post(409)

    assert Langfuse::Dataset.ensure(name: "cover-identification-eval"),
      "409 = ya existe, re-correr el seed sigue verde"
  end

  test "ensure returns false on other HTTP errors" do
    Langfuse::Config.stubs(:configured?).returns(true)
    stub_http_post(500)

    refute Langfuse::Dataset.ensure(name: "n")
  end

  test "ensure is a no-op without Langfuse configured" do
    Langfuse::Config.stubs(:configured?).returns(false)
    Net::HTTP.expects(:start).never

    refute Langfuse::Dataset.ensure(name: "n")
  end

  test "upsert_item POSTs to /api/public/dataset-items with the supplied id" do
    Langfuse::Config.stubs(:configured?).returns(true)
    stub_http_post(200)

    assert Langfuse::Dataset.upsert_item(
      dataset_name: "cover-identification-eval",
      id: "sample-shelf",
      input: {filename: "shelf.jpg"},
      expected_output: {title: "X"}
    )

    assert_equal "/api/public/dataset-items", captured_path
    assert_equal "cover-identification-eval", captured_body["datasetName"]
    assert_equal "sample-shelf", captured_body["id"]
    assert_equal({"filename" => "shelf.jpg"}, captured_body["input"])
    assert_equal({"title" => "X"}, captured_body["expectedOutput"])
  end

  test "upsert_item swallows network failures and returns false" do
    Langfuse::Config.stubs(:configured?).returns(true)
    Net::HTTP.stubs(:start).raises(Errno::ECONNREFUSED)

    assert_nothing_raised do
      refute Langfuse::Dataset.upsert_item(dataset_name: "n", id: "i", input: {})
    end
  end

  test "link_run_item POSTs to /api/public/dataset-run-items with item, trace and runName" do
    Langfuse::Config.stubs(:configured?).returns(true)
    stub_http_post(200)

    assert Langfuse::Dataset.link_run_item(
      dataset_name: "shelf-identification-eval",
      dataset_item_id: "shelf-1",
      trace_id: "abc-123",
      run_name: "claude-sonnet-4-6",
      run_description: "Comparativa modelos shelf 2026-05-26"
    )

    assert_equal "/api/public/dataset-run-items", captured_path
    assert_equal "shelf-1", captured_body["datasetItemId"]
    assert_equal "abc-123", captured_body["traceId"]
    assert_equal "claude-sonnet-4-6", captured_body["runName"]
    assert_equal "Comparativa modelos shelf 2026-05-26", captured_body["runDescription"]
    refute captured_body.key?("datasetName"), "datasetName no es válido en este endpoint"
  end

  test "link_run_item is a no-op without Langfuse configured" do
    Langfuse::Config.stubs(:configured?).returns(false)
    Net::HTTP.expects(:start).never

    refute Langfuse::Dataset.link_run_item(
      dataset_name: "d", dataset_item_id: "i", trace_id: "t", run_name: "r"
    )
  end
end
