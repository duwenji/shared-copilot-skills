# quiz-generator

Reusable quiz generation skill assets and validation utilities.

## Shared files

- `SKILL.md`
- `DATA_FORMAT_SPECIFICATION.md`
- `schemas/*.json`
- `prompts/*.md`
- `scripts/validate-quiz-metadata.mjs`
- `scripts/validate-quiz-questions.mjs`
- `scripts/normalize-quiz-ids.mjs`

## Consumer layout

```text
.github/
  skills/
    shared-copilot-skills/
      quiz-generator/
  skills-config/
    quiz-generator/
      invoke-validate.ps1
      quiz-generator.config.json
```

## Example commands

```powershell
node ./.github/skills/shared-copilot-skills/quiz-generator/scripts/validate-quiz-metadata.mjs \
  --metadata ./src/data/quizSets.json \
  --schema ./.github/skills/shared-copilot-skills/quiz-generator/schemas/quizset-metadata-schema.json

node ./.github/skills/shared-copilot-skills/quiz-generator/scripts/validate-quiz-questions.mjs \
  --quiz ./src/data/clean-architecture/clean-architecture.json \
  --schema ./.github/skills/shared-copilot-skills/quiz-generator/schemas/question-schema.json
```
