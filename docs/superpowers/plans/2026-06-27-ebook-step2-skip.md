# ebook-build step2 タイムスタンプベーススキップ 実装プラン

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ebook-build の step2（カバー生成）で、出力ファイルがすべての入力ファイルより新しい場合に AI 画像生成をスキップする。

**Architecture:** `invoke-build.ps1` にタイムスタンプ比較ヘルパー関数 `Test-StepUpToDate` と `-Force` スイッチを追加し、step2 ブランチの先頭でスキップ判定を行う。コンシューマー側の薄いラッパースクリプトにも `-Force` を pass-through する。

**Tech Stack:** PowerShell 7 (pwsh), ファイルシステムタイムスタンプ比較

## Global Constraints

- PowerShell 7 (pwsh) のみ想定（`-NoProfile -ExecutionPolicy Bypass` で呼ばれる環境）
- `Set-StrictMode -Version Latest` が有効なので `$null` チェックは厳密に行う
- 既存の exit code 規約を維持：成功 = 0、失敗 = `throw`（exit 1）

---

## ファイルマップ

| ファイル | 変更種別 | 内容 |
|---|---|---|
| `shared-copilot-skills/ebook-build/scripts/invoke-build.ps1` | Modify | `Test-StepUpToDate` 関数追加、`-Force` パラメータ追加、step2 スキップロジック追加 |
| `agent-skills-in-practice/.github/skills-config/ebook-build/invoke-build.ps1` | Modify | `-Force` スイッチ追加、dispatcher 呼び出しへの pass-through |

---

## Task 1: `Test-StepUpToDate` ヘルパー関数の追加と検証

**Files:**
- Modify: `shared-copilot-skills/ebook-build/scripts/invoke-build.ps1:100` （`Get-ConfigValue` 関数の直後）

**Interfaces:**
- Produces:
  ```powershell
  function Test-StepUpToDate {
      param([string[]]$Inputs, [string[]]$Outputs)
      # returns [bool]
  }
  ```

- [ ] **Step 1: 検証スクリプトを一時ファイルとして作成**

  以下を `$env:TEMP\test-step-up-to-date.ps1` として保存する（後で削除）：

  ```powershell
  Set-StrictMode -Version Latest
  $ErrorActionPreference = 'Stop'

  function Test-StepUpToDate {
      param(
          [string[]]$Inputs,
          [string[]]$Outputs
      )
      foreach ($out in $Outputs) {
          if (-not (Test-Path $out)) { return $false }
      }
      $oldestOutput = ($Outputs | ForEach-Object { (Get-Item $_).LastWriteTimeUtc } | Sort-Object)[0]
      $existingInputTimes = $Inputs | Where-Object { Test-Path $_ } | ForEach-Object { (Get-Item $_).LastWriteTimeUtc }
      if (-not $existingInputTimes) { return $false }
      $newestInput = ($existingInputTimes | Sort-Object -Descending)[0]
      return $oldestOutput -gt $newestInput
  }

  $tmp = Join-Path $env:TEMP 'test-step-uptodate'
  New-Item -ItemType Directory -Path $tmp -Force | Out-Null

  $inFile  = Join-Path $tmp 'input.txt'
  $outFile = Join-Path $tmp 'output.txt'

  # Case 1: 出力ファイルが存在しない → $false
  Remove-Item $outFile -ErrorAction SilentlyContinue
  Set-Content $inFile 'input'
  $r1 = Test-StepUpToDate -Inputs @($inFile) -Outputs @($outFile)
  if ($r1 -ne $false) { throw "Case 1 FAIL: expected `$false, got $r1" }
  Write-Host 'Case 1 PASS: 出力なし → $false' -ForegroundColor Green

  # Case 2: 有効な入力が存在しない → $false
  Set-Content $outFile 'output'
  $r2 = Test-StepUpToDate -Inputs @('C:\nonexistent\file.txt') -Outputs @($outFile)
  if ($r2 -ne $false) { throw "Case 2 FAIL: expected `$false, got $r2" }
  Write-Host 'Case 2 PASS: 入力なし → $false' -ForegroundColor Green

  # Case 3: 出力が入力より新しい → $true
  Set-Content $inFile 'input'
  Start-Sleep -Milliseconds 100
  Set-Content $outFile 'output'
  $r3 = Test-StepUpToDate -Inputs @($inFile) -Outputs @($outFile)
  if ($r3 -ne $true) { throw "Case 3 FAIL: expected `$true, got $r3" }
  Write-Host 'Case 3 PASS: 出力が新しい → $true' -ForegroundColor Green

  # Case 4: 出力が入力より古い → $false
  Set-Content $outFile 'output'
  Start-Sleep -Milliseconds 100
  Set-Content $inFile 'updated input'
  $r4 = Test-StepUpToDate -Inputs @($inFile) -Outputs @($outFile)
  if ($r4 -ne $false) { throw "Case 4 FAIL: expected `$false, got $r4" }
  Write-Host 'Case 4 PASS: 出力が古い → $false' -ForegroundColor Green

  Remove-Item $tmp -Recurse -Force
  Write-Host 'All cases PASS' -ForegroundColor Cyan
  ```

- [ ] **Step 2: 検証スクリプトを実行して FAIL を確認（関数未定義のため）**

  ```powershell
  # $env:TEMP\test-step-up-to-date.ps1 の関数定義部分を除いて実行するか
  # そのまま実行して全 PASS になることを確認する（関数はスクリプト内に定義済み）
  pwsh -NoProfile -File "$env:TEMP\test-step-up-to-date.ps1"
  ```

  期待出力：
  ```
  Case 1 PASS: 出力なし → $false
  Case 2 PASS: 入力なし → $false
  Case 3 PASS: 出力が新しい → $true
  Case 4 PASS: 出力が古い → $false
  All cases PASS
  ```

- [ ] **Step 3: `invoke-build.ps1` の `Get-ConfigValue` 関数の直後（100行目）に `Test-StepUpToDate` を追加**

  `shared-copilot-skills/ebook-build/scripts/invoke-build.ps1` の 100 行目：

  ```powershell
      $property.Value
  }
  ```

  の直後に以下を挿入：

  ```powershell

  function Test-StepUpToDate {
      param(
          [string[]]$Inputs,
          [string[]]$Outputs
      )
      foreach ($out in $Outputs) {
          if (-not (Test-Path $out)) { return $false }
      }
      $oldestOutput = ($Outputs | ForEach-Object { (Get-Item $_).LastWriteTimeUtc } | Sort-Object)[0]
      $existingInputTimes = $Inputs | Where-Object { Test-Path $_ } | ForEach-Object { (Get-Item $_).LastWriteTimeUtc }
      if (-not $existingInputTimes) { return $false }
      $newestInput = ($existingInputTimes | Sort-Object -Descending)[0]
      return $oldestOutput -gt $newestInput
  }
  ```

- [ ] **Step 4: 検証スクリプトを実行して全 PASS を確認**

  ```powershell
  pwsh -NoProfile -File "$env:TEMP\test-step-up-to-date.ps1"
  ```

  期待出力：
  ```
  Case 1 PASS: 出力なし → $false
  Case 2 PASS: 入力なし → $false
  Case 3 PASS: 出力が新しい → $true
  Case 4 PASS: 出力が古い → $false
  All cases PASS
  ```

- [ ] **Step 5: 一時ファイルを削除してコミット**

  ```powershell
  Remove-Item "$env:TEMP\test-step-up-to-date.ps1" -ErrorAction SilentlyContinue
  ```

  ```bash
  cd shared-copilot-skills
  git add ebook-build/scripts/invoke-build.ps1
  git commit -m "feat: add Test-StepUpToDate helper to ebook-build dispatcher"
  ```

---

## Task 2: `-Force` スイッチと step2 スキップロジックの追加

**Files:**
- Modify: `shared-copilot-skills/ebook-build/scripts/invoke-build.ps1:27` （param ブロックの末尾）
- Modify: `shared-copilot-skills/ebook-build/scripts/invoke-build.ps1:352` （`'step2'` case の先頭）

**Interfaces:**
- Consumes: `Test-StepUpToDate` （Task 1 で定義）
- Produces: `-Force` スイッチパラメータ（Task 3 が consumer 側から渡す）

- [ ] **Step 1: param ブロックに `-Force` スイッチを追加**

  `invoke-build.ps1` の 27 行目：

  ```powershell
      [string]$BuildStep
  )
  ```

  を以下に変更：

  ```powershell
      [string]$BuildStep,

      [switch]$Force
  )
  ```

- [ ] **Step 2: step2 ブランチの先頭にスキップロジックを追加**

  `invoke-build.ps1` の 352 行目：

  ```powershell
      'step2' {
          # INPUT : cover source (markdown or AI prompt), metadata.yaml
          # OUTPUT: $outputDir/cover.png + cover.pdf  (ai-image mode)
          #         $outputDir/cover.jpg + cover.pdf  (markdown mode)
          $script = Join-Path $scriptsDir 'invoke-ebook-step2-cover.ps1'
  ```

  を以下に変更：

  ```powershell
      'step2' {
          # INPUT : cover source (markdown or AI prompt), metadata.yaml
          # OUTPUT: $outputDir/cover.png + cover.pdf  (ai-image mode)
          #         $outputDir/cover.jpg + cover.pdf  (markdown mode)

          # --- up-to-date check ---
          $step2Inputs = @($metadataFile, $coverStyleFile)
          if ($coverMode -eq 'ai-image' -and $coverImagePromptFile) {
              $step2Inputs += $coverImagePromptFile
          } else {
              $step2Inputs += (Join-Path $sourceRoot $coverFile)
          }

          $coverPng = Join-Path $outputDir 'cover.png'
          $coverJpg = Join-Path $outputDir 'cover.jpg'
          $coverPdf = Join-Path $outputDir 'cover.pdf'
          $existingCover = if (Test-Path $coverPng) { $coverPng } else { $coverJpg }
          $step2Outputs = @($coverPdf, $existingCover)

          if (-not $Force -and (Test-StepUpToDate -Inputs $step2Inputs -Outputs $step2Outputs)) {
              Write-Host "[step2] cover files are up-to-date — skipping (use -Force to rebuild)" -ForegroundColor Yellow
              break
          }
          # --- end up-to-date check ---

          $script = Join-Path $scriptsDir 'invoke-ebook-step2-cover.ps1'
  ```

- [ ] **Step 3: スキップされることを手動確認（cover ファイルが既に存在する状態で）**

  `agent-skills-in-practice` リポジトリのルートで実行：

  ```powershell
  cd c:\Dev\tutorials\agent-skills-in-practice
  npm run ebook:step2
  ```

  `ebook-output/cover.pdf` と `ebook-output/cover.png` が既に存在し、入力ファイルより新しい場合の期待出力：

  ```
  [step2] cover files are up-to-date — skipping (use -Force to rebuild)
  ```

  スキップされない場合（初回実行や入力が新しい場合）は通常通り実行される。

- [ ] **Step 4: コミット**

  ```bash
  cd shared-copilot-skills
  git add ebook-build/scripts/invoke-build.ps1
  git commit -m "feat: add -Force switch and step2 up-to-date skip to ebook-build dispatcher"
  ```

---

## Task 3: コンシューマー側 `invoke-build.ps1` への `-Force` pass-through

**Files:**
- Modify: `agent-skills-in-practice/.github/skills-config/ebook-build/invoke-build.ps1`

**Interfaces:**
- Consumes: `-Force` スイッチ（Task 2 で shared dispatcher に追加済み）

- [ ] **Step 1: consumer スクリプトの param ブロックに `-Force` を追加**

  `agent-skills-in-practice/.github/skills-config/ebook-build/invoke-build.ps1` の 10〜15 行目：

  ```powershell
  [CmdletBinding()]
  param(
      [string]$ConfigFile = '.github/skills-config/ebook-build/agent-skills-in-practice.build.json',
      [Parameter(Mandatory = $true)]
      [ValidateSet('step1', 'step2', 'step3')]
      [string]$BuildStep
  )
  ```

  を以下に変更：

  ```powershell
  [CmdletBinding()]
  param(
      [string]$ConfigFile = '.github/skills-config/ebook-build/agent-skills-in-practice.build.json',
      [Parameter(Mandatory = $true)]
      [ValidateSet('step1', 'step2', 'step3')]
      [string]$BuildStep,

      [switch]$Force
  )
  ```

- [ ] **Step 2: dispatcher 呼び出しに `-Force` を pass-through**

  同ファイルの 55〜58 行目：

  ```powershell
  & pwsh -NoProfile -ExecutionPolicy Bypass -File $dispatcherScript `
      -RepoRoot   $repoRoot `
      -ConfigFile $configFileResolved `
      -BuildStep  $BuildStep
  ```

  を以下に変更：

  ```powershell
  $forceArg = if ($Force) { @('-Force') } else { @() }
  & pwsh -NoProfile -ExecutionPolicy Bypass -File $dispatcherScript `
      -RepoRoot   $repoRoot `
      -ConfigFile $configFileResolved `
      -BuildStep  $BuildStep `
      @forceArg
  ```

- [ ] **Step 3: スキップ動作をエンドツーエンドで確認**

  `ebook-output/cover.pdf` と `ebook-output/cover.png` が既に存在する状態で：

  ```powershell
  cd c:\Dev\tutorials\agent-skills-in-practice
  npm run ebook:step2
  ```

  期待出力（カバーが最新の場合）：
  ```
  [step2] cover files are up-to-date — skipping (use -Force to rebuild)
  ```

- [ ] **Step 4: `-Force` で強制実行されることを確認**

  ```powershell
  cd c:\Dev\tutorials\agent-skills-in-practice
  pwsh -NoProfile -ExecutionPolicy Bypass -File ./.github/skills-config/ebook-build/invoke-build.ps1 -BuildStep step2 -Force
  ```

  期待動作：スキップメッセージが出ず、通常の step2 実行ログが流れる（API キーが必要なため完走しなくてよい。ログに `[step2] cover files are up-to-date` が出なければ OK）。

- [ ] **Step 5: コミット**

  ```bash
  cd agent-skills-in-practice
  git add .github/skills-config/ebook-build/invoke-build.ps1
  git commit -m "feat: pass -Force through to shared ebook-build dispatcher in step2 skip"
  ```
