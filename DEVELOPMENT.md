# Development Guide

This repository contains three installable surfaces for the same product idea:

- `lib/zwischen`: the Ruby gem and canonical implementation.
- `packages/npm`: a Node.js wrapper package.
- `packages/pip`: a Python wrapper package.

When behavior differs, treat the Ruby gem as the source of truth unless the change is explicitly package-wrapper work.

## Ruby Command Flow

```text
bin/zwischen
  -> Zwischen::CLI
     -> Config.load
     -> ProjectDetector.detect
     -> Scanner::Orchestrator
        -> Scanner::Gitleaks
        -> Scanner::Semgrep
     -> Finding::Aggregator
     -> AI::Analyzer, when enabled
     -> Reporter::Terminal
```

`zwischen init` follows a separate path:

```text
CLI#init
  -> Setup.run
     -> Installer checks/installs Gitleaks
     -> Credentials saves ANTHROPIC_API_KEY when present
     -> Hooks installs .git/hooks/pre-push
     -> Config.init creates .zwischen.yml
```

`zwischen scan --pre-push` uses `GitDiff.changed_files`, passes those files to scanner adapters, filters findings to changed files again as a safety net, and only prints compact output for blocking findings.

## Config Contract

Project config lives at `.zwischen.yml`.

Current Ruby defaults:

- `ai.enabled: true`
- `ai.pre_push_enabled: false`
- `ai.provider: claude`
- `blocking.severity: high`
- Gitleaks and Semgrep enabled
- Semgrep config: `p/security-audit`

Credential lookup order is environment variables first, then `~/.zwischen/credentials`.

Supported Ruby credential environment variables:

- `ANTHROPIC_API_KEY` for `claude`
- `OPENAI_API_KEY` for `openai`

Local tool installs use `~/.zwischen/bin`.

## Common Change Checklists

Scanner changes:

- Add or edit a scanner under `lib/zwischen/scanner`.
- Return `Zwischen::Finding::Finding` objects with normalized `type`, `scanner`, `severity`, `file`, `line`, `message`, and `rule_id`.
- Register new scanner selection in `Scanner::Orchestrator`.
- Update `.zwischen.yml.example`, `README.md`, and relevant specs.
- Add or update scanner specs.

AI provider changes:

- Add a client under `lib/zwischen/ai`.
- Wire provider selection in `AI::Analyzer`.
- Add credential mapping in `Credentials` if the provider needs an API key.
- Update `.zwischen.yml.example`, `README.md`, and AI specs.

Hook changes:

- Update `Hooks` and `Setup`.
- Run installed-gem tests from `TESTING.md`.
- Update `TESTING.md` with exact hook behavior and bypass behavior.

Package-wrapper parity changes:

- Mirror command flags in `packages/npm/bin/zwischen.js` and `packages/pip/zwischen/cli.py`.
- Keep config key names aligned with `.zwischen.yml.example`.
- Update wrapper package READMEs.

## Known Iteration Points

- Ruby `Hooks.handle_existing_hook` has backup/append/skip logic, but `Setup#install_hook` currently backs up and replaces existing non-Zwischen hooks directly.
- Ruby config exposes `ignore` and `severity.fail_on`, but scanner adapters currently do not enforce ignore globs and blocking uses `blocking.severity`.
- npm and pip wrappers do not yet match Ruby feature parity. They do not support `uninstall`, `--only`, Ruby's changed-file pre-push filtering, or the Ruby JSON summary shape.
- npm and pip wrappers default AI provider to Ollama, while Ruby defaults to Claude.

## Verification

Ruby unit suite:

```bash
bundle exec rspec
```

Installed-gem workflow:

```bash
./scripts/test_as_gem.sh
```

Then follow `TESTING.md` from a temporary directory outside this repository.

npm wrapper smoke checks:

```bash
cd packages/npm
npm test
node bin/zwischen.js --help
```

pip wrapper smoke checks:

```bash
cd packages/pip
python -m pip install -e .
zwischen --help
```
