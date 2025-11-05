const fs = require('fs');
const path = require('path');

function getInstalledVersion() {
  try {
    const packageJsonPath = path.join(__dirname, '..', 'package.json')
    const packageJson = fs.readFileSync(packageJsonPath, 'utf8');
    const packageData = JSON.parse(packageJson);
    const version = packageData.version;
    return version;
  } catch (err) {
    return null;
  }
}

module.exports = {
  getInstalledVersion,
}