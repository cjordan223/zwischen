# frozen_string_literal: true

require "thor"
require "json"
require "colorize"
require "pathname"

module Zwischen
  class CLI < Thor
    # Disable Thor's pager to prevent help from hanging
    def self.exit_on_failure?
      true
    end

    # Disable pager for help output
    def help(command = nil, subcommand = false)
      ENV["THOR_PAGER"] = "cat" if ENV["THOR_PAGER"].nil?
      super
    end

    desc "init", "Initialize Zwischen configuration"
    def init
      Setup.run
    end

    desc "doctor", "Check if required tools are installed"
    def doctor
      installer = Installer.new
      puts "\n" + "=" * 60
      puts "Zwischen Doctor - Tool Status".colorize(:bold)
      puts "=" * 60 + "\n"

      tools = {
        "gitleaks" => "Secrets detection",
        "semgrep" => "Static analysis"
      }

      all_installed = true

      tools.each do |tool_name, description|
        # Check both ~/.zwischen/bin/ and system PATH
        local_path = File.join(File.expand_path("~/.zwischen/bin"), tool_name)
        installed = File.executable?(local_path) || installer.check_tool(tool_name)

        if installed
          # Get version from the correct path
          executable = File.executable?(local_path) ? local_path : tool_name
          version = begin
            `#{executable} --version 2>/dev/null`.strip.split("\n").first
          rescue
            nil
          end

          puts "✓ #{tool_name}".colorize(:green) + " - #{description}"
          puts "  Version: #{version}" if version && !version.empty?
          puts "  Location: #{executable}" if File.executable?(local_path)
        else
          all_installed = false
          puts "✗ #{tool_name}".colorize(:red) + " - #{description} - NOT FOUND"
          puts "  → #{installer.preferred_command(tool_name)}"
        end
        puts ""
      end

      if all_installed
        puts "✅ All tools are installed and ready!".colorize(:green)
      else
        puts "⚠️  Some tools are missing. Install them using the commands above.".colorize(:yellow)
      end

      puts ""
    end

    desc "scan", "Run security scan"
    method_option :only, type: :string, desc: "Only run specific scanners (secrets,sast)"
    method_option :ai, type: :string, desc: "Enable AI analysis (claude)"
    method_option :"api-key", type: :string, desc: "API key for AI provider"
    method_option :format, type: :string, default: "terminal", desc: "Output format (terminal, json, sarif)"
    method_option :"pre-push", type: :boolean, desc: "Pre-push mode (quiet, compact output)"
    method_option :changed, type: :boolean, desc: "Only scan files changed since the default branch"
    def scan
      config = Config.load
      project = ProjectDetector.detect
      pre_push = options[:"pre-push"]
      quiet = pre_push || %w[json sarif].include?(options[:format])

      # Suppress scanning message in pre-push/machine-readable modes
      unless quiet
        puts "🔍 Scanning #{project[:primary_type] || 'project'}...\n"
      end

      changed_files = nil
      if pre_push || options[:changed]
        changed_files = GitDiff.changed_files(include_working_tree: !pre_push)
        changed_files = changed_files.select do |path|
          candidate = path
          candidate = File.join(project[:root], candidate) unless Pathname.new(candidate).absolute?
          File.file?(candidate)
        end

        if changed_files.empty?
          puts Reporter::Sarif.report({ findings: [] }, project_root: project[:root]) if options[:format] == "sarif"
          exit 0
        end
      end

      # Run scanners
      orchestrator = Scanner::Orchestrator.new(config: config)
      findings = orchestrator.scan(project[:root], only: options[:only], pre_push: pre_push, files: changed_files)

      # Filter findings to changed files in pre-push/--changed mode
      # Note: This is a safety net. Scanners receive the file list and should only scan those,
      # but some scanners (like gitleaks) may return paths in different formats. This ensures
      # we only report findings for files the developer actually changed.
      if changed_files
        findings = GitDiff.filter_findings(findings: findings, changed_files: changed_files)
      end

      if findings.empty?
        # In pre-push mode, exit silently (no output)
        if options[:format] == "sarif"
          puts Reporter::Sarif.report({ findings: [] }, project_root: project[:root])
        elsif !quiet
          puts "✅ No issues found.".colorize(:green)
        end
        exit 0
      end

      # Aggregate findings
      aggregated = Finding::Aggregator.aggregate(findings)

      # Determine AI provider
      provider = if options[:ai] && !options[:ai].empty? && options[:ai] != "true"
                   options[:ai]
                 else
                   config.ai_provider
                 end

      # AI analysis if enabled
      ai_enabled = if pre_push
        # In pre-push mode, use config to determine AI
        config.ai_pre_push_enabled?
      else
        # Manual scan: use flag or config
        !options[:ai].nil? || config.ai_enabled?
      end

      if ai_enabled
        begin
          unless quiet
            puts "🤖 Analyzing findings with AI (#{provider})...\n"
          end
          
          api_key = options[:"api-key"] || config.ai_api_key(provider)
          provider_config = config.ai_provider_config(provider)

          analyzer = AI::Analyzer.new(
            provider: provider,
            api_key: api_key,
            config: provider_config,
            project_context: project
          )
          enhanced_findings = analyzer.analyze(aggregated[:findings])
          aggregated = Finding::Aggregator.aggregate(enhanced_findings)
        rescue AI::Error => e
          warn "⚠️  AI analysis unavailable: #{e.message}" unless pre_push
          # In pre-push mode, continue silently without AI
        end
      end

      # Report results
      if options[:format] == "json"
        require "json"
        puts JSON.pretty_generate({
          summary: aggregated[:summary],
          findings: aggregated[:findings].map { |f| f.to_h.merge(file: relative_path(f.file, project[:root])) }
        })
        blocking_severity = config.blocking_severity
        exit_code = aggregated[:findings].any? { |f| should_block?(f, blocking_severity, ai_enabled) } ? 1 : 0
        exit exit_code
      elsif options[:format] == "sarif"
        puts Reporter::Sarif.report(aggregated, project_root: project[:root])
        blocking_severity = config.blocking_severity
        exit_code = aggregated[:findings].any? { |f| should_block?(f, blocking_severity, ai_enabled) } ? 1 : 0
        exit exit_code
      else
        if pre_push
          exit_code = Reporter::Terminal.report_compact(aggregated, config: config, ai_enabled: ai_enabled)
        else
          exit_code = Reporter::Terminal.report(aggregated, config: config, ai_enabled: ai_enabled)
        end
        exit exit_code
      end
    rescue StandardError => e
      puts "❌ Error: #{e.message}".colorize(:red)
      puts e.backtrace if ENV["DEBUG"]
      exit 1
    end

    desc "uninstall", "Remove Zwischen git hook and optionally config"
    def uninstall
      Setup.uninstall
    end

    desc "version", "Print the Zwischen version"
    map %w[--version -v] => :version
    def version
      puts "zwischen #{Zwischen::VERSION}"
    end

    default_task :scan

    private

    # Scanners may emit absolute (and symlink-resolved) paths; report
    # machine-readable output relative to the project root like the
    # terminal and SARIF reporters do.
    def relative_path(path, project_root)
      expanded = File.expand_path(path.to_s)
      roots = [project_root, (File.realpath(project_root) rescue project_root)].uniq
      roots.each do |root|
        return expanded.delete_prefix("#{root}/") if expanded.start_with?("#{root}/")
      end
      path.to_s
    end

    def should_block?(finding, blocking_severity, ai_enabled)
      return false if ai_enabled && finding.raw_data["ai_false_positive"]

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
  end
end
