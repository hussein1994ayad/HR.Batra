const fs = require('fs');
const path = require('path');

const dashboardDir = path.join('c:', 'Users', 'HP', 'Desktop', 'HR.Batra', 'web', 'src', 'app', 'dashboard');

function replaceAlertsInFile(filePath) {
  let content = fs.readFileSync(filePath, 'utf-8');
  
  if (!content.includes('alert(')) return;
  
  let modified = false;

  // Replace alert('...نجاح...') with toast.success
  // Replace alert('...فشل...') or alert('...خطأ...') with toast.error
  // Otherwise toast
  
  const alertRegex = /alert\((.*?)\)/g;
  content = content.replace(alertRegex, (match, innerText) => {
    modified = true;
    const textLower = innerText.toLowerCase();
    if (textLower.includes('نجاح') || textLower.includes('✅') || textLower.includes('🎉') || textLower.includes('🚀')) {
      return `toast.success(${innerText})`;
    } else if (textLower.includes('فشل') || textLower.includes('خطأ') || textLower.includes('❌') || textLower.includes('err')) {
      return `toast.error(${innerText})`;
    } else {
      // Default to error if it contains warning words, otherwise just toast
      if (textLower.includes('يرجى') || textLower.includes('يجب') || textLower.includes('لا يمكن')) {
        return `toast.error(${innerText})`;
      }
      return `toast(${innerText})`;
    }
  });

  if (modified) {
    // Add import if missing
    if (!content.includes('import toast from')) {
      // Find the last import
      const lastImportIndex = content.lastIndexOf('import ');
      if (lastImportIndex !== -1) {
        const endOfLine = content.indexOf('\n', lastImportIndex);
        content = content.slice(0, endOfLine + 1) + "import toast from 'react-hot-toast';\n" + content.slice(endOfLine + 1);
      } else {
        content = "import toast from 'react-hot-toast';\n" + content;
      }
    }
    fs.writeFileSync(filePath, content, 'utf-8');
    console.log(`Updated ${filePath}`);
  }
}

function traverseDir(dir) {
  const files = fs.readdirSync(dir);
  for (const file of files) {
    const fullPath = path.join(dir, file);
    if (fs.statSync(fullPath).isDirectory()) {
      traverseDir(fullPath);
    } else if (fullPath.endsWith('.tsx') || fullPath.endsWith('.ts')) {
      replaceAlertsInFile(fullPath);
    }
  }
}

traverseDir(dashboardDir);
console.log('Done replacing alerts!');
