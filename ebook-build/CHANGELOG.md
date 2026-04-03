# Changelog

## ebook-build/v1.1.0

- Standardized the canonical consumer config contract across repositories.
- Added `validate-consumer-config.ps1` to check path format, required keys, and metadata consistency.
- Updated templates and docs to prefer forward-slash paths, `creator`, and `toc-depth: 2`.
- Added flat-docs compatibility support for repositories such as `spa-quiz-app` by passing chapter and cover settings through the shared runner.

## ebook-build/v1.0.0

- Initial central repository packaging of `ebook-build` skill.
- Includes scripts, shared style asset, and operation docs.
- Consumer-specific build and metadata configs moved to consumer repositories.
