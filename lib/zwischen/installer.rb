# frozen_string_literal: true

require "open3"
require "rbconfig"
require "net/http"
require "json"
require "fileutils"

module Zwischen
  class Installer
    ZWISCHEN_BIN_DIR = File.expand_path("~/.zwischen/bin")
    GITLEAKS_REPO = "gitleaks/gitleaks"

    PLATFORMS = {
      darwin: "macos",
      linux: "linux",
      mingw: "windows",
      mswin: "windows"
    }.freeze

    # Map Ruby platform to gitleaks release naming
    GITLEAKS_PLATFORMS = {
      "linux" => "linux",
      "macos" => "darwin"
    }.freeze

    GITLEAKS_ARCHS = {
      "x86_64" => "x64",
      "amd64" => "x64",
      "aarch64" => "arm64",
      "arm64" => "arm64"
    }.freeze

    INSTALL_COMMANDS = {
      gitleaks: {
        macos: {
          brew: "brew install gitleaks",
          manual: "Visit https://github.com/gitleaks/gitleaks/releases"
        },
        linux: {
          brew: "brew install gitleaks",
          manual: "Visit https://github.com/gitleaks/gitleaks/releases"
        },
        windows: {
          manual: "Visit https://github.com/gitleaks/gitleaks/releases"
        }
      },
      semgrep: {
        macos: {
          brew: "brew install semgrep",
          pip: "pip install semgrep",
          manual: "Visit https://semgrep.dev/docs/getting-started/"
        },
        linux: {
          pip: "pip install semgrep",
          pipx: "pipx install semgrep",
          manual: "Visit https://semgrep.dev/docs/getting-started/"
        },
        windows: {
          pip: "pip install semgrep",
          manual: "Visit https://semgrep.dev/docs/getting-started/"
        }
      }
    }.freeze

    def self.platform
      new.platform
    end

    def self.install_commands(tool, platform = nil)
      new.install_commands(tool, platform)
    end

    def platform
      host_os = RbConfig::CONFIG["host_os"].downcase
      case host_os
      when /darwin/
        "macos"
      when /linux/
        "linux"
      when /mingw|mswin/
        "windows"
      else
        "unknown"
      end
    end

    def install_commands(tool, platform = nil)
      platform ||= self.platform
      INSTALL_COMMANDS.dig(tool.to_sym, platform.to_sym) || {}
    end

    def preferred_command(tool, platform = nil)
      platform ||= self.platform
      commands = install_commands(tool, platform)

      # Prefer brew on macOS, pip on Linux
      if platform == "macos" && commands[:brew]
        commands[:brew]
      elsif commands[:pip]
        commands[:pip]
      elsif commands[:brew]
        commands[:brew]
      else
        commands[:manual]
      end
    end

    def check_tool(tool_name)
      system("which", tool_name, out: File::NULL, err: File::NULL)
    end

    def get_version(tool_name)
      return nil unless check_tool(tool_name)

      stdout, _stderr, status = Open3.capture3(tool_name, "--version")
      return nil unless status.success?

      stdout.strip.split("\n").first
    rescue StandardError
      nil
    end

    # Auto-install gitleaks binary if not present
    def auto_install_gitleaks
      return true if gitleaks_available?

      FileUtils.mkdir_p(ZWISCHEN_BIN_DIR)

      release = fetch_latest_gitleaks_release
      return false unless release

      asset = find_gitleaks_asset(release)
      return false unless asset

      download_and_extract_gitleaks(asset)
    end

    # Check if gitleaks is available (local or system)
    def gitleaks_available?
      !gitleaks_path.nil?
    end

    # Get path to gitleaks executable (local install or system)
    def gitleaks_path
      local = File.join(ZWISCHEN_BIN_DIR, "gitleaks")
      return local if File.executable?(local)

      check_tool("gitleaks") ? "gitleaks" : nil
    end

    private

    def fetch_latest_gitleaks_release
      uri = URI("https://api.github.com/repos/#{GITLEAKS_REPO}/releases/latest")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/vnd.github.v3+json"
      request["User-Agent"] = "Zwischen"

      response = http.request(request)
      return nil unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue StandardError => e
      warn "Failed to fetch gitleaks release: #{e.message}" if ENV["DEBUG"]
      nil
    end

    def find_gitleaks_asset(release)
      gitleaks_platform = GITLEAKS_PLATFORMS[platform]
      return nil unless gitleaks_platform

      arch = GITLEAKS_ARCHS[RbConfig::CONFIG["host_cpu"]] || "x64"

      # Asset name pattern: gitleaks_8.18.0_linux_x64.tar.gz
      pattern = /gitleaks_.*_#{gitleaks_platform}_#{arch}\.tar\.gz$/

      release["assets"]&.find { |a| a["name"] =~ pattern }
    end

    def download_and_extract_gitleaks(asset)
      require "open-uri"
      require "rubygems/package"
      require "zlib"
      require "stringio"

      download_url = asset["browser_download_url"]
      target_path = File.join(ZWISCHEN_BIN_DIR, "gitleaks")

      # Download tarball
      tarball = URI.open(download_url, "User-Agent" => "Zwischen").read

      # Extract gitleaks binary from tar.gz
      Zlib::GzipReader.wrap(StringIO.new(tarball)) do |gz|
        Gem::Package::TarReader.new(gz) do |tar|
          tar.each do |entry|
            if entry.full_name == "gitleaks"
              File.open(target_path, "wb") { |f| f.write(entry.read) }
              File.chmod(0o755, target_path)
              return true
            end
          end
        end
      end

      false
    rescue StandardError => e
      warn "Failed to install gitleaks: #{e.message}" if ENV["DEBUG"]
      false
    end
  end
end
