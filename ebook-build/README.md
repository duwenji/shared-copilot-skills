# ebook-build README

## 結論

この Skill は、電子書籍生成を 3 ステップに分割して実行する構成です。

- Step1: 原稿統合
- Step2: 表紙生成
- Step3: 最終化（Mermaid 変換 + EPUB/PDF/KDP）

共通ハブは使わず、各ステップは独立スクリプトとして実装されています。

## 主要スクリプト

- scripts/invoke-ebook-step1-manuscript.ps1
- scripts/invoke-ebook-step2-cover.ps1
- scripts/invoke-ebook-step3-finalize.ps1

## モジュール参照関係

結論として、公開モジュールは 3 ステップスクリプトのみです。

### 実行フロー依存（Step間）

| From | To | 種別 | 備考 |
|---|---|---|---|
| invoke-ebook-step1-manuscript.ps1 | `<project>.manuscript.md` | 生成物依存 | Step3 の必須入力 |
| invoke-ebook-step2-cover.ps1 | `cover.jpg` | 生成物依存 | Step3 の必須入力 |
| invoke-ebook-step3-finalize.ps1 | Step1/Step2 の成果物 | 入力依存 | 欠落時は Fail Fast |

### 補足

- `scripts` 配下は 3 ファイルのみを維持します。
- 各 Step スクリプトは self-contained で、共通 PowerShell モジュールの dot-source 参照はありません。

## 参照関係の確認コマンド

以下を実行すると、README の表と実装の整合を確認できます。

```powershell
Get-ChildItem -Path ./scripts -File | Select-Object -ExpandProperty Name
Select-String -Path ./scripts/invoke-ebook-step3-finalize.ps1 -Pattern 'manuscript\.md|cover\.jpg'
```

## ステップ別 I/O

### Step1: invoke-ebook-step1-manuscript.ps1

- Input: SourceRoot, MetadataFile, chapter/cover 設定
- Output: ebook-output/<project>.manuscript.md

### Step2: invoke-ebook-step2-cover.ps1

- Input: SourceRoot, MetadataFile, cover/template 設定
- Output: ebook-output/cover.jpg

### Step3: invoke-ebook-step3-finalize.ps1

- Input:
  - ebook-output/<project>.manuscript.md
  - ebook-output/cover.jpg
  - MetadataFile
- Output:
  - ebook-output/<project>.epub
  - ebook-output/<project>.pdf
  - ebook-output/<project>-kdp-registration.md
  - ebook-output/images/mermaid/*

## 実行例

```powershell
# Step1
pwsh -NoProfile -ExecutionPolicy Bypass -File ./scripts/invoke-ebook-step1-manuscript.ps1 -SourceRoot . -OutputDir ./ebook-output -ProjectName <project> -MetadataFile ./.github/skills-config/ebook-build/<project>.metadata.yaml -KindleTemplateDir ./scripts -StyleFile ./assets/style.css

# Step2
pwsh -NoProfile -ExecutionPolicy Bypass -File ./scripts/invoke-ebook-step2-cover.ps1 -SourceRoot . -OutputDir ./ebook-output -ProjectName <project> -MetadataFile ./.github/skills-config/ebook-build/<project>.metadata.yaml -KindleTemplateDir ./scripts -StyleFile ./assets/style.css

# Step3
pwsh -NoProfile -ExecutionPolicy Bypass -File ./scripts/invoke-ebook-step3-finalize.ps1 -OutputDir ./ebook-output -ProjectName <project> -MetadataFile ./.github/skills-config/ebook-build/<project>.metadata.yaml -KindleTemplateDir ./scripts -StyleFile ./assets/style.css -Formats epub,pdf,kdp-markdown
```

## ポリシー

- Fail Fast: 必須入力不足時は即時停止
- Step3 は Step1/Step2 成果物を再利用し、欠落時は失敗
- Mermaid 標準契約: mermaidMode=required, mermaidFormat=svg, failOnMermaidError=true