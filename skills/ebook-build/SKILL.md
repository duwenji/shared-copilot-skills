---
name: ebook-build
description: Build Kindle-compatible ebooks from markdown projects using PowerShell (EPUB, AZW3, MOBI). Use when generating publishable ebook files in a consumer repository that references this skill via Git submodule.
license: MIT
---

# Ebook Build Skill

## Overview

This skill packages the Kindle build flow as a reusable workflow for multi-repository distribution.

It is designed for:
- Building ebooks from numbered markdown chapter structures
- Reusing the same conversion scripts across repositories
- Consumer-side configuration with repository-specific metadata and output policy

## What This Skill Does

1. Detects source content root (direct or docs/)
2. Prepares an isolated build workspace
3. Reuses kindle conversion scripts and templates
4. Builds EPUB and optional AZW3/MOBI
5. Optionally injects EPUB page-list navigation
6. Copies resulting artifacts to the target output directory

## Requirements

- Windows PowerShell 5.1+
- Pandoc installed and available in PATH
- Calibre (ebook-convert) for AZW3/MOBI generation

## Inputs

Primary script: ./scripts/invoke-ebook-build.ps1

| Parameter | Required | Default | Description |
|---|---|---|---|
| sourceRoot | Yes | - | Source project root or docs root containing chapter folders |
| outputDir | No | sourceRoot/ebook-output | Destination for final ebook artifacts |
| projectName | No | folder name of sourceRoot | Base filename for outputs |
| formats | No | [epub, azw3, mobi] | Output formats to keep |
| enablePageList | No | true | Keep page-list injection step enabled |
| chapterDirPattern | No | ^\\d{2}- | Chapter directory pattern |
| chapterFilePattern | No | ^\\d{2}-.*\\.md$ | Chapter file pattern |
| coverFile | No | 00-COVER.md | Optional cover filename |
| preserveTemp | No | false | Keep temporary staging directory |
| metadataFile | No | ./.github/skills-config/ebook-build/<project>.metadata.yaml | Override metadata file |
| styleFile | No | ./.github/skills/ebook-build/assets/style.css | Override stylesheet file |
| configFile | No | - | JSON config file path (recommended in consumer repositories) |

## Shared Files

- ./scripts/invoke-ebook-build.ps1
- ./scripts/convert-to-kindle.ps1
- ./scripts/add-pagelist-functions.ps1
- ./assets/style.css
- ./docs/README.md
- ./docs/KINDLE-COMPATIBILITY-CHECKLIST.md

## Consumer Repository Files

- ./.github/skills-config/ebook-build/<repo>.build.json
- ./.github/skills-config/ebook-build/<repo>.metadata.yaml

Template files are provided in the central repository under:

- ./templates/ebook-build/repo.build.template.json
- ./templates/ebook-build/repo.metadata.template.yaml

## Quick Usage (in consumer repository)

```powershell
./.github/skills/ebook-build/scripts/invoke-ebook-build.ps1 \
  -ConfigFile ./.github/skills-config/ebook-build/<repo>.build.json
```

## Output

The skill writes artifacts such as:
- project-name.epub
- project-name.azw3 (if ebook-convert available)
- project-name.mobi (if ebook-convert available)

## Notes

- This skill is intentionally non-interactive for agent execution.
- It patches staged conversion scripts to disable terminal prompts.
- Metadata default search order is:
  1. ./.github/skills-config/ebook-build/<project>.metadata.yaml
  2. ./.github/skills/ebook-build/configs/<project>.metadata.yaml (legacy fallback)
- Regenerated files under `ebook-output/` are treated as reviewable build artifacts and should be included in commits when the source content, metadata, styles, or build flow changes.
- For the operational guide, see ./docs/README.md.
- For detailed flow and constraints, see ./EBOOK_BUILD_SPECIFICATION.md.
- For validation criteria, see ./VALIDATION_CHECKLIST.md and ./docs/KINDLE-COMPATIBILITY-CHECKLIST.md.
