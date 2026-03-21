#!/usr/bin/env node

import fs from 'fs';
import path from 'path';

function printUsage() {
  console.log('Usage: node normalize-quiz-ids.mjs --dataDir <path>');
  console.log('  --dataDir, -d  Root directory that contains quiz JSON files (required)');
}

function parseArgs(argv) {
  let dataDir = '';
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--help' || arg === '-h') {
      printUsage();
      process.exit(0);
    }
    if (arg === '--dataDir' || arg === '-d') {
      dataDir = path.resolve(argv[++i] ?? '');
      continue;
    }
    if (!arg.startsWith('-') && !dataDir) {
      dataDir = path.resolve(arg);
      continue;
    }
    throw new Error(`Unknown argument: ${arg}`);
  }

  if (!dataDir) {
    throw new Error('Missing required --dataDir argument');
  }
  return dataDir;
}

/**
 * IDを文字列から数値に変換する
 * ca-001 -> 1, q1 -> 1, step1-foundation-001 -> 1 など
 */
function extractNumericId(id) {
  if (typeof id === 'number') return id;
  if (typeof id !== 'string') return null;
  
  // 数字だけを抽出
  const match = id.match(/\d+/);
  return match ? parseInt(match[0], 10) : null;
}

/**
 * JSONファイルをクイズID形式に正規化する
 */
function normalizeQuizFile(filePath) {
  try {
    const content = fs.readFileSync(filePath, 'utf-8');
    const data = JSON.parse(content);
    
    // questionsキーがある場合（標準形式）
    if (data.questions && Array.isArray(data.questions)) {
      let hasChanges = false;
      
      data.questions = data.questions.map((q, index) => {
        const normalized = { ...q };
        
        // IDを数値化
        if (typeof normalized.id === 'string') {
          const numId = extractNumericId(normalized.id);
          if (numId !== null) {
            normalized.id = numId;
            hasChanges = true;
          }
        }
        // IDがない場合はインデックス+1
        if (!normalized.id && typeof normalized.id !== 'number') {
          normalized.id = index + 1;
          hasChanges = true;
        }
        
        // correctOptionIndexをcorrectAnswerに変換
        if (typeof normalized.correctOptionIndex === 'number' && !normalized.correctAnswer) {
          const answers = ['A', 'B', 'C', 'D'];
          normalized.correctAnswer = answers[normalized.correctOptionIndex];
          delete normalized.correctOptionIndex;
          hasChanges = true;
        }
        
        return normalized;
      });
      
      if (hasChanges) {
        fs.writeFileSync(filePath, JSON.stringify(data, null, 2) + '\n', 'utf-8');
        console.log(`✓ Updated: ${path.relative(process.cwd(), filePath)}`);
        return true;
      }
    }
    
    return false;
  } catch (error) {
    console.error(`✗ Failed to process ${filePath}:`, error.message);
    return false;
  }
}

/**
 * ディレクトリ内のすべてのJSONファイルを処理（再帰）
 */
function normalizeDirectory(dir) {
  const files = fs.readdirSync(dir);
  let updatedCount = 0;
  
  files.forEach(file => {
    const filePath = path.join(dir, file);
    const stat = fs.statSync(filePath);
    
    if (stat.isDirectory()) {
      // サブディレクトリを再帰処理
      updatedCount += normalizeDirectory(filePath);
    } else if (stat.isFile() && file.endsWith('.json')) {
      if (normalizeQuizFile(filePath)) {
        updatedCount++;
      }
    }
  });
  
  return updatedCount;
}

console.log('🔄 Normalizing quiz data IDs...\n');
try {
  const dataDir = parseArgs(process.argv.slice(2));
  const updated = normalizeDirectory(dataDir);
  console.log(`\n✅ Complete! Updated ${updated} file(s).`);
} catch (error) {
  if (error instanceof Error && (error.message.startsWith('Missing required') || error.message.startsWith('Unknown argument'))) {
    console.error(`❌ ${error.message}`);
    printUsage();
    process.exit(1);
  }
  console.error(`❌ Failed: ${error instanceof Error ? error.message : String(error)}`);
  process.exit(1);
}
