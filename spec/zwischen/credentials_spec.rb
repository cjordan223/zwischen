# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "yaml"

RSpec.describe Zwischen::Credentials do
  let(:temp_dir) { Dir.mktmpdir }
  let(:credentials_path) { File.join(temp_dir, ".zwischen", "credentials") }

  before do
    allow(described_class).to receive(:credentials_path).and_return(credentials_path)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return(nil)
    allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return(nil)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe ".save" do
    it "writes the api key for the default (claude) provider" do
      described_class.save(api_key: "sk-ant-secret")

      data = YAML.safe_load(File.read(credentials_path))
      expect(data["anthropic_api_key"]).to eq("sk-ant-secret")
    end

    it "sets restrictive permissions on the credentials file" do
      described_class.save(api_key: "sk-ant-secret")

      mode = File.stat(credentials_path).mode & 0o777
      expect(mode).to eq(0o600)
    end

    it "creates the parent directory when missing" do
      expect(File.directory?(File.dirname(credentials_path))).to be false

      described_class.save(api_key: "sk-ant-secret")

      expect(File.directory?(File.dirname(credentials_path))).to be true
    end

    it "preserves keys from other providers" do
      described_class.save(provider: "openai", api_key: "sk-openai")
      described_class.save(provider: "claude", api_key: "sk-ant")

      data = YAML.safe_load(File.read(credentials_path))
      expect(data["openai_api_key"]).to eq("sk-openai")
      expect(data["anthropic_api_key"]).to eq("sk-ant")
    end
  end

  describe ".load" do
    it "returns an empty hash when the file is missing" do
      expect(described_class.load).to eq({})
    end
  end

  describe ".get_api_key" do
    it "prefers the environment variable over the credentials file" do
      described_class.save(api_key: "file-key")
      allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return("env-key")

      expect(described_class.get_api_key).to eq("env-key")
    end

    it "falls back to the credentials file when the env var is unset" do
      described_class.save(api_key: "file-key")

      expect(described_class.get_api_key).to eq("file-key")
    end

    it "returns nil when no env var is set and the file is missing" do
      expect(described_class.get_api_key).to be_nil
    end

    it "returns nil for an unknown provider" do
      expect(described_class.get_api_key("unknown")).to be_nil
    end
  end
end
