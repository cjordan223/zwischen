# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Zwischen::Setup do
  let(:project_root) { Dir.mktmpdir }
  let(:shell) { instance_double(Thor::Shell::Color, say: nil) }
  let(:setup) do
    allow(Thor::Shell::Color).to receive(:new).and_return(shell)
    described_class.new
  end

  before do
    allow(Dir).to receive(:pwd).and_return(project_root)
  end

  after do
    FileUtils.rm_rf(project_root)
  end

  def hooks_dir
    File.join(project_root, ".git", "hooks")
  end

  def hook_path
    File.join(hooks_dir, "pre-push")
  end

  describe "#install_hook" do
    it "skips installation when there is no .git directory" do
      result = setup.send(:install_hook)

      expect(result).to be false
      expect(File.exist?(hook_path)).to be false
      expect(shell).to have_received(:say).with(/No \.git directory found/, :yellow)
    end

    it "reports already-installed for an existing Zwischen hook" do
      Zwischen::Hooks.install(project_root)
      original_content = File.read(hook_path)

      result = setup.send(:install_hook)

      expect(result).to be true
      expect(File.read(hook_path)).to eq(original_content)
      expect(Dir.glob("#{hook_path}.zwischen.backup*")).to be_empty
      expect(shell).to have_received(:say).with(/already installed/, :green)
    end

    it "backs up a foreign hook to pre-push.zwischen.backup before replacing it" do
      FileUtils.mkdir_p(hooks_dir)
      foreign_content = "#!/bin/sh\necho 'custom hook'\n"
      File.write(hook_path, foreign_content)

      result = setup.send(:install_hook)

      expect(result).to be true
      backup_path = "#{hook_path}.zwischen.backup"
      expect(File.exist?(backup_path)).to be true
      expect(File.read(backup_path)).to eq(foreign_content)
      expect(File.read(hook_path)).to include(Zwischen::Hooks::HOOK_MARKER)
    end

    it "uses a timestamped backup name when a backup already exists" do
      FileUtils.mkdir_p(hooks_dir)
      File.write("#{hook_path}.zwischen.backup", "old backup")
      foreign_content = "#!/bin/sh\necho 'another custom hook'\n"
      File.write(hook_path, foreign_content)

      result = setup.send(:install_hook)

      expect(result).to be true
      expect(File.read("#{hook_path}.zwischen.backup")).to eq("old backup")

      timestamped = Dir.glob("#{hook_path}.zwischen.backup.*")
      expect(timestamped.size).to eq(1)
      expect(timestamped.first).to match(/pre-push\.zwischen\.backup\.\d{14}\z/)
      expect(File.read(timestamped.first)).to eq(foreign_content)
      expect(File.read(hook_path)).to include(Zwischen::Hooks::HOOK_MARKER)
    end
  end

  describe "#configure_credentials" do
    before do
      allow(ENV).to receive(:[]).and_call_original
    end

    it "saves credentials when ANTHROPIC_API_KEY is set" do
      allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return("sk-ant-test")
      expect(Zwischen::Credentials).to receive(:save).with(api_key: "sk-ant-test")

      setup.send(:configure_credentials)
    end

    it "does nothing when ANTHROPIC_API_KEY is not set" do
      allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return(nil)
      expect(Zwischen::Credentials).not_to receive(:save)

      setup.send(:configure_credentials)
    end

    it "does nothing when ANTHROPIC_API_KEY is blank" do
      allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return("   ")
      expect(Zwischen::Credentials).not_to receive(:save)

      setup.send(:configure_credentials)
    end
  end

  describe "#create_config" do
    it "skips when a config file already exists" do
      File.write(File.join(project_root, Zwischen::Config::CONFIG_FILE), "existing: true")
      expect(Zwischen::Config).not_to receive(:init)

      result = setup.send(:create_config)

      expect(result).to be false
      expect(shell).to have_received(:say).with(/already exists/, :green)
    end

    it "creates the config when none exists" do
      expect(Zwischen::Config).to receive(:init).with(project_root, quiet: true).and_return(true)

      result = setup.send(:create_config)

      expect(result).to be true
      expect(shell).to have_received(:say).with(/Creating config/, :green)
    end
  end
end
