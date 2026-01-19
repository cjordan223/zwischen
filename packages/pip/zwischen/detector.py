"""Project and framework detection for Zwischen."""

import json
from pathlib import Path
from typing import Any

# Base detection patterns
DETECTION_PATTERNS = {
    "node": ["package.json"],
    "python": ["requirements.txt", "pyproject.toml", "setup.py", "Pipfile", "poetry.lock"],
    "ruby": ["Gemfile", "Rakefile"],
    "go": ["go.mod", "go.sum"],
    "java": ["pom.xml", "build.gradle", "build.gradle.kts"],
    "rust": ["Cargo.toml", "Cargo.lock"],
    "php": ["composer.json"],
    "dotnet": ["*.csproj", "*.sln", "*.fsproj"],
}

# JS framework detection
JS_FRAMEWORKS = {
    "nextjs": ["next"],
    "react": ["react"],
    "vue": ["vue"],
    "angular": ["@angular/core"],
    "svelte": ["svelte"],
    "express": ["express"],
    "nestjs": ["@nestjs/core"],
    "nuxt": ["nuxt"],
    "remix": ["@remix-run/react"],
    "astro": ["astro"],
    "gatsby": ["gatsby"],
}

# Python framework detection
PYTHON_FRAMEWORKS = {
    "django": ["django"],
    "fastapi": ["fastapi"],
    "flask": ["flask"],
    "pyramid": ["pyramid"],
    "tornado": ["tornado"],
    "starlette": ["starlette"],
    "streamlit": ["streamlit"],
    "jupyter": ["jupyter", "jupyterlab", "notebook"],
}

# Ruby framework detection
RUBY_FRAMEWORKS = {
    "rails": ["rails"],
    "sinatra": ["sinatra"],
    "hanami": ["hanami"],
    "grape": ["grape"],
    "roda": ["roda"],
}

# Framework to language mapping
FRAMEWORK_LANGUAGES = {
    "nextjs": "javascript", "react": "javascript", "vue": "javascript",
    "angular": "typescript", "svelte": "javascript", "express": "javascript",
    "nestjs": "typescript", "nuxt": "javascript", "remix": "javascript",
    "astro": "javascript", "gatsby": "javascript",
    "django": "python", "fastapi": "python", "flask": "python",
    "pyramid": "python", "tornado": "python", "starlette": "python",
    "streamlit": "python", "jupyter": "python",
    "rails": "ruby", "sinatra": "ruby", "hanami": "ruby",
    "grape": "ruby", "roda": "ruby",
}


def detect_project(project_root: str | Path = ".") -> dict[str, Any]:
    """Detect project type and frameworks."""
    project_root = Path(project_root)

    types = _detect_base_types(project_root)
    frameworks = _detect_frameworks(project_root)

    primary = frameworks[0] if frameworks else (types[0] if types else None)
    language = (
        FRAMEWORK_LANGUAGES.get(frameworks[0], types[0] if types else "unknown")
        if frameworks
        else (types[0] if types else "unknown")
    )

    return {
        "types": types,
        "primary_type": primary,
        "language": language,
        "frameworks": frameworks,
        "root": str(project_root),
    }


def _detect_base_types(project_root: Path) -> list[str]:
    """Detect base project types."""
    detected = []

    for type_name, patterns in DETECTION_PATTERNS.items():
        if any(_matches_pattern(project_root, p) for p in patterns):
            detected.append(type_name)

    return detected


def _matches_pattern(project_root: Path, pattern: str) -> bool:
    """Check if pattern matches any file."""
    if "*" in pattern:
        return bool(list(project_root.glob(pattern)))
    return (project_root / pattern).exists()


def _detect_frameworks(project_root: Path) -> list[str]:
    """Detect frameworks."""
    frameworks = []
    frameworks.extend(_detect_js_frameworks(project_root))
    frameworks.extend(_detect_python_frameworks(project_root))
    frameworks.extend(_detect_ruby_frameworks(project_root))
    return list(dict.fromkeys(frameworks))  # Unique, preserve order


def _detect_js_frameworks(project_root: Path) -> list[str]:
    """Detect JS frameworks from package.json."""
    package_json = project_root / "package.json"
    if not package_json.exists():
        return []

    try:
        with open(package_json) as f:
            pkg = json.load(f)

        all_deps = list(pkg.get("dependencies", {}).keys()) + list(
            pkg.get("devDependencies", {}).keys()
        )

        detected = []
        for framework, packages in JS_FRAMEWORKS.items():
            if any(p in all_deps for p in packages):
                detected.append(framework)

        # Sort by specificity
        priority = [
            "nextjs", "nuxt", "remix", "gatsby", "astro",
            "angular", "nestjs", "svelte", "vue", "react", "express"
        ]
        return sorted(detected, key=lambda x: priority.index(x) if x in priority else 999)

    except (json.JSONDecodeError, OSError):
        return []


def _detect_python_frameworks(project_root: Path) -> list[str]:
    """Detect Python frameworks."""
    frameworks = []
    files = ["requirements.txt", "pyproject.toml", "Pipfile"]

    for filename in files:
        filepath = project_root / filename
        if filepath.exists():
            try:
                content = filepath.read_text().lower()
                for framework, packages in PYTHON_FRAMEWORKS.items():
                    if any(p.lower() in content for p in packages):
                        frameworks.append(framework)
            except OSError:
                pass

    priority = [
        "django", "fastapi", "flask", "pyramid",
        "tornado", "starlette", "streamlit", "jupyter"
    ]
    unique = list(dict.fromkeys(frameworks))
    return sorted(unique, key=lambda x: priority.index(x) if x in priority else 999)


def _detect_ruby_frameworks(project_root: Path) -> list[str]:
    """Detect Ruby frameworks from Gemfile."""
    gemfile = project_root / "Gemfile"
    if not gemfile.exists():
        return []

    try:
        content = gemfile.read_text().lower()
        detected = []

        for framework, gems in RUBY_FRAMEWORKS.items():
            if any(f"gem '{g}'" in content or f'gem "{g}"' in content for g in gems):
                detected.append(framework)

        priority = ["rails", "hanami", "sinatra", "grape", "roda"]
        return sorted(detected, key=lambda x: priority.index(x) if x in priority else 999)

    except OSError:
        return []
