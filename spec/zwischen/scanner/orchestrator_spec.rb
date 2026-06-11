# frozen_string_literal: true

require "spec_helper"
require "zwischen/scanner/orchestrator"

RSpec.describe Zwischen::Scanner::Orchestrator do
  let(:project_root) { "/tmp/project" }

  let(:gitleaks_finding) { build_finding(scanner: "gitleaks", file: "app/models/user.rb") }
  let(:semgrep_finding) { build_finding(scanner: "semgrep", file: "lib/api.rb") }

  let(:gitleaks) do
    instance_double(Zwischen::Scanner::Gitleaks,
                    name: "gitleaks", available?: true, scan: [gitleaks_finding])
  end
  let(:semgrep) do
    instance_double(Zwischen::Scanner::Semgrep,
                    name: "semgrep", available?: true, scan: [semgrep_finding])
  end

  before do
    allow(Zwischen::Scanner::Gitleaks).to receive(:new).and_return(gitleaks)
    allow(Zwischen::Scanner::Semgrep).to receive(:new).and_return(semgrep)
  end

  def build_config(overrides = {})
    Zwischen::Config.new(overrides)
  end

  def build_orchestrator(overrides = {})
    described_class.new(config: build_config(overrides))
  end

  def build_finding(scanner: "gitleaks", file: "app/models/user.rb", severity: "high")
    Zwischen::Finding::Finding.new(
      type: scanner == "gitleaks" ? "secret" : "sast",
      scanner: scanner,
      severity: severity,
      file: file,
      line: 1,
      message: "test finding"
    )
  end

  describe "scanner selection via config" do
    it "builds both scanners when both are enabled (defaults)" do
      orchestrator = build_orchestrator
      expect(orchestrator.available_scanners).to contain_exactly(gitleaks, semgrep)
    end

    it "omits gitleaks when disabled in config" do
      orchestrator = build_orchestrator(
        "scanners" => { "gitleaks" => { "enabled" => false }, "semgrep" => { "enabled" => true } }
      )
      expect(orchestrator.available_scanners).to contain_exactly(semgrep)
    end

    it "omits semgrep when disabled via the boolean form" do
      orchestrator = build_orchestrator(
        "scanners" => { "gitleaks" => true, "semgrep" => false }
      )
      expect(orchestrator.available_scanners).to contain_exactly(gitleaks)
    end

    it "passes the configured semgrep ruleset to the Semgrep scanner" do
      build_orchestrator(
        "scanners" => { "gitleaks" => true, "semgrep" => { "enabled" => true, "config" => "p/ruby" } }
      )
      expect(Zwischen::Scanner::Semgrep).to have_received(:new).with(config: "p/ruby")
    end
  end

  describe "#scan" do
    let(:orchestrator) { build_orchestrator("ignore" => []) }

    describe "only: option mapping" do
      it "runs only gitleaks for only: 'secrets'" do
        expect(gitleaks).to receive(:scan).and_return([gitleaks_finding])
        expect(semgrep).not_to receive(:scan)

        expect(orchestrator.scan(project_root, only: "secrets")).to eq([gitleaks_finding])
      end

      it "runs only semgrep for only: 'sast'" do
        expect(semgrep).to receive(:scan).and_return([semgrep_finding])
        expect(gitleaks).not_to receive(:scan)

        expect(orchestrator.scan(project_root, only: "sast")).to eq([semgrep_finding])
      end

      it "runs both for only: 'secrets,sast'" do
        results = orchestrator.scan(project_root, only: "secrets,sast")
        expect(results).to contain_exactly(gitleaks_finding, semgrep_finding)
      end

      it "is case-insensitive and strips whitespace" do
        expect(gitleaks).to receive(:scan).and_return([gitleaks_finding])
        expect(semgrep).not_to receive(:scan)

        expect(orchestrator.scan(project_root, only: " SECRETS ")).to eq([gitleaks_finding])
      end

      it "selects no scanners for an unknown only: value" do
        expect(gitleaks).not_to receive(:scan)
        expect(semgrep).not_to receive(:scan)
        expect(orchestrator).to receive(:warn).with(/No scanners available/)

        expect(orchestrator.scan(project_root, only: "dast")).to eq([])
      end
    end

    describe "when no scanners are available" do
      let(:gitleaks) do
        instance_double(Zwischen::Scanner::Gitleaks, name: "gitleaks", available?: false)
      end
      let(:semgrep) do
        instance_double(Zwischen::Scanner::Semgrep, name: "semgrep", available?: false)
      end

      it "returns an empty array and warns" do
        expect(orchestrator).to receive(:warn).with(/No scanners available/)
        expect(orchestrator.scan(project_root)).to eq([])
      end

      it "suppresses the warning in pre-push mode" do
        expect(orchestrator).not_to receive(:warn)
        expect(orchestrator.scan(project_root, pre_push: true)).to eq([])
      end
    end

    it "flattens findings from all scanners into a single array" do
      extra = build_finding(scanner: "semgrep", file: "lib/other.rb")
      allow(semgrep).to receive(:scan).and_return([semgrep_finding, extra])

      results = orchestrator.scan(project_root)
      expect(results).to contain_exactly(gitleaks_finding, semgrep_finding, extra)
    end

    it "passes the files: list through to each scanner" do
      files = ["app/a.rb"]
      expect(gitleaks).to receive(:scan).with(project_root, files: files).and_return([])
      expect(semgrep).to receive(:scan).with(project_root, files: files).and_return([])

      orchestrator.scan(project_root, files: files)
    end
  end

  describe "#reject_ignored" do
    let(:orchestrator) { build_orchestrator } # default config ignore globs

    def reject_ignored(findings)
      orchestrator.send(:reject_ignored, findings, project_root)
    end

    it "drops findings under node_modules/, vendor/, and dist/" do
      ignored = [
        build_finding(file: "node_modules/lodash/index.js"),
        build_finding(file: "vendor/bundle/gem.rb"),
        build_finding(file: "dist/bundle.js"),
        build_finding(file: "packages/app/node_modules/left-pad/index.js")
      ]

      expect(reject_ignored(ignored)).to eq([])
    end

    it "relativizes absolute paths against project_root before matching" do
      finding = build_finding(file: File.join(project_root, "node_modules", "pkg", "index.js"))

      expect(reject_ignored([finding])).to eq([])
    end

    it "keeps non-matching paths" do
      survivors = [
        build_finding(file: "app/models/user.rb"),
        build_finding(file: File.join(project_root, "lib", "api.rb"))
      ]

      expect(reject_ignored(survivors)).to eq(survivors)
    end

    it "keeps paths that merely contain an ignored name as a substring" do
      finding = build_finding(file: "app/node_modules_helper.rb")

      expect(reject_ignored([finding])).to eq([finding])
    end

    it "returns findings unchanged when no ignore globs are configured" do
      orchestrator = build_orchestrator("ignore" => [])
      finding = build_finding(file: "node_modules/pkg/index.js")

      expect(orchestrator.send(:reject_ignored, [finding], project_root)).to eq([finding])
    end
  end
end
