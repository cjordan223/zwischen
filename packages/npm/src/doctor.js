const { execSync } = require('child_process');
const { getGitleaksPath, BIN_DIR } = require('./installer');
const path = require('path');

function doctor() {
  console.log('\n' + '='.repeat(60));
  console.log('Zwischen Doctor - Tool Status');
  console.log('='.repeat(60) + '\n');

  let allInstalled = true;

  const tools = [
    {
      name: 'gitleaks',
      description: 'Secrets detection',
      check: () => getGitleaksPath(),
      install: 'Auto-installed by zwischen init'
    },
    {
      name: 'semgrep',
      description: 'Static analysis (optional)',
      check: () => {
        try {
          execSync('which semgrep', { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] });
          return 'semgrep';
        } catch {
          return null;
        }
      },
      install: 'pip install semgrep'
    }
  ];

  for (const tool of tools) {
    const toolPath = tool.check();

    if (toolPath) {
      let version = '';
      try {
        version = execSync(`${toolPath} --version 2>/dev/null`, { encoding: 'utf8' })
          .trim()
          .split('\n')[0];
      } catch {}

      console.log(`\x1b[32m✓ ${tool.name}\x1b[0m - ${tool.description}`);
      if (version) {
        console.log(`  Version: ${version}`);
      }
      if (toolPath.startsWith(BIN_DIR)) {
        console.log(`  Location: ${toolPath}`);
      }
    } else {
      if (!tool.description.includes('optional')) {
        allInstalled = false;
      }
      console.log(`\x1b[31m✗ ${tool.name}\x1b[0m - ${tool.description} - NOT FOUND`);
      console.log(`  → ${tool.install}`);
    }
    console.log('');
  }

  if (allInstalled) {
    console.log('\x1b[32m✅ All required tools are installed!\x1b[0m\n');
  } else {
    console.log('\x1b[33m⚠️  Some tools are missing. Run "zwischen init" to install them.\x1b[0m\n');
  }
}

module.exports = { doctor };
