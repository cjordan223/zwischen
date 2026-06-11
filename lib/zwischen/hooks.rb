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

    # Delimiters around the block we append to a pre-existing foreign hook,
    # so uninstall can strip exactly our lines and leave the rest intact.
    APPEND_BEGIN = "# >>> #{HOOK_MARKER} >>>"
    APPEND_END = "# <<< #{HOOK_MARKER} <<<"

    def self.install(project_root = Dir.pwd)
      path = hook_path(project_root)
      hooks_dir = File.dirname(path)

      # Ensure hooks directory exists
      FileUtils.mkdir_p(hooks_dir) unless File.directory?(hooks_dir)

      if File.exist?(path)
        # Already present (standalone or appended) — never overwrite, an
        # appended hook also contains the user's own commands.
        return true if zwischen_hook?(path)

        # A foreign hook (husky shim, hand-written script, ...) keeps
        # working: we append our check instead of replacing the user's.
        return append_to_existing(path)
      end

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

    def self.append_to_existing(path)
      existing = File.read(path)
      return true if existing.include?(HOOK_MARKER) # already appended

      block = <<~BLOCK

        #{APPEND_BEGIN}
        # appended by 'zwischen init' - your original hook above still runs
        if [ "$ZWISCHEN_SKIP" != "1" ]; then
          zwischen scan --pre-push || exit $?
        fi
        #{APPEND_END}
      BLOCK

      File.write(path, existing.chomp + "\n" + block)
      File.chmod(0o755, path)

      true
    end

    def self.uninstall(project_root = Dir.pwd)
      path = hook_path(project_root)
      return false unless File.exist?(path)
      return false unless zwischen_hook?(path)

      content = File.read(path)
      if content.include?(APPEND_BEGIN)
        # We were appended to someone else's hook: strip only our block.
        stripped = content.gsub(/\n?#{Regexp.escape(APPEND_BEGIN)}.*?#{Regexp.escape(APPEND_END)}\n?/m, "\n")
        File.write(path, stripped)
      else
        # The whole file is ours.
        File.delete(path)
      end
      true
    end
  end
end
