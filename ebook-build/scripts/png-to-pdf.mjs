import { PDFDocument } from 'pdf-lib';
import { readFileSync, writeFileSync } from 'fs';
import { resolve, extname } from 'path';

const [,, inputImage, outputPdf] = process.argv;

if (!inputImage || !outputPdf) {
  console.error('Usage: node png-to-pdf.mjs <input.png|input.jpg> <output.pdf>');
  process.exit(1);
}

const imageBytes = readFileSync(resolve(inputImage));
const pdfDoc     = await PDFDocument.create();

// Detect format from magic bytes — providers like OpenAI may save PNG content
// even when the requested filename has a .jpg extension.
const isJpeg = imageBytes[0] === 0xFF && imageBytes[1] === 0xD8;
const image = isJpeg
  ? await pdfDoc.embedJpg(imageBytes)
  : await pdfDoc.embedPng(imageBytes);

const { width, height } = image;

const page = pdfDoc.addPage([width, height]);
page.drawImage(image, { x: 0, y: 0, width, height });

writeFileSync(resolve(outputPdf), await pdfDoc.save());
console.log(`PDF saved: ${resolve(outputPdf)} (${width} x ${height} px)`);
