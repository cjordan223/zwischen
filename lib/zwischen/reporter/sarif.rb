# frozen_string_literal: true

require "json"
require_relative "../version"

module Zwischen
  module Reporter
    # Renders findings as SARIF 2.1.0 for GitHub code scanning and other
    # SARIF consumers (zwischen scan --format sarif).
    class Sarif
      SCHEMA = "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json"

      SEVERITY_LEVELS = {
        "critical" => "error",
        "high" => "error",
        "medium" => "warning",
        "low" => "note",
        "info" => "note"
      }.freeze

      # GitHub uses security-severity to bucket alerts (9.0+ critical, 7.0+ high...)
      SECURITY_SEVERITY = {
        "critical" => "9.5",
        "high" => "8.0",
        "medium" => "5.0",
        "low" => "3.0",
        "info" => "1.0"
      }.freeze

      def self.report(aggregated_results, project_root: Dir.pwd)
        new(aggregated_results, project_root: project_root).render
      end

      def initialize(aggregated_results, project_root: Dir.pwd)
        @findings = aggregated_results[:findings]
        @project_root = project_root
      end

      def render
        JSON.pretty_generate(
          "$schema" => SCHEMA,
          "version" => "2.1.0",
          "runs" => [run]
        )
      end

      private

      def run
        {
          "tool" => {
            "driver" => {
              "name" => "Zwischen",
              "version" => Zwischen::VERSION,
              "informationUri" => "https://github.com/cjordan223/zwischen",
              "rules" => rules
            }
          },
          "results" => results
        }
      end

      def rules
        @findings.map { |f| rule_id(f) }.uniq.map do |id|
          finding = @findings.find { |f| rule_id(f) == id }
          {
            "id" => id,
            "shortDescription" => { "text" => finding.message },
            "properties" => {
              "security-severity" => SECURITY_SEVERITY.fetch(finding.severity, "5.0"),
              "tags" => ["security", finding.type]
            }
          }
        end
      end

      def results
        @findings.map do |finding|
          {
            "ruleId" => rule_id(finding),
            "level" => SEVERITY_LEVELS.fetch(finding.severity, "warning"),
            "message" => { "text" => message_for(finding) },
            "locations" => [{
              "physicalLocation" => {
                "artifactLocation" => { "uri" => relative_uri(finding.file) },
                "region" => { "startLine" => [finding.line || 1, 1].max }
              }
            }]
          }
        end
      end

      def rule_id(finding)
        finding.rule_id || "#{finding.scanner}/#{finding.type}"
      end

      def message_for(finding)
        parts = [finding.message]
        if finding.raw_data["ai_fix_suggestion"]
          parts << "Fix: #{finding.raw_data['ai_fix_suggestion']}"
        end
        parts.join(" ")
      end

      def relative_uri(path)
        expanded = File.expand_path(path.to_s)
        roots = [@project_root, (File.realpath(@project_root) rescue @project_root)].uniq
        roots.each do |root|
          return expanded.delete_prefix("#{root}/") if expanded.start_with?("#{root}/")
        end
        path.to_s
      end
    end
  end
end
