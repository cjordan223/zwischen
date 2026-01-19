# frozen_string_literal: true

require "faraday"
require "json"
require_relative "base_client"

module Zwischen
  module AI
    class OllamaClient < BaseClient
      def initialize(api_key: nil, config: {})
        super
        # Ollama usually doesn't need an API key, but we accept it if provided
        
        base_url = @config["url"] || "http://localhost:11434"
        # Ensure base URL doesn't end with /api/chat if user provided full path
        base_url = base_url.sub(/\/api\/chat\/?$/, "")

        @client = Faraday.new(url: base_url) do |conn|
          conn.request :json
          conn.response :json, content_type: /\bjson$/
          conn.adapter Faraday.default_adapter
        end
      end

      def analyze(prompt)
        model = @config["model"] || "llama3"

        response = @client.post("/api/chat") do |req|
          req.body = {
            model: model,
            messages: [
              {
                role: "user",
                content: prompt
              }
            ],
            stream: false
          }
        end

        if response.success?
          content = response.body.dig("message", "content")
          unless content
            raise Error, "Unexpected Ollama response format: #{response.body}"
          end
          content
        else
          error_message = response.body.dig("error") || "Unknown error"
          raise Error, "Ollama API error: #{error_message}"
        end
      rescue Faraday::Error => e
        raise Error, "Ollama connection error: #{e.message}. Is Ollama running?"
      end
    end
  end
end
