"""Security scanners for Zwischen."""

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

from .installer import get_gitleaks_path
from .config import load_config
from .ai import analyze_with_ai
from .detector import detect_project


def run_gitleaks(project_root: str = ".", files: list[str] | None = None) -> list[dict]:
    """Run gitleaks scanner."""
    gitleaks_path = get_gitleaks_path()
    if not gitleaks_path:
        return []

    findings = []

    try:
        if files:
            # Scan specific files
            for file in files:
                file_path = Path(project_root) / file
                if not file_path.exists():
                    continue

                result = subprocess.run(
                    [
                        gitleaks_path,
                        "detect",
                        "--source", str(file_path),
                        "--report-format", "json",
                        "--report-path", "-",
                        "--no-git",
                    ],
                    capture_output=True,
                    text=True,
                    cwd=project_root,
                )

                if result.stdout:
                    try:
                        parsed = json.loads(result.stdout)
                        findings.extend(parsed if isinstance(parsed, list) else [])
                    except json.JSONDecodeError:
                        pass
        else:
            # Scan entire project
            result = subprocess.run(
                [
                    gitleaks_path,
                    "detect",
                    "--source", project_root,
                    "--report-format", "json",
                    "--report-path", "-",
                    "--no-git",
                ],
                capture_output=True,
                text=True,
                cwd=project_root,
            )

            if result.stdout:
                try:
                    parsed = json.loads(result.stdout)
                    findings.extend(parsed if isinstance(parsed, list) else [])
                except json.JSONDecodeError:
                    pass

    except Exception as e:
        if os.environ.get("DEBUG"):
            print(f"Gitleaks error: {e}", file=sys.stderr)

    return [
        {
            "type": "secret",
            "scanner": "gitleaks",
            "severity": _map_gitleaks_severity(f.get("RuleID", "")),
            "file": f.get("File", ""),
            "line": f.get("StartLine", 0),
            "message": f.get("RuleID", "Secret detected"),
            "rule_id": f.get("RuleID", ""),
            "code_snippet": f.get("Secret", ""),
            "raw": f,
        }
        for f in findings
    ]


def _map_gitleaks_severity(rule_id: str) -> str:
    """Map gitleaks rule to severity."""
    rule_id = rule_id.lower()
    if re.search(r"aws.*key|api.*key|private.*key|secret.*key", rule_id):
        return "critical"
    if re.search(r"password|token|credential", rule_id):
        return "high"
    return "medium"


def run_semgrep(project_root: str = ".", files: list[str] | None = None) -> list[dict]:
    """Run semgrep scanner."""
    if not shutil.which("semgrep"):
        return []

    findings = []

    try:
        args = ["semgrep", "--json", "--config", "p/security-audit"]
        if files:
            args.extend(files)
        else:
            args.append(project_root)

        result = subprocess.run(
            args,
            capture_output=True,
            text=True,
            cwd=project_root,
        )

        if result.stdout:
            try:
                parsed = json.loads(result.stdout)
                for r in parsed.get("results", []):
                    findings.append({
                        "type": "vulnerability",
                        "scanner": "semgrep",
                        "severity": r.get("extra", {}).get("severity", "medium"),
                        "file": r.get("path", ""),
                        "line": r.get("start", {}).get("line", 0),
                        "message": r.get("extra", {}).get("message", r.get("check_id", "")),
                        "rule_id": r.get("check_id", ""),
                        "code_snippet": r.get("extra", {}).get("lines", ""),
                        "raw": r,
                    })
            except json.JSONDecodeError:
                pass

    except Exception as e:
        if os.environ.get("DEBUG"):
            print(f"Semgrep error: {e}", file=sys.stderr)

    return findings


def scan(
    ai: str | None = None,
    api_key: str | None = None,
    output_format: str = "terminal",
    pre_push: bool = False,
) -> None:
    """Run security scan."""
    project_root = os.getcwd()
    config = load_config(project_root)
    project = detect_project(project_root)

    if not pre_push:
        framework_info = (
            f"{project['frameworks'][0]} ({project['language']})"
            if project['frameworks']
            else project['primary_type'] or 'project'
        )
        print(f"\n🔍 Scanning {framework_info}...\n")

    # Run scanners
    gitleaks_findings = run_gitleaks(project_root)
    semgrep_findings = run_semgrep(project_root)
    findings = gitleaks_findings + semgrep_findings

    if not findings:
        if not pre_push:
            print("✅ No security issues found!\n")
        sys.exit(0)

    # AI analysis if requested
    if ai:
        if not pre_push:
            print(f"🤖 Analyzing with AI ({ai})...\n")
        try:
            findings = analyze_with_ai(
                findings,
                provider=ai,
                api_key=api_key or config.get("ai", {}).get("api_key"),
            )
        except Exception as e:
            if not pre_push:
                print(f"⚠️  AI analysis unavailable: {e}")

    # Report findings
    if output_format == "json":
        print(json.dumps({"findings": findings}, indent=2))
    else:
        _report_findings(findings, pre_push)

    # Exit with error if blocking findings
    blocking_severity = config.get("blocking", {}).get("severity", "high")
    has_blocking = any(_should_block(f, blocking_severity) for f in findings)
    sys.exit(1 if has_blocking else 0)


def _should_block(finding: dict, blocking_severity: str) -> bool:
    """Check if finding should block."""
    if finding.get("ai_false_positive"):
        return False

    severity = (finding.get("severity") or "medium").lower()
    if blocking_severity == "critical":
        return severity == "critical"
    if blocking_severity == "high":
        return severity in ("critical", "high")
    if blocking_severity == "none":
        return False
    return severity in ("critical", "high")


def _report_findings(findings: list[dict], compact: bool = False) -> None:
    """Report findings to terminal."""
    by_severity = {"critical": [], "high": [], "medium": [], "low": []}

    for f in findings:
        sev = (f.get("severity") or "medium").lower()
        if sev in by_severity:
            by_severity[sev].append(f)
        else:
            by_severity["medium"].append(f)

    print("🛡️  Security Scan Results\n")
    print(f"Found {len(findings)} issue(s):\n")

    colors = {
        "critical": "\033[31m",  # red
        "high": "\033[33m",      # yellow
        "medium": "\033[36m",    # cyan
        "low": "\033[37m",       # white
    }
    reset = "\033[0m"

    for severity, items in by_severity.items():
        if not items:
            continue

        print(f"{colors[severity]}{severity.upper()} ({len(items)}){reset}")

        for f in items:
            fp = " [FALSE POSITIVE]" if f.get("ai_false_positive") else ""
            print(f"  {f['file']}:{f['line']} - {f['message']}{fp}")
            if f.get("ai_fix_suggestion") and not compact:
                print(f"    💡 {f['ai_fix_suggestion']}")
        print()
