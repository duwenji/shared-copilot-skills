import { PDFDocument } from 'pdf-lib';
import { readFileSync, writeFileSync } from 'fs';
import { resolve } from 'path';

const [,, coverPdf, contentPdf, outputPdf] = process.argv;

if (!coverPdf || !contentPdf || !outputPdf) {
  console.error('Usage: node merge-pdfs.mjs <cover.pdf> <content.pdf> <output.pdf>');
  process.exit(1);
}

const coverDoc   = await PDFDocument.load(readFileSync(resolve(coverPdf)));
const contentDoc = await PDFDocument.load(readFileSync(resolve(contentPdf)));
const merged     = await PDFDocument.create();

const coverPages   = await merged.copyPages(coverDoc,   coverDoc.getPageIndices());
const contentPages = await merged.copyPages(contentDoc, contentDoc.getPageIndices());

for (const page of coverPages)   merged.addPage(page);
for (const page of contentPages) merged.addPage(page);

writeFileSync(resolve(outputPdf), await merged.save());
console.log(`PDF merged: ${resolve(outputPdf)} (${coverPages.length + contentPages.length} pages)`);
