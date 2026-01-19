const { execSync, spawnSync } = require('child_process');
const path = require('path');
const fs = require('fs');
const { getGitleaksPath } = require('./installer');
const { loadConfig } = require('./config');
const { analyzeWithAI } = require('./ai');

function runGitleaks(projectRoot, files = null) {
  const gitleaksPath = getGitleaksPath();
  if (!gitleaksPath) {
    return [];
  }

  const findings = [];

  try {
    if (files && files.length > 0) {
      // Scan specific files
      for (const file of files) {
        const filePath = path.join(projectRoot, file);
        if (!fs.existsSync(filePath)) continue;

        const result = spawnSync(gitleaksPath, [
          'detect',
          '--source', filePath,
          '--report-format', 'json',
          '--report-path', '-',
          '--no-git'
        ], { encoding: 'utf8', cwd: projectRoot });

        if (result.stdout) {
          try {
            const parsed = JSON.parse(result.stdout);
            findings.push(...(Array.isArray(parsed) ? parsed : []));
          } catch {}
        }
      }
    } else {
      // Scan entire project
      const result = spawnSync(gitleaksPath, [
        'detect',
        '--source', projectRoot,
        '--report-format', 'json',
        '--report-path', '-',
        '--no-git'
      ], { encoding: 'utf8', cwd: projectRoot });

      if (result.stdout) {
        try {
          const parsed = JSON.parse(result.stdout);
          findings.push(...(Array.isArray(parsed) ? parsed : []));
        } catch {}
      }
    }
  } catch (err) {
    if (process.env.DEBUG) {
      console.error('Gitleaks error:', err.message);
    }
  }

  return findings.map(f => ({
    type: 'secret',
    scanner: 'gitleaks',
    severity: mapGitleaksSeverity(f.RuleID),
    file: f.File,
    line: f.StartLine,
    message: f.RuleID || 'Secret detected',
    ruleId: f.RuleID,
    codeSnippet: f.Secret,
    raw: f
  }));
}

function mapGitleaksSeverity(ruleId) {
  const id = (ruleId || '').toLowerCase();
  if (/aws.*key|api.*key|private.*key|secret.*key/.test(id)) return 'critical';
  if (/password|token|credential/.test(id)) return 'high';
  return 'medium';
}

function runSemgrep(projectRoot, files = null) {
  // Check if semgrep is installed
  try {
    execSync('which semgrep', { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] });
  } catch {
    return []; // Semgrep not installed, skip silently
  }

  const findings = [];

  try {
    const args = ['--json', '--config', 'p/security-audit'];
    if (files && files.length > 0) {
      args.push(...files);
    } else {
      args.push(projectRoot);
    }

    const result = spawnSync('semgrep', args, {
      encoding: 'utf8',
      cwd: projectRoot,
      maxBuffer: 50 * 1024 * 1024
    });

    if (result.stdout) {
      try {
        const parsed = JSON.parse(result.stdout);
        if (parsed.results) {
          for (const r of parsed.results) {
            findings.push({
              type: 'vulnerability',
              scanner: 'semgrep',
              severity: r.extra?.severity || 'medium',
              file: r.path,
              line: r.start?.line,
              message: r.extra?.message || r.check_id,
              ruleId: r.check_id,
              codeSnippet: r.extra?.lines,
              raw: r
            });
          }
        }
      } catch {}
    }
  } catch (err) {
    if (process.env.DEBUG) {
      console.error('Semgrep error:', err.message);
    }
  }

  return findings;
}

async function scan(options = {}) {
  const projectRoot = process.cwd();
  const config = loadConfig(projectRoot);

  if (!options.prePush) {
    console.log('\n🔍 Scanning project...\n');
  }

  // Run scanners
  const gitleaksFindings = runGitleaks(projectRoot);
  const semgrepFindings = runSemgrep(projectRoot);
  let findings = [...gitleaksFindings, ...semgrepFindings];

  if (findings.length === 0) {
    if (!options.prePush) {
      console.log('✅ No security issues found!\n');
    }
    process.exit(0);
  }

  // AI analysis if requested
  if (options.ai) {
    if (!options.prePush) {
      console.log(`🤖 Analyzing with AI (${options.ai})...\n`);
    }
    try {
      findings = await analyzeWithAI(findings, {
        provider: options.ai,
        apiKey: options.apiKey || config.ai?.apiKey
      });
    } catch (err) {
      if (!options.prePush) {
        console.warn(`⚠️  AI analysis unavailable: ${err.message}`);
      }
    }
  }

  // Report findings
  if (options.format === 'json') {
    console.log(JSON.stringify({ findings }, null, 2));
  } else {
    reportFindings(findings, options.prePush);
  }

  // Exit with error if blocking findings
  const blockingSeverity = config.blocking?.severity || 'high';
  const hasBlocking = findings.some(f => shouldBlock(f, blockingSeverity));
  process.exit(hasBlocking ? 1 : 0);
}

function shouldBlock(finding, blockingSeverity) {
  if (finding.aiFalsePositive) return false;

  const severity = finding.severity?.toLowerCase();
  switch (blockingSeverity) {
    case 'critical':
      return severity === 'critical';
    case 'high':
      return severity === 'critical' || severity === 'high';
    case 'none':
      return false;
    default:
      return severity === 'critical' || severity === 'high';
  }
}

function reportFindings(findings, compact = false) {
  const bySeverity = { critical: [], high: [], medium: [], low: [] };

  for (const f of findings) {
    const sev = f.severity?.toLowerCase() || 'medium';
    if (bySeverity[sev]) {
      bySeverity[sev].push(f);
    } else {
      bySeverity.medium.push(f);
    }
  }

  console.log('🛡️  Security Scan Results\n');
  console.log(`Found ${findings.length} issue(s):\n`);

  const colors = {
    critical: '\x1b[31m', // red
    high: '\x1b[33m',     // yellow
    medium: '\x1b[36m',   // cyan
    low: '\x1b[37m'       // white
  };
  const reset = '\x1b[0m';

  for (const [severity, items] of Object.entries(bySeverity)) {
    if (items.length === 0) continue;

    console.log(`${colors[severity]}${severity.toUpperCase()} (${items.length})${reset}`);

    for (const f of items) {
      const fp = f.aiFalsePositive ? ' [FALSE POSITIVE]' : '';
      console.log(`  ${f.file}:${f.line} - ${f.message}${fp}`);
      if (f.aiFixSuggestion && !compact) {
        console.log(`    💡 ${f.aiFixSuggestion}`);
      }
    }
    console.log('');
  }
}

module.exports = { scan, runGitleaks, runSemgrep };
