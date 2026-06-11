# frozen_string_literal: true

require "pathname"

module Zwischen
  class GitDiff
    def self.default_branch
      # Try remote HEAD first (most reliable)
      result = `git remote show origin 2>/dev/null | grep 'HEAD branch'`.strip
      return result.split.last if $?.success? && !result.empty?

      # Fallback: check if main or master exists locally
      return "main" if system("git show-ref --verify --quiet refs/heads/main >/dev/null 2>&1")
      return "master" if system("git show-ref --verify --quiet refs/heads/master >/dev/null 2>&1")

      # Last resort
      "HEAD"
    end

    # include_working_tree: also count staged and untracked files. Used by
    # manual `scan --changed`; pre-push keeps committed-range semantics
    # because only committed changes get pushed.
    def self.changed_files(remote: nil, local: "HEAD", include_working_tree: false)
      branch = remote || default_branch
      remote_ref = "origin/#{branch}"

      files = []

      # Try remote diff first
      committed = `git diff --name-only #{remote_ref}...#{local} 2>/dev/null`.strip.split("\n")
      if $?.success? && !committed.empty?
        files = committed
      else
        # Fallback: local diff
        local_diff = `git diff --name-only HEAD@{1}...#{local} 2>/dev/null`.strip.split("\n")
        files = local_diff if $?.success?
      end

      if include_working_tree
        working = `git status --porcelain 2>/dev/null`.strip.split("\n").map { |l| l[3..]&.strip }.compact
        files |= working if $?.success?
      end

      files.reject { |f| f.nil? || f.empty? }
    rescue StandardError => e
      warn "Failed to get changed files: #{e.message}" if ENV["DEBUG"]
      []
    end

    def self.filter_findings(findings:, changed_files:)
      return findings if changed_files.empty?

      # Normalize paths for comparison
      # - Remove leading ./
      # - Convert backslashes to forward slashes
      # - Make relative to project root if absolute
      project_root = Dir.pwd
      normalized_changed = changed_files.map do |f|
        path = f.sub(/^\.\//, "").gsub("\\", "/")
        # If absolute, make relative to project root
        if Pathname.new(path).absolute?
          begin
            Pathname.new(path).relative_path_from(Pathname.new(project_root)).to_s
          rescue ArgumentError
            path
          end
        else
          path
        end
      end

      findings.select do |f|
        file_path = f.file.sub(/^\.\//, "").gsub("\\", "/")
        # If absolute, make relative to project root
        if Pathname.new(file_path).absolute?
          begin
            file_path = Pathname.new(file_path).relative_path_from(Pathname.new(project_root)).to_s
          rescue ArgumentError
            # Keep original if can't make relative
          end
        end
        normalized_changed.include?(file_path)
      end
    end
  end
end
