import { PDFDocument } from 'pdf-lib';
import { readFileSync, writeFileSync } from 'fs';
import { resolve } from 'path';

const [,, inputPng, outputPdf] = process.argv;

if (!inputPng || !outputPdf) {
  console.error('Usage: node png-to-pdf.mjs <input.png> <output.pdf>');
  process.exit(1);
}

const pngBytes = readFileSync(resolve(inputPng));
const pdfDoc   = await PDFDocument.create();
const pngImage = await pdfDoc.embedPng(pngBytes);
const { width, height } = pngImage;

const page = pdfDoc.addPage([width, height]);
page.drawImage(pngImage, { x: 0, y: 0, width, height });

writeFileSync(resolve(outputPdf), await pdfDoc.save());
console.log(`PDF saved: ${resolve(outputPdf)} (${width} x ${height} px)`);
