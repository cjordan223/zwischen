# frozen_string_literal: true

require "pathname"
require_relative "gitleaks"
require_relative "semgrep"

module Zwischen
  module Scanner
    class Orchestrator
      def initialize(config:)
        @config = config
        @scanners = build_scanners
      end

      def scan(project_root = Dir.pwd, only: nil, pre_push: false, files: nil)
        enabled_scanners = select_scanners(only)
        available_scanners = enabled_scanners.select(&:available?)

        if available_scanners.empty?
          warn "No scanners available. Run 'zwischen doctor' to check installation." unless pre_push
          return []
        end

        # Run scanners in parallel using threads
        threads = available_scanners.map do |scanner|
          Thread.new do
            [scanner.name, scanner.scan(project_root, files: files)]
          end
        end

        results = {}
        threads.each do |thread|
          scanner_name, findings = thread.value
          results[scanner_name] = findings
        end

        # Flatten all findings
        # Note: In pre-push mode, we pass file lists to scanners when available
        reject_ignored(results.values.flatten, project_root)
      end

      def available_scanners
        @scanners.select(&:available?)
      end

      def missing_scanners
        @scanners.reject(&:available?)
      end

      private

      # Drop findings whose file matches an ignore glob from .zwischen.yml.
      # Scanner output may use absolute or project-relative paths, so match
      # against the path relative to project_root.
      def reject_ignored(findings, project_root)
        globs = @config.ignored_paths
        return findings if globs.empty?

        findings.reject do |finding|
          path = finding.file
          if File.absolute_path?(path)
            path = Pathname.new(path).relative_path_from(project_root).to_s rescue path
          end

          flags = File::FNM_PATHNAME | File::FNM_EXTGLOB
          globs.any? do |glob|
            # A trailing "**" under FNM_PATHNAME only matches one path segment;
            # also try "**/*" so "**/dist/**" covers files nested below dist/.
            File.fnmatch?(glob, path, flags) ||
              File.fnmatch?(glob.sub(%r{/\*\*\z}, "/**/*"), path, flags)
          end
        end
      end

      def build_scanners
        scanners = []

        scanners << Gitleaks.new if @config.scanner_enabled?("gitleaks")
        scanners << Semgrep.new(config: @config.semgrep_config) if @config.scanner_enabled?("semgrep")

        scanners
      end

      def select_scanners(only)
        return @scanners if only.nil? || only.empty?

        only_list = only.split(",").map(&:strip)
        scanner_map = {
          "secrets" => "gitleaks",
          "sast" => "semgrep"
        }

        selected = only_list.map { |name| scanner_map[name.downcase] }.compact

        @scanners.select { |s| selected.include?(s.name) }
      end
    end
  end
end
