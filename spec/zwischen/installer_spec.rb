# frozen_string_literal: true

require "spec_helper"
require "zwischen/installer"

RSpec.describe Zwischen::Installer do
  let(:installer) { described_class.new }

  describe "#platform" do
    it "detects macos" do
      allow(RbConfig::CONFIG).to receive(:[]).with("host_os").and_return("darwin21.0")
      expect(installer.platform).to eq("macos")
    end

    it "detects linux" do
      allow(RbConfig::CONFIG).to receive(:[]).with("host_os").and_return("linux-gnu")
      expect(installer.platform).to eq("linux")
    end
  end

  describe "#gitleaks_path" do
    it "returns local path if executable exists" do
      local_path = File.join(Zwischen::Installer::ZWISCHEN_BIN_DIR, "gitleaks")
      allow(File).to receive(:executable?).with(local_path).and_return(true)
      expect(installer.gitleaks_path).to eq(local_path)
    end

    it "returns 'gitleaks' if system tool exists and local doesn't" do
      local_path = File.join(Zwischen::Installer::ZWISCHEN_BIN_DIR, "gitleaks")
      allow(File).to receive(:executable?).with(local_path).and_return(false)
      allow(installer).to receive(:check_tool).with("gitleaks").and_return(true)
      expect(installer.gitleaks_path).to eq("gitleaks")
    end

    it "returns nil if neither exists" do
      local_path = File.join(Zwischen::Installer::ZWISCHEN_BIN_DIR, "gitleaks")
      allow(File).to receive(:executable?).with(local_path).and_return(false)
      allow(installer).to receive(:check_tool).with("gitleaks").and_return(false)
      expect(installer.gitleaks_path).to be_nil
    end
  end

  describe "#auto_install_gitleaks" do
    it "returns true if already available" do
      allow(installer).to receive(:gitleaks_available?).and_return(true)
      expect(installer.auto_install_gitleaks).to be true
    end

    it "attempts to download and install if missing" do
      allow(installer).to receive(:gitleaks_available?).and_return(false)
      allow(FileUtils).to receive(:mkdir_p)
      
      mock_release = { "assets" => [{ "name" => "gitleaks_8.0.0_linux_x64.tar.gz", "browser_download_url" => "http://example.com" }] }
      allow(installer).to receive(:fetch_latest_gitleaks_release).and_return(mock_release)
      allow(installer).to receive(:platform).and_return("linux")
      allow(RbConfig::CONFIG).to receive(:[]).with("host_cpu").and_return("x86_64")
      
      allow(installer).to receive(:download_and_extract_gitleaks).and_return(true)
      
      expect(installer.auto_install_gitleaks).to be true
    end
  end
end
