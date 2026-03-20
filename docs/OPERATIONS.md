# Operations

## Versioning and tags

Use semantic versioning per skill.

- Tag format: `ebook-build/vMAJOR.MINOR.PATCH`
- PATCH: bug fix, backward compatible
- MINOR: feature addition, backward compatible
- MAJOR: breaking change

Every release must include:

1. `ebook-build/CHANGELOG.md` update
2. Validation summary
3. Migration notes for MAJOR and MINOR updates

## Branch and PR policy

- Protected branch: `main`
- Branch naming:
  - `feat/ebook-build-<topic>`
  - `fix/ebook-build-<topic>`
- PR title format: `ebook-build: <type> <summary>`
- Required review: at least 1 reviewer

## Consumer update policy

Consumers update at their own timing.

- Critical fix updates: target within 48 hours
- Feature updates: target next sprint or later
- Consumer PR should contain submodule pointer update only

## Rollback policy

Rollback by reverting consumer submodule pointer to last known good commit.
