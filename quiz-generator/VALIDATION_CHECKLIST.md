# Validation Checklist

## Shared Skill

1. `node scripts/validate-quiz-metadata.mjs --help` exits with code 0.
2. `node scripts/validate-quiz-questions.mjs --help` exits with code 0.
3. `node scripts/normalize-quiz-ids.mjs --help` exits with code 0.
4. Missing required arguments produce non-zero exit codes.
5. Schema files under `schemas/` are readable.

## Consumer Repository

1. Wrapper script can resolve repository root from `.github/skills-config/quiz-generator`.
2. Metadata validation succeeds for consumer `src/data/quizSets.json`.
3. Question validation succeeds for target quiz JSON files.
4. Normalization script can run against consumer data directory.
5. Existing app runtime can still load data from `public/data/`.
