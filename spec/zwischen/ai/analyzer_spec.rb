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

  describe "#analyze response parsing" do
    let(:finding) do
      Zwischen::Finding::Finding.new(
        type: "secret", scanner: "gitleaks", severity: "high",
        file: "config.env", line: 1, message: "AWS key", rule_id: "aws-access-token"
      )
    end

    def analyzer_with_response(response)
      analyzer = described_class.new(provider: "ollama")
      client = analyzer.instance_variable_get(:@client)
      allow(client).to receive(:analyze).and_return(response)
      analyzer
    end

    let(:annotation_json) do
      '{"1": {"priority": "high", "is_false_positive": false, ' \
        '"fix_suggestion": "Rotate the key.", "risk_explanation": "Full account access."}}'
    end

    it "parses bare JSON responses into annotations" do
      enhanced = analyzer_with_response(annotation_json).analyze([finding])
      expect(enhanced.first.raw_data["ai_fix_suggestion"]).to eq("Rotate the key.")
    end

    it "parses JSON wrapped in markdown code fences (common with small local models)" do
      fenced = "Here is my analysis:\n```json\n#{annotation_json}\n```\nHope that helps!"
      enhanced = analyzer_with_response(fenced).analyze([finding])
      expect(enhanced.first.raw_data["ai_fix_suggestion"]).to eq("Rotate the key.")
      expect(enhanced.first.raw_data["ai_risk_explanation"]).to eq("Full account access.")
    end

    it "returns original findings untouched when the response has no JSON" do
      enhanced = analyzer_with_response("I cannot analyze this.").analyze([finding])
      expect(enhanced).to eq([finding])
    end
  end
end
