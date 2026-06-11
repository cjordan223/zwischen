# Zwischen Python Package

Python wrapper for Zwischen, an AI-augmented security scanning CLI. This package exposes a Python implementation of the core workflow for Python users.

The Ruby gem in the repository root is currently the canonical implementation. This wrapper has a smaller command surface and may not match every Ruby feature.

## Installation

```bash
pip install zwischen-cli
```

The PyPI distribution is named `zwischen-cli` (the bare `zwischen` name is taken by an unrelated project), but the installed command is still `zwischen`.

For local development:

```bash
cd packages/pip
python -m pip install -e .
zwischen --help
```

## Commands

```bash
zwischen init
zwischen scan
zwischen scan --ai ollama
zwischen scan --ai openai --api-key "$OPENAI_API_KEY"
zwischen scan --format json
zwischen scan --pre-push
zwischen doctor
```

Supported scan flags:

- `--ai`: `ollama`, `openai`, or `anthropic`
- `--api-key`: provider API key
- `--format`: `terminal` or `json`
- `--pre-push`: compact hook mode

`--format json` prints only a JSON document on stdout (no banners), shaped like the Ruby gem's output: `{"summary": {"total": N, "by_severity": {...}}, "findings": [...]}`. File paths in findings are relative to the project root, and `ignore:` globs from `.zwischen.yml` are honored.

Not currently supported in this wrapper:

- `zwischen uninstall`
- `zwischen scan --only ...`
- `zwischen scan --changed`
- `zwischen scan --format sarif` (exits with status 2 and an error; use the Ruby gem for SARIF)
- Ruby's changed-file filtering for `--pre-push`

## Behavior

`zwischen init` tries to install Gitleaks into `~/.zwischen/bin`, creates `.zwischen.yml`, checks whether Semgrep is available, and installs or appends a Git `pre-push` hook when run inside a Git repository.

Semgrep is optional:

```bash
pip install semgrep
```

## Configuration

The Python wrapper creates this shape:

```yaml
ai:
  enabled: true
  pre_push_enabled: false
  provider: ollama
  model: llama3

blocking:
  severity: high

scanners:
  gitleaks: true
  semgrep: true

ignore:
  - "**/node_modules/**"
  - "**/vendor/**"
  - "**/.git/**"
  - "**/dist/**"
  - "**/build/**"
```

Blocking severities are `high`, `critical`, or `none`.

`ignore:` entries are glob patterns matched against paths relative to the project root; `**` spans directories (so `**/dist/**` also covers a top-level `dist/`). Findings in ignored paths are dropped from all output formats.

## License

MIT
