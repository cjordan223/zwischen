# frozen_string_literal: true

require_relative "zwischen/version"

module Zwischen
  class Error < StandardError; end
end

# Load all modules when gem is required
require_relative "zwischen/config"
require_relative "zwischen/project_detector"
require_relative "zwischen/finding/finding"
require_relative "zwischen/finding/aggregator"
require_relative "zwischen/scanner/base"
require_relative "zwischen/scanner/gitleaks"
require_relative "zwischen/scanner/semgrep"
require_relative "zwischen/scanner/orchestrator"
require_relative "zwischen/installer"
require_relative "zwischen/credentials"
require_relative "zwischen/git_diff"
require_relative "zwischen/hooks"
require_relative "zwischen/setup"
require_relative "zwischen/ai/anthropic_client"
require_relative "zwischen/ai/ollama_client"
require_relative "zwischen/ai/openai_client"
require_relative "zwischen/ai/analyzer"
require_relative "zwischen/reporter/terminal"
require_relative "zwischen/cli"
