const { scan, runGitleaks, runSemgrep } = require('./scanner');
const { init } = require('./init');
const { doctor } = require('./doctor');
const { loadConfig, createConfig } = require('./config');
const { installGitleaks, getGitleaksPath, isGitleaksInstalled } = require('./installer');
const { analyzeWithAI } = require('./ai');

module.exports = {
  // Commands
  scan,
  init,
  doctor,

  // Scanner functions
  runGitleaks,
  runSemgrep,

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
