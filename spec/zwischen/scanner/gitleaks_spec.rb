# frozen_string_literal: true

require "spec_helper"
require "zwischen/scanner/gitleaks"

RSpec.describe Zwischen::Scanner::Gitleaks do
  let(:scanner) { described_class.new }
  let(:project_root) { "/tmp/project" }
  let(:success_status) { instance_double(Process::Status, exitstatus: 0) }
  let(:findings_status) { instance_double(Process::Status, exitstatus: 1) }
  let(:error_status) { instance_double(Process::Status, exitstatus: 2) }

  def gitleaks_json(rule_id: "aws-access-key", file: "config/secrets.rb", line: 12, secret: "AKIA123")
    [
      {
        "RuleID" => rule_id,
        "File" => file,
        "StartLine" => line,
        "Secret" => secret
      }
    ].to_json
  end

  describe "#parse_output" do
    it "parses gitleaks JSON into Finding objects" do
      findings = scanner.parse_output(gitleaks_json)

      expect(findings.length).to eq(1)
      finding = findings.first
      expect(finding).to be_a(Zwischen::Finding::Finding)
      expect(finding.type).to eq("secret")
      expect(finding.scanner).to eq("gitleaks")
      expect(finding.file).to eq("config/secrets.rb")
      expect(finding.line).to eq(12)
      expect(finding.message).to eq("aws-access-key")
      expect(finding.rule_id).to eq("aws-access-key")
      expect(finding.code_snippet).to eq("AKIA123")
    end

    it "parses multiple findings from a JSON array" do
      output = JSON.parse(gitleaks_json(rule_id: "aws-access-key"))
        .concat(JSON.parse(gitleaks_json(rule_id: "generic-password", file: "db.yml", line: 3)))
        .to_json

      findings = scanner.parse_output(output)

      expect(findings.length).to eq(2)
      expect(findings.map(&:file)).to eq(["config/secrets.rb", "db.yml"])
    end

    it "defaults the message when RuleID is missing" do
      output = [{ "File" => "a.rb", "StartLine" => 1 }].to_json

      finding = scanner.parse_output(output).first
      expect(finding.message).to eq("Secret detected")
      expect(finding.rule_id).to be_nil
    end

    it "returns an empty array for empty output" do
      expect(scanner.parse_output("")).to eq([])
    end

    it "returns an empty array for whitespace-only output" do
      expect(scanner.parse_output("  \n  ")).to eq([])
    end

    it "warns and returns an empty array for malformed JSON" do
      expect(scanner).to receive(:warn).with(/Failed to parse Gitleaks output/)
      expect(scanner.parse_output("{not json")).to eq([])
    end

    describe "severity mapping" do
      def severity_for(rule_id)
        scanner.parse_output(gitleaks_json(rule_id: rule_id)).first.severity
      end

      it "maps key-related rules to critical" do
        expect(severity_for("aws-access-key")).to eq("critical")
        expect(severity_for("stripe-api-key")).to eq("critical")
        expect(severity_for("rsa-private-key")).to eq("critical")
      end

      it "maps password/token/credential rules to high" do
        expect(severity_for("generic-password")).to eq("high")
        expect(severity_for("github-token")).to eq("high")
        expect(severity_for("cloud-credential")).to eq("high")
      end

      it "maps generic key/secret rules to medium" do
        expect(severity_for("ssh-key")).to eq("medium")
        expect(severity_for("generic-secret")).to eq("medium")
      end

      it "defaults unknown rules to medium" do
        expect(severity_for("something-else")).to eq("medium")
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

    context "when scanning the whole project" do
      before { allow(scanner).to receive(:executable_path).and_return("/usr/bin/gitleaks") }

      it "runs gitleaks detect against the project root and parses output" do
        expected_command = [
          "/usr/bin/gitleaks", "detect",
          "--source", project_root,
          "--report-format", "json",
          "--report-path", "-",
          "--no-git"
        ]
        expect(Open3).to receive(:capture3)
          .with(*expected_command, chdir: project_root)
          .and_return([gitleaks_json, "", findings_status])

        findings = scanner.scan(project_root)
        expect(findings.length).to eq(1)
        expect(findings.first.rule_id).to eq("aws-access-key")
      end
    end
  end

  describe "#scan_files (files: passthrough)" do
    before { allow(scanner).to receive(:executable_path).and_return("/usr/bin/gitleaks") }

    it "returns an empty array for an empty files list" do
      # Note: Base#scan treats files: [] as "no file list" and falls back to a
      # full-project scan, so the empty-list short-circuit lives in #scan_files.
      expect(Open3).not_to receive(:capture3)
      expect(scanner.scan_files([], project_root)).to eq([])
    end

    it "invokes gitleaks once per file with the joined path" do
      files = ["app/a.rb", "lib/b.rb"]
      files.each do |file|
        allow(File).to receive(:exist?).with(File.join(project_root, file)).and_return(true)
      end

      files.each do |file|
        expected_command = [
          "/usr/bin/gitleaks", "detect",
          "--source", File.join(project_root, file),
          "--report-format", "json",
          "--report-path", "-",
          "--no-git"
        ]
        expect(Open3).to receive(:capture3)
          .with(*expected_command, chdir: project_root)
          .and_return([gitleaks_json(file: file), "", findings_status])
      end

      findings = scanner.scan(project_root, files: files)
      expect(findings.map(&:file)).to eq(files)
    end

    it "skips files that do not exist" do
      allow(File).to receive(:exist?).with(File.join(project_root, "gone.rb")).and_return(false)

      expect(Open3).not_to receive(:capture3)
      expect(scanner.scan(project_root, files: ["gone.rb"])).to eq([])
    end

    it "ignores files whose scan exits with an error status" do
      allow(File).to receive(:exist?).and_return(true)
      allow(Open3).to receive(:capture3).and_return(["boom", "bad args", error_status])

      expect(scanner.scan(project_root, files: ["a.rb"])).to eq([])
    end

    it "treats clean files (exit 0, empty output) as no findings" do
      allow(File).to receive(:exist?).and_return(true)
      allow(Open3).to receive(:capture3).and_return(["", "", success_status])

      expect(scanner.scan(project_root, files: ["a.rb"])).to eq([])
    end

    it "rescues execution errors and returns an empty array" do
      allow(File).to receive(:exist?).and_return(true)
      allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT, "gitleaks")

      expect(scanner).to receive(:warn).with(/Error running gitleaks/)
      expect(scanner.scan(project_root, files: ["a.rb"])).to eq([])
    end
  end
end
