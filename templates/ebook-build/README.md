# ebook-build consumer templates

These files are examples for each consumer repository.

Recommended location in consumer repository:

- `.github/skills-config/ebook-build/<repo>.build.json`
- `.github/skills-config/ebook-build/<repo>.metadata.yaml`

Run command from consumer repository root:

```powershell
.\.github\skills\ebook-build\scripts\invoke-ebook-build.ps1 `
  -ConfigFile .\.github\skills-config\ebook-build\<repo>.build.json
```
