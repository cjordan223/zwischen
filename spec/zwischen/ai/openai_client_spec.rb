# frozen_string_literal: true

require "spec_helper"
require "zwischen/ai/openai_client"

RSpec.describe Zwischen::AI::OpenAIClient do
  let(:api_key) { "sk-test-123" }
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:test_connection) do
    Faraday.new do |conn|
      conn.request :json
      conn.response :json, content_type: /\bjson$/
      conn.adapter :test, stubs
    end
  end
  let(:faraday_args) { [] }
  let(:json_headers) { { "Content-Type" => "application/json" } }

  before do
    connection = test_connection # build before stubbing Faraday.new
    args = faraday_args
    allow(Faraday).to receive(:new) do |**kwargs|
      args << kwargs
      connection
    end
  end

  def stub_completions(status: 200, body: { "choices" => [{ "message" => { "content" => "analysis" } }] },
                       content_type: "application/json")
    captured = {}
    stubs.post("/chat/completions") do |env|
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
        .to raise_error(Zwischen::AI::Error, /OpenAI API key not found/)
    end

    it "points the connection at the OpenAI API base URL" do
      described_class.new(api_key: api_key)
      expect(faraday_args.first[:url]).to eq("https://api.openai.com/v1/")
    end
  end

  describe "#analyze" do
    it "posts to /chat/completions with the default model and user message" do
      captured = stub_completions
      described_class.new(api_key: api_key).analyze("review this finding")

      expect(captured[:body]).to eq(
        "model" => "gpt-4",
        "messages" => [{ "role" => "user", "content" => "review this finding" }]
      )
    end

    it "uses the model from config when provided" do
      captured = stub_completions
      described_class.new(api_key: api_key, config: { "model" => "gpt-4o-mini" }).analyze("prompt")

      expect(captured[:body]["model"]).to eq("gpt-4o-mini")
    end

    it "sends the API key as a Bearer Authorization header" do
      captured = stub_completions
      described_class.new(api_key: api_key).analyze("prompt")

      expect(captured[:headers]["Authorization"]).to eq("Bearer sk-test-123")
    end

    it "returns the first choice's message content from a successful response" do
      stub_completions(body: { "choices" => [{ "message" => { "content" => "likely a false positive" } }] })
      result = described_class.new(api_key: api_key).analyze("prompt")

      expect(result).to eq("likely a false positive")
    end

    it "parses a JSON string body when the response middleware did not decode it" do
      stub_completions(
        body: { "choices" => [{ "message" => { "content" => "decoded anyway" } }] }.to_json,
        content_type: "text/plain"
      )
      result = described_class.new(api_key: api_key).analyze("prompt")

      expect(result).to eq("decoded anyway")
    end

    it "raises Zwischen::AI::Error with the API error message on a 4xx response" do
      stub_completions(status: 401, body: { "error" => { "message" => "Incorrect API key provided" } })

      expect { described_class.new(api_key: api_key).analyze("prompt") }
        .to raise_error(Zwischen::AI::Error, "OpenAI API error: Incorrect API key provided")
    end

    it "raises Zwischen::AI::Error on a 5xx response" do
      stub_completions(status: 500, body: { "error" => { "message" => "The server had an error" } })

      expect { described_class.new(api_key: api_key).analyze("prompt") }
        .to raise_error(Zwischen::AI::Error, "OpenAI API error: The server had an error")
    end

    it "raises Zwischen::AI::Error when the request times out" do
      stubs.post("/chat/completions") { raise Faraday::TimeoutError, "execution expired" }

      expect { described_class.new(api_key: api_key).analyze("prompt") }
        .to raise_error(Zwischen::AI::Error, "Network error: execution expired")
    end

    it "raises Zwischen::AI::Error when the connection fails" do
      stubs.post("/chat/completions") { raise Faraday::ConnectionFailed, "Connection refused" }

      expect { described_class.new(api_key: api_key).analyze("prompt") }
        .to raise_error(Zwischen::AI::Error, /Network error: Connection refused/)
    end

    it "raises Zwischen::AI::Error when the response body is invalid JSON" do
      stub_completions(body: "not json at all", content_type: "text/plain")

      expect { described_class.new(api_key: api_key).analyze("prompt") }
        .to raise_error(Zwischen::AI::Error, /Invalid JSON response/)
    end
  end
end
