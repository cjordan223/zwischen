# frozen_string_literal: true

require "faraday"
require "json"
require_relative "base_client"

module Zwischen
  module AI
    class OpenAIClient < BaseClient
      API_BASE_URL = "https://api.openai.com/v1"

      def initialize(api_key: nil, config: {})
        super
        raise Error, "OpenAI API key not found." unless @api_key

        @client = Faraday.new(url: API_BASE_URL) do |conn|
          conn.request :json
          conn.response :json, content_type: /\bjson$/
          conn.adapter Faraday.default_adapter
        end
      end

      def analyze(prompt)
        model = @config["model"] || "gpt-4"

        response = @client.post("/chat/completions") do |req|
          req.headers["Authorization"] = "Bearer #{@api_key}"
          req.body = {
            model: model,
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
          body.dig("choices", 0, "message", "content")
        else
          error_message = body.dig("error", "message") rescue body
          raise Error, "OpenAI API error: #{error_message}"
        end
      rescue Faraday::Error => e
        raise Error, "Network error: #{e.message}"
      rescue JSON::ParserError => e
        raise Error, "Invalid JSON response: #{e.message}"
      end
    end
  end
end
