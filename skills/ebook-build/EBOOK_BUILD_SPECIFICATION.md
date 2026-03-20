# Ebook Build Specification

## Goal

Provide a reusable, agent-friendly, self-contained ebook build workflow for markdown repositories that follow numbered chapter conventions.

## Source Discovery

Given `sourceRoot`:

1. If `sourceRoot` contains chapter directories matching `chapterDirPattern`, use `sourceRoot`.
2. Otherwise, if `sourceRoot/docs` contains matching chapter directories, use `sourceRoot/docs`.
3. Otherwise, fail with a clear diagnostic.

## Chapter Contract

- Chapter directories: `chapterDirPattern` (default `^\\d{2}-`)
- Section markdown files: `chapterFilePattern` (default `^\\d{2}-.*\\.md$`)
- Cover file: `coverFile` (default `00-COVER.md`, optional)
- Root `README.md`: optional, copied into staging when present so converter-side TOC updates remain safe

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
7. Copy requested artifacts to `outputDir` using `projectName` as the filename base.
8. Fail if no requested artifacts were copied.
9. Clean temporary workspace unless `preserveTemp` is enabled.

## Page-List Behavior

- Default behavior is controlled by `enablePageList`.
- If `enablePageList: true` and `add-pagelist-functions.ps1` is missing, the runner logs a warning and continues with page-list disabled.

## Format Behavior

- `epub`: expected if Pandoc is available
- `azw3`: expected when `ebook-convert` is available
- `mobi`: expected when `ebook-convert` is available

Missing optional formats produce warnings, not hard failures.

## Error Strategy

Hard fail:

- source root not found
- metadata or stylesheet not found
- core conversion script missing
- no chapter content found
- staged converter exits with non-zero status
- no requested artifacts copied to output directory

Soft warnings:

- optional output format not produced
- page-list requested but helper script missing

## Reuse Scope

Reusable across repositories that satisfy the chapter contract and provide project-specific config + metadata.

Project-specific responsibilities:

- maintain each project's `.github/skills-config/ebook-build/*.build.json`
- maintain each project's `.github/skills-config/ebook-build/*.metadata.yaml`
- keep `projectName`, `sourceRoot`, and output policy aligned with repository layout
