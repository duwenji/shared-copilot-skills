# Ebook Build Validation Checklist

## Build Execution

- [ ] Runner exits with code 0
- [ ] No unexpected interactive prompts appear
- [ ] Output directory is created or reused successfully

## Artifacts

- [ ] EPUB output exists
- [ ] Output filenames use `projectName` as the base name
- [ ] Exactly one EPUB artifact is copied to output

## Structural Quality

- [ ] TOC is generated
- [ ] Internal links work
- [ ] Heading hierarchy is readable
- [ ] Chapter order matches numbered folders
- [ ] Section order matches numbered files
- [ ] Chapter and section headings display their numeric prefixes
- [ ] Code blocks render correctly
- [ ] EPUB navigation works without a page-list section

## Configuration Consistency

- [ ] Consumer `*.build.json` files use forward-slash paths (`./...`)
- [ ] Consumer metadata uses `creator` instead of legacy `author`
- [ ] `styleFile` is omitted unless a custom stylesheet is intentionally required
- [ ] `validate-consumer-config.ps1` passes for the target repository set

## Repository Integrity

- [ ] Cover file is included when `00-COVER.md` exists
- [ ] Root `README.md` remains valid after TOC refresh (when present)
- [ ] Chapter and section titles are derived from folder and file names, not markdown H1 headings

## Compatibility

- [ ] Preview EPUB in an EPUB reader
- [ ] Validate EPUB in at least one reader without Kindle-specific tooling
