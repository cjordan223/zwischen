# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Zwischen::Reporter::Terminal do
  def build_finding(severity:, file: "app/models/user.rb", line: 42,
                    message: "Hardcoded secret detected", rule_id: "generic-api-key", raw_data: {})
    Zwischen::Finding::Finding.new(
      type: "secret",
      scanner: "gitleaks",
      severity: severity,
      file: file,
      line: line,
      message: message,
      rule_id: rule_id,
      raw_data: raw_data
    )
  end

  def aggregate(*findings)
    Zwischen::Finding::Aggregator.aggregate(findings)
  end

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end

  def run_compact(aggregated, config:, ai_enabled: false)
    described_class.report_compact(aggregated, config: config, ai_enabled: ai_enabled)
  end

  describe ".report" do
    it "returns 1 and prints details when blocking findings are present" do
      aggregated = aggregate(build_finding(severity: "critical"))

      exit_code = nil
      output = capture_stdout do
        exit_code = described_class.report(aggregated)
      end

      expect(exit_code).to eq(1)
      expect(output).to include("Zwischen Security Scan Results")
      expect(output).to include("Total Findings: 1")
      expect(output).to include("CRITICAL")
      expect(output).to include("app/models/user.rb:42")
      expect(output).to include("Hardcoded secret detected")
      expect(output).to include("generic-api-key")
    end

    it "returns 0 when only non-blocking findings are present" do
      aggregated = aggregate(
        build_finding(severity: "low", message: "Weak hash algorithm", line: 7)
      )

      exit_code = nil
      output = capture_stdout do
        exit_code = described_class.report(aggregated)
      end

      expect(exit_code).to eq(0)
      expect(output).to include("LOW")
      expect(output).to include("app/models/user.rb:7")
      expect(output).to include("Weak hash algorithm")
    end

    it "prints findings grouped by file with severity counts in the summary" do
      aggregated = aggregate(
        build_finding(severity: "critical", file: "a.rb", line: 1),
        build_finding(severity: "medium", file: "b.rb", line: 2, message: "Insecure random")
      )

      output = capture_stdout { described_class.report(aggregated) }

      expect(output).to include("Total Findings: 2")
      expect(output).to include("Critical: 1")
      expect(output).to include("Medium: 1")
      expect(output).to include("a.rb")
      expect(output).to include("b.rb")
    end

    it "marks AI false positives instead of reporting them as blocking" do
      aggregated = aggregate(
        build_finding(severity: "critical", raw_data: { "ai_false_positive" => true })
      )

      exit_code = nil
      output = capture_stdout do
        exit_code = described_class.report(aggregated, ai_enabled: true)
      end

      expect(exit_code).to eq(0)
      expect(output).to include("FALSE POSITIVE")
    end
  end

  describe ".report_compact" do
    let(:config) { instance_double(Zwischen::Config, blocking_severity: "high") }

    it "returns 1 and prints only blocking findings" do
      aggregated = aggregate(
        build_finding(severity: "high"),
        build_finding(severity: "low", line: 7, message: "Minor style issue")
      )

      exit_code = nil
      output = capture_stdout do
        exit_code = run_compact(aggregated, config: config)
      end

      expect(exit_code).to eq(1)
      expect(output).to include("1 issue found")
      expect(output).to include("HIGH")
      expect(output).to include("app/models/user.rb:42")
      expect(output).to include("Hardcoded secret detected")
      expect(output).to include("Push blocked")
      expect(output).not_to include("Minor style issue")
    end

    it "returns 0 silently when no findings block" do
      aggregated = aggregate(build_finding(severity: "medium"))

      exit_code = nil
      output = capture_stdout do
        exit_code = run_compact(aggregated, config: config)
      end

      expect(exit_code).to eq(0)
      expect(output).to eq("")
    end

    context "when blocking severity is critical" do
      let(:config) { instance_double(Zwischen::Config, blocking_severity: "critical") }

      it "does not block on high findings" do
        aggregated = aggregate(build_finding(severity: "high"))

        exit_code = nil
        output = capture_stdout do
          exit_code = run_compact(aggregated, config: config)
        end

        expect(exit_code).to eq(0)
        expect(output).to eq("")
      end
    end

    it "returns 0 when AI marks the only blocking finding as a false positive" do
      aggregated = aggregate(
        build_finding(severity: "critical", raw_data: { "ai_false_positive" => true })
      )

      exit_code = nil
      output = capture_stdout do
        exit_code = run_compact(aggregated, config: config, ai_enabled: true)
      end

      expect(exit_code).to eq(0)
      expect(output).to eq("")
    end
  end
end
