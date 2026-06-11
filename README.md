# Zwischen

[![CI](https://github.com/cjordan223/zwischen/actions/workflows/ci.yml/badge.svg)](https://github.com/cjordan223/zwischen/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/zwischen)](https://rubygems.org/gems/zwischen)
[![npm](https://img.shields.io/npm/v/zwischen)](https://www.npmjs.com/package/zwischen)
[![PyPI](https://img.shields.io/pypi/v/zwischen-cli)](https://pypi.org/project/zwischen-cli/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

AI-augmented security scanning for local development workflows. Zwischen runs Gitleaks for secrets, optionally runs Semgrep for static analysis, aggregates findings, and can ask an AI provider to prioritize risks and suggest fixes.

The Ruby gem is the canonical implementation in this repository. The npm and pip packages are convenience wrappers with a smaller command surface.

## Installation

Install from a package manager once published:

```bash
gem install zwischen
npm install -g zwischen
pip install zwischen-cli
```

For local development from this repository:

```bash
bundle install
bundle exec ruby -Ilib bin/zwischen --help
```

## Quick Start

Run these commands from the project you want to scan:

```bash
zwischen init
zwischen scan
zwischen doctor
```

`zwischen init` creates `.zwischen.yml`, installs a `pre-push` hook when the current directory is a Git repository, and tries to install Gitleaks into `~/.zwischen/bin` when it is missing. Semgrep is optional and must be installed separately.

## Commands

| Command | Ruby gem | npm/pip wrappers |
| --- | --- | --- |
| `zwischen init` | Installs/checks tools, creates config, installs pre-push hook, backs up existing non-Zwischen hook before replacing it. | Installs/checks tools, creates config, installs or appends pre-push hook. |
| `zwischen scan` | Runs enabled scanners and prints a terminal report. | Runs Gitleaks and Semgrep when available. |
| `zwischen scan --only secrets,sast` | Limits scanners to Gitleaks (`secrets`) and/or Semgrep (`sast`). | Not supported. |
| `zwischen scan --ai claude` | Enables AI analysis for a manual scan. Also supports `ollama` and `openai`. | Supports `ollama`, `openai`, and `anthropic`. |
| `zwischen scan --format json` | Prints summary and findings as JSON. | Prints findings as JSON. |
| `zwischen scan --pre-push` | Quiet hook mode. Scans changed files only and prints compact output only for blocking findings. | Quiet hook mode, but currently scans the project rather than changed files only. |
| `zwischen doctor` | Shows Gitleaks and Semgrep status. | Shows Gitleaks and Semgrep status. |
| `zwischen uninstall` | Removes the Zwischen hook and optionally removes config/credentials. | Not supported. |

## AI Providers

Ruby defaults to `claude` in `.zwischen.yml.example`; npm and pip currently default to `ollama`.

| Provider | Ruby flag/config | Setup |
| --- | --- | --- |
| Claude | `claude` | Set `ANTHROPIC_API_KEY` or pass `--api-key`. |
| Ollama | `ollama` | Install Ollama, pull the configured model, and keep Ollama running locally. |
| OpenAI | `openai` | Set `OPENAI_API_KEY` or pass `--api-key`. |

Manual scans use AI when `--ai` is present or when config enables AI. Pre-push scans only use AI when `ai.pre_push_enabled: true` is set, to keep hooks fast by default.

## Configuration

Create or edit `.zwischen.yml` in the scanned project:

```yaml
ai:
  enabled: true
  pre_push_enabled: false
  provider: claude
  ollama:
    model: llama3
    url: http://localhost:11434
  openai:
    model: gpt-4
  claude:
    model: claude-3-5-sonnet-20241022

blocking:
  severity: high # high, critical, or none

scanners:
  gitleaks:
    enabled: true
  semgrep:
    enabled: true
    config: p/security-audit
```

The Ruby implementation accepts both boolean scanner entries (`gitleaks: true`) and detailed entries (`gitleaks: { enabled: true }`). Findings in paths matching the `ignore` globs are dropped before reporting.

Credentials are read from environment variables first, then from `~/.zwischen/credentials`. The Ruby initializer stores `ANTHROPIC_API_KEY` in that credentials file when it is present.

## Repository Layout

```text
bin/zwischen                  Ruby executable
lib/zwischen/                 Ruby gem implementation
lib/zwischen/scanner/         Gitleaks and Semgrep scanner adapters
lib/zwischen/ai/              Claude, Ollama, and OpenAI clients
packages/npm/                 Node wrapper package
packages/pip/                 Python wrapper package
spec/                         Ruby RSpec suite
scripts/test_as_gem.sh        Build and install the gem for end-to-end testing
TESTING.md                    Installed-gem end-to-end test plan
DEVELOPMENT.md                Architecture and modification guide
```

## Development

```bash
bundle exec rspec
./scripts/test_as_gem.sh
```

Use `DEVELOPMENT.md` before larger changes. Update `TESTING.md` whenever hook behavior, scanner selection, blocking rules, package parity, or AI provider behavior changes.

## License

MIT
