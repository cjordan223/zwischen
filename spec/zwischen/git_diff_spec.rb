# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Zwischen::GitDiff do
  def set_last_status(success)
    # `$?` cannot be assigned directly; run a real no-op command so the
    # code under test sees the desired exit status after stubbed backticks.
    system(success ? "true" : "false")
  end

  describe ".changed_files" do
    it "parses file names from the remote diff" do
      set_last_status(true)
      allow(described_class).to receive(:`)
        .with("git diff --name-only origin/main...HEAD 2>/dev/null")
        .and_return("lib/a.rb\nlib/b.rb\n")

      expect(described_class.changed_files(remote: "main")).to eq(["lib/a.rb", "lib/b.rb"])
    end

    it "falls back to the local diff when the remote diff is empty" do
      set_last_status(true)
      allow(described_class).to receive(:`)
        .with("git diff --name-only origin/main...HEAD 2>/dev/null")
        .and_return("")
      allow(described_class).to receive(:`)
        .with("git diff --name-only HEAD@{1}...HEAD 2>/dev/null")
        .and_return("lib/c.rb\n")

      expect(described_class.changed_files(remote: "main")).to eq(["lib/c.rb"])
    end

    it "returns an empty array when git commands fail" do
      set_last_status(false)
      allow(described_class).to receive(:`).and_return("")

      expect(described_class.changed_files(remote: "main")).to eq([])
    end
  end

  describe ".default_branch" do
    it "uses the remote HEAD branch when available" do
      set_last_status(true)
      allow(described_class).to receive(:`)
        .with("git remote show origin 2>/dev/null | grep 'HEAD branch'")
        .and_return("  HEAD branch: develop\n")

      expect(described_class.default_branch).to eq("develop")
    end

    it "falls back to a local main branch" do
      set_last_status(false)
      allow(described_class).to receive(:`).and_return("")
      allow(described_class).to receive(:system)
        .with(%r{refs/heads/main}).and_return(true)

      expect(described_class.default_branch).to eq("main")
    end

    it "falls back to master, then HEAD" do
      set_last_status(false)
      allow(described_class).to receive(:`).and_return("")
      allow(described_class).to receive(:system)
        .with(%r{refs/heads/main}).and_return(false)
      allow(described_class).to receive(:system)
        .with(%r{refs/heads/master}).and_return(false)

      expect(described_class.default_branch).to eq("HEAD")
    end
  end

  describe ".filter_findings" do
    let(:project_root) { Dir.mktmpdir }

    before do
      allow(Dir).to receive(:pwd).and_return(project_root)
    end

    after do
      FileUtils.rm_rf(project_root)
    end

    def finding(file)
      Zwischen::Finding::Finding.new(
        type: "secret",
        scanner: "gitleaks",
        severity: "high",
        file: file,
        message: "hardcoded secret"
      )
    end

    it "returns all findings when there are no changed files" do
      findings = [finding("lib/a.rb"), finding("lib/b.rb")]
      expect(described_class.filter_findings(findings: findings, changed_files: [])).to eq(findings)
    end

    it "keeps only findings whose files were changed" do
      matched = finding("lib/a.rb")
      unmatched = finding("lib/other.rb")

      result = described_class.filter_findings(
        findings: [matched, unmatched],
        changed_files: ["lib/a.rb"]
      )

      expect(result).to eq([matched])
    end

    it "matches findings with absolute paths against relative changed files" do
      absolute = finding(File.join(project_root, "lib", "a.rb"))

      result = described_class.filter_findings(
        findings: [absolute],
        changed_files: ["lib/a.rb"]
      )

      expect(result).to eq([absolute])
    end

    it "matches relative findings against absolute changed file paths" do
      relative = finding("lib/a.rb")

      result = described_class.filter_findings(
        findings: [relative],
        changed_files: [File.join(project_root, "lib", "a.rb")]
      )

      expect(result).to eq([relative])
    end

    it "normalizes leading ./ and backslashes" do
      dotted = finding("./lib/a.rb")
      windows = finding("lib\\b.rb")

      result = described_class.filter_findings(
        findings: [dotted, windows],
        changed_files: ["lib/a.rb", "lib\\b.rb"]
      )

      expect(result).to eq([dotted, windows])
    end
  end
end
