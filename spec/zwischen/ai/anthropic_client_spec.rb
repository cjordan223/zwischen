# frozen_string_literal: true

require "spec_helper"
require "zwischen/ai/anthropic_client"

RSpec.describe Zwischen::AI::AnthropicClient do
  let(:api_key) { "sk-ant-test-123" }
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:test_connection) do
    Faraday.new do |conn|
      conn.request :json
      conn.response :json, content_type: /\bjson$/
      conn.adapter :test, stubs
    end
  end
  let(:faraday_args) { [] }

  before do
    connection = test_connection # build before stubbing Faraday.new
    args = faraday_args
    allow(Faraday).to receive(:new) do |**kwargs|
      args << kwargs
      connection
    end
  end

  def stub_messages(status: 200, body: { "content" => [{ "type" => "text", "text" => "analysis" }] },
                    content_type: "application/json")
    captured = {}
    stubs.post("/messages") do |env|
      captured[:body] = JSON.parse(env.body)
      captured[:headers] = env.request_headers.dup
      raw = body.is_a?(String) ? body : body.to_json
      [status, { "Content-Type" => content_type }, raw]
    end
    captured
  end

  describe "#initialize" do
    it "raises Zwischen::AI::Error when no API key is given" do
      expect { described_class.new }
        .to raise_error(Zwischen::AI::Error, /Claude API key not found/)
    end

    it "points the connection at the Anthropic API base URL" do
      described_class.new(api_key: api_key)
      expect(faraday_args.first[:url]).to eq("https://api.anthropic.com/v1/")
    end
  end

  describe "#analyze" do
    it "posts to /messages with the default model, max_tokens, and user message" do
      captured = stub_messages
      described_class.new(api_key: api_key).analyze("review this finding")

      expect(captured[:body]).to eq(
        "model" => "claude-3-5-sonnet-20241022",
        "max_tokens" => 4096,
        "messages" => [{ "role" => "user", "content" => "review this finding" }]
      )
    end

    it "uses the model from config when provided" do
      captured = stub_messages
      described_class.new(api_key: api_key, config: { "model" => "claude-3-haiku-20240307" }).analyze("prompt")

      expect(captured[:body]["model"]).to eq("claude-3-haiku-20240307")
    end

    it "sends the x-api-key and anthropic-version headers" do
      captured = stub_messages
      described_class.new(api_key: api_key).analyze("prompt")

      expect(captured[:headers]["x-api-key"]).to eq("sk-ant-test-123")
      expect(captured[:headers]["anthropic-version"]).to eq("2023-06-01")
    end

    it "returns the first content block's text from a successful response" do
      stub_messages(body: { "content" => [{ "type" => "text", "text" => "likely a false positive" }] })
      result = described_class.new(api_key: api_key).analyze("prompt")

      expect(result).to eq("likely a false positive")
    end

    it "parses a JSON string body when the response middleware did not decode it" do
      stub_messages(
        body: { "content" => [{ "type" => "text", "text" => "decoded anyway" }] }.to_json,
        content_type: "text/plain"
      )
      result = described_class.new(api_key: api_key).analyze("prompt")

      expect(result).to eq("decoded anyway")
    end

    it "raises Zwischen::AI::Error with the API error message on a 4xx response" do
      stub_messages(
        status: 401,
        body: { "type" => "error", "error" => { "type" => "authentication_error", "message" => "invalid x-api-key" } }
      )

      expect { described_class.new(api_key: api_key).analyze("prompt") }
        .to raise_error(Zwischen::AI::Error, "Claude API error: invalid x-api-key")
    end

    it "raises Zwischen::AI::Error on a 5xx response" do
      stub_messages(status: 529, body: { "error" => { "message" => "Overloaded" } })

      expect { described_class.new(api_key: api_key).analyze("prompt") }
        .to raise_error(Zwischen::AI::Error, "Claude API error: Overloaded")
    end

    it "raises Zwischen::AI::Error when the request times out" do
      stubs.post("/messages") { raise Faraday::TimeoutError, "execution expired" }

      expect { described_class.new(api_key: api_key).analyze("prompt") }
        .to raise_error(Zwischen::AI::Error, "Network error: execution expired")
    end

    it "raises Zwischen::AI::Error when the connection fails" do
      stubs.post("/messages") { raise Faraday::ConnectionFailed, "Connection refused" }

      expect { described_class.new(api_key: api_key).analyze("prompt") }
        .to raise_error(Zwischen::AI::Error, /Network error: Connection refused/)
    end

    it "raises Zwischen::AI::Error when the response body is invalid JSON" do
      stub_messages(body: "not json at all", content_type: "text/plain")

      expect { described_class.new(api_key: api_key).analyze("prompt") }
        .to raise_error(Zwischen::AI::Error, /Invalid JSON response/)
    end
  end
end
