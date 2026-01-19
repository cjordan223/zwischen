"""Configuration handling for Zwischen."""

from pathlib import Path
from typing import Any
import yaml

DEFAULT_CONFIG = {
    "ai": {
        "enabled": True,
        "pre_push_enabled": False,
        "provider": "ollama",
        "model": "llama3",
    },
    "blocking": {
        "severity": "high",
    },
    "scanners": {
        "gitleaks": {"enabled": True},
        "semgrep": {"enabled": True, "config": "p/security-audit"},
    },
    "ignore": [
        "**/node_modules/**",
        "**/vendor/**",
        "**/.git/**",
        "**/dist/**",
        "**/build/**",
        "**/test/fixtures/**",
    ],
}

EXAMPLE_CONFIG = """# Zwischen Configuration

# AI Provider Configuration
ai:
  enabled: true
  pre_push_enabled: false  # Disable AI in pre-push hooks (performance)
  provider: ollama         # Options: ollama, openai, anthropic
  model: llama3            # Model name for your provider
  # url: http://localhost:11434  # For Ollama (default)
  # api_key: null          # For OpenAI/Anthropic (or use env vars)

# What blocks a push
blocking:
  severity: high  # block on high or critical (default)
  # severity: critical  # only block on critical
  # severity: none  # never block, just warn

# Scanner Configuration
scanners:
  gitleaks: true  # Auto-installed if missing
  semgrep: true   # Optional, install with: pip install semgrep

# Ignored Paths (glob patterns)
ignore:
  - "**/node_modules/**"
  - "**/vendor/**"
  - "**/.git/**"
  - "**/dist/**"
  - "**/build/**"
"""


def deep_merge(base: dict, override: dict) -> dict:
    """Deep merge two dictionaries."""
    result = base.copy()
    for key, value in override.items():
        if (
            key in result
            and isinstance(result[key], dict)
            and isinstance(value, dict)
        ):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = value
    return result


def load_config(project_root: str | Path = ".") -> dict:
    """Load configuration from .zwischen.yml."""
    config_path = Path(project_root) / ".zwischen.yml"

    if not config_path.exists():
        return DEFAULT_CONFIG.copy()

    try:
        with open(config_path) as f:
            user_config = yaml.safe_load(f) or {}
        return deep_merge(DEFAULT_CONFIG, user_config)
    except Exception as e:
        print(f"Warning: Could not parse .zwischen.yml: {e}")
        return DEFAULT_CONFIG.copy()


def create_config(project_root: str | Path = ".") -> bool:
    """Create configuration file."""
    config_path = Path(project_root) / ".zwischen.yml"

    if config_path.exists():
        return False

    with open(config_path, "w") as f:
        f.write(EXAMPLE_CONFIG)
    return True
