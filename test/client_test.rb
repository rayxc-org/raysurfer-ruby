# frozen_string_literal: true

require_relative "test_helper"

class FakeClient < Raysurfer::Client
  attr_reader :calls

  def initialize(**kwargs)
    super
    @calls = []
  end

  private

  def request(method, path, body: nil, headers: nil)
    @calls << { method: method, path: path, body: body, headers: headers }

    case path
    when "/api/retrieve/search"
      { "matches" => [], "total_found" => 0, "cache_hit" => false }
    when "/api/store/code-block"
      { "success" => true, "code_block_id" => "cb_123", "embedding_id" => "emb_123", "message" => "stored" }
    when "/api/store/execution-result"
      { "success" => true, "code_blocks_stored" => 1, "message" => "uploaded" }
    when "/api/store/cache-usage"
      { "success" => true, "vote_pending" => true, "message" => "queued" }
    else
      {}
    end
  end
end

class ClientTest < Minitest::Test
  def test_search_payload_shape
    client = FakeClient.new(api_key: "rs_test")
    result = client.search(task: "Generate report")

    call = client.calls.last
    assert_equal "POST", call[:method]
    assert_equal "/api/retrieve/search", call[:path]
    assert_equal "Generate report", call[:body][:task]
    assert_equal 5, call[:body][:top_k]
    assert_equal 0, result["total_found"]
  end

  def test_store_code_block
    client = FakeClient.new(api_key: "rs_test")

    result = client.store_code_block(
      name: "shopify_order_node",
      source: "def fetch_order(id)\nend",
      entrypoint: "fetch_order",
      language: "ruby",
      description: "Fetch order from Shopify"
    )

    call = client.calls.last
    assert_equal "/api/store/code-block", call[:path]
    assert_equal "ruby", call[:body][:language]
    assert_equal true, result["success"]
  end

  def test_upload_requires_hash_file_written
    client = FakeClient.new(api_key: "rs_test")

    error = assert_raises(ArgumentError) do
      client.upload(task: "x", file_written: "bad", succeeded: true)
    end

    assert_match "file_written", error.message
  end

  def test_upload_and_vote
    client = FakeClient.new(api_key: "rs_test")

    upload = client.upload(
      task: "Generate quarterly report",
      file_written: { path: "report.rb", content: "puts 'ok'" },
      succeeded: true
    )
    vote = client.vote_code_snip(
      task: "Generate quarterly report",
      code_block_id: "cb_123",
      code_block_name: "report_node",
      code_block_description: "Report helper",
      succeeded: true
    )

    assert_equal true, upload["success"]
    assert_equal true, vote["vote_pending"]
  end
end
