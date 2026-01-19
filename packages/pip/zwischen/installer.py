"""Gitleaks installer for Zwischen."""

import os
import platform
import shutil
import stat
import tarfile
import tempfile
from pathlib import Path
from urllib.request import urlopen, Request
import json

ZWISCHEN_DIR = Path.home() / ".zwischen"
BIN_DIR = ZWISCHEN_DIR / "bin"
GITLEAKS_REPO = "gitleaks/gitleaks"

PLATFORMS = {
    "Darwin": "darwin",
    "Linux": "linux",
    "Windows": "windows",
}

ARCHS = {
    "x86_64": "x64",
    "AMD64": "x64",
    "aarch64": "arm64",
    "arm64": "arm64",
}


def fetch_json(url: str) -> dict:
    """Fetch JSON from URL."""
    req = Request(url, headers={"User-Agent": "zwischen"})
    with urlopen(req) as response:
        return json.loads(response.read().decode())


def download_file(url: str, dest: Path) -> None:
    """Download file from URL."""
    req = Request(url, headers={"User-Agent": "zwischen"})
    with urlopen(req) as response:
        with open(dest, "wb") as f:
            shutil.copyfileobj(response, f)


def install_gitleaks() -> bool:
    """Install gitleaks binary."""
    plat = PLATFORMS.get(platform.system())
    arch = ARCHS.get(platform.machine(), "x64")

    if not plat:
        print(f"Unsupported platform: {platform.system()}")
        return False

    # Ensure directories exist
    BIN_DIR.mkdir(parents=True, exist_ok=True)

    gitleaks_name = "gitleaks.exe" if plat == "windows" else "gitleaks"
    gitleaks_path = BIN_DIR / gitleaks_name

    # Check if already installed
    if gitleaks_path.exists():
        return True

    print("  Downloading gitleaks...")

    try:
        # Get latest release
        release = fetch_json(f"https://api.github.com/repos/{GITLEAKS_REPO}/releases/latest")

        # Find matching asset
        pattern = f"gitleaks_"
        suffix = f"_{plat}_{arch}.tar.gz"
        asset = next(
            (a for a in release["assets"] if a["name"].startswith(pattern) and a["name"].endswith(suffix)),
            None,
        )

        if not asset:
            print(f"No gitleaks binary found for {plat}_{arch}")
            return False

        # Download and extract
        with tempfile.TemporaryDirectory() as tmpdir:
            tarball_path = Path(tmpdir) / "gitleaks.tar.gz"
            download_file(asset["browser_download_url"], tarball_path)

            with tarfile.open(tarball_path, "r:gz") as tar:
                for member in tar.getmembers():
                    if member.name == "gitleaks":
                        member.name = gitleaks_name
                        tar.extract(member, BIN_DIR)
                        break

        # Make executable
        if plat != "windows":
            gitleaks_path.chmod(gitleaks_path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

        print("  ✓ Installed gitleaks")
        return True

    except Exception as e:
        print(f"  ✗ Failed to install gitleaks: {e}")
        return False


def get_gitleaks_path() -> str | None:
    """Get path to gitleaks executable."""
    gitleaks_name = "gitleaks.exe" if platform.system() == "Windows" else "gitleaks"
    local_path = BIN_DIR / gitleaks_name

    if local_path.exists():
        return str(local_path)

    # Check system PATH
    system_path = shutil.which("gitleaks")
    return system_path


def is_gitleaks_installed() -> bool:
    """Check if gitleaks is installed."""
    return get_gitleaks_path() is not None
