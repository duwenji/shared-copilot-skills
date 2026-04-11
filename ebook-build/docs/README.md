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
- Node.js is optional but recommended when the source contains Mermaid diagrams; the runner will use `mmdc` or `npx @mermaid-js/mermaid-cli` when Mermaid preprocessing is enabled

```powershell
pandoc --version
node --version
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
- Manual-style repositories must still be expressed as numbered chapter directories and numbered section files; the flat `docs/*.md` compatibility profile is deprecated.

## Metadata default lookup

If `metadataFile` is not explicitly provided, the runner checks:

1. `.github/skills-config/ebook-build/<project>.metadata.yaml`
2. `.github/skills/ebook-build/configs/<project>.metadata.yaml` (legacy fallback)

## Validation checklist

After each build, verify:

- `../VALIDATION_CHECKLIST.md`

Focus on TOC integrity, heading hierarchy, internal links, chapter numbering, code block rendering, and Mermaid image rendering when enabled.

## Architecture and debugging references

Use these documents together when investigating generation behavior:

- `../EBOOK_BUILD_SPECIFICATION.md` — contract, config, output expectations, and manuscript assembly rules
- `./GENERATION-PIPELINE.md` — current end-to-end pipeline with Mermaid sequence and flow diagrams, including the multi-file merge process

## Optional Mermaid preprocessing

The shared runner can convert fenced `mermaid` blocks into static images before `pandoc` generates the EPUB.

Recommended consumer config:

```json
{
  "mermaidMode": "auto",
  "mermaidFormat": "svg",
  "failOnMermaidError": false
}
```

Behavior:

- `off`: skip Mermaid processing and keep the source block as-is
- `auto`: try `mmdc`, then `npx @mermaid-js/mermaid-cli`; warn and continue if rendering is unavailable
- `required`: fail the build if Mermaid rendering cannot be completed

Use `png` only when a target EPUB reader has SVG rendering issues.

## Chapter and section contract

- Chapter directories must match `^\d{2}-`.
- Section files must match `^\d{2}-.*\.md$`; intentionally widening the pattern is treated as non-compliant.
- Sections are discovered only from files directly under each chapter directory.
- `00-COVER.md` is treated as an optional cover file outside the chapter sequence.
- If `sourceRoot` does not contain chapter directories, the runner falls back to `sourceRoot/docs`.
- Chapter display titles prefer the first H1 from chapter `README.md`, then fall back to a single section file H1, and finally to the directory slug.
- Section display titles prefer the first H1 from the section file and fall back to the file slug when no H1 is present.

## Troubleshooting

### Pandoc not found

- Install Pandoc
- Restart PowerShell

### Markdown files are not detected

- Confirm chapter directory names match `^\d{2}-`
- Confirm chapter file names match `^\d{2}-.*\.md$`

### Mermaid blocks stay as text

- Set `"mermaidMode": "auto"` or `"required"` in the consumer build config
- Confirm `node` and `npx` are available, or install `mmdc` globally
- Re-run the build and verify that the generated EPUB shows diagrams as images instead of source text
