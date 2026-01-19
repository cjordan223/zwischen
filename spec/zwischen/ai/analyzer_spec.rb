# frozen_string_literal: true

require "spec_helper"
require "zwischen/ai/analyzer"

RSpec.describe Zwischen::AI::Analyzer do
  describe "#initialize" do
    it "instantiates AnthropicClient by default" do
      expect(Zwischen::AI::AnthropicClient).to receive(:new).and_call_original
      
      analyzer = described_class.new(api_key: "test")
      client = analyzer.instance_variable_get(:@client)
      expect(client).to be_a(Zwischen::AI::AnthropicClient)
    end

    it "instantiates OllamaClient when provider is ollama" do
      expect(Zwischen::AI::OllamaClient).to receive(:new).and_call_original
      
      analyzer = described_class.new(provider: "ollama")
      client = analyzer.instance_variable_get(:@client)
      expect(client).to be_a(Zwischen::AI::OllamaClient)
    end

    it "instantiates OpenAIClient when provider is openai" do
      expect(Zwischen::AI::OpenAIClient).to receive(:new).and_call_original

      analyzer = described_class.new(provider: "openai", api_key: "test")
      client = analyzer.instance_variable_get(:@client)
      expect(client).to be_a(Zwischen::AI::OpenAIClient)
    end
  end
end
