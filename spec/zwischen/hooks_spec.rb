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

    def init_repo(dir)
      system("git", "init", "-q", dir, exception: true)
      system("git", "-C", dir, "config", "user.email", "t@t.co", exception: true)
      system("git", "-C", dir, "config", "user.name", "t", exception: true)
    end

    it "respects core.hooksPath so the hook lands where git executes it" do
      init_repo(project_root)
      system("git", "-C", project_root, "config", "core.hooksPath", ".husky", exception: true)

      resolved = described_class.hook_path(project_root)
      expect(File.expand_path(resolved)).to end_with("/.husky/pre-push")
      expect(resolved).not_to include(".git/hooks")
    end

    it "resolves the shared hooks dir from inside a linked worktree" do
      init_repo(project_root)
      File.write(File.join(project_root, "f"), "x")
      system("git", "-C", project_root, "add", ".", exception: true)
      system("git", "-C", project_root, "commit", "-qm", "i", exception: true)

      worktree = File.join(Dir.mktmpdir, "wt")
      system("git", "-C", project_root, "worktree", "add", "-q", worktree, "-b", "wt", exception: true)

      resolved = described_class.hook_path(worktree)
      expect(resolved).to eq(File.join(File.realpath(project_root), ".git", "hooks", "pre-push"))
      expect(described_class.install(worktree)).to be true
      expect(File.executable?(resolved)).to be true
    ensure
      system("git", "-C", project_root, "worktree", "remove", "--force", worktree, exception: false) if worktree
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
