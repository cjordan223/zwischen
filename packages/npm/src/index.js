const { scan, runGitleaks, runSemgrep } = require('./scanner');
const { init } = require('./init');
const { doctor } = require('./doctor');
const { loadConfig, createConfig } = require('./config');
const { installGitleaks, getGitleaksPath, isGitleaksInstalled } = require('./installer');
const { analyzeWithAI } = require('./ai');
const { detectProject } = require('./detector');

module.exports = {
  // Commands
  scan,
  init,
  doctor,

  // Scanner functions
  runGitleaks,
  runSemgrep,

  // Project detection
  detectProject,

  // Config
  loadConfig,
  createConfig,

  // Installer
  installGitleaks,
  getGitleaksPath,
  isGitleaksInstalled,

  // AI
  analyzeWithAI
};
