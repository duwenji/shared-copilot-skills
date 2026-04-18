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

function renderPdf(inputPath, outputPath, browserPath, showPageNumbers = false) {
  const fileUrl = `file:///${inputPath.replace(/\\/g, '/')}`;
  const profileDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ebook-pdf-'));

  try {
    const commonArgs = [
      '--disable-gpu',
      '--allow-file-access-from-files',
      '--run-all-compositor-stages-before-draw',
      '--virtual-time-budget=3000',
      '--no-first-run',
      '--no-default-browser-check',
      '--export-tagged-pdf',
      '--generate-pdf-document-outline',
      `--user-data-dir=${profileDir}`,
      `--print-to-pdf=${outputPath}`,
      fileUrl
    ];

    if (showPageNumbers) {
      // ページ番号のみ右下、他は空
      const footerHtml = Buffer.from('<div style="width:100%;font-size:10px;text-align:right;margin-right:20px;"><span class="pageNumber"></span></div>').toString('base64');
      const headerHtml = Buffer.from('<div></div>').toString('base64');
      commonArgs.splice(commonArgs.length - 1, 0,
        `--pdf-footer-template=data:text/html;base64,${footerHtml}`,
        `--pdf-header-template=data:text/html;base64,${headerHtml}`
      );
    } else {
      commonArgs.splice(commonArgs.length - 1, 0, '--no-pdf-header-footer');
    }

    try {
      tryRender(browserPath, ['--headless=new', ...commonArgs], outputPath);
    } catch {
      tryRender(browserPath, ['--headless', ...commonArgs], outputPath);
    }
  } finally {
    fs.rmSync(profileDir, { recursive: true, force: true });
  }
}

function renderImage(inputPath, outputPath, browserPath, width, height) {
  const fileUrl = `file:///${inputPath.replace(/\\/g, '/')}`;
  const profileDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ebook-shot-'));

  try {
    const commonArgs = [
      '--disable-gpu',
      '--allow-file-access-from-files',
      '--run-all-compositor-stages-before-draw',
      '--hide-scrollbars',
      '--default-background-color=ffffff',
      '--force-device-scale-factor=1.5',
      '--virtual-time-budget=3000',
      '--no-first-run',
      '--no-default-browser-check',
      `--user-data-dir=${profileDir}`,
      `--window-size=${width},${height}`,
      `--screenshot=${outputPath}`,
      fileUrl
    ];

    try {
      tryRender(browserPath, ['--headless=new', ...commonArgs], outputPath);
    } catch {
      tryRender(browserPath, ['--headless', ...commonArgs], outputPath);
    }
  } finally {
    fs.rmSync(profileDir, { recursive: true, force: true });
  }
}

function main() {
  const cliArgs = process.argv.slice(2);
  let mode = 'pdf';

  if (cliArgs[0] === 'pdf' || cliArgs[0] === 'image') {
    mode = cliArgs.shift();
  }

  const showPageNumbers = cliArgs.includes('--page-numbers');
  const normalizedArgs = cliArgs.filter((arg) => arg !== '--page-numbers');

  const [inputPath, outputPath, browserPath, widthArg, heightArg] = normalizedArgs;
  if (!inputPath || !outputPath || !browserPath) {
    throw new Error('Usage: node render-html-to-pdf.cjs [pdf|image] <inputHtml> <outputPath> <browserPath> [width height] [--page-numbers]');
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

  if (mode === 'image') {
    const width = Number.parseInt(widthArg || '1600', 10);
    const height = Number.parseInt(heightArg || '2400', 10);
    renderImage(resolvedInput, resolvedOutput, resolvedBrowser, width, height);

    if (!fs.existsSync(resolvedOutput)) {
      throw new Error(`Image was not produced: ${resolvedOutput}`);
    }

    console.log(`Generated image: ${resolvedOutput}`);
    return;
  }

  renderPdf(resolvedInput, resolvedOutput, resolvedBrowser, showPageNumbers);

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
