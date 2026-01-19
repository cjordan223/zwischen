"""Doctor command for Zwischen."""

import shutil
import subprocess

from .installer import get_gitleaks_path, BIN_DIR


def doctor() -> None:
    """Check if required tools are installed."""
    print("\n" + "=" * 60)
    print("Zwischen Doctor - Tool Status")
    print("=" * 60 + "\n")

    all_installed = True

    tools = [
        {
            "name": "gitleaks",
            "description": "Secrets detection",
            "check": get_gitleaks_path,
            "install": "Auto-installed by zwischen init",
        },
        {
            "name": "semgrep",
            "description": "Static analysis (optional)",
            "check": lambda: shutil.which("semgrep"),
            "install": "pip install semgrep",
        },
    ]

    for tool in tools:
        tool_path = tool["check"]()

        if tool_path:
            version = ""
            try:
                result = subprocess.run(
                    [tool_path, "--version"],
                    capture_output=True,
                    text=True,
                )
                version = result.stdout.strip().split("\n")[0]
            except Exception:
                pass

            print(f"\033[32m✓ {tool['name']}\033[0m - {tool['description']}")
            if version:
                print(f"  Version: {version}")
            if tool_path.startswith(str(BIN_DIR)):
                print(f"  Location: {tool_path}")
        else:
            if "optional" not in tool["description"]:
                all_installed = False
            print(f"\033[31m✗ {tool['name']}\033[0m - {tool['description']} - NOT FOUND")
            print(f"  → {tool['install']}")

        print()

    if all_installed:
        print("\033[32m✅ All required tools are installed!\033[0m\n")
    else:
        print('\033[33m⚠️  Some tools are missing. Run "zwischen init" to install them.\033[0m\n')
