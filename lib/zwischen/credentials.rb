# frozen_string_literal: true

require "yaml"
require "fileutils"

module Zwischen
  class Credentials
    PROVIDER_ENV_VARS = {
      "claude" => "ANTHROPIC_API_KEY",
      "openai" => "OPENAI_API_KEY"
    }.freeze

    PROVIDER_KEYS = {
      "claude" => "anthropic_api_key",
      "openai" => "openai_api_key"
    }.freeze

    def self.credentials_path
      File.join(Dir.home, ".zwischen", "credentials")
    end

    def self.ensure_directory
      dir = File.dirname(credentials_path)
      FileUtils.mkdir_p(dir) unless File.directory?(dir)
    end

    def self.load
      return {} unless File.exist?(credentials_path)

      YAML.safe_load(File.read(credentials_path)) || {}
    rescue StandardError => e
      warn "Failed to load credentials: #{e.message}"
      {}
    end

    def self.save(provider: "claude", api_key:)
      ensure_directory

      credentials = load
      
      key_name = PROVIDER_KEYS[provider]
      if key_name
        credentials[key_name] = api_key
      else
        warn "Unknown provider: #{provider}"
      end

      File.write(credentials_path, credentials.to_yaml)
      File.chmod(0o600, credentials_path)
    rescue StandardError => e
      warn "Failed to save credentials: #{e.message}"
      raise
    end

    def self.get_api_key(provider = "claude")
      # Priority: ENV var > credentials file
      env_var = PROVIDER_ENV_VARS[provider]
      return ENV[env_var] if env_var && ENV[env_var]

      key_name = PROVIDER_KEYS[provider]
      return nil unless key_name

      credentials = load
      credentials[key_name]
    end
  end
end
