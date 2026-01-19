# frozen_string_literal: true

require_relative "base"
require "json"
require_relative "../finding/finding"

module Zwischen
  module Scanner
    class Semgrep < Base
      # Use open ruleset that works without Semgrep login
      DEFAULT_CONFIG = "p/security-audit"

      def initialize(config: DEFAULT_CONFIG)
        super(name: "semgrep", command: "semgrep")
        @config = config
      end

      def build_command(project_root)
        [executable_path, "--json", "--config", @config, project_root]
      end

      def build_command_for_files(files, _project_root)
        [executable_path, "--json", "--config", @config, *files]
      end

      def parse_output(output)
        return [] if output.strip.empty?

        findings = []
        json_data = JSON.parse(output)

        # Semgrep returns results in a "results" array
        Array(json_data["results"]).each do |result|
          severity = map_severity(result["extra"]&.dig("severity"))
          
          findings << Zwischen::Finding::Finding.new(
            type: "sast",
            scanner: "semgrep",
            severity: severity,
            file: result["path"],
            line: result["start"]&.dig("line"),
            message: result["message"] || result["check_id"],
            rule_id: result["check_id"],
            code_snippet: result["extra"]&.dig("lines"),
            raw_data: result
          )
        end

        findings
      rescue JSON::ParserError => e
        warn "Failed to parse Semgrep output: #{e.message}"
        []
      end

      private

      def map_severity(severity)
        case severity.to_s.downcase
        when "error", "critical"
          "critical"
        when "warning", "high"
          "high"
        when "info", "medium"
          "medium"
        when "low"
          "low"
        else
          "medium" # Default for unknown
        end
      end
    end
  end
end
