# frozen_string_literal: true

require_relative "base"
require "json"
require_relative "../finding/finding"

module Zwischen
  module Scanner
    class Gitleaks < Base
      def initialize
        super(name: "gitleaks", command: "gitleaks")
      end

      def build_command(project_root)
        [
          executable_path, "detect",
          "--source", project_root,
          "--report-format", "json",
          "--report-path", "-",
          "--no-git"
        ]
      end

      def scan_files(files, project_root)
        return [] if files.empty?

        # Gitleaks doesn't have native multi-file support, so we scan each file individually
        # This is acceptable for pre-push since we typically have only a few changed files
        findings = []

        files.each do |file|
          file_path = File.join(project_root, file)
          next unless File.exist?(file_path)

          command = [
            executable_path, "detect",
            "--source", file_path,
            "--report-format", "json",
            "--report-path", "-",
            "--no-git"
          ]

          stdout, stderr, status = Open3.capture3(*command, chdir: project_root)

          # Gitleaks: exit 0 = clean, exit 1 = findings, exit 2+ = error
          if status.exitstatus <= 1
            findings.concat(parse_output(stdout)) unless stdout.strip.empty?
          elsif status.exitstatus > 1
            warn "Warning: #{@name} scan failed on #{file} (exit #{status.exitstatus}): #{stderr}" if ENV["DEBUG"]
          end
        end

        findings
      rescue StandardError => e
        warn "Error running #{@name}: #{e.message}"
        []
      end

      def parse_output(output)
        return [] if output.strip.empty?

        findings = []
        json_data = JSON.parse(output)

        # Gitleaks returns an array of findings
        Array(json_data).each do |finding|
          findings << Zwischen::Finding::Finding.new(
            type: "secret",
            scanner: "gitleaks",
            severity: map_severity(finding["RuleID"]),
            file: finding["File"],
            line: finding["StartLine"],
            message: finding["RuleID"] || "Secret detected",
            rule_id: finding["RuleID"],
            code_snippet: finding["Secret"],
            raw_data: finding
          )
        end

        findings
      rescue JSON::ParserError => e
        warn "Failed to parse Gitleaks output: #{e.message}"
        []
      end

      private

      def build_command_for_files(files, project_root)
        files.map do |file|
          [
            executable_path, "detect",
            "--source", File.join(project_root, file),
            "--report-format", "json",
            "--report-path", "-",
            "--no-git"
          ]
        end
      end

      def map_severity(rule_id)
        # Gitleaks doesn't provide severity, so we map based on rule type
        case rule_id.to_s.downcase
        when /aws.*key|api.*key|private.*key|secret.*key/
          "critical"
        when /password|token|credential/
          "high"
        when /key|secret/
          "medium"
        else
          "medium"
        end
      end
    end
  end
end
