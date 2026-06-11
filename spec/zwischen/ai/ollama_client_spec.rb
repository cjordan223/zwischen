# frozen_string_literal: true

require "spec_helper"
require "zwischen/ai/ollama_client"

RSpec.describe Zwischen::AI::OllamaClient do
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

  def stub_chat(status: 200, body: { "message" => { "content" => "analysis" } })
    captured = {}
    stubs.post("/api/chat") do |env|
      captured[:body] = JSON.parse(env.body)
      captured[:headers] = env.request_headers.dup
      [status, json_headers, body.to_json]
    end
    captured
  end

  describe "#initialize" do
    it "does not require an API key" do
      expect { described_class.new }.not_to raise_error
    end

    it "uses http://localhost:11434 as the default URL" do
      described_class.new
      expect(faraday_args.first[:url]).to eq("http://localhost:11434")
    end

    it "uses the URL from config when provided" do
      described_class.new(config: { "url" => "http://ollama.internal:9999" })
      expect(faraday_args.first[:url]).to eq("http://ollama.internal:9999")
    end

    it "strips a trailing /api/chat from a user-provided URL" do
      described_class.new(config: { "url" => "http://localhost:11434/api/chat" })
      expect(faraday_args.first[:url]).to eq("http://localhost:11434")
    end

    it "strips a trailing /api/chat/ with trailing slash" do
      described_class.new(config: { "url" => "http://localhost:11434/api/chat/" })
      expect(faraday_args.first[:url]).to eq("http://localhost:11434")
    end
  end

  describe "#analyze" do
    it "posts to /api/chat with the default model and non-streaming chat payload" do
      captured = stub_chat
      described_class.new.analyze("review this finding")

      expect(captured[:body]).to eq(
        "model" => "llama3",
        "messages" => [{ "role" => "user", "content" => "review this finding" }],
        "stream" => false
      )
    end

    it "uses the model from config when provided" do
      captured = stub_chat
      described_class.new(config: { "model" => "codellama" }).analyze("prompt")

      expect(captured[:body]["model"]).to eq("codellama")
    end

    it "returns the message content from a successful response" do
      stub_chat(body: { "message" => { "role" => "assistant", "content" => "looks like a real secret" } })
      result = described_class.new.analyze("prompt")

      expect(result).to eq("looks like a real secret")
    end

    it "raises Zwischen::AI::Error when a successful response has no message content" do
      stub_chat(body: { "done" => true })

      expect { described_class.new.analyze("prompt") }
        .to raise_error(Zwischen::AI::Error, /Unexpected Ollama response format/)
    end

    it "raises Zwischen::AI::Error with the API error message on a 4xx response" do
      stub_chat(status: 404, body: { "error" => "model 'llama3' not found" })

      expect { described_class.new.analyze("prompt") }
        .to raise_error(Zwischen::AI::Error, "Ollama API error: model 'llama3' not found")
    end

    it "raises Zwischen::AI::Error with 'Unknown error' on a 5xx response without an error body" do
      stub_chat(status: 500, body: {})

      expect { described_class.new.analyze("prompt") }
        .to raise_error(Zwischen::AI::Error, "Ollama API error: Unknown error")
    end

    it "raises Zwischen::AI::Error when the connection fails" do
      stubs.post("/api/chat") { raise Faraday::ConnectionFailed, "Connection refused" }

      expect { described_class.new.analyze("prompt") }
        .to raise_error(Zwischen::AI::Error, /Ollama connection error: .*Is Ollama running\?/)
    end

    it "raises Zwischen::AI::Error when the request times out" do
      stubs.post("/api/chat") { raise Faraday::TimeoutError, "execution expired" }

      expect { described_class.new.analyze("prompt") }
        .to raise_error(Zwischen::AI::Error, /Ollama connection error: execution expired/)
    end
  end
end
