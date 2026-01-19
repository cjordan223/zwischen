# frozen_string_literal: true

require "open3"
require_relative "../installer"

module Zwischen
  module Scanner
    class Base
      attr_reader :name, :command

      ZWISCHEN_BIN_DIR = File.expand_path("~/.zwischen/bin")

      def initialize(name:, command:)
        @name = name
        @command = command
        @executable_path = nil
      end

      def available?
        !executable_path.nil?
      end

      # Find executable in ~/.zwischen/bin or system PATH
      def executable_path
        @executable_path ||= find_executable(@command)
      end

      def find_executable(name)
        # Check ~/.zwischen/bin first
        local = File.join(ZWISCHEN_BIN_DIR, name)
        return local if File.executable?(local)

        # Fall back to system PATH
        system("which", name, out: File::NULL, err: File::NULL) ? name : nil
      end

      def scan(project_root = Dir.pwd, files: nil)
        return [] unless available?

        if files && !files.empty?
          return scan_files(files, project_root) if respond_to?(:scan_files, true)
          command = build_command_for_files(files, project_root)
        else
          command = build_command(project_root)
        end

        stdout, stderr, status = Open3.capture3(*command, chdir: project_root)

        # Most security scanners use exit code 0 = clean, 1 = findings found, 2+ = error
        # We treat both 0 and 1 as success since findings are valid results
        if status.exitstatus <= 1
          parse_output(stdout)
        else
          warn "Warning: #{@name} scan failed (exit #{status.exitstatus}): #{stderr}" unless stderr.empty?
          []
        end
      rescue StandardError => e
        warn "Error running #{@name}: #{e.message}"
        []
      end

      def parse_output(_output)
        raise NotImplementedError, "Subclasses must implement parse_output"
      end

      protected

      def build_command(_project_root)
        raise NotImplementedError, "Subclasses must implement build_command"
      end

      def build_command_for_files(_files, _project_root)
        raise NotImplementedError, "Subclasses must implement build_command_for_files"
      end

      def read_file_snippet(file_path, line_number, context_lines = 3)
        return nil unless File.exist?(file_path)

        lines = File.readlines(file_path)
        start_line = [0, line_number - context_lines - 1].max
        end_line = [lines.length - 1, line_number + context_lines - 1].min

        lines[start_line..end_line].join
      rescue StandardError
        nil
      end
    end
  end
end
