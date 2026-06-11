# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-06-11

### Added
- Initial release
- Gitleaks and Semgrep scanner orchestration with auto-install
- AI-powered finding triage via Ollama, OpenAI, or Anthropic
- Pre-push git hook that blocks pushes introducing secrets or security issues
- `--changed` flag to scan only files changed since the default branch
- SARIF 2.1.0 output (`--format sarif`) for GitHub code scanning
- Composite GitHub Action (`uses: cjordan223/zwischen@main`)
- Ignore globs in `.zwischen.yml` enforced at the orchestrator level
- Project type detection (Next.js, React, Django, Rails, and more)
- npm (`zwischen`) and pip (`zwischen-cli`) wrapper packages

[Unreleased]: https://github.com/cjordan223/zwischen/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/cjordan223/zwischen/releases/tag/v0.1.0
