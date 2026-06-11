# Zwischen v0.1.1 Round 2 Testing Report

Test root: `/tmp/zw2-4u4Pyb`

Round 2 was run against published packages from Rubygems, npm, and PyPI. Product source was not modified; this report is the only repo file changed.

## 1. Environment

| Item | Observed |
| --- | --- |
| OS | Darwin 25.5.0, arm64 |
| Git | 2.50.1 (Apple Git-155) |
| Ruby | Homebrew Ruby 4.0.3 |
| Ruby 3.3 floor | rbenv Ruby 3.3.11 installed during this run |
| Node / npm | Node v25.9.0 / npm 11.12.1 |
| Python | 3.14.5 |
| Docker | 29.1.3, daemon available |
| act | Not installed |
| Semgrep | 1.165.0 |
| Ollama | `127.0.0.1:11434`, model `llama3.2:latest` |
| Ruby package | `zwischen` 0.1.1 |
| npm package | `zwischen` 0.1.1 |
| PyPI package | `zwischen-cli` 0.1.1 |

Note: as in round 1, Homebrew Semgrep fails inside the filesystem sandbox with a macOS trust-anchor error. Semgrep-dependent tests were run outside the sandbox, with all test repos and HOME values still under `/tmp/zw2-4u4Pyb`.

## 2. Scorecard

| ID | Result | Notes |
| --- | --- | --- |
| Registry gate | PASS | Ruby, npm, and PyPI all installed 0.1.1. |
| A1 | PASS | `blocking.severity: critical` with high-only AWS finding exited 0. |
| A2 | PASS | `blocking.severity: none` exited 0 and still printed the high finding. |
| A3 | PASS | `blocking.severity: high` exited 1 for the high finding. |
| A4 | PASS | npm and pip wrappers honored `ignore:` and omitted `ignored.env`. |
| A5 | PASS | npm and pip JSON stdout parsed directly, included `summary` and `findings`, and used relative `file` paths. |
| A6 | PASS | npm and pip SARIF requests exited 2, wrote clear unsupported-wrapper errors to stderr, and left stdout empty. |
| A7 | PASS | pip `zwischen --version` printed `zwischen, version 0.1.1` and exited 0. |
| A8 | PASS | Ruby JSON `findings[*].file` values were project-relative. |
| A9 | PASS | Ruby `scan --changed` reported committed-ahead, staged-only, and untracked secret files. |
| A10 | PASS | Ollama finding count stayed 10. Attempt 2 produced `Fix`/`Risk` annotations; parse-failure attempts warned and preserved raw findings. Dead-port fail-open preserved findings and exit code. |
| B1 | PASS | Custom `core.hooksPath` and linked worktree pushes were blocked. Real Husky push was blocked after bypassing Husky's generated failing pre-commit for commit creation. |
| B2 | PASS | Ruby 3.3.11 installed the gem, `init` installed gitleaks, and demo scan returned 10 findings. |
| B3 | PASS | Linux Ruby container auto-installed gitleaks, found the secret, and blocked a local push. Node and pip wrapper containers found the planted secret. |
| B4 | PASS | Offline init exited 0 with manual install hints and created config/hook. Offline scan warned `No scanners available` without crashing. |
| B5 | PASS with caveat | Generated SARIF validated against SchemaStore SARIF 2.1.0. The exact OASIS raw URL from the test plan returned 404. |
| B6 | FAIL | Express scans were fine, but 20-file clean pre-push median was 5.14s, above the ~3s budget. |
| B7 | SKIPPED | `act` is not installed. |

## 3. Benchmarks

| Benchmark | Round 1 | Round 2 | Change |
| --- | ---: | ---: | ---: |
| Ruby gem install | 3.984s | 4.18s | +4.9% |
| npm install | 1.116s | 1.18s | +5.7% |
| pip install | 2.560s | 2.34s | -8.6% |
| Demo gitleaks-only scan median | 0.408s | 0.387s | -5.1% |
| Demo gitleaks+Semgrep scan median | 2.096s | 2.292s | +9.4% |
| Ollama AI scan | 24.936s | 13.210s annotated run | -47.0% |
| Dead-port AI fail-open | 2.796s | 2.226s | -20.4% |
| Huge 50MB file scan | 4.609s | not repeated | n/a |
| Clean pre-push hook, 1-file median | 1.786s | not repeated | n/a |
| Express full scan, gitleaks-only | n/a | 0.37s, max RSS 82 MB | n/a |
| Express full scan, gitleaks+Semgrep | n/a | 2.82s, max RSS 354 MB | n/a |
| Express clean pre-push, 20 files | n/a | median 5.14s, max RSS 247-297 MB | over ~3s budget |

No directly comparable round-1 benchmark regressed by more than 25%. The new B6 20-file hook benchmark misses the design budget.

## 4. Bugs / Findings

### Major: 20-file clean pre-push latency exceeds budget

Repro:

1. Clone `expressjs/express`.
2. Configure Zwischen with gitleaks and Semgrep enabled.
3. Push five clean commits, each changing 20 files, to a local bare origin.
4. Time each `git push` with `/usr/bin/time -l`.

Expected: hook stays near the documented ~3s budget.

Actual: runs were 5.50s, 5.19s, 5.11s, 5.07s, and 5.14s; median 5.14s.

Evidence: `/tmp/zw2-4u4Pyb/b6_scale.log`.

### Observation: Husky hook is backed up and replaced, not merged

In a real Husky v9 setup, `core.hooksPath` was `.husky/_`. `zwischen init` backed up `.husky/_/pre-push` to `.husky/_/pre-push.zwischen.backup` and replaced `.husky/_/pre-push` with the Zwischen hook. A secret push was blocked, and `.husky/pre-commit` remained. This satisfies the blocking assertion, but it is replacement-with-backup rather than inline coexistence.

Evidence: `/tmp/zw2-4u4Pyb/b1_hooks.log`, `/tmp/zw2-4u4Pyb/b1_husky_followup.log`.

### External test-plan issue: OASIS SARIF schema URL returns 404

The requested URL `https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json` returned 404, as did the same path on `main`. The generated SARIF validated successfully against `https://www.schemastore.org/sarif-2.1.0.json`.

Evidence: `/tmp/zw2-4u4Pyb/b5_sarif.log`, `/tmp/zw2-4u4Pyb/b5_schemastore_validation.log`.

## 5. Docs Drift

| Claim | Observed |
| --- | --- |
| Round-1 fixed bugs should pass in v0.1.1 | Confirmed for A1-A10. |
| Hook-manager coexistence | Blocking works for custom hooksPath, real Husky, and linked worktree. Real Husky's generated pre-push shim is backed up and replaced. |
| SARIF official schema URL in test plan | The exact OASIS raw URL returns 404; SchemaStore validation passes. |
| Hook budget around 3s | New 20-file Express benchmark median is 5.14s. |

## 6. Wrapper Parity Matrix

| Feature | Ruby gem | npm wrapper | pip wrapper |
| --- | --- | --- | --- |
| Published install at 0.1.1 | PASS | PASS | PASS |
| `--version` | Falls back to `gem list` | PASS | PASS |
| `init` | PASS | PASS | PASS |
| `scan` | PASS | PASS | PASS |
| `doctor` | PASS | PASS | PASS |
| `scan --format json` | PASS, pure JSON with relative paths | PASS, pure JSON with `summary` | PASS, pure JSON with `summary` |
| `scan --format sarif` | PASS | PASS, exits 2 unsupported | PASS, exits 2 unsupported |
| `ignore:` globs | PASS | PASS | PASS |
| `uninstall` | PASS | Not supported, accepted gap | Not supported, accepted gap |
| `--only` | PASS | Not supported, accepted gap | Not supported, accepted gap |
| `--changed` | PASS | Not supported, accepted gap | Not supported, accepted gap |

## 7. Raw Evidence

Key logs and outputs:

- `/tmp/zw2-4u4Pyb/a_regressions.log`
- `/tmp/zw2-4u4Pyb/b1_hooks.log`
- `/tmp/zw2-4u4Pyb/b1_husky_followup.log`
- `/tmp/zw2-4u4Pyb/b2_ruby33.log`
- `/tmp/zw2-4u4Pyb/b3_docker.log`
- `/tmp/zw2-4u4Pyb/b3_ruby_followup.log`
- `/tmp/zw2-4u4Pyb/b4_offline.log`
- `/tmp/zw2-4u4Pyb/b5_sarif.log`
- `/tmp/zw2-4u4Pyb/b5_schemastore_validation.log`
- `/tmp/zw2-4u4Pyb/b6_scale.log`
- `/tmp/zw2-4u4Pyb/round1_compare_bench.log`
