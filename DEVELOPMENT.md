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
     -> Reporter::Terminal (or Reporter::Sarif for --format sarif)
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

`zwischen scan --pre-push` uses `GitDiff.changed_files`, passes those files to scanner adapters, filters findings to changed files again as a safety net, and only prints compact output for blocking findings. `zwischen scan --changed` applies the same changed-files scoping to a manual scan with full output.

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

- Existing non-Zwischen pre-push hooks (husky shims, hand-written scripts) are backed up and then appended to, not replaced — the original checks keep running, and `zwischen uninstall` strips only the appended block.
- Ruby config exposes `severity.fail_on`, but blocking decisions use `blocking.severity`. (`ignore` globs are enforced by the orchestrator.)
- npm and pip wrappers do not yet match Ruby feature parity. They do not support `uninstall`, `--only`, `--changed`, `--format sarif`, Ruby's changed-file pre-push filtering, or the Ruby JSON summary shape.
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

npm wrapper smoke checks (mirrors CI):

```bash
cd packages/npm
node bin/zwischen.js --help
npm pack --dry-run
```

pip wrapper smoke checks:

```bash
cd packages/pip
python -m pip install -e .
zwischen --help
```

## Releasing

Releases are automated by `.github/workflows/release.yml`, triggered by a
version tag:

```bash
# bump lib/zwischen/version.rb, packages/npm/package.json,
# packages/pip/pyproject.toml, and CHANGELOG.md first
git tag vX.Y.Z
git push origin vX.Y.Z
```

Registry setup (already configured as of v0.1.0; reference for new registries
or token rotation):

1. **RubyGems** — trusted publisher on the `zwischen` gem:
   repository `cjordan223/zwischen`, workflow `release.yml`, environment `release`.
2. **PyPI** — trusted publisher on the `zwischen-cli` project, same
   repository, workflow, and environment. (The bare `zwischen` name is taken
   on PyPI by an unrelated package, so the distribution is `zwischen-cli`;
   the installed command is still `zwischen`.)
3. **npm** — granular access token saved as the `NPM_TOKEN` repository
   secret. Must have read/write on the `zwischen` package and **bypass 2FA**
   enabled, or CI publishes fail with `EOTP`. When rotating, set the secret
   via the interactive prompt (`gh secret set NPM_TOKEN`) — never pass the
   token as a command argument.
4. **GitHub** — the `release` environment in repo settings, so OIDC claims
   match the workflows.
