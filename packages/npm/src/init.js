const fs = require('fs');
const path = require('path');
const { installGitleaks, isGitleaksInstalled } = require('./installer');
const { createConfig } = require('./config');

const PRE_PUSH_HOOK = `#!/bin/sh
# Zwischen pre-push hook
# Runs security scan on changed files before push

zwischen scan --pre-push
`;

async function init() {
  const projectRoot = process.cwd();

  console.log('\n🛡️  Initializing Zwischen...\n');

  // 1. Install gitleaks if needed
  if (!isGitleaksInstalled()) {
    console.log('  Installing gitleaks...');
    const success = await installGitleaks();
    if (!success) {
      console.log('  ⚠️  Could not auto-install gitleaks');
    }
  } else {
    console.log('  ✓ gitleaks already installed');
  }

  // 2. Check for semgrep (optional)
  try {
    require('child_process').execSync('which semgrep', { stdio: 'pipe' });
    console.log('  ✓ semgrep available');
  } catch {
    console.log('  ↳ semgrep not found (optional)');
    console.log('    → pip install semgrep');
  }

  // 3. Create config file
  if (createConfig(projectRoot)) {
    console.log('  ✓ Created .zwischen.yml');
  } else {
    console.log('  ✓ Config already exists');
  }

  // 4. Install git hook
  const gitDir = path.join(projectRoot, '.git');
  if (fs.existsSync(gitDir)) {
    const hooksDir = path.join(gitDir, 'hooks');
    fs.mkdirSync(hooksDir, { recursive: true });

    const hookPath = path.join(hooksDir, 'pre-push');

    if (fs.existsSync(hookPath)) {
      const content = fs.readFileSync(hookPath, 'utf8');
      if (!content.includes('zwischen')) {
        // Append to existing hook
        fs.appendFileSync(hookPath, '\n' + PRE_PUSH_HOOK);
        console.log('  ✓ Added to existing pre-push hook');
      } else {
        console.log('  ✓ Pre-push hook already configured');
      }
    } else {
      fs.writeFileSync(hookPath, PRE_PUSH_HOOK);
      fs.chmodSync(hookPath, 0o755);
      console.log('  ✓ Installed pre-push hook');
    }
  } else {
    console.log('  ↳ Not a git repository, skipping hook installation');
  }

  console.log('\n✅ Zwischen initialized!\n');
  console.log('Run "zwischen scan" to scan your project.');
  console.log('Security checks will run automatically before each push.\n');
}

module.exports = { init };
