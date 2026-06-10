# frozen_string_literal: true

require_relative "lib/zwischen/version"

Gem::Specification.new do |spec|
  spec.name          = "zwischen"
  spec.version       = Zwischen::VERSION
  spec.authors       = ["Conner Jordan"]
  spec.email         = ["connercharlesjordan@gmail.com"]

  spec.summary       = "AI-augmented security scanning CLI for vibe coders"
  spec.description   = "Orchestrates Gitleaks and Semgrep scanners, aggregates findings, and uses AI to prioritize and explain security issues"
  spec.homepage      = "https://github.com/cjordan223/zwischen"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir["lib/**/*", "bin/**/*", "*.md", "*.gemspec", ".zwischen.yml.example"].reject do |f|
    File.directory?(f) || f.start_with?(*%w[spec/ test/ features/ .git .github])
  end
  spec.bindir        = "bin"
  spec.executables   = ["zwischen"]
  spec.require_paths = ["lib"]

  spec.add_dependency "thor", "~> 1.3"
  spec.add_dependency "faraday", "~> 2.0"
  spec.add_dependency "colorize", "~> 0.8.1"

  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rake", "~> 13.0"
end
