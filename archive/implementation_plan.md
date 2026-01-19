# Zwischen Implementation Plan (Source of Truth)

**Last Updated:** 2026-01-18

## Current Goal: Zero-Friction Installation

Users should run `zwischen init` and have everything work immediately - no manual tool installation, no service enrollment, no external sign-ups.

---

## Approach: Auto-Install & Open Rulesets

### 1. Auto-Install Gitleaks

**Problem:** Users must manually install gitleaks before using Zwischen.

**Solution:** Auto-download gitleaks binary during `zwischen init`.

- Gitleaks is a standalone Go binary (~15MB)
- No enrollment or sign-up required
- Releases available at: https://github.com/gitleaks/gitleaks/releases
- Install to: `~/.zwischen/bin/gitleaks`
- Update scanner to use this path if system gitleaks not found

**Implementation:**
```ruby
# lib/zwischen/installer.rb
def auto_install_gitleaks
  # Detect platform: linux/darwin, amd64/arm64
  # Download from GitHub releases
  # Extract to ~/.zwischen/bin/gitleaks
  # Make executable
end
```

### 2. Semgrep: Open Rulesets Only

**Problem:** `--config auto` may require Semgrep login/enrollment.

**Solution:** Use explicit open-source rulesets that work without login.

**Rulesets to use:**
- `p/security-audit` - General security vulnerabilities
- `p/secrets` - Secret detection (backup for gitleaks)
- `p/owasp-top-ten` - OWASP Top 10 vulnerabilities

**Implementation:**
```ruby
# lib/zwischen/scanner/semgrep.rb
DEFAULT_CONFIG = "p/security-audit"  # Instead of "auto"
```

**For semgrep installation:**
- Use `pip install semgrep` (no enrollment needed for CLI)
- Or `pipx install semgrep` for isolation
- Falls back gracefully if not installed

### 3. Updated Setup Flow

```
$ zwischen init
🛡️  Installing Zwischen security layer...
  ✓ Installing gitleaks (downloaded to ~/.zwischen/bin/)
  ✓ Checking semgrep (install with: pip install semgrep)
  ✓ Installing pre-push hook
  ✓ Creating config (.zwischen.yml)
  ✓ Done!

Zwischen will now scan automatically before pushes.
```

### 4. Scanner Path Resolution

Scanners should check both system PATH and `~/.zwischen/bin/`:
```ruby
def find_executable(name)
  # Check ~/.zwischen/bin first
  local_path = File.expand_path("~/.zwischen/bin/#{name}")
  return local_path if File.executable?(local_path)

  # Fall back to system PATH
  system("which", name, out: File::NULL) ? name : nil
end
```

---

## Files to Modify

| File | Change |
|------|--------|
| `lib/zwischen/installer.rb` | Add `auto_install_gitleaks` method |
| `lib/zwischen/setup.rb` | Call auto-install during init |
| `lib/zwischen/scanner/base.rb` | Check ~/.zwischen/bin/ for executables |
| `lib/zwischen/scanner/semgrep.rb` | Change default config from "auto" to "p/security-audit" |
| `lib/zwischen/config.rb` | Update DEFAULT_CONFIG for semgrep |
| `.zwischen.yml.example` | Document the open ruleset |

---

## Gitleaks Download Details

**GitHub Releases API:**
```
https://api.github.com/repos/gitleaks/gitleaks/releases/latest
```

**Binary naming convention:**
- `gitleaks_{version}_linux_x64.tar.gz`
- `gitleaks_{version}_linux_arm64.tar.gz`
- `gitleaks_{version}_darwin_x64.tar.gz`
- `gitleaks_{version}_darwin_arm64.tar.gz`

**Installation path:** `~/.zwischen/bin/gitleaks`

---

## Success Criteria

After implementation:

1. **Fresh install test:**
   ```bash
   gem install zwischen
   cd ~/some-project
   zwischen init
   # Should auto-download gitleaks, install hook, create config
   # No manual steps required
   ```

2. **Scan works immediately:**
   ```bash
   zwischen scan
   # Should find secrets using auto-installed gitleaks
   # Should run semgrep if installed (optional)
   ```

3. **No enrollment required:**
   - Gitleaks: standalone binary, no account needed
   - Semgrep: open rulesets only, no login prompts

---

## Implementation Status

| Task | Status |
|------|--------|
| Auto-install gitleaks | ✅ Complete |
| Semgrep open rulesets | ✅ Complete |
| Scanner path resolution | ✅ Complete |
| Update setup flow | ✅ Complete |
| Update config defaults | ✅ Complete |
| Integration testing | ✅ Complete |

---

## Test Results & Integration Notes (2026-01-19)

### 1. Auto-Installation
- **Verified:** `zwischen init` successfully detects missing `gitleaks`, downloads the appropriate binary for the platform/architecture (tested on linux_x64), and installs it to `~/.zwischen/bin/`.
- **Path Resolution:** Scanners correctly prioritize `~/.zwischen/bin/` over the system PATH.

### 2. Gitleaks Integration
- **Compatibility Fix:** Updated `Gitleaks` scanner to support version 8.30.0+ flags.
  - Replaced `--format json` with `--report-format json`.
  - Added `--report-path -` to stream results to stdout for parsing.
- **Verification:** Successfully detected `aws-access-token` in a test `secrets.py` file during `zwischen scan`.

### 3. AI Analysis Status
- **Claude:** Currently the only supported provider. Requires `ANTHROPIC_API_KEY`.
- **Note:** AI analysis is currently skipped or fails if no API key is provided. There is currently no compatibility with local LLMs (like Ollama) or other providers.
- **Graceful Failure:** The system is designed to return raw findings if AI analysis fails or is unavailable.

### 4. Unit Tests
- Added `spec/zwischen/installer_spec.rb` (100% pass).
- Added `spec/zwischen/scanner/base_spec.rb` (100% pass).
- Total test suite: 29 examples, 0 failures.
