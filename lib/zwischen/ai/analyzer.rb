# frozen_string_literal: true

require_relative "anthropic_client"
require_relative "ollama_client"
require_relative "openai_client"
require_relative "../finding/finding"

module Zwischen
  module AI
    class Analyzer
      def initialize(provider: "claude", api_key: nil, config: {}, project_context: {})
        @project_context = project_context
        
        client_class = case provider.to_s.downcase
                       when "claude", "anthropic" then AnthropicClient
                       when "ollama" then OllamaClient
                       when "openai" then OpenAIClient
                       else
                         # Fallback or error
                         AnthropicClient
                       end

        @client = client_class.new(api_key: api_key, config: config)
      end

      def analyze(findings)
        return findings if findings.empty?

        prompt = build_prompt(findings)
        response = @client.analyze(prompt)

        enhance_findings(findings, response)
      rescue AI::Error => e
        warn "AI analysis failed: #{e.message}. Returning original findings."
        findings
      rescue StandardError => e
        warn "AI analysis failed: #{e.message}. Returning original findings."
        findings
      end

      private

      def build_prompt(findings)
        project_info = "Project type: #{@project_context[:primary_type] || 'unknown'}, Language: #{@project_context[:language] || 'unknown'}"

        findings_text = findings.map.with_index(1) do |finding, idx|
          <<~FINDING
            #{idx}. [#{finding.severity.upcase}] #{finding.file}:#{finding.line}
               Rule: #{finding.rule_id}
               Message: #{finding.message}
           #{finding.code_snippet ? "   Code:\n   #{finding.code_snippet.split("\n").map { |l| "   #{l}" }.join("\n")}" : ""}
          FINDING
        end.join("\n")

        <<~PROMPT
          You are a senior security engineer reviewing security scan findings. Analyze the following findings and provide:

          1. Prioritization: Which findings are most critical and should be addressed first?
          2. False positives: Are any of these false positives that can be safely ignored?
          3. Fix suggestions: For each real finding, provide a clear, actionable fix suggestion.

          #{project_info}

          Findings:
          #{findings_text}

          Please respond in the following JSON format for each finding (by index number):
          {
            "1": {
              "priority": "high|medium|low",
              "is_false_positive": false,
              "fix_suggestion": "Clear explanation of how to fix this issue",
              "risk_explanation": "Why this is a security risk"
            },
            ...
          }

          If a finding is a false positive, set is_false_positive to true and explain why.
        PROMPT
      end

      def enhance_findings(findings, ai_response)
        # Try to parse JSON from the response
        # Look for JSON object in the response
        json_match = ai_response.match(/\{[\s\S]*\}/m)
        return findings unless json_match

        ai_analysis = JSON.parse(json_match[0])

        findings.map.with_index(1) do |finding, idx|
          analysis = ai_analysis[idx.to_s]
          next finding unless analysis

          # Add AI insights to raw_data
          enhanced_data = finding.raw_data.merge(
            "ai_priority" => analysis["priority"],
            "ai_false_positive" => analysis["is_false_positive"] || false,
            "ai_fix_suggestion" => analysis["fix_suggestion"],
            "ai_risk_explanation" => analysis["risk_explanation"]
          )

          # Create new finding with enhanced data
          Zwischen::Finding::Finding.new(
            type: finding.type,
            scanner: finding.scanner,
            severity: finding.severity,
            file: finding.file,
            line: finding.line,
            message: finding.message,
            rule_id: finding.rule_id,
            code_snippet: finding.code_snippet,
            raw_data: enhanced_data
          )
        end
      rescue JSON::ParserError => e
        warn "Failed to parse AI response: #{e.message}"
        findings
      end
    end
  end
end
