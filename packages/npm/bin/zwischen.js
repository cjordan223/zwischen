#!/usr/bin/env node

const { program } = require('commander');
const { scan } = require('../src/scanner');
const { init } = require('../src/init');
const { doctor } = require('../src/doctor');
const pkg = require('../package.json');

program
  .name('zwischen')
  .description('AI-augmented security scanning for vibe coders')
  .version(pkg.version);

program
  .command('init')
  .description('Initialize Zwischen in your project')
  .action(init);

program
  .command('scan')
  .description('Run security scan')
  .option('--ai <provider>', 'AI provider (ollama, openai, anthropic)')
  .option('--api-key <key>', 'API key for AI provider')
  .option('--format <format>', 'Output format (terminal, json)', 'terminal')
  .option('--pre-push', 'Pre-push mode (compact output)')
  .action(scan);

program
  .command('doctor')
  .description('Check if required tools are installed')
  .action(doctor);

program.parse();
