"""Zwischen - AI-augmented security scanning for vibe coders."""

__version__ = "0.1.0"

from .scanner import scan, run_gitleaks, run_semgrep
from .installer import install_gitleaks, get_gitleaks_path, is_gitleaks_installed
from .config import load_config, create_config
from .ai import analyze_with_ai

__all__ = [
    "scan",
    "run_gitleaks",
    "run_semgrep",
    "install_gitleaks",
    "get_gitleaks_path",
    "is_gitleaks_installed",
    "load_config",
    "create_config",
    "analyze_with_ai",
]
