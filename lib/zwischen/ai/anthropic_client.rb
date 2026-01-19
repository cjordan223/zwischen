# frozen_string_literal: true

require "faraday"
require "json"
require_relative "base_client"

module Zwischen
  module AI
    class AnthropicClient < BaseClient
      API_BASE_URL = "https://api.anthropic.com/v1"
      API_VERSION = "2023-06-01"

      def initialize(api_key: nil, config: {})
        super
        raise Error, "Claude API key not found." unless @api_key

        @client = Faraday.new(url: API_BASE_URL) do |conn|
          conn.request :json
          conn.response :json, content_type: /\bjson$/
          conn.adapter Faraday.default_adapter
        end
      end

      def analyze(prompt)
        model = @config["model"] || "claude-3-5-sonnet-20241022"

        response = @client.post("/messages") do |req|
          req.headers["x-api-key"] = @api_key
          req.headers["anthropic-version"] = API_VERSION
          req.body = {
            model: model,
            max_tokens: 4096,
            messages: [
              {
                role: "user",
                content: prompt
              }
            ]
          }
        end

        body = response.body
        body = JSON.parse(body) if body.is_a?(String)

        if response.success?
          body.dig("content", 0, "text")
        else
          error_message = body.dig("error", "message") rescue body
          raise Error, "Claude API error: #{error_message}"
        end
      rescue Faraday::Error => e
        raise Error, "Network error: #{e.message}"
      rescue JSON::ParserError => e
        raise Error, "Invalid JSON response: #{e.message}"
      end
    end
  end
end
