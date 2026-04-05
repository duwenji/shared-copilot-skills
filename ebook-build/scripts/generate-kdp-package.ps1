[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectName,
    [Parameter(Mandatory = $true)]
    [string]$MetadataFile,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,
    [string]$KdpMetadataFile,
    [string]$EpubPath,
    [string]$PdfPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Convert-SimpleYamlToMap {
    param([string]$Path)

    $result = @{}
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path $Path)) {
        return $result
    }

    $lines = Get-Content -Path $Path -Encoding UTF8
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        $trimmed = $line.Trim()
        if ($trimmed -eq '---' -or $trimmed.StartsWith('#')) { continue }

        if ($line -notmatch '^(?<key>[A-Za-z0-9_-]+)\s*:\s*(?<value>.*)$') {
            continue
        }

        $key = $Matches['key']
        $value = $Matches['value'].Trim()

        if ($value -eq '>' -or $value -eq '|') {
            $buffer = New-Object 'System.Collections.Generic.List[string]'
            while (($i + 1) -lt $lines.Count -and $lines[$i + 1] -match '^\s{2,}.+$') {
                $i += 1
                $buffer.Add($lines[$i].Trim())
            }

            if ($value -eq '>') {
                $result[$key] = ($buffer.ToArray() -join ' ').Trim()
            } else {
                $result[$key] = ($buffer.ToArray() -join [Environment]::NewLine).Trim()
            }
            continue
        }

        if ([string]::IsNullOrWhiteSpace($value)) {
            $items = New-Object 'System.Collections.Generic.List[string]'
            while (($i + 1) -lt $lines.Count -and $lines[$i + 1] -match '^\s*-\s+(?<item>.+)$') {
                $i += 1
                $items.Add($Matches['item'].Trim().Trim('"').Trim("'"))
            }

            if ($items.Count -gt 0) {
                $result[$key] = @($items.ToArray())
            } else {
                $result[$key] = ''
            }
            continue
        }

        $normalizedValue = $value.Trim().Trim('"').Trim("'")
        if ($normalizedValue -eq 'null') {
            $result[$key] = $null
        } elseif ($normalizedValue -eq 'true') {
            $result[$key] = $true
        } elseif ($normalizedValue -eq 'false') {
            $result[$key] = $false
        } else {
            $result[$key] = $normalizedValue
        }
    }

    return $result
}

function Merge-Maps {
    param(
        [hashtable]$BaseMap,
        [hashtable]$OverrideMap
    )

    $merged = @{}
    foreach ($entry in $BaseMap.GetEnumerator()) {
        $merged[$entry.Key] = $entry.Value
    }
    foreach ($entry in $OverrideMap.GetEnumerator()) {
        if ($null -ne $entry.Value -and -not [string]::IsNullOrWhiteSpace([string]$entry.Value)) {
            $merged[$entry.Key] = $entry.Value
        }
    }

    return $merged
}

function Get-StringValue {
    param(
        [hashtable]$Map,
        [string[]]$Keys,
        [string]$Default = ''
    )

    foreach ($key in $Keys) {
        if ($Map.ContainsKey($key)) {
            $value = $Map[$key]
            if ($value -is [System.Array]) {
                if ($value.Count -gt 0) {
                    return (($value | ForEach-Object { [string]$_ }) -join ', ').Trim()
                }
            } elseif ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
                return ([string]$value).Trim()
            }
        }
    }

    return $Default
}

function Get-ArrayValue {
    param(
        [hashtable]$Map,
        [string[]]$Keys,
        [string[]]$Default = @()
    )

    foreach ($key in $Keys) {
        if (-not $Map.ContainsKey($key)) { continue }

        $value = $Map[$key]
        if ($value -is [System.Array]) {
            $items = @($value | ForEach-Object { ([string]$_).Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            if ($items.Count -gt 0) {
                return $items
            }
        } elseif ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
            $items = @(([string]$value) -split '[;,|]' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            if ($items.Count -gt 0) {
                return $items
            }
        }
    }

    return $Default
}

function Join-MarkdownList {
    param([string[]]$Items)

    if ($null -eq $Items -or $Items.Count -eq 0) {
        return '- TBD'
    }

    return (($Items | ForEach-Object { '- ' + $_ }) -join [Environment]::NewLine)
}

$baseMetadata = Convert-SimpleYamlToMap -Path $MetadataFile
$kdpMetadata = Convert-SimpleYamlToMap -Path $KdpMetadataFile
$metadata = Merge-Maps -BaseMap $baseMetadata -OverrideMap $kdpMetadata

$title = Get-StringValue -Map $metadata -Keys @('title') -Default $ProjectName
$subtitle = Get-StringValue -Map $metadata -Keys @('subtitle') -Default 'TBD'
$creator = Get-StringValue -Map $metadata -Keys @('creator', 'author') -Default 'TBD'
$language = Get-StringValue -Map $metadata -Keys @('language') -Default 'ja-JP'
$publisher = Get-StringValue -Map $metadata -Keys @('publisher') -Default 'Self Published'
$rights = Get-StringValue -Map $metadata -Keys @('rights') -Default '権利確認要'
$identifier = Get-StringValue -Map $metadata -Keys @('identifier', 'asin') -Default 'TBD'
$date = Get-StringValue -Map $metadata -Keys @('date') -Default ((Get-Date).ToString('yyyy-MM-dd'))
$description = Get-StringValue -Map $metadata -Keys @('description', 'abstract', 'summary') -Default 'TODO: KDP 商品説明文を最終化してください。'
$keywords = @(Get-ArrayValue -Map $metadata -Keys @('keywords', 'keyword', 'subject') -Default @('TBD'))
if (@($keywords).Count -gt 7) { $keywords = @($keywords | Select-Object -First 7) }
$categories = @(Get-ArrayValue -Map $metadata -Keys @('categories', 'category') -Default @('TBD'))
if (@($categories).Count -gt 3) { $categories = @($categories | Select-Object -First 3) }
$territories = Get-StringValue -Map $metadata -Keys @('territories', 'distributionTerritories') -Default 'Worldwide'
$royaltyPlan = Get-StringValue -Map $metadata -Keys @('royaltyPlan', 'royalty') -Default '70%（要条件確認）'
$listPrice = Get-StringValue -Map $metadata -Keys @('listPrice', 'price', 'priceJpy') -Default 'TBD'
$kdpSelect = Get-StringValue -Map $metadata -Keys @('kdpSelect', 'enrollInKdpSelect') -Default '任意（出版時に判断）'
$isbn = Get-StringValue -Map $metadata -Keys @('isbn') -Default 'Kindle 版のみなら通常不要'
$ageRange = Get-StringValue -Map $metadata -Keys @('ageRange') -Default '指定なし'
$gradeRange = Get-StringValue -Map $metadata -Keys @('gradeRange') -Default '指定なし'
$trimSize = Get-StringValue -Map $metadata -Keys @('trimSize') -Default '6in x 9in'
$bleed = Get-StringValue -Map $metadata -Keys @('bleed') -Default 'No bleed'
$layout = Get-StringValue -Map $metadata -Keys @('layout', 'printLayout') -Default 'fixed-layout PDF'

$artifacts = New-Object 'System.Collections.Generic.List[string]'
if (-not [string]::IsNullOrWhiteSpace($EpubPath)) { $artifacts.Add("- EPUB: $EpubPath") }
if (-not [string]::IsNullOrWhiteSpace($PdfPath)) { $artifacts.Add("- PDF: $PdfPath") }
if ($artifacts.Count -eq 0) { $artifacts.Add('- 生成物は ebook-output フォルダを確認') }

$todos = New-Object 'System.Collections.Generic.List[string]'
if ($subtitle -eq 'TBD') { $todos.Add('- サブタイトルを最終確定') }
if ($description -like 'TODO:*') { $todos.Add('- KDP 商品説明文を最終化') }
if (@($keywords).Count -eq 1 -and $keywords[0] -eq 'TBD') { $todos.Add('- 検索キーワードを 7 個まで設定') }
if (@($categories).Count -eq 1 -and $categories[0] -eq 'TBD') { $todos.Add('- カテゴリを最大 3 件まで設定') }
if ($listPrice -eq 'TBD') { $todos.Add('- 価格とロイヤルティを決定') }

$projectLine = "- プロジェクト名: $ProjectName"
$metadataLine = "- 元メタデータ: $MetadataFile"
$kdpMetadataLine = if ($KdpMetadataFile) { "- KDP 追加メタデータ: $KdpMetadataFile" } else { '- KDP 追加メタデータ: 未指定（基本メタデータから自動生成）' }

$content = @"
# KDP 登録情報一式: $title

- 生成日時: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
$projectLine
$metadataLine
$kdpMetadataLine

## 1. 基本書誌情報

| 項目 | 値 |
|---|---|
| タイトル | $title |
| サブタイトル | $subtitle |
| 著者 | $creator |
| 言語 | $language |
| 出版社 | $publisher |
| 権利 | $rights |
| 識別子 | $identifier |
| 出版日 | $date |
| ISBN | $isbn |

## 2. KDP 商品説明文

> $description

## 3. キーワード（最大 7）

$(Join-MarkdownList -Items $keywords)

## 4. カテゴリ（最大 3）

$(Join-MarkdownList -Items $categories)

## 5. 価格・ロイヤルティ・配信設定

| 項目 | 値 |
|---|---|
| 価格 | $listPrice |
| ロイヤルティ | $royaltyPlan |
| 配信地域 | $territories |
| KDP Select | $kdpSelect |
| 対象年齢 | $ageRange |
| 対象学年 | $gradeRange |

## 6. PDF / 印刷設定メモ

| 項目 | 値 |
|---|---|
| レイアウト | $layout |
| Trim size | $trimSize |
| Bleed | $bleed |

## 7. アップロード対象ファイル

$($artifacts.ToArray() -join [Environment]::NewLine)

## 8. 公開前 TODO

$(if ($todos.Count -gt 0) { $todos.ToArray() -join [Environment]::NewLine } else { '- 主要項目は入力済みです。KDP 画面で最終確認してください。' })
"@

$outputDir = Split-Path -Parent $OutputPath
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($OutputPath, $content.Trim() + [Environment]::NewLine, $utf8NoBom)
Write-Host "Generated: $OutputPath" -ForegroundColor Green
