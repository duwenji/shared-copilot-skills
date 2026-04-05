---
name: ebook-build
description: Build EPUB ebooks from numbered markdown projects using PowerShell. Use when generating publishable EPUB files in a consumer repository that references this skill via Git submodule.
license: MIT
---

# Ebook Build Skill

## Overview

This skill packages a reusable ebook build flow for multi-repository distribution.

It is designed for:
- Building EPUB and PDF ebooks from numbered markdown chapter structures
- Emitting shared cover artifacts as `cover.pdf` and `cover.jpg` in `ebook-output/`
- Reusing the same conversion scripts across repositories
- Consumer-side configuration with repository-specific metadata and output policy

## What This Skill Does

1. Detects source content root (direct or docs/)
2. Prepares an isolated build workspace
3. Reuses shared conversion scripts and templates
4. Builds EPUB/PDF from numbered markdown chapter structures
5. Generates `cover.pdf` and `cover.jpg` when PDF output is requested
6. Copies the resulting artifacts to the target output directory

## Requirements

- Windows PowerShell 5.1+
- Pandoc installed and available in PATH
- Node.js plus a local Chrome or Edge installation when generating PDF and cover artifacts

## Inputs

Primary script: ./scripts/invoke-ebook-build.ps1

| Parameter | Required | Default | Description |
|---|---|---|---|
| sourceRoot | Yes | - | Source project root or docs root containing chapter folders |
| outputDir | No | sourceRoot/ebook-output | Destination for final ebook artifacts |
| projectName | No | folder name of sourceRoot | Base filename for outputs |
| formats | No | [epub] | Optional compatibility input. Supported values are `epub`, `pdf`, and `kdp-markdown` |
| chapterDirPattern | No | ^\\d{2}- | Chapter directory pattern |
| chapterFilePattern | No | ^\\d{2}-.*\\.md$ | Chapter file pattern |
| coverFile | No | 00-COVER.md | Optional cover filename |
| preserveTemp | No | false | Keep temporary staging directory |
| metadataFile | No | ./.github/skills-config/ebook-build/<project>.metadata.yaml | Override metadata file |
| styleFile | No | auto-resolved from the shared skill root | Override stylesheet file only when you intentionally replace the shared default |
| configFile | No | - | JSON config file path (recommended in consumer repositories) |

## Shared Files

- ./scripts/invoke-ebook-build.ps1
- ./scripts/convert-to-kindle.ps1
- ./assets/style.css
- ./docs/README.md

## Consumer Repository Files

- ./.github/skills-config/ebook-build/<repo>.build.json
- ./.github/skills-config/ebook-build/<repo>.metadata.yaml

Template files are provided in the central repository under:

- ./templates/ebook-build/repo.build.template.json
- ./templates/ebook-build/repo.metadata.template.yaml

## Quick Usage (in consumer repository)

```powershell
./.github/skills-config/ebook-build/invoke-build.ps1
```

## Output

The skill writes artifacts such as:
- `project-name.epub`
- `project-name.pdf`
- `cover.pdf`
- `cover.jpg`
- `project-name-kdp-registration.md`

## Notes

- This skill is intentionally non-interactive for agent execution.
- It patches staged conversion scripts to disable terminal prompts.
- Chapter and section display titles are derived from folder and file slugs, not markdown H1 headings.
- Canonical consumer JSON paths use forward slashes (`./...`) for cross-environment consistency.
- Canonical metadata uses `creator` rather than `author` and should usually include `toc-depth: 2`.
- Metadata default search order is:
  1. ./.github/skills-config/ebook-build/<project>.metadata.yaml
  2. ./.github/skills/ebook-build/configs/<project>.metadata.yaml (legacy fallback)
- Regenerated files under `ebook-output/` are treated as reviewable build artifacts and should be included in commits when the source content, metadata, styles, or build flow changes.
- For the operational guide, see ./docs/README.md.
- For detailed flow and constraints, see ./EBOOK_BUILD_SPECIFICATION.md.
- For validation criteria, see ./VALIDATION_CHECKLIST.md.
