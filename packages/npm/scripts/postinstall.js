#!/usr/bin/env node

const { installGitleaks, isGitleaksInstalled } = require('../src/installer');

async function main() {
  if (isGitleaksInstalled()) {
    return;
  }

  console.log('\n🛡️  Zwischen: Installing gitleaks...');

  try {
    const success = await installGitleaks();
    if (success) {
      console.log('✓ Gitleaks installed successfully\n');
    } else {
      console.log('⚠️  Could not auto-install gitleaks. Run "zwischen init" to retry.\n');
    }
  } catch (err) {
    console.log(`⚠️  Could not auto-install gitleaks: ${err.message}\n`);
  }
}

main().catch(console.error);
