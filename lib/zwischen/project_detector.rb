# frozen_string_literal: true

require "json"
require "yaml"

module Zwischen
  class ProjectDetector
    # Base detection patterns for runtime/language
    DETECTION_PATTERNS = {
      "node" => ["package.json"],
      "python" => ["requirements.txt", "pyproject.toml", "setup.py", "Pipfile", "poetry.lock"],
      "ruby" => ["Gemfile", "Rakefile"],
      "go" => ["go.mod", "go.sum"],
      "java" => ["pom.xml", "build.gradle", "build.gradle.kts"],
      "rust" => ["Cargo.toml", "Cargo.lock"],
      "php" => ["composer.json"],
      "dotnet" => ["*.csproj", "*.sln", "*.fsproj"]
    }.freeze

    # Framework detection in package.json dependencies
    JS_FRAMEWORKS = {
      "nextjs" => ["next"],
      "react" => ["react"],
      "vue" => ["vue"],
      "angular" => ["@angular/core"],
      "svelte" => ["svelte"],
      "express" => ["express"],
      "nestjs" => ["@nestjs/core"],
      "nuxt" => ["nuxt"],
      "remix" => ["@remix-run/react"],
      "astro" => ["astro"],
      "gatsby" => ["gatsby"]
    }.freeze

    # Framework detection in Python dependencies
    PYTHON_FRAMEWORKS = {
      "django" => ["django", "Django"],
      "fastapi" => ["fastapi", "FastAPI"],
      "flask" => ["flask", "Flask"],
      "pyramid" => ["pyramid"],
      "tornado" => ["tornado"],
      "starlette" => ["starlette"],
      "streamlit" => ["streamlit"],
      "jupyter" => ["jupyter", "jupyterlab", "notebook"]
    }.freeze

    # Framework detection in Gemfile
    RUBY_FRAMEWORKS = {
      "rails" => ["rails"],
      "sinatra" => ["sinatra"],
      "hanami" => ["hanami"],
      "grape" => ["grape"],
      "roda" => ["roda"]
    }.freeze

    # Map frameworks to primary language
    FRAMEWORK_LANGUAGES = {
      "nextjs" => "javascript", "react" => "javascript", "vue" => "javascript",
      "angular" => "typescript", "svelte" => "javascript", "express" => "javascript",
      "nestjs" => "typescript", "nuxt" => "javascript", "remix" => "javascript",
      "astro" => "javascript", "gatsby" => "javascript",
      "django" => "python", "fastapi" => "python", "flask" => "python",
      "pyramid" => "python", "tornado" => "python", "starlette" => "python",
      "streamlit" => "python", "jupyter" => "python",
      "rails" => "ruby", "sinatra" => "ruby", "hanami" => "ruby",
      "grape" => "ruby", "roda" => "ruby"
    }.freeze

    def self.detect(project_root = Dir.pwd)
      new(project_root).detect
    end

    def initialize(project_root = Dir.pwd)
      @project_root = project_root
    end

    def detect
      detected_types = detect_base_types
      frameworks = detect_frameworks

      # Determine primary type - prefer framework over base type
      primary = frameworks.first || detected_types.first

      # Determine language
      language = if frameworks.any?
                   FRAMEWORK_LANGUAGES[frameworks.first] || detected_types.first
                 else
                   detected_types.first
                 end

      {
        types: detected_types,
        primary_type: primary,
        language: language || "unknown",
        frameworks: frameworks,
        root: @project_root
      }
    end

    private

    def detect_base_types
      detected = []

      DETECTION_PATTERNS.each do |type, patterns|
        if patterns.any? { |pattern| matches_pattern?(pattern) }
          detected << type
        end
      end

      detected
    end

    def detect_frameworks
      frameworks = []

      # Detect JS frameworks from package.json
      frameworks.concat(detect_js_frameworks)

      # Detect Python frameworks
      frameworks.concat(detect_python_frameworks)

      # Detect Ruby frameworks
      frameworks.concat(detect_ruby_frameworks)

      frameworks.uniq
    end

    def detect_js_frameworks
      package_json_path = File.join(@project_root, "package.json")
      return [] unless File.exist?(package_json_path)

      begin
        package = JSON.parse(File.read(package_json_path))
        all_deps = (package["dependencies"] || {}).keys +
                   (package["devDependencies"] || {}).keys

        detected = []
        JS_FRAMEWORKS.each do |framework, packages|
          if packages.any? { |pkg| all_deps.include?(pkg) }
            detected << framework
          end
        end

        # Sort by specificity (Next.js before React, etc.)
        sort_by_specificity(detected, %w[nextjs nuxt remix gatsby astro angular nestjs svelte vue react express])
      rescue JSON::ParserError
        []
      end
    end

    def detect_python_frameworks
      frameworks = []

      # Check requirements.txt
      req_path = File.join(@project_root, "requirements.txt")
      if File.exist?(req_path)
        content = File.read(req_path).downcase
        frameworks.concat(match_python_deps(content))
      end

      # Check pyproject.toml
      pyproject_path = File.join(@project_root, "pyproject.toml")
      if File.exist?(pyproject_path)
        content = File.read(pyproject_path).downcase
        frameworks.concat(match_python_deps(content))
      end

      # Check Pipfile
      pipfile_path = File.join(@project_root, "Pipfile")
      if File.exist?(pipfile_path)
        content = File.read(pipfile_path).downcase
        frameworks.concat(match_python_deps(content))
      end

      sort_by_specificity(frameworks.uniq, %w[django fastapi flask pyramid tornado starlette streamlit jupyter])
    end

    def match_python_deps(content)
      detected = []
      PYTHON_FRAMEWORKS.each do |framework, packages|
        if packages.any? { |pkg| content.include?(pkg.downcase) }
          detected << framework
        end
      end
      detected
    end

    def detect_ruby_frameworks
      gemfile_path = File.join(@project_root, "Gemfile")
      return [] unless File.exist?(gemfile_path)

      content = File.read(gemfile_path).downcase
      detected = []

      RUBY_FRAMEWORKS.each do |framework, gems|
        if gems.any? { |gem| content.include?("gem '#{gem}'") || content.include?("gem \"#{gem}\"") }
          detected << framework
        end
      end

      sort_by_specificity(detected, %w[rails hanami sinatra grape roda])
    end

    def sort_by_specificity(detected, priority_order)
      detected.sort_by { |f| priority_order.index(f) || 999 }
    end

    def matches_pattern?(pattern)
      if pattern.include?("*")
        Dir.glob(File.join(@project_root, pattern)).any?
      else
        File.exist?(File.join(@project_root, pattern))
      end
    end
  end
end
