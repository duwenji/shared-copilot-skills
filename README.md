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
- `templates/tutorial-content/` : Starter `README.md` / `docs/00-COVER.md` templates for new tutorial repositories
- `docs/OPERATIONS.md` : Tagging, release, and update policy

## Included skill

- `ebook-build`
- `quiz-generator`

## `ebook-build` highlights

The shared `ebook-build` skill now supports three publish-oriented outputs from the same Markdown source:

- `*.epub` — primary ebook artifact for KDP upload and EPUB readers
- `*.pdf` — fixed-layout review/print-oriented artifact generated via Pandoc + local Chrome/Edge
- `*-kdp-registration.md` — a Markdown checklist containing KDP metadata, pricing, categories, and upload references

Typical consumer configuration lives under `.github/skills-config/ebook-build/` and uses:

- `<repo>.build.json`
- `<repo>.metadata.yaml`
- optional `<repo>.kdp.yaml`

> For PDF generation, consumers should have **Pandoc**, **Node.js**, and a local **Chrome/Edge** installation available.

## Consumer integration (Git submodule)

Canonical mount path:

```bash
git submodule add https://github.com/<org>/shared-copilot-skills.git .github/skills/shared-copilot-skills
git commit -m "chore: add shared skills submodule"
```

Important: `git submodule` imports at repository granularity. You cannot install only an individual skill (for example, `ebook-build` only) with this method.

After clone:

```bash
git submodule update --init --recursive
```

Update to latest remote main (consumer controlled):

```bash
git submodule update --remote --merge .github/skills/shared-copilot-skills
git add .github/skills/shared-copilot-skills
git commit -m "chore: update shared skills submodule"
```

## Submodule update rule

Use this repository as the single source of truth for shared skills.

1. Change shared skills here.
2. Push the shared repository first.
3. Update each consumer repository submodule pointer after that.

Do not use `.gitignore` to hide or manage `.github/skills/shared-copilot-skills` changes.

- `.gitignore` is appropriate for generated local files.
- Submodule version changes must be reviewed and committed as submodule pointer updates.

## Scope boundary

- Shared in this repository: scripts, assets, skill docs, and skill definition
- Kept in each consumer repository: build config and metadata files

See `templates/ebook-build/`, `templates/quiz-generator/`, and `templates/tutorial-content/` for sample consumer files.

For new tutorial/material repositories, start from `templates/tutorial-content/README.template.md` and `templates/tutorial-content/00-COVER.template.md` so the `spa-quiz-app` guidance stays consistent.

For nested submodule mount (`.github/skills/shared-copilot-skills`), keep path-sensitive settings in consumer wrappers under `.github/skills-config/<skill-name>/`.
Legacy `.github/skills/shared-skills` mounts remain supported by the consumer wrapper for backward compatibility.
