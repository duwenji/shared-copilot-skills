# Ebook Build Specification

## Goal

Provide a reusable, agent-friendly build workflow for markdown repositories that follow numbered chapter conventions and need EPUB, PDF, a preserved merged manuscript at `projectName.manuscript.md`, fixed-name `cover.pdf` / `cover.jpg`, and KDP registration Markdown artifacts.

## Canonical Consumer Config Contract

Preferred JSON shape:

```json
{
  "sourceRoot": ".",
  "outputDir": "./ebook-output",
  "projectName": "replace-with-project-name",
  "formats": ["epub", "pdf", "kdp-markdown"],
  "metadataFile": "./.github/skills-config/ebook-build/replace-with-project-name.metadata.yaml",
  "kdpMetadataFile": "./.github/skills-config/ebook-build/replace-with-project-name.kdp.yaml",
  "chapterDirPattern": "^\\d{2}-",
  "chapterFilePattern": "^\\d{2}-.*\\.md$",
  "coverFile": "00-COVER.md"
}
```

Rules:

- Use forward-slash path notation in consumer JSON config.
- `styleFile` is optional and should normally be omitted so the wrapper can resolve the shared default.
- `formats` may include `epub`, `pdf`, and `kdp-markdown`.
- `kdpMetadataFile` is optional; when omitted, the generator falls back to the base metadata file and placeholder defaults.
- Repositories that need a broader `chapterFilePattern` such as `^.*\\.md$` should use the documented flat-docs compatibility profile rather than an ad hoc exception.
- Optional Mermaid keys are supported for EPUB-safe diagram rendering:
  - `mermaidMode`: `off | auto | required` (default: `auto`)
  - `mermaidFormat`: `svg | png` (default: `svg`)
  - `failOnMermaidError`: `true | false` (default: `false`)

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
7. Copy the generated artifacts to `outputDir` using `projectName` as the filename base, including the preserved merged manuscript `projectName.manuscript.md`; when `pdf` is requested, also emit fixed-name `cover.pdf` and `cover.jpg` in the same folder. `cover.pdf` is sized as a paperback cover spread using the trim size plus a spine width derived from the generated page count.
8. Optionally generate `projectName-kdp-registration.md` from the base metadata and optional KDP metadata.
9. Fail if any requested artifact was not produced.
10. Clean temporary workspace unless `preserveTemp` is enabled.

## Optional Mermaid Preprocessing

When `mermaidMode` is `auto` or `required`, the runner scans staged markdown for fenced `mermaid` blocks and renders them to `images/mermaid/` before `pandoc` runs.

Resolution order:

1. `mmdc`
2. `npx @mermaid-js/mermaid-cli`

If rendering is unavailable:

- `auto`: warn and leave the source block unchanged
- `required`: fail the build with a clear diagnostic

Use `svg` by default for quality and file size. Switch to `png` only for EPUB readers with poor SVG support.

## Format Behavior

- `projectName.manuscript.md`: the merged Markdown manuscript is preserved in `outputDir` whenever the document converter runs, so reviewers can inspect the exact assembled source used for ebook generation.
- `epub`: generated by Pandoc when requested.
- `pdf`: generated via an HTML print pass and a local Chrome/Edge renderer for a fixed-layout style output. When requested, the workflow also emits `cover.pdf` and `cover.jpg` to `outputDir` using fixed filenames. The standalone `cover.pdf` is rendered as a KDP-style full cover sheet (front panel on the right, blank back/spine areas) using trim size metadata and the final PDF page count.
- `kdp-markdown`: generated as `projectName-kdp-registration.md` using the base metadata and optional KDP-specific overrides.
- Mermaid diagrams are embedded as static images when preprocessing is enabled and a supported renderer is available.

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
