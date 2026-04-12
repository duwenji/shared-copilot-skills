# Ebook Build 検証チェックリスト

## 判定ルール

- Critical: 出版可否に直結する欠陥（manuscript 未生成、承認ゲート破綻、重大文字化け、成果物欠落）
- Major: 品質低下が明確な欠陥（見出し階層崩れ、章順不整合、主要メタデータ不備）
- Minor: 軽微な改善事項（文言揺れ、注記不足）
- 承認条件: Critical 0 件 かつ Major 3 件以下
- 不承認条件: Critical 1 件以上 または Major 4 件以上

### Severity 具体例

- Critical 例:
	- `projectName.manuscript.md` が未生成
	- `buildPhase=continue` で承認トークン未配置なのに処理継続
	- 内部リンクが大量に壊れ、読了に支障
	- 生成成果物（epub/pdf/kdp）の必須ファイル欠落
- Major 例:
	- 見出し階層が不整合（章・節の構造が崩れる）
	- 章順/節順が番号順と不一致
	- Mermaid 図の一部が未変換で可読性低下
	- 主要 metadata（title/creator/language）不足
- Minor 例:
	- 表記揺れ（用語、句読点、全角半角）
	- 軽微な注記不足
	- 文言改善余地はあるが意味は維持

## A. Contract & Config（自動）

- [ ] `*.build.json` が JSON 構文として有効
- [ ] 必須キーが存在（`sourceRoot`, `outputDir`, `projectName`, `metadataFile`, `chapterDirPattern`, `chapterFilePattern`）
- [ ] `buildPhase` が `full|manuscript-only|continue`
- [ ] `requireManuscriptApproval` が bool
- [ ] `approvalTokenFile` が path 形式
- [ ] Mermaid 標準値（`mermaidMode=required`, `mermaidFormat=svg`, `failOnMermaidError=true`）

## B. Metadata Integrity（自動）

- [ ] metadata YAML が構文として有効
- [ ] `title`, `creator`, `language` が存在
- [ ] `creator` を使用（`author` のみ運用は不可）
- [ ] `toc-depth` 指定時に値が妥当

## C. Source Structure（自動）

- [ ] 章ディレクトリが `^\d{2}-` に一致
- [ ] 節ファイルが `^\d{2}-.*\.md$` に一致
- [ ] 章内ソート順が番号順
- [ ] `coverFile` または `coverTemplate` で表紙が解決可能

## D. Mermaid Processing（自動）

- [ ] Mermaid ブロック検出時に CLI 解決できる（`mmdc` 優先、次点 `npx`）
- [ ] 変換失敗時、`required` 運用としてビルドが失敗する
- [ ] 成功時、Markdown が画像参照へ置換される

## E. Manuscript Artifact（自動）

- [ ] `projectName.manuscript.md` が生成される
- [ ] ファイルが空でない
- [ ] UTF-8 で読める
- [ ] コードフェンスの開閉が崩れていない
- [ ] 見出し階層（`#`, `##`, `###`）が破綻していない

## F. Link & Reference（自動 + 手動）

- [ ] 内部アンカーリンク構文が有効（自動）
- [ ] 主要リンク先が文脈的に正しい（手動）

## G. Output Completeness（自動）

- [ ] `buildPhase=manuscript-only` で manuscript のみ収集して停止する
- [ ] 承認トークンなし `buildPhase=continue` は失敗する
- [ ] 承認トークンあり `buildPhase=continue` は epub/pdf/kdp 生成に進む
- [ ] `coverTemplateMode=file` で `coverFile` が優先される
- [ ] `coverTemplateMode=template` でテンプレートから表紙が生成される
- [ ] `coverTemplateMode=auto` で file 優先、template fallback が機能する
- [ ] 出力ファイル命名が `projectName` で一貫する

## H. Manual Editorial Review（手動）

- [ ] 文章可読性（段落崩れ・重複・意味破綻なし）
- [ ] 章立ての論理順（導入→本論→まとめ）
- [ ] 図表の可読性（Mermaid 含む）
- [ ] コード例の体裁（改行・インデント・説明）
- [ ] 権利表記/引用表記の妥当性

## Issue 記録テンプレート

- [ ] `ID`
- [ ] `Severity`（Critical/Major/Minor）
- [ ] `File/Section`
- [ ] `Observation`
- [ ] `Repro/Check Method`
- [ ] `Fix Recommendation`
- [ ] `Status`（Open/Resolved/Accepted Risk）

### 記録フォーマット（そのまま利用可）

```md
# Manuscript Review Report

- Project:
- Reviewer:
- Reviewed At:
- Build Phase: manuscript-only
- Decision: Approve / Reject
- Gate Result: Critical=<n>, Major=<n>, Minor=<n>

## Findings

### ISSUE-001
- Severity:
- File/Section:
- Observation:
- Repro/Check Method:
- Fix Recommendation:
- Status:

### ISSUE-002
- Severity:
- File/Section:
- Observation:
- Repro/Check Method:
- Fix Recommendation:
- Status:
```

- shared テンプレート: `assets/review-templates/manuscript-review-report.template.md`

## レビューフロー

1. `buildPhase=manuscript-only` を実行
2. 自動チェック（A〜G）を実行
3. 手動チェック（H）を実施
4. Issue を Critical/Major/Minor で集計
5. 判定（承認/不承認）
6. 承認時のみ `approvalTokenFile` を作成
7. `buildPhase=continue` を実行

### 推奨実行コマンド（pwsh）

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File ./.github/skills-config/ebook-build/invoke-build.ps1
```

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File ./scripts/new-manuscript-review-report.ps1 -RepoRoot .
```
