# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Zwischen::Config do
  let(:temp_dir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe ".load" do
    it "loads default config when no file exists" do
      config = Zwischen::Config.load(temp_dir)
      expect(config.ai_provider).to eq("claude")
      expect(config.scanner_enabled?("gitleaks")).to be true
    end

    it "merges user config with defaults" do
      config_file = File.join(temp_dir, ".zwischen.yml")
      File.write(config_file, <<~YAML)
        scanners:
          gitleaks:
            enabled: false
      YAML

      config = Zwischen::Config.load(temp_dir)
      expect(config.scanner_enabled?("gitleaks")).to be false
      expect(config.scanner_enabled?("semgrep")).to be true
    end
  end

  describe "#ai_provider_config" do
    it "returns config for specific provider" do
      config = Zwischen::Config.new
      ollama_config = config.ai_provider_config("ollama")
      expect(ollama_config["model"]).to eq("llama3")
      expect(ollama_config["url"]).to include("localhost")
    end

    it "returns empty hash for unknown provider" do
      config = Zwischen::Config.new
      expect(config.ai_provider_config("unknown")).to eq({})
    end
  end

  describe ".init" do
    it "creates config file" do
      result = Zwischen::Config.init(temp_dir)
      expect(result).to be true
      expect(File.exist?(File.join(temp_dir, ".zwischen.yml"))).to be true
    end

    it "does not overwrite existing config" do
      config_file = File.join(temp_dir, ".zwischen.yml")
      File.write(config_file, "existing: true")

      result = Zwischen::Config.init(temp_dir)
      expect(result).to be false
    end
  end
end
