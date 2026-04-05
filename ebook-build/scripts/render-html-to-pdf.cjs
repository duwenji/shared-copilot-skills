#!/usr/bin/env node
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

function tryRender(browserPath, args, outputPath) {
  const result = spawnSync(browserPath, args, {
    encoding: 'utf8',
    timeout: 120000,
    windowsHide: true
  });

  if (fs.existsSync(outputPath)) {
    return;
  }

  const details = [result.stdout, result.stderr].filter(Boolean).join('\n').trim();
  if (result.error) {
    throw result.error;
  }

  throw new Error(details || `Browser exited with status ${result.status}`);
}

function main() {
  const [inputPath, outputPath, browserPath] = process.argv.slice(2);
  if (!inputPath || !outputPath || !browserPath) {
    throw new Error('Usage: node render-html-to-pdf.cjs <inputHtml> <outputPdf> <browserPath>');
  }

  const resolvedInput = path.resolve(inputPath);
  const resolvedOutput = path.resolve(outputPath);
  const resolvedBrowser = path.resolve(browserPath);

  if (!fs.existsSync(resolvedInput)) {
    throw new Error(`Input HTML not found: ${resolvedInput}`);
  }
  if (!fs.existsSync(resolvedBrowser)) {
    throw new Error(`Browser executable not found: ${resolvedBrowser}`);
  }

  fs.mkdirSync(path.dirname(resolvedOutput), { recursive: true });
  if (fs.existsSync(resolvedOutput)) {
    fs.unlinkSync(resolvedOutput);
  }

  const fileUrl = `file:///${resolvedInput.replace(/\\/g, '/')}`;
  const profileDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ebook-pdf-'));

  try {
    const commonArgs = [
      '--disable-gpu',
      '--run-all-compositor-stages-before-draw',
      '--no-first-run',
      '--no-default-browser-check',
      `--user-data-dir=${profileDir}`,
      `--print-to-pdf=${resolvedOutput}`,
      '--no-pdf-header-footer',
      fileUrl
    ];

    try {
      tryRender(resolvedBrowser, ['--headless=new', ...commonArgs], resolvedOutput);
    } catch {
      tryRender(resolvedBrowser, ['--headless', ...commonArgs], resolvedOutput);
    }
  } finally {
    fs.rmSync(profileDir, { recursive: true, force: true });
  }

  if (!fs.existsSync(resolvedOutput)) {
    throw new Error(`PDF was not produced: ${resolvedOutput}`);
  }

  console.log(`Generated PDF: ${resolvedOutput}`);
}

try {
  main();
} catch (error) {
  console.error(error && error.stack ? error.stack : String(error));
  process.exit(1);
}
