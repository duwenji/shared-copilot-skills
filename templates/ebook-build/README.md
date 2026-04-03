# ebook-build consumer templates

These files are starting points for each consumer repository.

## Files

| Template file | Copy to consumer repo as |
|---|---|
| `invoke-build.template.ps1` | `.github/skills-config/ebook-build/invoke-build.ps1` |
| `repo.build.template.json` | `.github/skills-config/ebook-build/<repo>.build.json` |
| `repo.metadata.template.yaml` | `.github/skills-config/ebook-build/<repo>.metadata.yaml` |

## Setup steps

1. Copy all three files to `.github/skills-config/ebook-build/` in the consumer repository.
2. In `invoke-build.ps1`, replace `<repo-name>` with the actual project name.
3. In `<repo>.build.json`, fill in `projectName`, `sourceRoot`, `outputDir`, and `metadataFile` using forward-slash paths (`./...`).
4. In `<repo>.metadata.yaml`, fill in `title`, `creator`, `language`, and other book metadata.
5. Leave `styleFile` out unless you intentionally override the shared stylesheet; the wrapper resolves the default automatically.
6. Validate the config before release:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .github/skills/shared-copilot-skills/ebook-build/scripts/validate-consumer-config.ps1 -RepoRoot .
```

## Run command

From consumer repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .github/skills-config/ebook-build/invoke-build.ps1
```

The wrapper script (`invoke-build.ps1`) reads the build config, resolves all paths relative to the repo root, and delegates to the shared `invoke-ebook-build.ps1`. This approach avoids path resolution issues that arise when calling the shared script directly from a consumer repo.
