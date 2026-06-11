# frozen_string_literal: true

require "spec_helper"
require "stringio"
require "tmpdir"
require "fileutils"
require "json"

RSpec.describe Zwischen::CLI do
  let(:project_root) { Dir.mktmpdir }
  let(:project) { { root: project_root, primary_type: "ruby", types: ["ruby"] } }

  let(:config) do
    instance_double(
      Zwischen::Config,
      ai_provider: "claude",
      ai_enabled?: false,
      ai_pre_push_enabled?: false,
      blocking_severity: "high"
    )
  end

  let(:orchestrator) { instance_double(Zwischen::Scanner::Orchestrator) }

  after do
    FileUtils.rm_rf(project_root)
  end

  def build_finding(severity: "critical", file: "app.rb", line: 10, message: "Hardcoded API key", raw_data: {})
    Zwischen::Finding::Finding.new(
      type: "secret",
      scanner: "gitleaks",
      severity: severity,
      file: file,
      line: line,
      message: message,
      rule_id: "generic-api-key",
      raw_data: raw_data
    )
  end

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end

  # Runs the CLI, asserting it exits via SystemExit. Returns [output, exit_status].
  def run_cli(args)
    status = nil
    output = capture_stdout do
      expect { described_class.start(args) }.to raise_error(SystemExit) do |error|
        status = error.status
      end
    end
    [output, status]
  end

  describe "scan" do
    before do
      allow(Zwischen::Config).to receive(:load).and_return(config)
      allow(Zwischen::ProjectDetector).to receive(:detect).and_return(project)
      allow(Zwischen::Scanner::Orchestrator).to receive(:new).with(config: config).and_return(orchestrator)
      allow(Zwischen::AI::Analyzer).to receive(:new)
    end

    context "with no findings" do
      it "exits 0" do
        allow(orchestrator).to receive(:scan).and_return([])

        output, status = run_cli(%w[scan])

        expect(status).to eq(0)
        expect(output).to include("Scanning")
        expect(Zwischen::AI::Analyzer).not_to have_received(:new)
      end
    end

    context "with blocking findings" do
      it "exits 1 when the terminal reporter signals blocking findings" do
        allow(orchestrator).to receive(:scan).and_return([build_finding])
        allow(Zwischen::Reporter::Terminal).to receive(:report).and_return(1)

        _output, status = run_cli(%w[scan])

        expect(status).to eq(1)
        expect(Zwischen::Reporter::Terminal).to have_received(:report)
      end
    end

    context "with --format json" do
      it "prints valid JSON with summary and findings keys and exits 1 for blocking findings" do
        allow(orchestrator).to receive(:scan).and_return([build_finding(severity: "critical")])

        output, status = run_cli(%w[scan --format json])

        json_text = output[output.index("{")..]
        parsed = JSON.parse(json_text)
        expect(parsed).to have_key("summary")
        expect(parsed).to have_key("findings")
        expect(parsed["summary"]["total"]).to eq(1)
        expect(parsed["findings"].first["severity"]).to eq("critical")
        expect(parsed["findings"].first["file"]).to eq("app.rb")
        expect(status).to eq(1)
      end

      it "exits 0 when no findings block" do
        allow(orchestrator).to receive(:scan).and_return([build_finding(severity: "low")])

        output, status = run_cli(%w[scan --format json])

        parsed = JSON.parse(output[output.index("{")..])
        expect(parsed["findings"].first["severity"]).to eq("low")
        expect(status).to eq(0)
      end
    end

    context "in pre-push mode" do
      it "exits 0 silently when there are no changed files" do
        allow(Zwischen::GitDiff).to receive(:changed_files).and_return([])

        output, status = run_cli(%w[scan --pre-push])

        expect(status).to eq(0)
        expect(output).to eq("")
      end

      it "filters findings to changed files via GitDiff.filter_findings" do
        File.write(File.join(project_root, "app.rb"), "puts 'hi'")
        allow(Zwischen::GitDiff).to receive(:changed_files).and_return(["app.rb"])

        finding = build_finding(file: "app.rb")
        unrelated = build_finding(file: "other.rb", line: 5)
        allow(orchestrator).to receive(:scan).and_return([finding, unrelated])
        allow(Zwischen::GitDiff).to receive(:filter_findings)
          .with(findings: [finding, unrelated], changed_files: ["app.rb"])
          .and_return([finding])
        allow(Zwischen::Reporter::Terminal).to receive(:report_compact).and_return(1)

        _output, status = run_cli(%w[scan --pre-push])

        expect(status).to eq(1)
        expect(Zwischen::GitDiff).to have_received(:filter_findings)
        expect(Zwischen::Reporter::Terminal).to have_received(:report_compact) do |aggregated, **_kwargs|
          expect(aggregated[:findings]).to eq([finding])
        end
      end

      it "exits 0 silently when filtering removes all findings" do
        File.write(File.join(project_root, "app.rb"), "puts 'hi'")
        allow(Zwischen::GitDiff).to receive(:changed_files).and_return(["app.rb"])
        allow(orchestrator).to receive(:scan).and_return([build_finding(file: "other.rb")])
        allow(Zwischen::GitDiff).to receive(:filter_findings).and_return([])

        output, status = run_cli(%w[scan --pre-push])

        expect(status).to eq(0)
        expect(output).to eq("")
      end
    end
  end

  describe "#should_block?" do
    subject(:cli) { described_class.new }

    let(:critical_finding) { build_finding(severity: "critical") }
    let(:high_finding) { build_finding(severity: "high") }
    let(:medium_finding) { build_finding(severity: "medium") }

    context "when blocking severity is critical" do
      it "blocks only critical findings" do
        expect(cli.send(:should_block?, critical_finding, "critical", false)).to be true
        expect(cli.send(:should_block?, high_finding, "critical", false)).to be false
      end
    end

    context "when blocking severity is high" do
      it "blocks critical and high findings but not medium" do
        expect(cli.send(:should_block?, critical_finding, "high", false)).to be true
        expect(cli.send(:should_block?, high_finding, "high", false)).to be true
        expect(cli.send(:should_block?, medium_finding, "high", false)).to be false
      end
    end

    context "when blocking severity is none" do
      it "blocks nothing" do
        expect(cli.send(:should_block?, critical_finding, "none", false)).to be false
        expect(cli.send(:should_block?, high_finding, "none", false)).to be false
      end
    end

    context "when blocking severity is unrecognized" do
      it "defaults to blocking critical and high" do
        expect(cli.send(:should_block?, critical_finding, "bogus", false)).to be true
        expect(cli.send(:should_block?, high_finding, "bogus", false)).to be true
        expect(cli.send(:should_block?, medium_finding, "bogus", false)).to be false
      end
    end

    context "when AI marks a finding as a false positive" do
      let(:false_positive) do
        build_finding(severity: "critical", raw_data: { "ai_false_positive" => true })
      end

      it "does not block when AI is enabled" do
        expect(cli.send(:should_block?, false_positive, "high", true)).to be false
      end

      it "still blocks when AI is disabled" do
        expect(cli.send(:should_block?, false_positive, "high", false)).to be true
      end
    end
  end

  describe "doctor" do
    it "runs without crashing when tools are missing" do
      installer = instance_double(Zwischen::Installer)
      allow(Zwischen::Installer).to receive(:new).and_return(installer)
      allow(installer).to receive(:check_tool).and_return(false)
      allow(installer).to receive(:preferred_command).and_return("brew install <tool>")
      allow(File).to receive(:executable?).and_call_original
      allow(File).to receive(:executable?).with(/\.zwischen/).and_return(false)

      output = capture_stdout do
        expect { described_class.start(%w[doctor]) }.not_to raise_error
      end

      expect(output).to include("Zwischen Doctor")
      expect(output).to include("gitleaks")
      expect(output).to include("semgrep")
      expect(output).to include("NOT FOUND")
      expect(output).to include("Some tools are missing")
    end
  end
end
