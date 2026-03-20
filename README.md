# shared-copilot-skills

Central repository for reusable GitHub Copilot skills.

This repository is intended to be consumed from business repositories via Git submodule with pinned commit versions.

## Repository layout

- `skills/<skill-name>/SKILL.md` : Skill definition and bundled assets
- `skills/<skill-name>/scripts/` : Reusable automation scripts
- `skills/<skill-name>/assets/` : Shared assets
- `skills/<skill-name>/docs/` : Skill operation and validation docs
- `skills/<skill-name>/CHANGELOG.md` : Per-skill release notes
- `templates/<skill-name>/` : Consumer-side template files (repo-specific config)
- `docs/OPERATIONS.md` : Tagging, release, and update policy

## Included skill

- `ebook-build`

## Consumer integration (Git submodule)

```bash
git submodule add https://github.com/<org>/shared-copilot-skills.git .github/skills/ebook-build
git commit -m "chore: add ebook-build submodule"
```

After clone:

```bash
git submodule update --init --recursive
```

Update to latest remote main (consumer controlled):

```bash
git submodule update --remote --merge .github/skills/ebook-build
git add .github/skills/ebook-build
git commit -m "chore: update ebook-build skill"
```

## Scope boundary

- Shared in this repository: scripts, assets, skill docs, and skill definition
- Kept in each consumer repository: build config and metadata files

See `templates/ebook-build/` for sample consumer files.
