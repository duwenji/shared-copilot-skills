# CHANGELOG

## [v2.0.0] - 2026-04-11 BREAKING

### Changed
- **BREAKING** `New-BookManuscript` / `New-PdfReaderManuscript`: `shouldPreserveVirtualSectionNesting` ロジックを廃止。
  抑制（suppressed）経路の先頭ファイル本文見出しを `N.1.1` 形式から `N.1` 形式へ変更。
  `headingLevelOffset` は `$renderSectionHeading` のみで決定し、`includeSectionNumberInBody` も同様。
- `EBOOK_BUILD_SPECIFICATION.md`: virtual `N.1` ネスト仕様を削除し、平坦化規則（`N.1 本文`）に更新。

### Migration
- 依存リポジトリは `ebook:build` を再実行して manuscript を再生成し、見出し差分を確認してください。
- 旧 `3.1.1` を前提にした内部リンク（raw hash）がある場合は別途修正が必要です。

---

## v1.1.0 - 2026-04-05

### Added
- Added `templates/tutorial-content/README.template.md` and `00-COVER.template.md` for new tutorial/material repositories
- Standardized the `spa-quiz-app` guidance line to `関連トピックをクイズ形式で復習できます`

### Changed
- Documented the new tutorial-content template flow in `README.md`, `CONTRIBUTING.md`, and `PUBLISHING.md`
- Extended the validation checklist to verify the standardized quiz callout

## v1.0.0 - 2026-04-04

### Added
- Added repository-level guidance files for operations, validation, and contribution flow
- Clarified the role of this repository as the central source for reusable shared skills
