# Ebook Build Usage Guide

This guide explains how to use the shared `ebook-build` skill from a consumer repository.

## Layout in consumer repository

```text
.github/
├── skills/
│   └── shared-copilot-skills/              # Git submodule from shared-copilot-skills
│       └── ebook-build/
│           ├── SKILL.md
│           ├── scripts/
│           ├── assets/
│           └── docs/
└── skills-config/
    └── ebook-build/
        ├── <repo>.build.json               # Consumer-specific runtime config
        ├── <repo>.metadata.yaml            # Consumer-specific metadata
        └── invoke-build.ps1                # Local wrapper that resolves repo-specific paths

ebook-output/
```

## Run command

```powershell
./.github/skills-config/ebook-build/invoke-build.ps1
```

## Prerequisites

- Pandoc is available in PATH

```powershell
pandoc --version
```

## Config ownership

- Shared and versioned in submodule:
  - `.github/skills/shared-copilot-skills/ebook-build/scripts/*`
  - `.github/skills/shared-copilot-skills/ebook-build/assets/style.css`
  - `.github/skills/shared-copilot-skills/ebook-build/docs/*`
- Owned by each consumer repository:
  - `.github/skills-config/ebook-build/<repo>.build.json`
  - `.github/skills-config/ebook-build/<repo>.metadata.yaml`

## Canonical config contract

- Prefer forward-slash paths in JSON config values (`./ebook-output`, `./.github/skills-config/...`).
- Keep `styleFile` unset unless you need a custom stylesheet; the wrapper resolves the shared default safely.
- Prefer `creator` over `author` in metadata YAML.
- Set `toc-depth: 2` in metadata when you want stable section depth in the generated EPUB TOC.
- For manual-style repositories that do not use numbered chapter files, use the documented flat-docs compatibility profile (`chapterDirPattern: "^docs$"`, `chapterFilePattern: "^.*\\.md$"`, `coverFile: "README.md"`).

## Metadata default lookup

If `metadataFile` is not explicitly provided, the runner checks:

1. `.github/skills-config/ebook-build/<project>.metadata.yaml`
2. `.github/skills/ebook-build/configs/<project>.metadata.yaml` (legacy fallback)

## Validation checklist

After each build, verify:

- `../VALIDATION_CHECKLIST.md`

Focus on TOC integrity, heading hierarchy, internal links, chapter numbering, and code block rendering.

## Chapter and section contract

- Chapter directories must match `^\d{2}-`.
- Section files must match `^\d{2}-.*\.md$` unless the consumer config intentionally widens the pattern.
- Sections are discovered only from files directly under each chapter directory.
- `00-COVER.md` is treated as an optional cover file outside the chapter sequence.
- If `sourceRoot` does not contain chapter directories, the runner falls back to `sourceRoot/docs`.
- Chapter and section display titles are derived from folder and file names, not markdown H1 headings.

## Troubleshooting

### Pandoc not found

- Install Pandoc
- Restart PowerShell

### Markdown files are not detected

- Confirm chapter directory names match `^\d{2}-`
- Confirm chapter file names match `^\d{2}-.*\.md$`
