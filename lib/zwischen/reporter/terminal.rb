# frozen_string_literal: true

require "colorize"
require_relative "../finding/finding"

module Zwischen
  module Reporter
    class Terminal
      SEVERITY_COLORS = {
        "critical" => :red,
        "high" => :red,
        "medium" => :yellow,
        "low" => :blue,
        "info" => :cyan
      }.freeze

      SEVERITY_BADGES = {
        "critical" => "🔴 CRITICAL",
        "high" => "🔴 HIGH",
        "medium" => "🟡 MEDIUM",
        "low" => "🔵 LOW",
        "info" => "ℹ️  INFO"
      }.freeze

      def self.report(aggregated_results, ai_enabled: false)
        new(aggregated_results, ai_enabled: ai_enabled).report
      end

      def self.report_compact(aggregated_results, config:, ai_enabled: false)
        new(aggregated_results, ai_enabled: ai_enabled, config: config).report_compact
      end

      def initialize(aggregated_results, ai_enabled: false, config: nil)
        @results = aggregated_results
        @ai_enabled = ai_enabled
        @config = config
      end

      # Show paths relative to the working directory when they live under it.
      # Scanners may emit symlink-resolved absolute paths (/tmp vs /private/tmp
      # on macOS), so compare against the resolved cwd too.
      def display_path(path)
        expanded = File.expand_path(path.to_s)
        [Dir.pwd, (File.realpath(Dir.pwd) rescue Dir.pwd)].uniq.each do |root|
          return expanded.delete_prefix("#{root}/") if expanded.start_with?("#{root}/")
        end
        path.to_s
      end

      def report
        print_summary
        print_findings
        exit_code
      end

      def report_compact
        blocking_severity = @config&.blocking_severity || "high"
        findings = @results[:findings]

        # Filter to only blocking findings
        blocking_findings = findings.select { |f| should_block?(f, blocking_severity) }

        # If no blocking findings, exit silently (exit code 0)
        return 0 if blocking_findings.empty?

        # Show compact output for blocking findings
        puts "🛡️  Zwischen: #{blocking_findings.length} issue#{blocking_findings.length == 1 ? '' : 's'} found\n\n"

        blocking_findings.each do |finding|
          severity_color = SEVERITY_COLORS[finding.severity] || :white
          severity_label = finding.severity.upcase

          puts "  #{severity_label}".colorize(severity_color) + "  #{display_path(finding.file)}:#{finding.line || '?'}"
          puts "            #{finding.message}"

          # Show fix suggestion if available
          if @ai_enabled && finding.raw_data["ai_fix_suggestion"]
            puts "            → #{finding.raw_data['ai_fix_suggestion']}"
          end

          puts ""
        end

        puts "Push blocked. Fix issues above or:"
        puts "  • Run 'zwischen scan' for full report"
        puts "  • Run 'git push --no-verify' to skip (not recommended)"

        1 # Exit code 1 = push blocked
      end

      private

      def print_summary
        summary = @results[:summary]
        puts "\n" + "=" * 60
        puts "Zwischen Security Scan Results".colorize(:bold)
        puts "=" * 60
        puts "\nTotal Findings: #{summary[:total]}".colorize(:bold)

        if summary[:by_severity].any?
          puts "\nBy Severity:"
          summary[:by_severity].each do |severity, count|
            color = SEVERITY_COLORS[severity] || :white
            puts "  #{severity.capitalize}: #{count}".colorize(color)
          end
        end

        puts "\n" + "-" * 60
      end

      def print_findings
        findings = @results[:findings]
        return if findings.empty?

        puts "\nFindings:\n\n"

        @results[:grouped].each do |file, file_findings|
          puts "📄 #{display_path(file)}".colorize(:bold)
          puts "-" * 60

          file_findings.each do |finding|
            print_finding(finding)
          end

          puts "\n"
        end
      end

      def print_finding(finding)
        # Skip false positives if AI analysis marked them
        if @ai_enabled && finding.raw_data["ai_false_positive"]
          puts "  ⚠️  [FALSE POSITIVE] #{finding.message}".colorize(:light_black)
          return
        end

        severity_color = SEVERITY_COLORS[finding.severity] || :white
        badge = SEVERITY_BADGES[finding.severity] || finding.severity.upcase

        puts "  #{badge}".colorize(severity_color) + " #{display_path(finding.file)}:#{finding.line || '?'}"
        puts "    #{finding.message}"

        if finding.rule_id
          puts "    Rule: #{finding.rule_id}".colorize(:light_black)
        end

        if finding.code_snippet
          snippet = finding.code_snippet.split("\n").first(3).join("\n")
          puts "    Code:".colorize(:light_black)
          puts "    #{snippet}".colorize(:light_black)
        end

        # AI recommendations
        if @ai_enabled && finding.raw_data["ai_fix_suggestion"]
          puts "    💡 Fix: #{finding.raw_data['ai_fix_suggestion']}".colorize(:green)
        end

        if @ai_enabled && finding.raw_data["ai_risk_explanation"]
          puts "    ⚠️  Risk: #{finding.raw_data['ai_risk_explanation']}".colorize(:yellow)
        end

        puts ""
      end

      def should_block?(finding, blocking_severity)
        return false if @ai_enabled && finding.raw_data["ai_false_positive"]

        case blocking_severity
        when "critical"
          finding.critical?
        when "high"
          finding.critical? || finding.high?
        when "none"
          false
        else
          # Default: block on high or critical
          finding.critical? || finding.high?
        end
      end

      def exit_code
        findings = @results[:findings]
        blocking_severity = @config&.blocking_severity || "high"
        
        blocking = findings.any? { |f| should_block?(f, blocking_severity) }

        blocking ? 1 : 0
      end
    end
  end
end
