# Ebook Build Validation Checklist

## Build Execution

- [ ] Runner exits with code 0
- [ ] No unexpected interactive prompts appear
- [ ] Output directory is created or reused successfully

## Artifacts

- [ ] EPUB output exists
- [ ] AZW3 output exists or a clear warning is shown
- [ ] MOBI output exists or a clear warning is shown
- [ ] Output filenames use `projectName` as the base name
- [ ] At least one requested artifact is copied to output

## Structural Quality

- [ ] TOC is generated
- [ ] Internal links work
- [ ] Heading hierarchy is readable
- [ ] Code blocks render correctly

## Repository Integrity

- [ ] Cover file is included when `00-COVER.md` exists
- [ ] Root `README.md` remains valid after TOC refresh (when present)
- [ ] Chapter order matches numbered folders and files

## EPUB Optional Feature

- [ ] Page-list step runs when `enablePageList` is true and helper script exists
- [ ] If helper script is missing, warning is logged and build still succeeds

## Compatibility

- [ ] Review `docs/KINDLE-COMPATIBILITY-CHECKLIST.md`
- [ ] Preview EPUB in an EPUB reader
- [ ] Validate AZW3/MOBI on the target Kindle environment
