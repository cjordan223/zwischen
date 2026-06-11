# Zwischen npm Package

Node.js wrapper for Zwischen, an AI-augmented security scanning CLI. This package exposes a JavaScript implementation of the core workflow for Node users.

The Ruby gem in the repository root is currently the canonical implementation. This wrapper has a smaller command surface and may not match every Ruby feature.

## Installation

```bash
npm install -g zwischen
```

For local development:

```bash
cd packages/npm
npm install
node bin/zwischen.js --help
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

`--format json` prints only a JSON document to stdout (no banners), matching the Ruby gem's shape: a `summary` object (`total` plus `by_severity` counts) and a `findings` array. File paths are relative to the project root, and `ignore:` globs from `.zwischen.yml` are applied.

Not currently supported in this wrapper:

- `zwischen uninstall`
- `zwischen scan --only ...`
- `zwischen scan --changed`
- `zwischen scan --format sarif` (exits with code 2 and an error message; use the Ruby gem)
- Ruby's changed-file filtering for `--pre-push`

## Behavior

The package `postinstall` script attempts to install Gitleaks into `~/.zwischen/bin`. `zwischen init` retries that install if needed, creates `.zwischen.yml`, checks whether Semgrep is available, and installs or appends a Git `pre-push` hook when run inside a Git repository.

Semgrep is optional:

```bash
pip install semgrep
```

## Configuration

The npm wrapper creates this shape:

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
```

Blocking severities are `high`, `critical`, or `none`.

## License

MIT
