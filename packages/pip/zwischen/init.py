"""Initialization for Zwischen."""

import os
import shutil
import stat
from pathlib import Path

from .installer import install_gitleaks, is_gitleaks_installed
from .config import create_config

PRE_PUSH_HOOK = """#!/bin/sh
# Zwischen pre-push hook
# Runs security scan on changed files before push

zwischen scan --pre-push
"""


def init() -> None:
    """Initialize Zwischen in project."""
    project_root = Path.cwd()

    print("\n🛡️  Initializing Zwischen...\n")

    # 1. Install gitleaks if needed
    if not is_gitleaks_installed():
        print("  Installing gitleaks...")
        if not install_gitleaks():
            print("  ⚠️  Could not auto-install gitleaks")
    else:
        print("  ✓ gitleaks already installed")

    # 2. Check for semgrep (optional)
    if shutil.which("semgrep"):
        print("  ✓ semgrep available")
    else:
        print("  ↳ semgrep not found (optional)")
        print("    → pip install semgrep")

    # 3. Create config file
    if create_config(project_root):
        print("  ✓ Created .zwischen.yml")
    else:
        print("  ✓ Config already exists")

    # 4. Install git hook
    git_dir = project_root / ".git"
    if git_dir.exists():
        hooks_dir = git_dir / "hooks"
        hooks_dir.mkdir(parents=True, exist_ok=True)

        hook_path = hooks_dir / "pre-push"

        if hook_path.exists():
            content = hook_path.read_text()
            if "zwischen" not in content:
                # Append to existing hook
                with open(hook_path, "a") as f:
                    f.write("\n" + PRE_PUSH_HOOK)
                print("  ✓ Added to existing pre-push hook")
            else:
                print("  ✓ Pre-push hook already configured")
        else:
            hook_path.write_text(PRE_PUSH_HOOK)
            hook_path.chmod(hook_path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
            print("  ✓ Installed pre-push hook")
    else:
        print("  ↳ Not a git repository, skipping hook installation")

    print("\n✅ Zwischen initialized!\n")
    print('Run "zwischen scan" to scan your project.')
    print("Security checks will run automatically before each push.\n")
