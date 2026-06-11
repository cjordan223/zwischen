# frozen_string_literal: true

require "spec_helper"
require "zwischen/scanner/semgrep"

RSpec.describe Zwischen::Scanner::Semgrep do
  let(:scanner) { described_class.new }
  let(:project_root) { "/tmp/project" }
  let(:success_status) { instance_double(Process::Status, exitstatus: 0) }
  let(:findings_status) { instance_double(Process::Status, exitstatus: 1) }
  let(:error_status) { instance_double(Process::Status, exitstatus: 2) }

  def semgrep_json(severity: "ERROR", check_id: "ruby.lang.security.eval", path: "app/code.rb",
                   line: 42, message: "Dangerous eval", lines: "eval(params[:x])")
    {
      "results" => [
        {
          "check_id" => check_id,
          "path" => path,
          "start" => { "line" => line, "col" => 1 },
          "message" => message,
          "extra" => { "severity" => severity, "lines" => lines }
        }
      ]
    }.to_json
  end

  describe "#parse_output" do
    it "parses semgrep JSON results into Finding objects" do
      findings = scanner.parse_output(semgrep_json)

      expect(findings.length).to eq(1)
      finding = findings.first
      expect(finding).to be_a(Zwischen::Finding::Finding)
      expect(finding.type).to eq("sast")
      expect(finding.scanner).to eq("semgrep")
      expect(finding.file).to eq("app/code.rb")
      expect(finding.line).to eq(42)
      expect(finding.message).to eq("Dangerous eval")
      expect(finding.rule_id).to eq("ruby.lang.security.eval")
      expect(finding.code_snippet).to eq("eval(params[:x])")
    end

    it "falls back to check_id when message is missing" do
      output = { "results" => [{ "check_id" => "rule.id", "path" => "a.rb" }] }.to_json

      finding = scanner.parse_output(output).first
      expect(finding.message).to eq("rule.id")
    end

    it "handles results without extra or start blocks" do
      output = { "results" => [{ "check_id" => "rule.id", "path" => "a.rb" }] }.to_json

      finding = scanner.parse_output(output).first
      expect(finding.line).to be_nil
      expect(finding.code_snippet).to be_nil
      expect(finding.severity).to eq("medium")
    end

    it "returns an empty array for empty output" do
      expect(scanner.parse_output("")).to eq([])
    end

    it "returns an empty array when the results key is absent" do
      expect(scanner.parse_output({ "errors" => [] }.to_json)).to eq([])
    end

    it "returns an empty array for an empty results array" do
      expect(scanner.parse_output({ "results" => [] }.to_json)).to eq([])
    end

    it "warns and returns an empty array for malformed JSON" do
      expect(scanner).to receive(:warn).with(/Failed to parse Semgrep output/)
      expect(scanner.parse_output("not-json{{")).to eq([])
    end

    describe "severity mapping" do
      def severity_for(raw)
        scanner.parse_output(semgrep_json(severity: raw)).first.severity
      end

      it "maps ERROR/critical to critical" do
        expect(severity_for("ERROR")).to eq("critical")
        expect(severity_for("critical")).to eq("critical")
      end

      it "maps WARNING/high to high" do
        expect(severity_for("WARNING")).to eq("high")
        expect(severity_for("high")).to eq("high")
      end

      it "maps INFO/medium to medium" do
        expect(severity_for("INFO")).to eq("medium")
        expect(severity_for("medium")).to eq("medium")
      end

      it "maps low to low" do
        expect(severity_for("LOW")).to eq("low")
      end

      it "defaults unknown severities to medium" do
        expect(severity_for("EXPERIMENTAL")).to eq("medium")
        expect(severity_for(nil)).to eq("medium")
      end
    end
  end

  describe "#scan" do
    context "when the binary is unavailable" do
      before { allow(scanner).to receive(:executable_path).and_return(nil) }

      it "returns an empty array without executing anything" do
        expect(Open3).not_to receive(:capture3)
        expect(scanner.scan(project_root)).to eq([])
      end
    end

    context "when the binary is available" do
      before { allow(scanner).to receive(:executable_path).and_return("/usr/bin/semgrep") }

      it "scans the project root with the default ruleset" do
        expected_command = ["/usr/bin/semgrep", "--json", "--config", "p/security-audit", project_root]
        expect(Open3).to receive(:capture3)
          .with(*expected_command, chdir: project_root)
          .and_return([semgrep_json, "", findings_status])

        findings = scanner.scan(project_root)
        expect(findings.length).to eq(1)
        expect(findings.first.rule_id).to eq("ruby.lang.security.eval")
      end

      it "uses a custom ruleset when configured" do
        custom = described_class.new(config: "p/ruby")
        allow(custom).to receive(:executable_path).and_return("/usr/bin/semgrep")

        expect(Open3).to receive(:capture3)
          .with("/usr/bin/semgrep", "--json", "--config", "p/ruby", project_root, chdir: project_root)
          .and_return(["", "", success_status])

        expect(custom.scan(project_root)).to eq([])
      end

      it "passes a files: list through as positional arguments in one invocation" do
        files = ["app/a.rb", "lib/b.rb"]
        expected_command = ["/usr/bin/semgrep", "--json", "--config", "p/security-audit", *files]
        expect(Open3).to receive(:capture3)
          .with(*expected_command, chdir: project_root)
          .and_return([semgrep_json(path: "app/a.rb"), "", findings_status])

        findings = scanner.scan(project_root, files: files)
        expect(findings.map(&:file)).to eq(["app/a.rb"])
      end

      it "returns an empty array and warns when semgrep exits with an error" do
        allow(Open3).to receive(:capture3).and_return(["", "config error", error_status])

        expect(scanner).to receive(:warn).with(/semgrep scan failed \(exit 2\)/)
        expect(scanner.scan(project_root)).to eq([])
      end

      it "rescues execution errors and returns an empty array" do
        allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT, "semgrep")

        expect(scanner).to receive(:warn).with(/Error running semgrep/)
        expect(scanner.scan(project_root)).to eq([])
      end
    end
  end
end
