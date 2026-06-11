# frozen_string_literal: true

require "spec_helper"
require "zwischen/ai/base_client"

RSpec.describe Zwischen::AI::BaseClient do
  describe Zwischen::AI::Error do
    it "is a StandardError" do
      expect(Zwischen::AI::Error.ancestors).to include(StandardError)
    end
  end

  describe "#initialize" do
    it "stores the api_key" do
      client = described_class.new(api_key: "secret-key")
      expect(client.api_key).to eq("secret-key")
    end

    it "stores the config" do
      client = described_class.new(config: { "model" => "test-model" })
      expect(client.config).to eq({ "model" => "test-model" })
    end

    it "defaults api_key to nil and config to an empty hash" do
      client = described_class.new
      expect(client.api_key).to be_nil
      expect(client.config).to eq({})
    end

    it "calls validate_config! during initialization" do
      expect_any_instance_of(described_class).to receive(:validate_config!)
      described_class.new
    end
  end

  describe "#analyze" do
    it "raises NotImplementedError" do
      client = described_class.new
      expect { client.analyze("prompt") }.to raise_error(NotImplementedError)
    end

    it "includes the class name in the error message" do
      subclass = Class.new(described_class)
      stub_const("Zwischen::AI::FakeClient", subclass)

      client = Zwischen::AI::FakeClient.new
      expect { client.analyze("prompt") }
        .to raise_error(NotImplementedError, /Zwischen::AI::FakeClient must implement #analyze/)
    end
  end
end
