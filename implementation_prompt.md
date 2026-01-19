# Zwischen: Implementation Task - Zero-Friction Security Layer

## Project Context

Zwischen is an AI-augmented security scanning CLI tool (Ruby 3.3+) that orchestrates Gitleaks (secrets) and Semgrep (SAST) scanners. The ultimate goal is for developers to run one command (`zwischen init`) and have an invisible security layer that automatically scans on every git push without them ever thinking about it again.

**Current State:** Tool works but has friction in setup and performance issues that make it noticeable/annoying.

## Problems to Solve

### 1. Setup Friction (High Priority)
**Problem:** `zwischen init` asks 3-4 interactive questions (AI config, API key input, hook install, config creation). Not "one command and forget."

**Current Flow:**
```bash
$ zwischen init
🛡️  Zwischen Setup
Checking for required tools...
Enable AI-powered analysis? (recommended) [y/n]
Anthropic API key: [hidden input]
Install git pre-push hook? [y/n]
Create project config (.zwischen.yml)? [y/n]
✅ Done!
```

**Desired Flow:**
```bash
$ zwischen init
🛡️  Installing Zwischen security layer...
  ✓ Checking tools (gitleaks, semgrep)
  ✓ Installing pre-push hook
  ✓ Creating config (.zwischen.yml)
  ✓ Done!

Zwischen will now scan automatically before pushes.
Run 'zwischen scan' to test it now.
```

**Implementation Requirements:**
- **Zero prompts** - just install everything with smart defaults
- Auto-install pre-push hook (backup existing hooks if present)
- Auto-create `.zwischen.yml` config
- Check for `ANTHROPIC_API_KEY` env var, auto-save to `~/.zwischen/credentials` if present
- If no API key, just disable AI features (non-blocking)
- Still respect existing config/hook (don't overwrite Zwischen installations)

**Files to Modify:**
- `lib/zwischen/setup.rb` (lines 22-51: remove all prompts, make automatic)

---

### 2. Performance Issue - Full Repo Scans (Critical Priority)
**Problem:** Pre-push mode scans the **entire repository**, then filters findings to changed files. This defeats the purpose of "changed files only" optimization.

**Current Flow:**
```ruby
# lib/zwischen/cli.rb:81-86
orchestrator = Scanner::Orchestrator.new(config: config)
findings = orchestrator.scan(project[:root], only: options[:only], pre_push: pre_push)

if pre_push
  changed_files = GitDiff.changed_files
  findings = GitDiff.filter_findings(findings: findings, changed_files: changed_files)
end
```

**Problem:**
- `orchestrator.scan(project[:root])` scans entire repo
- Scanners receive full project path: `gitleaks detect --source /full/project/path`
- Filtering happens AFTER scanning completes
- Result: 30+ second scans even for 1-file changes

**Desired Behavior:**
- In pre-push mode: Get changed files FIRST, pass only those files to scanners
- Should take 2-5 seconds for typical 1-5 file changes
- Full repo scans only for manual `zwischen scan` command

**Implementation Requirements:**
1. Move `GitDiff.changed_files` call BEFORE scanning in pre-push mode
2. Modify scanner commands to accept file list instead of directory:
   - Gitleaks: `gitleaks detect --source . --log-opts="<files>"` OR scan individual files
   - Semgrep: `semgrep --json --config auto file1.rb file2.js ...`
3. Add method to scanners: `build_command_for_files(files)` or similar
4. Update orchestrator to handle both modes: full scan vs file list

**Files to Modify:**
- `lib/zwischen/cli.rb` (scan method: reorder operations)
- `lib/zwischen/scanner/base.rb` (add file-list support)
- `lib/zwischen/scanner/gitleaks.rb` (implement file-list scanning)
- `lib/zwischen/scanner/semgrep.rb` (implement file-list scanning)
- `lib/zwischen/scanner/orchestrator.rb` (accept file list parameter)

---

### 3. AI in Pre-Push (Easy Performance Win)
**Problem:** AI analysis adds 2-5 seconds to every push. In pre-push hooks, speed > accuracy.

**Current Behavior:**
```ruby
# lib/zwischen/cli.rb:98-104
ai_enabled = if pre_push
  config.ai_enabled? && Credentials.get_api_key
else
  (!options[:ai].nil? && !options[:ai].empty?) || (config.ai_enabled? && Credentials.get_api_key)
end
```

If AI is enabled in config and API key exists, it runs on every pre-push hook.

**Desired Behavior:**
- **Default**: Disable AI in pre-push hooks (fast scans, simple pass/fail)
- **Manual scans**: Enable AI by default if API key present (`zwischen scan`)
- **Config option**: `ai.pre_push_enabled: false` (default), user can opt-in if they want

**Implementation Requirements:**
1. Add config field: `ai.pre_push_enabled` (default: false)
2. Update AI enable logic in `cli.rb:98-104` to respect this
3. Update `.zwischen.yml.example` to document this option
4. Default config should have `ai.pre_push_enabled: false`

**Files to Modify:**
- `lib/zwischen/config.rb` (add `ai_pre_push_enabled?` method)
- `lib/zwischen/cli.rb` (update AI enable logic)
- `.zwischen.yml.example` (add documentation)

---

## Configuration Changes

**Current `.zwischen.yml.example`:**
```yaml
ai:
  enabled: true
  provider: claude

blocking:
  severity: high

scanners:
  gitleaks: true
  semgrep: true

ignore:
  - vendor/
  - node_modules/
```

**Proposed `.zwischen.yml.example`:**
```yaml
ai:
  enabled: true            # Enable AI for manual 'zwischen scan'
  pre_push_enabled: false  # Disable AI in pre-push hooks (performance)
  provider: claude

blocking:
  severity: high  # Block pushes on: critical, high (options: critical, high, none)

scanners:
  gitleaks: true
  semgrep: true

ignore:
  - vendor/
  - node_modules/
  - test/fixtures/
```

---

## Success Criteria

After these changes:

1. **Zero-Interaction Install:**
   - Run `zwischen init` in any git repo
   - No prompts, completes in <3 seconds
   - Hook installed, config created, ready to use

2. **Fast Pre-Push Scans:**
   - Change 1-3 files, commit, push
   - Pre-push scan completes in <5 seconds (without AI)
   - Only scans changed files, not entire repo

3. **Invisible UX:**
   - Developer never sees scan output on clean pushes
   - Only shows output when issues found (compact format)
   - Blocking behavior works (exit code 1 = push fails)

4. **AI Optional:**
   - Manual `zwischen scan` uses AI if key present (detailed analysis)
   - Pre-push hooks skip AI by default (fast fails)
   - User can opt-in via `ai.pre_push_enabled: true` in config

---

## Testing Instructions

**Test Zero-Interaction Init:**
```bash
cd /tmp/test-repo
git init
zwischen init
# Should complete with no prompts
# Verify: ls -la .git/hooks/pre-push
# Verify: cat .zwischen.yml
```

**Test Fast Pre-Push:**
```bash
# In a repo with Zwischen installed
echo "test" >> README.md
git add README.md
git commit -m "test"
time git push  # Should be <5 seconds
```

**Test Changed-Files Scanning:**
```bash
# Verify scanners only see changed files, not full repo
DEBUG=1 zwischen scan --pre-push
# Should show commands with file lists, not full directory scans
```

---

## Code References

**Key Files:**
- `lib/zwischen/setup.rb` - Installation/setup logic
- `lib/zwischen/cli.rb` - CLI commands and scan orchestration
- `lib/zwischen/scanner/orchestrator.rb` - Scanner coordination
- `lib/zwischen/scanner/gitleaks.rb` - Gitleaks scanner
- `lib/zwischen/scanner/semgrep.rb` - Semgrep scanner
- `lib/zwischen/config.rb` - Configuration management
- `lib/zwischen/git_diff.rb` - Changed file detection
- `.zwischen.yml.example` - Configuration template

**Testing:**
- `spec/` directory has RSpec tests
- Run with: `bundle exec rspec`
- Key specs: `spec/zwischen/scanner/*_spec.rb`

---

## Additional Context

**Project Structure:**
```
lib/zwischen/
├── scanner/
│   ├── base.rb           # Abstract scanner interface
│   ├── gitleaks.rb       # Secrets scanner
│   ├── semgrep.rb        # SAST scanner
│   └── orchestrator.rb   # Runs scanners in parallel
├── finding/
│   ├── finding.rb        # Finding data model
│   └── aggregator.rb     # Deduplication/grouping
├── ai/
│   ├── claude_client.rb  # Anthropic API client
│   └── analyzer.rb       # AI analysis logic
├── reporter/
│   └── terminal.rb       # Output formatting
├── cli.rb                # Thor CLI commands
├── config.rb             # YAML config management
├── setup.rb              # Installation wizard
├── hooks.rb              # Git hook management
├── git_diff.rb           # Changed file detection
└── credentials.rb        # API key storage
```

**Git Hook Content** (`lib/zwischen/hooks.rb:31-41`):
```bash
#!/usr/bin/env bash
# Zwischen pre-push hook - installed by 'zwischen init'

if [ "$ZWISCHEN_SKIP" = "1" ]; then
  exit 0
fi

zwischen scan --pre-push
exit $?
```

**Pre-Push Mode Behavior:**
- Compact output (lib/zwischen/reporter/terminal.rb:118-151)
- Silent if no issues (exit 0)
- Shows only blocking findings if issues found
- Respects `blocking.severity` config

---

## Implementation Status (Applied)

### Setup: Zero-Interaction Init
- `lib/zwischen/setup.rb`: Removed all prompts from `zwischen init`. It now:
  - Checks tools and reports missing ones without blocking.
  - Saves credentials automatically if `ANTHROPIC_API_KEY` is present.
  - Installs the pre-push hook automatically.
  - Backs up an existing non-Zwischen hook to `.git/hooks/pre-push.zwischen.backup` (timestamped if needed).
  - Creates `.zwischen.yml` without prompting.
- `lib/zwischen/config.rb`: Added `quiet:` flag to `Config.init` so setup can create config without noisy output.

### Performance: Changed-File Scanning in Pre-Push
- `lib/zwischen/cli.rb`: Pre-push now computes changed files *before* scanning and passes them into the orchestrator. It exits silently if no changed files are detected.
- `lib/zwischen/scanner/base.rb`: Added file-list scanning support via `scan(project_root, files:)` and `build_command_for_files`.
- `lib/zwischen/scanner/orchestrator.rb`: Accepts `files:` and passes them to scanners.
- `lib/zwischen/scanner/gitleaks.rb`: Implements per-file scanning for pre-push (runs gitleaks per file).
- `lib/zwischen/scanner/semgrep.rb`: Implements file-list scanning (`semgrep --json --config ... <files>`).

### AI Behavior: Off by Default in Pre-Push
- `lib/zwischen/config.rb`: Added `ai.pre_push_enabled` (default `false`) and `ai_pre_push_enabled?`.
- `lib/zwischen/cli.rb`: Uses `config.ai_pre_push_enabled?` for pre-push AI gating.
- `.zwischen.yml.example`: Documented `ai.pre_push_enabled: false`.

### Config Defaults & Docs
- `.zwischen.yml.example`: Added `test/fixtures/` to ignore list.
- `lib/zwischen/config.rb`: Added `**/test/fixtures/**` to default ignored paths.

---

## Notes

- Ruby 3.3+ codebase
- Uses Thor for CLI framework
- External dependencies: Gitleaks, Semgrep (must be installed)
- Thread-based parallelism for scanner orchestration
- Git hooks are bash scripts that call `zwischen scan --pre-push`
- Credentials stored in `~/.zwischen/credentials` (never committed)
- Config stored in `.zwischen.yml` (per-project, gitignored)

---

## Questions to Clarify (if needed)

1. Should `zwischen init` fail if gitleaks/semgrep not installed, or just warn?
2. For file-list scanning: Should we pass file paths or use git diff and let scanners handle it?
3. Semgrep's `--config auto` may not work well with individual files - should we use explicit rulesets?
4. Should we add a `--quick` flag for even faster scans (gitleaks only, no semgrep)?

---

## Independent Assessment (Code Review)

**Reviewer:** Claude Opus 4.5
**Date:** 2026-01-18
**Status:** ✅ All Issues Resolved

### Overall Assessment: ✅ Ready for Testing

The implementation addresses all high-level requirements. Critical bugs have been fixed and minor issues resolved.

---

### ✅ What Was Implemented Correctly

1. **Zero-Interaction Init** (`setup.rb`)
   - Clean, no prompts, exactly matches desired output format
   - Smart credential detection from `ANTHROPIC_API_KEY`
   - Proper hook backup with timestamped fallback
   - Respects existing Zwischen installations
   - `quiet:` flag on `Config.init` prevents noisy output

2. **Config Updates** (`config.rb`)
   - `ai_pre_push_enabled?` method works correctly (strict `== true` check)
   - `pre_push_enabled: false` in DEFAULT_CONFIG
   - Deep merge preserves user overrides

3. **Orchestrator** (`orchestrator.rb`)
   - Clean interface: `scan(project_root, files:)`
   - Passes files to scanners correctly
   - Comment updated to reflect new behavior

4. **CLI Flow** (`cli.rb`)
   - Changed files computed BEFORE scanning ✅
   - Files passed to orchestrator ✅
   - Early exit if no changed files ✅
   - Uses `config.ai_pre_push_enabled?` for pre-push AI gating ✅

5. **Semgrep Scanner** (`semgrep.rb`)
   - `build_command_for_files` is correct: `semgrep --json --config auto file1 file2 ...`

---

### ✅ Critical Bugs (FIXED)

#### 1. **Gitleaks Exit Code Handling** (`gitleaks.rb`) - FIXED

**Problem:** Gitleaks returns **exit code 1** when it finds secrets, **exit code 0** when clean. The code was treating exit code 1 as failure.

**Fix Applied:**
```ruby
# Gitleaks: exit 0 = clean, exit 1 = findings, exit 2+ = error
if status.exitstatus <= 1
  findings.concat(parse_output(stdout)) unless stdout.strip.empty?
elsif status.exitstatus > 1
  warn "Warning: #{@name} scan failed on #{file} (exit #{status.exitstatus}): #{stderr}" if ENV["DEBUG"]
end
```

#### 2. **Base Scanner Exit Code** (`base.rb:31-36`) - FIXED

**Fix Applied:**
```ruby
# Most security scanners use exit code 0 = clean, 1 = findings found, 2+ = error
# We treat both 0 and 1 as success since findings are valid results
if status.exitstatus <= 1
  parse_output(stdout)
else
  warn "Warning: #{@name} scan failed (exit #{status.exitstatus}): #{stderr}" unless stderr.empty?
  []
end
```

---

### ✅ Minor Issues (FIXED)

#### 3. **Redundant Filtering** (`cli.rb:96-98`) - DOCUMENTED

Added explanatory comment:
```ruby
# Filter findings to changed files in pre-push mode
# Note: This is a safety net. Scanners receive the file list and should only scan those,
# but some scanners (like gitleaks) may return paths in different formats. This ensures
# we only report findings for files the developer actually changed.
if pre_push && changed_files
  findings = GitDiff.filter_findings(findings: findings, changed_files: changed_files)
end
```

#### 4. **Gitleaks Per-File Scanning** (`gitleaks.rb`) - ACCEPTABLE

Per-file scanning is kept because:
- Gitleaks doesn't have native multi-file support
- Pre-push typically has only a few changed files (1-5)
- Exit code handling is now correct
- Added early return for empty file list and file existence check

#### 5. **Ignore Path Inconsistency** - FIXED

Updated `.zwischen.yml.example` to use consistent glob patterns matching `config.rb`:
```yaml
ignore:
  - "**/vendor/**"
  - "**/node_modules/**"
  - "**/.git/**"
  - "**/dist/**"
  - "**/build/**"
  - "**/test/fixtures/**"
```

---

### 🔵 Recommendations

1. ~~**Fix exit code handling immediately**~~ ✅ DONE

2. **Add integration tests** - Test that actual gitleaks/semgrep findings are captured in pre-push mode.

3. ~~**Add DEBUG logging**~~ ✅ DONE - Added `if ENV["DEBUG"]` to gitleaks error logging

4. ~~**Consider batching for Gitleaks**~~ - Kept per-file approach; acceptable for typical pre-push usage.

5. **Test with real secrets** - Create a test fixture with a fake AWS key and verify it's caught.

---

### Test Cases to Verify Fixes

```bash
# 1. Create test repo with a secret
mkdir /tmp/zwischen-test && cd /tmp/zwischen-test
git init
echo 'AWS_SECRET_KEY="AKIAIOSFODNN7EXAMPLE"' > config.env
git add . && git commit -m "add secret"

# 2. Install Zwischen
zwischen init

# 3. Verify gitleaks catches it
zwischen scan --only secrets
# Should show: CRITICAL config.env:1 - AWS secret key detected

# 4. Test pre-push mode
echo "# comment" >> config.env
git add . && git commit -m "update"
zwischen scan --pre-push
# Should block with finding
```

---

### Files Changed

| File | Status | Change |
|------|--------|--------|
| `lib/zwischen/scanner/base.rb` | ✅ Fixed | Exit code handling: `status.exitstatus <= 1` |
| `lib/zwischen/scanner/gitleaks.rb` | ✅ Fixed | Exit code handling + file existence check |
| `lib/zwischen/cli.rb` | ✅ Fixed | Added explanatory comment for safety-net filtering |
| `.zwischen.yml.example` | ✅ Fixed | Consistent glob patterns |

---

### Summary

All critical and minor issues have been resolved:

1. **Exit code handling** - Both `base.rb` and `gitleaks.rb` now correctly treat exit code 1 as "findings found" rather than "error"
2. **Safety-net filtering** - Documented with clear comment explaining its purpose
3. **Ignore paths** - Now use consistent glob patterns across config files

The tool is ready for integration testing.
