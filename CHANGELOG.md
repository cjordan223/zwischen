# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.1] - 2026-06-11

### Fixed
- `blocking.severity` is now honored by manual terminal scans — `critical`
  and `none` previously behaved like `high` because the CLI never passed
  config to the terminal reporter
- Hooks install where git actually executes them: `core.hooksPath`
  (husky/pre-commit setups) and linked worktrees are now resolved via
  `git rev-parse --git-path hooks` — previously the hook was written to
  `.git/hooks` and silently never ran under `core.hooksPath`, and
  worktrees skipped installation entirely
- `--format json` file paths are project-relative, matching terminal and
  SARIF output
- AI response parsing strips markdown code fences, so small local models
  that wrap JSON in ``` blocks still produce annotations
- npm/pip wrappers: `ignore:` globs are enforced, `--format json` emits
  pure JSON with a `summary` key and relative paths, `--format sarif`
  fails fast with a clear error, and pip `zwischen --version` no longer
  crashes

### Changed
- `scan --changed` now includes staged and untracked files; pre-push
  keeps committed-range semantics since only commits get pushed

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

[Unreleased]: https://github.com/cjordan223/zwischen/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/cjordan223/zwischen/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/cjordan223/zwischen/releases/tag/v0.1.0
