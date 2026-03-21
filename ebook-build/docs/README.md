# Ebook Build Usage Guide

This guide explains how to use the shared `ebook-build` skill from a consumer repository.

## Layout in consumer repository

```text
.github/
├── skills/
│   └── ebook-build/                         # Git submodule from shared-copilot-skills
│       ├── SKILL.md
│       ├── scripts/
│       ├── assets/
│       └── docs/
└── skills-config/
    └── ebook-build/
        ├── <repo>.build.json               # Consumer-specific runtime config
        └── <repo>.metadata.yaml            # Consumer-specific metadata

ebook-output/
```

## Run command

```powershell
.\.github\skills\ebook-build\scripts\invoke-ebook-build.ps1 `
  -ConfigFile .\.github\skills-config\ebook-build\<repo>.build.json
```

## Prerequisites

- Pandoc is available in PATH
- Calibre `ebook-convert` is available in PATH for AZW3/MOBI generation

```powershell
pandoc --version
ebook-convert --version
```

## Config ownership

- Shared and versioned in submodule:
  - `.github/skills/ebook-build/scripts/*`
  - `.github/skills/ebook-build/assets/style.css`
  - `.github/skills/ebook-build/docs/*`
- Owned by each consumer repository:
  - `.github/skills-config/ebook-build/<repo>.build.json`
  - `.github/skills-config/ebook-build/<repo>.metadata.yaml`

## Metadata default lookup

If `metadataFile` is not explicitly provided, the runner checks:

1. `.github/skills-config/ebook-build/<project>.metadata.yaml`
2. `.github/skills/ebook-build/configs/<project>.metadata.yaml` (legacy fallback)

## Validation checklist

After each build, verify:

- `./KINDLE-COMPATIBILITY-CHECKLIST.md`
- `../VALIDATION_CHECKLIST.md`

Focus on TOC integrity, heading hierarchy, internal links, and code block rendering.

## Reader-first page-list guidance

- `enablePageList: true` generates page-list entries from heading anchors first, which improves practical navigation in readers.
- Build order applies page-list to EPUB before AZW3/MOBI conversion, so output formats stay aligned.
- Recommended operation:
  - Draft iterations (speed-first): set `enablePageList` to `false`
  - Release candidates (reader UX): set `enablePageList` to `true`

## Troubleshooting

### Pandoc not found

- Install Pandoc
- Restart PowerShell

### ebook-convert not found

- Install Calibre
- Restart PowerShell

### Markdown files are not detected

- Confirm chapter directory names match `^\d{2}-`
- Confirm chapter file names match `^\d{2}-.*\.md$`
