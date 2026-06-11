# Raw scanner output vs. AI triage

The output below is from a real run of `zwischen scan` against
[zwischen-demo](https://github.com/cjordan223/zwischen-demo), an intentionally
vulnerable Express app. The AI pass used a fully local model (`gpt-oss` via
Ollama) — nothing left the machine. Outputs are trimmed to three of the ten
findings; both runs found the same ten.

## Before: what the scanners say

Gitleaks and Semgrep are precise about *what matched*, and silent about
*what to do*:

```text
============================================================
Zwischen Security Scan Results
============================================================

Total Findings: 10

By Severity:
  Critical: 6
  High: 3
  Medium: 1

📄 .env.production
------------------------------------------------------------
  🔴 HIGH .env.production:3
    Identified a pattern that may indicate AWS credentials, risking
    unauthorized cloud resource access and data breaches on AWS platforms.
    Rule: aws-access-token

📄 config/secrets.js
------------------------------------------------------------
  🔴 HIGH config/secrets.js:10
    Found a Stripe Access Token, posing a risk to payment processing
    services and sensitive financial data.
    Rule: stripe-access-token

📄 routes/users.js
------------------------------------------------------------
  🔴 CRITICAL routes/users.js:10
    Detected user input used to manually construct a SQL string. [...]
    Rule: javascript.express.security.injection.tainted-sql-string
```

Ten findings, six of them critical, in rule-ID vocabulary. The reader still
has to answer the real questions themselves: *which of these is urgent, and
what exactly do I change?*

## After: the same scan with `--ai ollama`

Each finding now carries a concrete fix and an explanation of the actual
risk, written against the project's context (Express app):

```text
📄 .env.production
------------------------------------------------------------
  🔴 HIGH .env.production:3
    Identified a pattern that may indicate AWS credentials [...]
    Rule: aws-access-token
    💡 Fix: Remove the AWS access key from the environment file and rotate
       the credentials immediately. Store AWS credentials in a dedicated
       credentials file with limited permissions or in an IAM role if
       running on AWS infrastructure. Use environment variables or the
       AWS SDK's credential provider chain.
    ⚠️  Risk: Exposed AWS access keys can grant full access to cloud
       resources, leading to data theft, infrastructure tampering, or
       accidental public exposure.

📄 config/secrets.js
------------------------------------------------------------
  🔴 HIGH config/secrets.js:10
    Found a Stripe Access Token [...]
    Rule: stripe-access-token
    💡 Fix: Remove the Stripe secret from the codebase. Store it in a
       secure environment variable and use Stripe's official SDK to load
       it at runtime. Ensure that production secrets are only available
       in the production environment.
    ⚠️  Risk: Exposing Stripe secret keys can allow attackers to create
       charges, refund payments, or access transaction data.

📄 routes/users.js
------------------------------------------------------------
  🔴 CRITICAL routes/users.js:10
    Detected user input used to manually construct a SQL string. [...]
    💡 Fix: Replace manual SQL string concatenation with parameterized
       queries. For example, use
       db.query('SELECT * FROM users WHERE id = ?', [req.params.id]).
       If you use an ORM like Sequelize, let it handle query construction.
    ⚠️  Risk: Manually concatenating user input into SQL statements allows
       attackers to inject malicious SQL, which can read, modify, or
       delete data in the database.
```

## What the AI layer is allowed to do

The model annotates; the scanners decide. AI cannot add findings, and a
false-positive verdict only affects blocking — the finding stays in the
report, marked `[FALSE POSITIVE]`, so the human always sees what was
downgraded and why.

The same annotations flow into machine-readable output: `--format sarif`
embeds each fix suggestion in the SARIF message, so GitHub code scanning
alerts show the remediation inline.

## Reproduce it

```bash
git clone https://github.com/cjordan223/zwischen-demo && cd zwischen-demo
gem install zwischen && zwischen init
zwischen scan --ai ollama    # or --ai claude / --ai openai with an API key
```

Model quality matters: in our runs, `gpt-oss` produced accurate verdicts on
all ten findings, while a smaller code-tuned model incorrectly flagged two
real injection vulnerabilities as false positives. If triage verdicts drive
decisions, prefer a larger general model — or keep `blocking.severity` strict
so the deterministic layer has the final word.
