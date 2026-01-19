# Zwischen

AI-augmented security scanning for vibe coders. Zero-config secrets detection and vulnerability scanning with optional AI analysis.

## Installation

Choose your preferred package manager:

### npm (for Node.js/React/Next.js developers)

```bash
npm install -g zwischen
```

### pip (for Python developers)

```bash
pip install zwischen
```

### gem (for Ruby developers)

```bash
gem install zwischen
```

## Quick Start

```bash
# Initialize in your project (auto-installs gitleaks)
zwischen init

# Scan your project
zwischen scan

# Scan with AI analysis (local Ollama)
zwischen scan --ai ollama

# Scan with OpenAI
zwischen scan --ai openai
```

## Features

- **Zero Configuration**: Auto-installs gitleaks, works out of the box
- **Multi-Language**: Works with Node.js, Python, Ruby, Go, Java, Rust, and more
- **AI-Powered Analysis**: Optional AI to prioritize findings and suggest fixes
- **Multiple AI Providers**: Ollama (local), OpenAI, Anthropic
- **Git Hooks**: Automatically scans before each push

## AI Providers

| Provider | Setup |
|----------|-------|
| Ollama (local, free) | Install [Ollama](https://ollama.ai), run `ollama pull llama3` |
| OpenAI | Set `OPENAI_API_KEY` environment variable |
| Anthropic | Set `ANTHROPIC_API_KEY` environment variable |

## Configuration

Create `.zwischen.yml` in your project root:

```yaml
ai:
  provider: ollama    # ollama, openai, or anthropic
  model: llama3       # model name for your provider

blocking:
  severity: high      # critical, high, or none

scanners:
  gitleaks: true      # auto-installed
  semgrep: true       # optional: pip install semgrep
```

## Usage

```bash
# Scan with local AI (Ollama)
zwischen scan --ai ollama

# Scan with OpenAI
zwischen scan --ai openai --api-key sk-...

# Output as JSON
zwischen scan --format json

# Check tool status
zwischen doctor
```

## License

MIT
