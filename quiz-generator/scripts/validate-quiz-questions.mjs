#!/usr/bin/env node

import fs from 'fs';
import path from 'path';
import { fileURLToPath, pathToFileURL } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function printUsage() {
  console.log('Usage: node validate-quiz-questions.mjs --quiz <path> [--schema <path>]');
  console.log('  --quiz, -q    Path to quiz JSON file (required)');
  console.log('  --schema, -s  Path to question schema (default: ../schemas/question-schema.json)');
  console.log('  --ajv         Ajv module specifier or absolute path (default: ajv)');
}

function parseArgs(argv) {
  const opts = {
    quizFilePath: '',
    questionSchemaPath: path.resolve(__dirname, '../schemas/question-schema.json'),
    ajvModule: 'ajv'
  };

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--help' || arg === '-h') {
      printUsage();
      process.exit(0);
    }
    if (arg === '--quiz' || arg === '-q') {
      opts.quizFilePath = path.resolve(argv[++i] ?? '');
      continue;
    }
    if (arg === '--schema' || arg === '-s') {
      opts.questionSchemaPath = path.resolve(argv[++i] ?? '');
      continue;
    }
    if (arg === '--ajv') {
      opts.ajvModule = argv[++i] ?? 'ajv';
      continue;
    }
    if (!arg.startsWith('-') && !opts.quizFilePath) {
      opts.quizFilePath = path.resolve(arg);
      continue;
    }
    if (!arg.startsWith('-') && opts.quizFilePath && opts.questionSchemaPath === path.resolve(__dirname, '../schemas/question-schema.json')) {
      opts.questionSchemaPath = path.resolve(arg);
      continue;
    }
    throw new Error(`Unknown argument: ${arg}`);
  }

  if (!opts.quizFilePath) {
    throw new Error('Missing required --quiz argument');
  }

  return opts;
}

try {
  const { quizFilePath, questionSchemaPath, ajvModule } = parseArgs(process.argv.slice(2));
  const ajvRef = path.isAbsolute(ajvModule) ? pathToFileURL(ajvModule).href : ajvModule;
  const { default: Ajv } = await import(ajvRef);
  const ajv = new Ajv();

  // Quiz JSON ファイルを読み込み
  const quizData = JSON.parse(fs.readFileSync(quizFilePath, 'utf-8'));

  // スキーマを読み込み
  const questionSchema = JSON.parse(fs.readFileSync(questionSchemaPath, 'utf-8'));

  // validate 関数を作成
  const validateQuestion = ajv.compile(questionSchema);

  let hasErrors = false;

  if (!Array.isArray(quizData.questions)) {
    console.error('❌ Error: "questions" field must be an array');
    process.exit(1);
  }

  quizData.questions.forEach((question, index) => {
    const valid = validateQuestion(question);

    if (!valid) {
      hasErrors = true;
      console.error(`\n❌ Question ${index + 1} (ID: ${question.id}) has errors:`);
      validateQuestion.errors?.forEach(error => {
        console.error(`   - ${error.dataPath || 'root'}: ${error.message}`);
      });
    }
  });

  if (!hasErrors) {
    console.log(`✓ All ${quizData.questions.length} questions are valid!`);
    process.exit(0);
  } else {
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
