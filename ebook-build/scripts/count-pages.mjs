import { PDFDocument } from 'pdf-lib';
import { readFileSync } from 'fs';
import { resolve } from 'path';

const [,, pdfPath] = process.argv;
if (!pdfPath) {
  console.error('Usage: node count-pages.mjs <input.pdf>');
  process.exit(1);
}

try {
  const pdf = await PDFDocument.load(readFileSync(resolve(pdfPath)), { ignoreEncryption: true });
  console.log(pdf.getPageCount());
} catch (e) {
  console.error('Error:', e.message);
  process.exit(1);
}
