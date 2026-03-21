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

## Submodule workflow

Shared skill changes must be made in `shared-copilot-skills` first.

1. Modify the shared skill in this repository.
2. Commit and push the shared repository.
3. In each consumer repository, update `.github/skills` to the target commit.
4. Commit the submodule pointer update in the consumer repository.

Do not use `.gitignore` to manage shared skill updates.

- `.gitignore` can ignore generated local files.
- `.gitignore` cannot replace submodule pointer management.
- Hiding `.github/skills` changes via ignore rules makes shared skill updates harder to review.

If a consumer wants to suppress noisy local submodule worktree changes temporarily, use submodule-specific Git settings with care. Do not use that as the default team policy.

## Rollback policy

Rollback by reverting consumer submodule pointer to last known good commit.
