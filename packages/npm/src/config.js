const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

const DEFAULT_CONFIG = {
  ai: {
    enabled: true,
    prePushEnabled: false,
    provider: 'ollama',
    model: 'llama3'
  },
  blocking: {
    severity: 'high'
  },
  scanners: {
    gitleaks: { enabled: true },
    semgrep: { enabled: true, config: 'p/security-audit' }
  },
  ignore: [
    '**/node_modules/**',
    '**/vendor/**',
    '**/.git/**',
    '**/dist/**',
    '**/build/**',
    '**/test/fixtures/**'
  ]
};

const EXAMPLE_CONFIG = `# Zwischen Configuration

# AI Provider Configuration
ai:
  enabled: true
  pre_push_enabled: false  # Disable AI in pre-push hooks (performance)
  provider: ollama         # Options: ollama, openai, anthropic
  model: llama3            # Model name for your provider
  # url: http://localhost:11434  # For Ollama (default)
  # api_key: null          # For OpenAI/Anthropic (or use env vars)

# What blocks a push
blocking:
  severity: high  # block on high or critical (default)
  # severity: critical  # only block on critical
  # severity: none  # never block, just warn

# Scanner Configuration
scanners:
  gitleaks: true  # Auto-installed if missing
  semgrep: true   # Optional, install with: pip install semgrep

# Ignored Paths (glob patterns)
ignore:
  - "**/node_modules/**"
  - "**/vendor/**"
  - "**/.git/**"
  - "**/dist/**"
  - "**/build/**"
`;

function loadConfig(projectRoot = process.cwd()) {
  const configPath = path.join(projectRoot, '.zwischen.yml');

  if (!fs.existsSync(configPath)) {
    return DEFAULT_CONFIG;
  }

  try {
    const content = fs.readFileSync(configPath, 'utf8');
    const userConfig = yaml.load(content) || {};
    return deepMerge(DEFAULT_CONFIG, userConfig);
  } catch (err) {
    console.warn(`Warning: Could not parse .zwischen.yml: ${err.message}`);
    return DEFAULT_CONFIG;
  }
}

function createConfig(projectRoot = process.cwd()) {
  const configPath = path.join(projectRoot, '.zwischen.yml');

  if (fs.existsSync(configPath)) {
    return false;
  }

  fs.writeFileSync(configPath, EXAMPLE_CONFIG);
  return true;
}

function deepMerge(base, override) {
  const result = { ...base };
  for (const key of Object.keys(override)) {
    if (
      typeof override[key] === 'object' &&
      override[key] !== null &&
      !Array.isArray(override[key]) &&
      typeof base[key] === 'object' &&
      base[key] !== null
    ) {
      result[key] = deepMerge(base[key], override[key]);
    } else {
      result[key] = override[key];
    }
  }
  return result;
}

module.exports = { loadConfig, createConfig, DEFAULT_CONFIG, EXAMPLE_CONFIG };
