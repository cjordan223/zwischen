# frozen_string_literal: true

require "thor"
require "fileutils"
require_relative "credentials"
require_relative "hooks"
require_relative "config"

module Zwischen
  class Setup
    def self.run
      new.run
    end

    def self.uninstall
      new.uninstall
    end

    def initialize
      @shell = Thor::Shell::Color.new
    end

    def run
      @shell.say("\n🛡️  Installing Zwischen security layer...\n", :bold)

      check_tools
      configure_credentials
      install_hook
      create_config

      @shell.say("  ✓ Done!", :green)
      @shell.say("\nZwischen will now scan automatically before pushes.")
      @shell.say("Run 'zwischen scan' to test it now.\n")
    end

    def uninstall
      @shell.say("\n🗑️  Zwischen Uninstall\n", :bold)

      project_root = Dir.pwd
      hook_path = Hooks.hook_path(project_root)

      # Remove hook
      if Hooks.installed?(project_root)
        if @shell.yes?("Remove git hook?", default: true)
          if Hooks.uninstall(project_root)
            @shell.say("  ✓ Removed .git/hooks/pre-push", :green)
          else
            @shell.say("  ✗ Failed to remove hook", :red)
          end
        end
      else
        @shell.say("  ↳ No Zwischen hook found", :yellow)
      end

      # Remove config
      config_path = File.join(project_root, Config::CONFIG_FILE)
      if File.exist?(config_path)
        if @shell.yes?("Remove project config (.zwischen.yml)?", default: false)
          File.delete(config_path)
          @shell.say("  ✓ Removed .zwischen.yml", :green)
        else
          @shell.say("  ↳ Kept .zwischen.yml", :yellow)
        end
      end

      # Remove credentials
      if File.exist?(Credentials.credentials_path)
        if @shell.yes?("Remove global credentials (~/.zwischen/credentials)?", default: false)
          File.delete(Credentials.credentials_path)
          @shell.say("  ✓ Removed credentials", :green)
        else
          @shell.say("  ↳ Kept credentials", :yellow)
        end
      end

      @shell.say("\n✅ Zwischen uninstalled from this project.\n", :green)
    end

    private

    def check_tools
      installer = Installer.new

      # Auto-install gitleaks if missing
      unless installer.gitleaks_available?
        @shell.say("  ↳ Installing gitleaks...", :yellow)
        if installer.auto_install_gitleaks
          @shell.say("  ✓ Installed gitleaks to ~/.zwischen/bin/", :green)
        else
          @shell.say("  ⚠️  Could not auto-install gitleaks", :yellow)
          @shell.say("    → #{installer.preferred_command('gitleaks')}", :yellow)
        end
      else
        @shell.say("  ✓ gitleaks available", :green)
      end

      # Check semgrep (optional, not auto-installed)
      if installer.check_tool("semgrep")
        @shell.say("  ✓ semgrep available", :green)
      else
        @shell.say("  ↳ semgrep not found (optional)", :yellow)
        @shell.say("    → #{installer.preferred_command('semgrep')}", :yellow)
      end
    end

    def configure_credentials
      api_key = ENV["ANTHROPIC_API_KEY"]
      return unless api_key && !api_key.strip.empty?

      Credentials.save(api_key: api_key)
      @shell.say("  ✓ Credentials stored in ~/.zwischen/credentials - never committed", :green)
    end

    def install_hook
      project_root = Dir.pwd
      git_dir = File.join(project_root, ".git")

      unless File.directory?(git_dir)
        @shell.say("  ⚠️  No .git directory found. Skipping hook installation.", :yellow)
        return false
      end

      hook_path = Hooks.hook_path(project_root)

      if File.exist?(hook_path)
        if Hooks.zwischen_hook?(hook_path)
          @shell.say("  ✓ Pre-push hook already installed", :green)
          return true
        end

        backup_path = "#{hook_path}.zwischen.backup"
        if File.exist?(backup_path)
          timestamp = Time.now.strftime("%Y%m%d%H%M%S")
          backup_path = "#{backup_path}.#{timestamp}"
        end
        FileUtils.cp(hook_path, backup_path)
        @shell.say("  ✓ Backed up existing hook to #{backup_path}", :green)
      end

      if Hooks.install(project_root)
        @shell.say("  ✓ Installing pre-push hook", :green)
        true
      else
        @shell.say("  ✗ Failed to install hook", :red)
        false
      end
    end

    def create_config
      project_root = Dir.pwd
      config_path = File.join(project_root, Config::CONFIG_FILE)

      if File.exist?(config_path)
        @shell.say("  ✓ Config already exists (.zwischen.yml)", :green)
        return false
      end

      if Config.init(project_root, quiet: true)
        @shell.say("  ✓ Creating config (.zwischen.yml)", :green)
        true
      else
        @shell.say("  ✗ Failed to create config", :red)
        false
      end
    end
  end
end
