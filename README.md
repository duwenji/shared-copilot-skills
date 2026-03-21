# shared-copilot-skills

Central repository for reusable GitHub Copilot skills.

This repository is intended to be consumed from business repositories via Git submodule with pinned commit versions.

## Repository layout

- `<skill-name>/SKILL.md` : Skill definition and bundled assets
- `<skill-name>/scripts/` : Reusable automation scripts
- `<skill-name>/assets/` : Shared assets
- `<skill-name>/docs/` : Skill operation and validation docs
- `<skill-name>/prompts/` : Reusable generation prompts (optional)
- `<skill-name>/CHANGELOG.md` : Per-skill release notes
- `templates/<skill-name>/` : Consumer-side template files (repo-specific config)
- `docs/OPERATIONS.md` : Tagging, release, and update policy

## Included skill

- `ebook-build`
- `quiz-generator`

## Consumer integration (Git submodule)

```bash
git submodule add https://github.com/<org>/shared-copilot-skills.git .github/skills
git commit -m "chore: add shared skills submodule"
```

After clone:

```bash
git submodule update --init --recursive
```

Update to latest remote main (consumer controlled):

```bash
git submodule update --remote --merge .github/skills
git add .github/skills
git commit -m "chore: update shared skills submodule"
```

## Scope boundary

- Shared in this repository: scripts, assets, skill docs, and skill definition
- Kept in each consumer repository: build config and metadata files

See `templates/ebook-build/` and `templates/quiz-generator/` for sample consumer files.

For nested submodule mount (`.github/skills/shared-copilot-skills`), keep path-sensitive settings in consumer wrappers under `.github/skills-config/<skill-name>/`.
