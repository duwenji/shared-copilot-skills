/**
 * Convert a high-res image to a PDF with correct physical page dimensions.
 * Usage: node paperback-to-pdf.mjs <input.png|jpg> <output.pdf> <width-in> <height-in>
 *
 * Unlike png-to-pdf.mjs (which uses pixel dimensions as points), this script
 * sets the page size from the supplied physical measurements so the PDF has
 * the exact print dimensions required by KDP.
 */
import { PDFDocument } from 'pdf-lib';
import { readFileSync, writeFileSync } from 'fs';
import { resolve } from 'path';

const [,, inputImage, outputPdf, widthInStr, heightInStr] = process.argv;

if (!inputImage || !outputPdf || !widthInStr || !heightInStr) {
  console.error('Usage: node paperback-to-pdf.mjs <input> <output.pdf> <width-in> <height-in>');
  process.exit(1);
}

const widthIn  = parseFloat(widthInStr);
const heightIn = parseFloat(heightInStr);
const PT_PER_IN = 72;

const imageBytes = readFileSync(resolve(inputImage));
const pdfDoc     = await PDFDocument.create();

const isJpeg = imageBytes[0] === 0xFF && imageBytes[1] === 0xD8;
const image  = isJpeg
  ? await pdfDoc.embedJpg(imageBytes)
  : await pdfDoc.embedPng(imageBytes);

const pageW = widthIn  * PT_PER_IN;
const pageH = heightIn * PT_PER_IN;

const page = pdfDoc.addPage([pageW, pageH]);
page.drawImage(image, { x: 0, y: 0, width: pageW, height: pageH });

writeFileSync(resolve(outputPdf), await pdfDoc.save());
console.log(`PDF saved: ${resolve(outputPdf)} (${widthIn}" × ${heightIn}")`);
