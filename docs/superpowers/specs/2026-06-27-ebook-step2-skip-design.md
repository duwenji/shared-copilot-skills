# Design: ebook-build step2 タイムスタンプベーススキップ

**Date:** 2026-06-27  
**Status:** Approved  
**Scope:** `shared-copilot-skills/ebook-build/scripts/invoke-build.ps1`

---

## 背景と目的

ebook-build の step2（カバー生成）は AI 画像生成 API を呼び出すため、実行コストと時間がかかる。ソースファイル（カバープロンプト、メタデータ）が前回のビルド以降に変更されていない場合、step2 をスキップすることで不要な API コールと待機時間を排除する。

判定方法はタイムスタンプ比較（Make 方式）：**すべての出力ファイルが存在し、かつ最も古い出力 > 最も新しい入力** の場合にスキップ。

---

## 変更対象ファイル

| ファイル | 変更内容 |
|---|---|
| `shared-copilot-skills/ebook-build/scripts/invoke-build.ps1` | ヘルパー関数追加、`-Force` パラメータ追加、step2 ブランチにスキップロジック追加 |
| `agent-skills-in-practice/.github/skills-config/ebook-build/invoke-build.ps1` | `-Force` スイッチの pass-through 追加 |

---

## 設計詳細

### 1. `Test-StepUpToDate` ヘルパー関数

`invoke-build.ps1` の既存ヘルパー関数（`Print-ScriptInvocation` など）の近くに追加する。

```powershell
function Test-StepUpToDate {
    param(
        [string[]]$Inputs,
        [string[]]$Outputs
    )
    # すべての出力ファイルが存在するか
    foreach ($out in $Outputs) {
        if (-not (Test-Path $out)) { return $false }
    }
    # 最も古い出力 vs 最も新しい入力
    $oldestOutput = ($Outputs | ForEach-Object { (Get-Item $_).LastWriteTimeUtc } | Sort-Object)[0]
    $existingInputTimes = $Inputs | Where-Object { Test-Path $_ } | ForEach-Object { (Get-Item $_).LastWriteTimeUtc }
    # 有効な入力が一つもなければ安全のためスキップしない
    if (-not $existingInputTimes) { return $false }
    $newestInput = ($existingInputTimes | Sort-Object -Descending)[0]
    return $oldestOutput -gt $newestInput
}
```

**入力ファイルのうち存在しないものは無視する**（オプション設定で未指定のファイルに対応するため）。

### 2. `-Force` スイッチパラメータ

```powershell
param(
    [Parameter(Mandatory = $true)] [string]$RepoRoot,
    [Parameter(Mandatory = $true)] [string]$ConfigFile,
    [Parameter(Mandatory = $true)] [ValidateSet('step1','step2','step3')] [string]$BuildStep,
    [switch]$Force   # ← 追加
)
```

`-Force` を指定した場合、up-to-date チェックをバイパスして必ず実行する。

### 3. step2 ブランチでのスキップロジック

```powershell
'step2' {
    # 入力ファイル定義
    $step2Inputs = @($metadataFile, $coverStyleFile)
    if ($coverMode -eq 'ai-image' -and $coverImagePromptFile) {
        $step2Inputs += $coverImagePromptFile
    } else {
        $step2Inputs += (Join-Path $sourceRoot $coverFile)
    }

    # 出力ファイル定義
    $coverPng = Join-Path $outputDir 'cover.png'
    $coverJpg = Join-Path $outputDir 'cover.jpg'
    $coverPdf = Join-Path $outputDir 'cover.pdf'
    $existingCover = if (Test-Path $coverPng) { $coverPng } else { $coverJpg }
    $step2Outputs = @($coverPdf, $existingCover)

    # スキップ判定
    if (-not $Force -and (Test-StepUpToDate -Inputs $step2Inputs -Outputs $step2Outputs)) {
        Write-Host "[step2] cover files are up-to-date — skipping (use -Force to rebuild)" -ForegroundColor Yellow
        # exit 0 相当：正常終了
        break
    }

    # 既存の step2 実行ロジック（変更なし）...
}
```

**スキップ時の出力例：**
```
[step2] cover files are up-to-date — skipping (use -Force to rebuild)
```

### 4. コンシューマー側 invoke-build.ps1 の `-Force` pass-through

`agent-skills-in-practice/.github/skills-config/ebook-build/invoke-build.ps1` に `-Force` スイッチを追加し、shared dispatcher へ渡す：

```powershell
param(
    ...
    [switch]$Force
)
...
& pwsh -NoProfile -ExecutionPolicy Bypass -File $dispatcherScript `
    -RepoRoot   $repoRoot `
    -ConfigFile $configFileResolved `
    -BuildStep  $BuildStep `
    $(if ($Force) { '-Force' })
```

---

## 入力・出力の対応表

| coverMode | 入力ファイル | 出力ファイル |
|---|---|---|
| `ai-image` | `coverImagePromptFile`, `metadataFile`, `coverStyleFile` | `cover.pdf`, `cover.png` |
| `markdown` | `sourceRoot/coverFile`（00-COVER.md）, `metadataFile`, `coverStyleFile` | `cover.pdf`, `cover.jpg` |

---

## スコープ外

- step1 / step3 へのスキップ拡張（将来 `Test-StepUpToDate` を再利用すれば容易）
- コンテンツハッシュによる判定
- `npm run ebook:step2` の `-Force` フラグ対応（package.json のスクリプト定義への追加は別タスク）
