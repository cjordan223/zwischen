# Zwischen End-to-End Testing

This guide verifies Zwischen as an installed Ruby gem, not from source. The installed-gem path matters because end users run the generated executable and packaged files.

Run the tests from a temporary directory outside the repository, such as `/tmp/zwischen-test-*`.

## Install the Gem Under Test

```bash
cd /path/to/zwischen
./scripts/test_as_gem.sh

export PATH="$HOME/.local/share/gem/ruby/$(ruby -e 'puts RUBY_VERSION[/\d+\.\d+/]')/bin:$PATH"

which zwischen
zwischen --help
```

Expected:

- `which zwischen` points at the user gem bin path, not this repository's `bin/zwischen`.
- `zwischen --help` lists `doctor`, `init`, `scan`, and `uninstall`.

## Test Suite 1: Installation and Init

### Test 1.1: Gem Installation

```bash
gem list zwischen
gem which zwischen
zwischen --help
```

Expected:

- `gem list zwischen` includes the version under test.
- `gem which zwischen` resolves to the installed gem.
- Help exits successfully without opening a pager.

### Test 1.2: Init in a Git Repository

```bash
TEST_DIR=$(mktemp -d -t zwischen-test-XXXXXX)
cd "$TEST_DIR"
mkdir test-repo && cd test-repo
git init
git config user.email test@example.com
git config user.name "Zwischen Test"
printf "# Test\n" > README.md
git add README.md
git commit -m "Initial"
zwischen init
```

Expected:

- `.zwischen.yml` exists.
- `.git/hooks/pre-push` exists and is executable.
- The hook contains `Zwischen pre-push hook`.
- `~/.zwischen/bin/gitleaks` exists when auto-install succeeds, or `zwischen init` prints the manual install command when it cannot auto-install.
- `~/.zwischen/credentials` is created only when `ANTHROPIC_API_KEY` was set before running `zwischen init`.

### Test 1.3: Config Structure

```bash
ruby -ryaml -e 'p YAML.safe_load(File.read(".zwischen.yml")).keys'
zwischen doctor
```

Expected:

- Config includes `ai`, `blocking`, `scanners`, and `ignore`.
- `zwischen doctor` reports Gitleaks status and Semgrep status without crashing.

## Test Suite 2: Pre-Push Hook

### Test 2.1: Clean Push Path

```bash
printf "def hello():\n    pass\n" > test.py
git add test.py
git commit -m "Add clean file"
.git/hooks/pre-push
echo $?
```

Expected:

- Hook exits `0`.
- Hook is silent when no changed files or no blocking findings are detected.

### Test 2.2: Blocking Finding

```bash
cat > config.env <<'EOF'
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
EOF
git add config.env
git commit -m "Add secret"
.git/hooks/pre-push
echo $?
```

Expected:

- Hook exits `1` when Gitleaks maps the finding to `high` or `critical`.
- Compact output starts with `Zwischen:` and lists severity, file, line, and message.
- Output includes the push-blocked guidance.

### Test 2.3: Bypass Mechanisms

Expected:

- `git push --no-verify` bypasses Git hooks.
- `ZWISCHEN_SKIP=1 .git/hooks/pre-push` exits `0`.

## Test Suite 3: Manual Scan Commands

### Test 3.1: Standard Scan

```bash
zwischen scan
echo $?
```

Expected:

- Prints the scanning banner and full terminal report when findings exist.
- Exits `1` when findings meet the configured blocking severity.
- Exits `0` when no blocking findings exist.

### Test 3.2: JSON Output

```bash
zwischen scan --format json
```

Expected:

- Prints valid JSON with `summary` and `findings`.
- Exit code still reflects configured blocking behavior.

### Test 3.3: Scanner Selection

```bash
zwischen scan --only secrets
zwischen scan --only sast
zwischen scan --only secrets,sast
```

Expected:

- `secrets` selects Gitleaks.
- `sast` selects Semgrep.
- Missing scanners are skipped with a warning outside pre-push mode.

### Test 3.4: Changed Files Filtering

```bash
cat > changed.env <<'EOF'
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
EOF
git add changed.env
git commit -m "Add changed secret"

cat > uncommitted.env <<'EOF'
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
EOF
zwischen scan --pre-push
```

Expected:

- Pre-push mode only reports findings from files returned by `GitDiff.changed_files`.
- Uncommitted files outside that diff are not reported.

### Test 3.5: SARIF Output

```bash
zwischen scan --format sarif
```

Expected:

- Prints valid SARIF 2.1.0 JSON (`version`, `runs[0].tool.driver.name == "Zwischen"`).
- File URIs are project-relative.
- Exit code still reflects configured blocking behavior.
- With no findings, prints an empty SARIF document and exits `0`.

### Test 3.6: Changed-Only Manual Scan

```bash
zwischen scan --changed
```

Expected:

- Only files changed since the default branch are scanned and reported.
- Exits `0` silently when there are no changed files.

## Test Suite 4: Blocking Configuration

### Test 4.1: Default Blocking

```yaml
blocking:
  severity: high
```

Expected:

- `critical` and `high` findings block.
- `medium`, `low`, and `info` findings do not block.

### Test 4.2: Critical Only

```yaml
blocking:
  severity: critical
```

Expected:

- `critical` findings block.
- `high` findings do not block.

### Test 4.3: No Blocking

```yaml
blocking:
  severity: none
```

Expected:

- Findings may be reported.
- Scan exits `0`.
- Pre-push hook allows the push.

## Test Suite 5: Uninstall

### Test 5.1: Remove Zwischen Hook

```bash
zwischen uninstall
# Answer y for hook removal.
# Answer n for config removal unless testing config deletion.
# Answer n for credentials removal unless testing credentials deletion.
```

Expected:

- Zwischen hook is removed.
- `.zwischen.yml` is preserved when answering `n`.
- `~/.zwischen/credentials` is preserved when answering `n`.

### Test 5.2: Preserve Non-Zwischen Hook

```bash
printf "#!/bin/sh\nprintf 'custom hook\\n'\n" > .git/hooks/pre-push
chmod +x .git/hooks/pre-push
zwischen uninstall
```

Expected:

- Custom hook remains because it does not contain the Zwischen marker.
- Uninstall reports that no Zwischen hook was found.

## Test Suite 6: Edge Cases

### Test 6.1: No Git Repository

```bash
NO_GIT_DIR=$(mktemp -d -t zwischen-no-git-XXXXXX)
cd "$NO_GIT_DIR"
zwischen init
```

Expected:

- Config is created.
- Hook installation is skipped with a warning.

### Test 6.2: Existing Pre-Push Hook

```bash
cd "$TEST_DIR/test-repo"
printf "#!/bin/sh\nprintf 'existing hook\\n'\n" > .git/hooks/pre-push
chmod +x .git/hooks/pre-push
zwischen init
```

Expected for the current Ruby implementation:

- Existing hook is copied to `.git/hooks/pre-push.zwischen.backup` or a timestamped variant.
- New Zwischen hook replaces `.git/hooks/pre-push`.


### Test 6.3: Default Branch Detection

Expected:

- Remote `origin` HEAD is preferred when available.
- Local `main` is used before local `master`.
- `HEAD` is the final fallback.

## Test Suite 7: AI Integration

### Test 7.1: Claude

```bash
ANTHROPIC_API_KEY=... zwischen scan --ai claude
```

Expected:

- AI analysis runs after scanner findings are aggregated.
- Findings may include fix suggestions and risk explanations.
- AI failures fall back to original findings without aborting the scan.

### Test 7.2: Ollama

```bash
ollama pull llama3
ollama serve
zwischen scan --ai ollama
```

Expected:

- Ollama analysis runs against the configured local URL.
- If Ollama is not running, scan continues without AI and prints an AI warning outside pre-push mode.

### Test 7.3: AI Disabled for Pre-Push

```yaml
ai:
  enabled: true
  pre_push_enabled: false
```

Expected:

- Manual `zwischen scan` can use AI.
- `zwischen scan --pre-push` does not use AI unless `pre_push_enabled` is `true`.

## Report Template

```markdown
# Zwischen Test Report

## Environment
- Ruby version:
- Gem location:
- Test directory:
- Gitleaks version:
- Semgrep version:

## Results
- Test 1.1:
- Test 1.2:
- Test 1.3:
- Test 2.1:
- Test 2.2:
- Test 2.3:
- Test 3.1:
- Test 3.2:
- Test 3.3:
- Test 3.4:
- Test 3.5:
- Test 3.6:
- Test 4.1:
- Test 4.2:
- Test 4.3:
- Test 5.1:
- Test 5.2:
- Test 6.1:
- Test 6.2:
- Test 6.3:
- Test 7.1:
- Test 7.2:
- Test 7.3:

## Failures

## Notes

## Overall Status
```

## Cleanup

```bash
gem uninstall zwischen --user-install
rm -rf /tmp/zwischen-test-* /tmp/zwischen-no-git-*
```
