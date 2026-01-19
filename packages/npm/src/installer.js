const https = require('https');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const os = require('os');
const zlib = require('zlib');
const tar = require('tar');

const ZWISCHEN_DIR = path.join(os.homedir(), '.zwischen');
const BIN_DIR = path.join(ZWISCHEN_DIR, 'bin');
const GITLEAKS_REPO = 'gitleaks/gitleaks';

const PLATFORMS = {
  darwin: 'darwin',
  linux: 'linux',
  win32: 'windows'
};

const ARCHS = {
  x64: 'x64',
  arm64: 'arm64'
};

async function fetchJSON(url) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: { 'User-Agent': 'zwischen' } }, (res) => {
      if (res.statusCode === 302 || res.statusCode === 301) {
        return fetchJSON(res.headers.location).then(resolve).catch(reject);
      }
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          resolve(JSON.parse(data));
        } catch (e) {
          reject(e);
        }
      });
    }).on('error', reject);
  });
}

async function downloadFile(url, dest) {
  return new Promise((resolve, reject) => {
    const file = fs.createWriteStream(dest);
    https.get(url, { headers: { 'User-Agent': 'zwischen' } }, (res) => {
      if (res.statusCode === 302 || res.statusCode === 301) {
        file.close();
        fs.unlinkSync(dest);
        return downloadFile(res.headers.location, dest).then(resolve).catch(reject);
      }
      res.pipe(file);
      file.on('finish', () => {
        file.close();
        resolve();
      });
    }).on('error', (err) => {
      fs.unlinkSync(dest);
      reject(err);
    });
  });
}

async function installGitleaks() {
  const platform = PLATFORMS[process.platform];
  const arch = ARCHS[process.arch] || 'x64';

  if (!platform) {
    console.error(`Unsupported platform: ${process.platform}`);
    return false;
  }

  // Ensure directories exist
  fs.mkdirSync(BIN_DIR, { recursive: true });

  const gitleaksPath = path.join(BIN_DIR, process.platform === 'win32' ? 'gitleaks.exe' : 'gitleaks');

  // Check if already installed
  if (fs.existsSync(gitleaksPath)) {
    return true;
  }

  console.log('  Downloading gitleaks...');

  try {
    // Get latest release
    const release = await fetchJSON(`https://api.github.com/repos/${GITLEAKS_REPO}/releases/latest`);

    // Find matching asset
    const pattern = new RegExp(`gitleaks_.*_${platform}_${arch}\\.tar\\.gz$`);
    const asset = release.assets.find(a => pattern.test(a.name));

    if (!asset) {
      console.error(`No gitleaks binary found for ${platform}_${arch}`);
      return false;
    }

    // Download tarball
    const tarballPath = path.join(BIN_DIR, 'gitleaks.tar.gz');
    await downloadFile(asset.browser_download_url, tarballPath);

    // Extract
    await tar.x({
      file: tarballPath,
      cwd: BIN_DIR,
      filter: (p) => p === 'gitleaks'
    });

    // Cleanup tarball
    fs.unlinkSync(tarballPath);

    // Make executable
    if (process.platform !== 'win32') {
      fs.chmodSync(gitleaksPath, 0o755);
    }

    console.log('  ✓ Installed gitleaks');
    return true;
  } catch (err) {
    console.error(`  ✗ Failed to install gitleaks: ${err.message}`);
    return false;
  }
}

function getGitleaksPath() {
  const localPath = path.join(BIN_DIR, process.platform === 'win32' ? 'gitleaks.exe' : 'gitleaks');
  if (fs.existsSync(localPath)) {
    return localPath;
  }

  // Check system PATH
  try {
    const cmd = process.platform === 'win32' ? 'where gitleaks' : 'which gitleaks';
    const result = execSync(cmd, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] }).trim();
    return result || null;
  } catch {
    return null;
  }
}

function isGitleaksInstalled() {
  return getGitleaksPath() !== null;
}

module.exports = {
  installGitleaks,
  getGitleaksPath,
  isGitleaksInstalled,
  BIN_DIR,
  ZWISCHEN_DIR
};
