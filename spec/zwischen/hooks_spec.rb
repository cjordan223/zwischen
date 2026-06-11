# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Zwischen::Hooks do
  let(:project_root) { Dir.mktmpdir }
  let(:hooks_dir) { File.join(project_root, ".git", "hooks") }
  let(:hook_path) { File.join(hooks_dir, "pre-push") }

  after do
    FileUtils.rm_rf(project_root)
  end

  def create_foreign_hook
    FileUtils.mkdir_p(hooks_dir)
    File.write(hook_path, "#!/bin/sh\necho 'custom hook'\n")
    File.chmod(0o755, hook_path)
  end

  describe ".hook_path" do
    it "points at .git/hooks/pre-push under the project root" do
      expect(described_class.hook_path(project_root)).to eq(hook_path)
    end
  end

  describe ".install" do
    it "creates an executable pre-push hook containing the Zwischen marker" do
      result = described_class.install(project_root)

      expect(result).to be true
      expect(File.exist?(hook_path)).to be true
      expect(File.executable?(hook_path)).to be true
      expect(File.read(hook_path)).to include(Zwischen::Hooks::HOOK_MARKER)
    end

    it "creates the hooks directory when .git/hooks does not exist" do
      expect(File.directory?(hooks_dir)).to be false

      described_class.install(project_root)

      expect(File.directory?(hooks_dir)).to be true
      expect(File.exist?(hook_path)).to be true
    end

    it "includes the ZWISCHEN_SKIP escape hatch and scan command" do
      described_class.install(project_root)

      content = File.read(hook_path)
      expect(content).to include('ZWISCHEN_SKIP')
      expect(content).to include("zwischen scan --pre-push")
    end
  end

  describe ".zwischen_hook?" do
    it "returns true for an installed Zwischen hook" do
      described_class.install(project_root)
      expect(described_class.zwischen_hook?(hook_path)).to be true
    end

    it "returns false for a foreign hook" do
      create_foreign_hook
      expect(described_class.zwischen_hook?(hook_path)).to be false
    end

    it "returns false when the hook does not exist" do
      expect(described_class.zwischen_hook?(hook_path)).to be false
    end
  end

  describe ".installed?" do
    it "returns false when .git/hooks does not exist" do
      expect(described_class.installed?(project_root)).to be false
    end

    it "returns true after install" do
      described_class.install(project_root)
      expect(described_class.installed?(project_root)).to be true
    end

    it "returns false when a foreign hook occupies pre-push" do
      create_foreign_hook
      expect(described_class.installed?(project_root)).to be false
    end
  end

  describe ".uninstall" do
    it "removes a Zwischen hook and returns true" do
      described_class.install(project_root)

      expect(described_class.uninstall(project_root)).to be true
      expect(File.exist?(hook_path)).to be false
    end

    it "leaves a foreign hook alone and returns false" do
      create_foreign_hook
      original_content = File.read(hook_path)

      expect(described_class.uninstall(project_root)).to be false
      expect(File.exist?(hook_path)).to be true
      expect(File.read(hook_path)).to eq(original_content)
    end

    it "returns false when no hook exists" do
      expect(described_class.uninstall(project_root)).to be false
    end
  end
end
