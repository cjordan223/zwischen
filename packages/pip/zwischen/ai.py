"""AI provider clients for Zwischen."""

import json
import os
import re
from typing import Any

import requests


def _build_prompt(findings: list[dict]) -> str:
    """Build AI analysis prompt."""
    def format_finding(i: int, f: dict) -> str:
        code_line = f"   Code: {f['code_snippet']}" if f.get('code_snippet') else ""
        return (
            f"{i + 1}. [{(f.get('severity') or 'medium').upper()}] {f['file']}:{f['line']}\n"
            f"   Rule: {f.get('rule_id', 'unknown')}\n"
            f"   Message: {f.get('message', '')}\n"
            f"{code_line}"
        )

    findings_text = "\n\n".join(format_finding(i, f) for i, f in enumerate(findings))

    return f"""You are a senior security engineer reviewing security scan findings. Analyze the following findings and provide:

1. Prioritization: Which findings are most critical and should be addressed first?
2. False positives: Are any of these false positives that can be safely ignored?
3. Fix suggestions: For each real finding, provide a clear, actionable fix suggestion.

Findings:
{findings_text}

Please respond in the following JSON format for each finding (by index number):
{{
  "1": {{
    "priority": "high|medium|low",
    "is_false_positive": false,
    "fix_suggestion": "Clear explanation of how to fix this issue",
    "risk_explanation": "Why this is a security risk"
  }}
}}

If a finding is a false positive, set is_false_positive to true and explain why."""


def _call_ollama(prompt: str, config: dict) -> str:
    """Call Ollama API."""
    base_url = config.get("url", "http://localhost:11434")
    model = config.get("model", "llama3")

    response = requests.post(
        f"{base_url}/api/chat",
        json={
            "model": model,
            "messages": [{"role": "user", "content": prompt}],
            "stream": False,
        },
        timeout=120,
    )

    if response.status_code != 200:
        raise Exception(f"Ollama error: {response.text}")

    data = response.json()
    if "error" in data:
        raise Exception(f"Ollama error: {data['error']}")

    return data.get("message", {}).get("content", "")


def _call_openai(prompt: str, config: dict) -> str:
    """Call OpenAI API."""
    api_key = config.get("api_key") or os.environ.get("OPENAI_API_KEY")
    if not api_key:
        raise Exception("OpenAI API key not found. Set OPENAI_API_KEY or provide --api-key")

    model = config.get("model", "gpt-4o-mini")

    response = requests.post(
        "https://api.openai.com/v1/chat/completions",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        json={
            "model": model,
            "messages": [{"role": "user", "content": prompt}],
        },
        timeout=120,
    )

    if response.status_code != 200:
        raise Exception(f"OpenAI error: {response.text}")

    data = response.json()
    if "error" in data:
        raise Exception(f"OpenAI error: {data['error']['message']}")

    return data.get("choices", [{}])[0].get("message", {}).get("content", "")


def _call_anthropic(prompt: str, config: dict) -> str:
    """Call Anthropic API."""
    api_key = config.get("api_key") or os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        raise Exception("Anthropic API key not found. Set ANTHROPIC_API_KEY or provide --api-key")

    model = config.get("model", "claude-3-haiku-20240307")

    response = requests.post(
        "https://api.anthropic.com/v1/messages",
        headers={
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
            "Content-Type": "application/json",
        },
        json={
            "model": model,
            "max_tokens": 4096,
            "messages": [{"role": "user", "content": prompt}],
        },
        timeout=120,
    )

    if response.status_code != 200:
        raise Exception(f"Anthropic error: {response.text}")

    data = response.json()
    if "error" in data:
        raise Exception(f"Anthropic error: {data['error']['message']}")

    return data.get("content", [{}])[0].get("text", "")


def analyze_with_ai(
    findings: list[dict],
    provider: str = "ollama",
    api_key: str | None = None,
    **config,
) -> list[dict]:
    """Analyze findings with AI."""
    if not findings:
        return findings

    prompt = _build_prompt(findings)
    config["api_key"] = api_key

    provider = provider.lower()
    if provider == "ollama":
        response = _call_ollama(prompt, config)
    elif provider == "openai":
        response = _call_openai(prompt, config)
    elif provider in ("anthropic", "claude"):
        response = _call_anthropic(prompt, config)
    else:
        raise Exception(f"Unknown AI provider: {provider}")

    # Parse AI response
    try:
        json_match = re.search(r"\{[\s\S]*\}", response)
        if not json_match:
            return findings

        analysis = json.loads(json_match.group())

        return [
            {
                **f,
                "ai_priority": analysis.get(str(i + 1), {}).get("priority"),
                "ai_false_positive": analysis.get(str(i + 1), {}).get("is_false_positive", False),
                "ai_fix_suggestion": analysis.get(str(i + 1), {}).get("fix_suggestion"),
                "ai_risk_explanation": analysis.get(str(i + 1), {}).get("risk_explanation"),
            }
            for i, f in enumerate(findings)
        ]

    except (json.JSONDecodeError, Exception) as e:
        if os.environ.get("DEBUG"):
            print(f"Failed to parse AI response: {e}")
        return findings
