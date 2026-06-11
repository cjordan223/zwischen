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
  Critical: 7
  High: 3

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
    💡 Fix: Remove the AWS access token from the file and store it in an
       environment variable or AWS Secrets Manager. Verify the IAM policy
       attached to the token has the principle of least privilege. Rotate
       the key immediately and add the file to .gitignore.
    ⚠️  Risk: An exposed AWS access token can grant attackers full access
       to the associated AWS resources, leading to data loss,
       infrastructure tampering, or financial damage.

📄 config/secrets.js
------------------------------------------------------------
  🔴 HIGH config/secrets.js:10
    Found a Stripe Access Token [...]
    Rule: stripe-access-token
    💡 Fix: Remove the Stripe test secret key from the source. Store it
       in an environment variable or a secrets manager. Rotate the key if
       it has been exposed, and add the file to .gitignore.
    ⚠️  Risk: Exposing a Stripe secret key can allow attackers to
       manipulate payment processing, create fraudulent charges, or
       access sensitive customer financial information.

📄 routes/users.js
------------------------------------------------------------
  🔴 CRITICAL routes/users.js:10
    Detected user input used to manually construct a SQL string. [...]
    💡 Fix: Replace the manual string concatenation with a parameterized
       query. For example, if using PostgreSQL with pg, use $1
       placeholders and pass the values as an array. If you use an ORM
       (Sequelize, Knex), let it build the query for you. Never
       interpolate raw user input into SQL strings.
    ⚠️  Risk: Manual string concatenation of user data into SQL opens the
       door to SQL injection, which can read, modify, or delete data in
       the database.
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
