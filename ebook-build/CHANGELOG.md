# Changelog

## ebook-build/v2.1.0

- 仕様文書を日本語運用に統一（`SKILL.md`, `EBOOK_BUILD_SPECIFICATION.md`, `VALIDATION_CHECKLIST.md`）。
- `EBOOK_BUILD_SPECIFICATION.md` に Mermaid シーケンス図を追加（通常ビルド、Mermaid前処理、manuscript承認ゲート）。
- `scripts/invoke-ebook-build.ps1` に 2 段階承認ゲートを追加。
	- `buildPhase`: `full | manuscript-only | continue`
	- `requireManuscriptApproval`: 承認トークン必須化
	- `approvalTokenFile`: 承認トークンパス指定
- `scripts/invoke-ebook-build.ps1` に表紙テンプレート切替を追加。
	- `coverTemplateMode`: `auto | file | template`
	- `coverTemplate`: テンプレート名
- shared 側に標準表紙テンプレートを追加。
	- `assets/cover-templates/classic.md`
	- `assets/cover-templates/minimal.md`
	- `assets/cover-templates/technical.md`
- `scripts/validate-consumer-config.ps1` を拡張し、新規契約キーの検証を追加。
- `templates/ebook-build/*` を新契約（承認ゲート/表紙テンプレート/strict Mermaid）に同期。
- `scripts/new-manuscript-review-report.ps1` を追加し、manuscript レビューレポートをテンプレートから自動生成可能にした。
- `assets/review-templates/manuscript-review-report.template.md` を追加し、レビュー記録フォーマットを共通化した。

## ebook-build/v2.0.0

- Promoted `SKILL.md` to the canonical interface entrypoint and removed dependency on `docs/*` references.
- Standardized Mermaid policy to strict mode by default:
	- `mermaidMode`: `required`
	- `mermaidFormat`: `svg`
	- `failOnMermaidError`: `true`
- Updated `scripts/invoke-ebook-build.ps1` defaults to match the strict Mermaid contract.
- Updated `scripts/validate-consumer-config.ps1` to enforce the strict Mermaid contract in consumer `*.build.json` files.
- Updated validation criteria to require Mermaid image rendering and strict Mermaid config values.
- Removed the `docs/` directory from the shared skill package and consolidated normative guidance into:
	- `SKILL.md`
	- `EBOOK_BUILD_SPECIFICATION.md`
	- `VALIDATION_CHECKLIST.md`

## ebook-build/v1.1.0

- Standardized the canonical consumer config contract across repositories.
- Added `validate-consumer-config.ps1` to check path format, required keys, and metadata consistency.
- Updated templates and docs to prefer forward-slash paths, `creator`, and `toc-depth: 2`.
- Added flat-docs compatibility support for repositories such as `spa-quiz-app` by passing chapter and cover settings through the shared runner.

## ebook-build/v1.0.0

- Initial central repository packaging of `ebook-build` skill.
- Includes scripts, shared style asset, and operation docs.
- Consumer-specific build and metadata configs moved to consumer repositories.
