# frozen_string_literal: true

require "fileutils"
require "open3"

module Zwischen
  class Hooks
    HOOK_MARKER = "Zwischen pre-push hook"

    # Resolve the hooks directory through git itself so the hook lands where
    # git will actually execute it — this respects core.hooksPath (husky,
    # pre-commit framework, etc.) and linked worktrees, where .git is a file.
    def self.hook_path(project_root = Dir.pwd)
      stdout, _stderr, status = Open3.capture3(
        "git", "rev-parse", "--git-path", "hooks", chdir: project_root
      )
      hooks_dir = status.success? ? stdout.strip : nil
      hooks_dir = File.join(".git", "hooks") if hooks_dir.nil? || hooks_dir.empty?
      hooks_dir = File.expand_path(hooks_dir, project_root)

      File.join(hooks_dir, "pre-push")
    rescue StandardError
      File.join(project_root, ".git", "hooks", "pre-push")
    end

    def self.zwischen_hook?(hook_path)
      return false unless File.exist?(hook_path)

      File.read(hook_path).include?(HOOK_MARKER)
    end

    def self.installed?(project_root = Dir.pwd)
      path = hook_path(project_root)
      zwischen_hook?(path)
    end

    def self.install(project_root = Dir.pwd)
      path = hook_path(project_root)
      hooks_dir = File.dirname(path)

      # Ensure hooks directory exists
      FileUtils.mkdir_p(hooks_dir) unless File.directory?(hooks_dir)

      hook_content = <<~HOOK
        #!/usr/bin/env bash
        # #{HOOK_MARKER} - installed by 'zwischen init'

        if [ "$ZWISCHEN_SKIP" = "1" ]; then
          exit 0
        fi

        zwischen scan --pre-push
        exit $?
      HOOK

      File.write(path, hook_content)
      File.chmod(0o755, path)

      true
    end

    def self.handle_existing_hook(hook_path, shell)
      return :skip unless File.exist?(hook_path)
      return :install if zwischen_hook?(hook_path) # Already a Zwischen hook, can overwrite

      shell.say("\n⚠️  A pre-push hook already exists at #{hook_path}", :yellow)
      choice = shell.ask("What would you like to do?", limited_to: %w[backup append skip], default: "backup")

      case choice
      when "backup"
        backup_path = "#{hook_path}.zwischen.backup"
        FileUtils.cp(hook_path, backup_path)
        shell.say("  ✓ Backed up to #{backup_path}", :green)
        :install
      when "append"
        existing_content = File.read(hook_path)
        new_content = <<~APPEND
          #{existing_content}

          # #{HOOK_MARKER} - appended by 'zwischen init'
          if [ "$ZWISCHEN_SKIP" = "1" ]; then
            exit 0
          fi

          zwischen scan --pre-push || exit $?
        APPEND
        File.write(hook_path, new_content)
        File.chmod(0o755, hook_path)
        shell.say("  ✓ Appended Zwischen check to existing hook", :green)
        :skip # Don't install new hook, already appended
      when "skip"
        shell.say("  ↳ Skipping hook installation", :yellow)
        :skip
      end
    end

    def self.uninstall(project_root = Dir.pwd)
      path = hook_path(project_root)
      return false unless File.exist?(path)
      return false unless zwischen_hook?(path)

      File.delete(path)
      true
    end
  end
end
