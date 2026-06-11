const { execSync, spawnSync } = require('child_process');
const path = require('path');
const fs = require('fs');
const { getGitleaksPath } = require('./installer');
const { loadConfig } = require('./config');
const { analyzeWithAI } = require('./ai');
const { detectProject } = require('./detector');

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

const SEVERITY_LEVELS = ['critical', 'high', 'medium', 'low', 'info'];

// Convert a .zwischen.yml ignore glob to a RegExp. Mirrors the Ruby
// orchestrator's fnmatch semantics: "*" and "?" stay within one path
// segment, "**" spans directories, and patterns match paths relative
// to the project root.
function globToRegExp(glob) {
  let regex = '';
  let i = 0;
  while (i < glob.length) {
    const char = glob[i];
    if (char === '*') {
      if (glob[i + 1] === '*') {
        if (glob[i + 2] === '/') {
          // "**/" matches zero or more leading directories
          regex += '(?:[^/]+/)*';
          i += 3;
        } else {
          // bare or trailing "**" matches anything, including "/"
          regex += '.*';
          i += 2;
        }
      } else {
        regex += '[^/]*';
        i += 1;
      }
    } else if (char === '?') {
      regex += '[^/]';
      i += 1;
    } else {
      regex += char.replace(/[.+^${}()|[\]\\]/g, '\\$&');
      i += 1;
    }
  }
  return new RegExp(`^${regex}$`);
}

// Drop findings whose file matches an ignore glob from .zwischen.yml.
// Equivalent to the Ruby orchestrator's #reject_ignored.
function rejectIgnored(findings, globs) {
  if (!Array.isArray(globs) || globs.length === 0) return findings;
  const matchers = globs.map(globToRegExp);
  return findings.filter(f => !matchers.some(re => re.test(f.file)));
}

// Scanner output may use absolute paths; report everything relative
// to the project root, like the Ruby gem.
function relativizeFindingPaths(findings, projectRoot) {
  return findings.map(f => {
    if (f.file && path.isAbsolute(f.file)) {
      return { ...f, file: path.relative(projectRoot, f.file) };
    }
    return f;
  });
}

// Matches the Ruby aggregator's summary shape: total count plus
// per-severity counts (only severities that actually occur).
function buildSummary(findings) {
  const summary = { total: findings.length, by_severity: {} };
  for (const severity of SEVERITY_LEVELS) {
    const count = findings.filter(f => (f.severity || '').toLowerCase() === severity).length;
    if (count > 0) summary.by_severity[severity] = count;
  }
  return summary;
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
  if (options.format === 'sarif') {
    console.error('SARIF output is not supported by the npm wrapper; use the Ruby gem (gem install zwischen)');
    process.exit(2);
  }

  const projectRoot = process.cwd();
  const config = loadConfig(projectRoot);
  const project = detectProject(projectRoot);
  const jsonMode = options.format === 'json';

  if (!options.prePush && !jsonMode) {
    const frameworkInfo = project.frameworks.length > 0
      ? `${project.frameworks[0]} (${project.language})`
      : project.primaryType || 'project';
    console.log(`\n🔍 Scanning ${frameworkInfo}...\n`);
  }

  // Run scanners
  const gitleaksFindings = runGitleaks(projectRoot);
  const semgrepFindings = runSemgrep(projectRoot);
  let findings = relativizeFindingPaths([...gitleaksFindings, ...semgrepFindings], projectRoot);
  findings = rejectIgnored(findings, config.ignore);

  if (findings.length === 0) {
    if (jsonMode) {
      console.log(JSON.stringify({ summary: buildSummary(findings), findings }, null, 2));
    } else if (!options.prePush) {
      console.log('✅ No security issues found!\n');
    }
    process.exit(0);
  }

  // AI analysis if requested
  if (options.ai) {
    if (!options.prePush && !jsonMode) {
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
  if (jsonMode) {
    console.log(JSON.stringify({ summary: buildSummary(findings), findings }, null, 2));
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
