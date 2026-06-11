# Why Zwischen blocks your push instead of your pull request

Most security scanning happens in CI. You push, a pipeline runs, and five
minutes later a bot tells you the secret you just committed is now part of
your repository's permanent history. The feedback arrives after the one
moment it could have been cheap to act on.

Zwischen ("between" in German) sits in the gap between *commit* and *push* —
the last point where a leaked credential is still a local problem. This
write-up covers the three design decisions that shaped it.

## Decision 1: pre-push, not pre-commit, not CI-only

There are three places a scanner can live, and they fail differently.

**Pre-commit hooks** run constantly. Commit-heavy workflows (WIP commits,
fixup commits, `git commit -am` muscle memory) mean a slow scanner gets
bypassed with `--no-verify` within a week — developers optimize away
friction faster than security teams can add it. A scanner nobody runs
catches nothing.

**CI-only scanning** is too late for secrets. Once a key is pushed, it's in
the remote history: rotating it is mandatory, scrubbing it is painful, and
any fork or mirror made in the window has a copy. CI is the right place for
deep SAST passes that take minutes; it's the wrong place for the "you are
about to leak a credential" check.

**Pre-push** is the compromise: it runs maybe a dozen times a day instead of
a hundred, so a 1–3 second scan is tolerable. And it fires at exactly the
boundary where a finding changes category from "local mistake" to
"incident."

The hook is deliberately mundane — a five-line bash script that calls
`zwischen scan --pre-push` and propagates the exit code. Mundane is a
feature: anyone can read it in five seconds, and both standard escape
hatches (`git push --no-verify`, `ZWISCHEN_SKIP=1`) work, because a hook you
can't bypass in an emergency is a hook that gets uninstalled.

In pre-push mode, scanners receive only the files changed since the remote
branch, and findings are filtered to that set again afterwards as a safety
net. Scanning the diff instead of the project keeps the hook fast and the
output relevant: you're never blocked for a problem someone else committed
last year.

## Decision 2: orchestrate scanners, don't reinvent them

Gitleaks and Semgrep are excellent. What they're bad at is being one tool:
different invocations, different JSON shapes, different severity vocabularies,
different exit-code conventions. Zwischen's scanner layer is a thin adapter
per tool — build the command, parse the JSON, normalize severities into one
five-level scale — plus an orchestrator that runs the adapters in threads,
flattens the results, and applies ignore globs from `.zwischen.yml`.

The interesting work is in the defaults, not the architecture. `zwischen
init` downloads a pinned gitleaks release into `~/.zwischen/bin` when it's
missing, because "first install gitleaks" is where most developers abandon a
tool like this. Semgrep stays optional and uses open rulesets that work
without an account. The goal is that `init` is the only command anyone is
required to learn.

## Decision 3: AI as triage, not as scanner

The tempting design is to let a language model scan code directly. It's also
the wrong one: LLM scanning is slow, non-deterministic, and unverifiable —
three properties you cannot accept in something that blocks pushes.

So Zwischen inverts it. Deterministic scanners decide *what exists*; the
model only annotates *what to do about it*. Aggregated findings go to the
provider — Claude, OpenAI, or a local model via Ollama — with the project
type for context, and the model returns structured JSON per finding:
priority, false-positive verdict, a concrete fix, and a risk explanation.
Those annotations are attached to the findings, never substituted for them.

This split keeps every failure mode safe:

- **AI unavailable?** The scan completes with raw findings; analysis is a
  layer, not a dependency.
- **AI hallucinating?** It can reorder and annotate, but it cannot invent a
  finding, and a false-positive verdict only downgrades blocking — the
  finding stays visible and marked in the report.
- **Privacy concerns?** Point the provider at Ollama and nothing leaves the
  machine — local-first AI is a config line, not a fork.

Raw scanner output answers "what matched a pattern?" Triage answers the
question developers actually have, which is "what do I fix first, and how?"
A wall of twelve findings in rule-ID vocabulary gets ignored; a ranked list
with one-line fixes gets actioned. The before/after in
[triage-example.md](triage-example.md) shows the difference on a real scan.

By default AI runs only on manual scans, not in the hook (`pre_push_enabled:
false`) — blocking decisions stay fast and deterministic, and you opt into
the latency where it pays off.

## The shape of the whole thing

Each decision is a moat against the failure mode that kills developer
security tools: friction. Friction at install (solved: one command, scanners
auto-provisioned), friction per-push (solved: diff-only scans, quiet-by-default
hook, real escape hatches), and friction at triage (solved: the model reads
the wall of findings so you don't have to).

The result is a tool whose happy path is invisible. You run `zwischen init`
once, and the next time you hear from it is the moment it saves you from
rotating an AWS key at 5pm on a Friday.
