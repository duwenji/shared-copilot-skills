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

function renderPdf(inputPath, outputPath, browserPath) {
  const fileUrl = `file:///${inputPath.replace(/\\/g, '/')}`;
  const profileDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ebook-pdf-'));

  try {
    const commonArgs = [
      '--disable-gpu',
      '--run-all-compositor-stages-before-draw',
      '--virtual-time-budget=3000',
      '--no-first-run',
      '--no-default-browser-check',
      `--user-data-dir=${profileDir}`,
      `--print-to-pdf=${outputPath}`,
      '--no-pdf-header-footer',
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

function renderImage(inputPath, outputPath, browserPath, width, height) {
  const fileUrl = `file:///${inputPath.replace(/\\/g, '/')}`;
  const profileDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ebook-shot-'));

  try {
    const commonArgs = [
      '--disable-gpu',
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

  const [inputPath, outputPath, browserPath, widthArg, heightArg] = cliArgs;
  if (!inputPath || !outputPath || !browserPath) {
    throw new Error('Usage: node render-html-to-pdf.cjs [pdf|image] <inputHtml> <outputPath> <browserPath> [width height]');
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

  renderPdf(resolvedInput, resolvedOutput, resolvedBrowser);

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
