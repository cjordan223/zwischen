const fs = require('fs');
const path = require('path');

// Base detection patterns
const DETECTION_PATTERNS = {
  node: ['package.json'],
  python: ['requirements.txt', 'pyproject.toml', 'setup.py', 'Pipfile', 'poetry.lock'],
  ruby: ['Gemfile', 'Rakefile'],
  go: ['go.mod', 'go.sum'],
  java: ['pom.xml', 'build.gradle', 'build.gradle.kts'],
  rust: ['Cargo.toml', 'Cargo.lock'],
  php: ['composer.json'],
  dotnet: ['*.csproj', '*.sln', '*.fsproj']
};

// JS framework detection
const JS_FRAMEWORKS = {
  nextjs: ['next'],
  react: ['react'],
  vue: ['vue'],
  angular: ['@angular/core'],
  svelte: ['svelte'],
  express: ['express'],
  nestjs: ['@nestjs/core'],
  nuxt: ['nuxt'],
  remix: ['@remix-run/react'],
  astro: ['astro'],
  gatsby: ['gatsby']
};

// Python framework detection
const PYTHON_FRAMEWORKS = {
  django: ['django'],
  fastapi: ['fastapi'],
  flask: ['flask'],
  pyramid: ['pyramid'],
  tornado: ['tornado'],
  starlette: ['starlette'],
  streamlit: ['streamlit'],
  jupyter: ['jupyter', 'jupyterlab', 'notebook']
};

// Ruby framework detection
const RUBY_FRAMEWORKS = {
  rails: ['rails'],
  sinatra: ['sinatra'],
  hanami: ['hanami'],
  grape: ['grape'],
  roda: ['roda']
};

// Framework to language mapping
const FRAMEWORK_LANGUAGES = {
  nextjs: 'javascript', react: 'javascript', vue: 'javascript',
  angular: 'typescript', svelte: 'javascript', express: 'javascript',
  nestjs: 'typescript', nuxt: 'javascript', remix: 'javascript',
  astro: 'javascript', gatsby: 'javascript',
  django: 'python', fastapi: 'python', flask: 'python',
  pyramid: 'python', tornado: 'python', starlette: 'python',
  streamlit: 'python', jupyter: 'python',
  rails: 'ruby', sinatra: 'ruby', hanami: 'ruby',
  grape: 'ruby', roda: 'ruby'
};

function detectProject(projectRoot = process.cwd()) {
  const types = detectBaseTypes(projectRoot);
  const frameworks = detectFrameworks(projectRoot);

  const primary = frameworks[0] || types[0];
  const language = frameworks.length > 0
    ? (FRAMEWORK_LANGUAGES[frameworks[0]] || types[0])
    : types[0];

  return {
    types,
    primaryType: primary,
    language: language || 'unknown',
    frameworks,
    root: projectRoot
  };
}

function detectBaseTypes(projectRoot) {
  const detected = [];

  for (const [type, patterns] of Object.entries(DETECTION_PATTERNS)) {
    if (patterns.some(pattern => matchesPattern(projectRoot, pattern))) {
      detected.push(type);
    }
  }

  return detected;
}

function matchesPattern(projectRoot, pattern) {
  if (pattern.includes('*')) {
    // Simple glob - just check if any file matches
    const dir = fs.readdirSync(projectRoot).filter(f => {
      const ext = pattern.replace('*', '');
      return f.endsWith(ext);
    });
    return dir.length > 0;
  }
  return fs.existsSync(path.join(projectRoot, pattern));
}

function detectFrameworks(projectRoot) {
  const frameworks = [];

  frameworks.push(...detectJsFrameworks(projectRoot));
  frameworks.push(...detectPythonFrameworks(projectRoot));
  frameworks.push(...detectRubyFrameworks(projectRoot));

  return [...new Set(frameworks)];
}

function detectJsFrameworks(projectRoot) {
  const packageJsonPath = path.join(projectRoot, 'package.json');
  if (!fs.existsSync(packageJsonPath)) return [];

  try {
    const pkg = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));
    const allDeps = [
      ...Object.keys(pkg.dependencies || {}),
      ...Object.keys(pkg.devDependencies || {})
    ];

    const detected = [];
    for (const [framework, packages] of Object.entries(JS_FRAMEWORKS)) {
      if (packages.some(p => allDeps.includes(p))) {
        detected.push(framework);
      }
    }

    // Sort by specificity
    const priority = ['nextjs', 'nuxt', 'remix', 'gatsby', 'astro', 'angular', 'nestjs', 'svelte', 'vue', 'react', 'express'];
    return detected.sort((a, b) => {
      const ai = priority.indexOf(a);
      const bi = priority.indexOf(b);
      return (ai === -1 ? 999 : ai) - (bi === -1 ? 999 : bi);
    });
  } catch {
    return [];
  }
}

function detectPythonFrameworks(projectRoot) {
  const frameworks = [];
  const files = ['requirements.txt', 'pyproject.toml', 'Pipfile'];

  for (const file of files) {
    const filePath = path.join(projectRoot, file);
    if (fs.existsSync(filePath)) {
      const content = fs.readFileSync(filePath, 'utf8').toLowerCase();
      for (const [framework, packages] of Object.entries(PYTHON_FRAMEWORKS)) {
        if (packages.some(p => content.includes(p.toLowerCase()))) {
          frameworks.push(framework);
        }
      }
    }
  }

  const priority = ['django', 'fastapi', 'flask', 'pyramid', 'tornado', 'starlette', 'streamlit', 'jupyter'];
  return [...new Set(frameworks)].sort((a, b) => {
    const ai = priority.indexOf(a);
    const bi = priority.indexOf(b);
    return (ai === -1 ? 999 : ai) - (bi === -1 ? 999 : bi);
  });
}

function detectRubyFrameworks(projectRoot) {
  const gemfilePath = path.join(projectRoot, 'Gemfile');
  if (!fs.existsSync(gemfilePath)) return [];

  const content = fs.readFileSync(gemfilePath, 'utf8').toLowerCase();
  const detected = [];

  for (const [framework, gems] of Object.entries(RUBY_FRAMEWORKS)) {
    if (gems.some(g => content.includes(`gem '${g}'`) || content.includes(`gem "${g}"`))) {
      detected.push(framework);
    }
  }

  const priority = ['rails', 'hanami', 'sinatra', 'grape', 'roda'];
  return detected.sort((a, b) => {
    const ai = priority.indexOf(a);
    const bi = priority.indexOf(b);
    return (ai === -1 ? 999 : ai) - (bi === -1 ? 999 : bi);
  });
}

module.exports = { detectProject };
