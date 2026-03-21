#!/usr/bin/env node

import fs from 'fs';
import path from 'path';
import { fileURLToPath, pathToFileURL } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function printUsage() {
  console.log('Usage: node validate-quiz-metadata.mjs --metadata <path> [--schema <path>]');
  console.log('  --metadata, -m  Path to quizSets.json (required)');
  console.log('  --schema, -s    Path to quizset metadata schema (default: ../schemas/quizset-metadata-schema.json)');
  console.log('  --ajv           Ajv module specifier or absolute path (default: ajv)');
}

function parseArgs(argv) {
  const opts = {
    metadataFilePath: '',
    metadataSchemaPath: path.resolve(__dirname, '../schemas/quizset-metadata-schema.json'),
    ajvModule: 'ajv'
  };

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--help' || arg === '-h') {
      printUsage();
      process.exit(0);
    }
    if (arg === '--metadata' || arg === '-m') {
      opts.metadataFilePath = path.resolve(argv[++i] ?? '');
      continue;
    }
    if (arg === '--schema' || arg === '-s') {
      opts.metadataSchemaPath = path.resolve(argv[++i] ?? '');
      continue;
    }
    if (arg === '--ajv') {
      opts.ajvModule = argv[++i] ?? 'ajv';
      continue;
    }
    if (!arg.startsWith('-') && !opts.metadataFilePath) {
      opts.metadataFilePath = path.resolve(arg);
      continue;
    }
    if (!arg.startsWith('-') && opts.metadataFilePath && opts.metadataSchemaPath === path.resolve(__dirname, '../schemas/quizset-metadata-schema.json')) {
      opts.metadataSchemaPath = path.resolve(arg);
      continue;
    }
    throw new Error(`Unknown argument: ${arg}`);
  }

  if (!opts.metadataFilePath) {
    throw new Error('Missing required --metadata argument');
  }

  return opts;
}

try {
  const { metadataFilePath, metadataSchemaPath, ajvModule } = parseArgs(process.argv.slice(2));
  const ajvRef = path.isAbsolute(ajvModule) ? pathToFileURL(ajvModule).href : ajvModule;
  const { default: Ajv } = await import(ajvRef);
  const ajv = new Ajv();

  // メタデータ JSON ファイルを読み込み
  const metadataData = JSON.parse(fs.readFileSync(metadataFilePath, 'utf-8'));

  // スキーマを読み込み
  const metadataSchema = JSON.parse(fs.readFileSync(metadataSchemaPath, 'utf-8'));

  // validate 関数を作成
  const validateMetadata = ajv.compile(metadataSchema);

  let hasErrors = false;
  let validCount = 0;

  if (!Array.isArray(metadataData.quizSets)) {
    console.error('❌ Error: "quizSets" field must be an array');
    process.exit(1);
  }

  metadataData.quizSets.forEach((quizSet, index) => {
    const valid = validateMetadata(quizSet);

    if (!valid) {
      hasErrors = true;
      console.error(`\n❌ Quiz Set ${index + 1} (ID: ${quizSet.id}) has errors:`);
      validateMetadata.errors?.forEach(error => {
        console.error(`   - ${error.dataPath || 'root'}: ${error.message}`);
      });
    } else {
      validCount++;
    }
  });

  if (!hasErrors) {
    console.log(`✓ All ${validCount} quiz set metadata entries are valid!`);
    process.exit(0);
  } else {
    console.log(`\n🔴 Validation failed for some entries. ${validCount} valid, ${metadataData.quizSets.length - validCount} invalid.`);
    process.exit(1);
  }
} catch (error) {
  if (error instanceof Error && (error.message.startsWith('Missing required') || error.message.startsWith('Unknown argument'))) {
    console.error(`❌ ${error.message}`);
    printUsage();
    process.exit(1);
  }
  console.error(`❌ Error reading or parsing file: ${error instanceof Error ? error.message : String(error)}`);
  process.exit(1);
}
