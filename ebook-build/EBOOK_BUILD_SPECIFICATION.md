# Ebook Build Specification

## Goal

Provide a reusable, agent-friendly, self-contained EPUB build workflow for markdown repositories that follow numbered chapter conventions.

## Canonical Consumer Config Contract

Preferred JSON shape:

```json
{
  "sourceRoot": ".",
  "outputDir": "./ebook-output",
  "projectName": "replace-with-project-name",
  "metadataFile": "./.github/skills-config/ebook-build/replace-with-project-name.metadata.yaml",
  "chapterDirPattern": "^\\d{2}-",
  "chapterFilePattern": "^\\d{2}-.*\\.md$",
  "coverFile": "00-COVER.md"
}
```

Rules:

- Use forward-slash path notation in consumer JSON config.
- `styleFile` is optional and should normally be omitted so the wrapper can resolve the shared default.
- Repositories that need a broader `chapterFilePattern` such as `^.*\\.md$` should use the documented flat-docs compatibility profile rather than an ad hoc exception.

Flat-docs compatibility profile (for manual-style repos such as `spa-quiz-app`):

```json
{
  "sourceRoot": ".",
  "outputDir": "./ebook-output",
  "projectName": "repo-name",
  "metadataFile": "./.github/skills-config/ebook-build/repo-name.metadata.yaml",
  "chapterDirPattern": "^docs$",
  "chapterFilePattern": "^.*\\.md$",
  "coverFile": "README.md"
}
```

## Canonical Metadata Contract

Preferred YAML keys:

- `title`
- `creator`
- `language`
- `rights`
- `date`
- `publisher`
- `identifier`
- `subject`
- `toc-depth` (recommended value: `2`)

`author` is treated as a legacy form and should be migrated to `creator` in consumer repositories.

## Source Discovery

Given `sourceRoot`:

1. If `sourceRoot` contains chapter directories matching `chapterDirPattern`, use `sourceRoot`.
2. Otherwise, if `sourceRoot/docs` contains matching chapter directories, use `sourceRoot/docs`.
3. Otherwise, fail with a clear diagnostic.

## Chapter Contract

- Chapter directories: `chapterDirPattern` (default `^\\d{2}-`)
- Section markdown files: `chapterFilePattern` (default `^\\d{2}-.*\\.md$`) located directly under each chapter directory
- Cover file: `coverFile` (default `00-COVER.md`, optional) and treated as outside the chapter sequence
- Root `README.md`: optional, copied into staging when present so converter-side TOC updates remain safe
- Nested section subdirectories are out of scope for this workflow
- Display titles are derived from folder and file slugs, with the leading numeric prefix preserved in EPUB headings

## Staging Contract

The runner creates an isolated temporary workspace:

- `temp/book/` staged source root
- `temp/book/kindle/` staged conversion scripts, metadata, and stylesheet
- `temp/book/kindle/output/` intermediate outputs

## Build Steps

1. Resolve configuration values from command-line parameters, config file, and defaults.
2. Validate required file paths and discover the effective content root.
3. Stage chapter content, optional cover, and optional root `README.md`.
4. Stage converter scripts, metadata, and stylesheet.
5. Patch the staged converter for non-interactive execution.
6. Run the staged converter.
7. Copy the generated EPUB to `outputDir` using `projectName` as the filename base.
8. Fail if the EPUB artifact was not produced.
9. Clean temporary workspace unless `preserveTemp` is enabled.

## Format Behavior

- `epub`: expected if Pandoc is available

## Error Strategy

Hard fail:

- source root not found
- metadata or stylesheet not found
- core conversion script missing
- no chapter content found
- staged converter exits with non-zero status
- EPUB artifact not produced by the converter

## Reuse Scope

Reusable across repositories that satisfy the chapter contract and provide project-specific config + metadata.

Project-specific responsibilities:

- maintain each project's `.github/skills-config/ebook-build/*.build.json`
- maintain each project's `.github/skills-config/ebook-build/*.metadata.yaml`
- keep `projectName`, `sourceRoot`, and output policy aligned with repository layout
