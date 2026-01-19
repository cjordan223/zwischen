# Zwischen

AI-augmented security scanning for vibe coders. Zero-config secrets detection and vulnerability scanning.

## Installation

```bash
pip install zwischen
```

## Quick Start

```bash
# Initialize in your project
zwischen init

# Scan your project
zwischen scan

# Scan with AI analysis (using local Ollama)
zwischen scan --ai ollama

# Scan with OpenAI
zwischen scan --ai openai
```

## Features

- **Zero-config**: Auto-installs gitleaks, works out of the box
- **Multi-language**: Works with any project (Node.js, Python, Go, etc.)
- **AI-powered**: Optional AI analysis to prioritize findings and suggest fixes
- **Git hooks**: Automatically scans before each push

## AI Providers

Zwischen supports multiple AI providers:

| Provider | Setup |
|----------|-------|
| Ollama (default) | Install [Ollama](https://ollama.ai), run `ollama pull llama3` |
| OpenAI | Set `OPENAI_API_KEY` environment variable |
| Anthropic | Set `ANTHROPIC_API_KEY` environment variable |

## Configuration

Create `.zwischen.yml` in your project root:

```yaml
ai:
  provider: ollama
  model: llama3

blocking:
  severity: high  # critical, high, or none

scanners:
  gitleaks: true
  semgrep: true
```

## License

MIT
