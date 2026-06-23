<#
.SYNOPSIS
  Step 1 - Merge source chapters into a single manuscript file.
#>
param(
    [string]$SourceRoot,
    [string]$OutputDir,
    [string]$ProjectName,
    [string]$MetadataFile,
    [string]$KindleTemplateDir,
    [string]$StyleFile,
    [string]$ChapterDirPattern  = '^\d{2}-',
    [string]$ChapterFilePattern = '^\d{2}-.*\.md$',
    [string]$CoverFile          = 'Readme.md',
    [string]$ManuscriptLeadFile,
    [switch]$SkipCoverInManuscript,
    [ValidateSet('auto', 'file', 'template')]
    [string]$CoverTemplateMode  = 'auto',
    [string]$CoverTemplate      = 'classic',
    [switch]$NumberHeadings,
    [bool]$CollectAssets       = $false,
    [switch]$PreserveTemp,
    [string]$SamplesRoot        = '',
    [string]$SamplesTitle       = 'Samples Catalog'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host 'Step 1: Merge source chapters into manuscript - starting' -ForegroundColor Cyan
Write-Host "Parameters: SourceRoot=$SourceRoot OutputDir=$OutputDir ProjectName=$ProjectName" -ForegroundColor DarkCyan

function Ensure-Path {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path $Path)) { throw "$Label not found: $Path" }
}

function Get-YamlScalarValue {
    param([string]$Path, [string]$Key)
    if (-not (Test-Path $Path)) { return $null }
    $pattern = "(?m)^\s*$([regex]::Escape($Key))\s*:\s*(?<value>.+?)\s*$"
    $text = Get-Content -Path $Path -Raw -Encoding UTF8
    $match = [regex]::Match($text, $pattern)
    if (-not $match.Success) { return $null }
    $value = $match.Groups['value'].Value.Trim().Trim("'", '"')
    if ([string]::IsNullOrWhiteSpace($value)) { return $null }
    return $value
}

function Get-YamlIndentedMap {
    param(
        [string]$Path,
        [string]$ParentKey,
        [string]$MapKey
    )

    $result = @{}
    if (-not (Test-Path $Path)) { return $result }

    $lines = Get-Content -Path $Path -Encoding UTF8
    $parentIndent = $null
    $mapIndent = $null

    foreach ($line in $lines) {
        if ($null -eq $parentIndent) {
            $parentMatch = [regex]::Match($line, '^(?<indent>\s*)' + [regex]::Escape($ParentKey) + ':\s*$')
            if ($parentMatch.Success) {
                $parentIndent = $parentMatch.Groups['indent'].Value.Length
            }
            continue
        }

        if ($null -eq $mapIndent) {
            if ($line -match '^\s*$' -or $line -match '^\s*#') {
                continue
            }

            $currentIndent = ([regex]::Match($line, '^(?<indent>\s*)')).Groups['indent'].Value.Length
            if ($currentIndent -le $parentIndent) { break }

            $mapMatch = [regex]::Match($line, '^(?<indent>\s*)' + [regex]::Escape($MapKey) + ':\s*$')
            if ($mapMatch.Success) {
                $mapIndent = $mapMatch.Groups['indent'].Value.Length
            }
            continue
        }

        if ($line -match '^\s*$' -or $line -match '^\s*#') {
            continue
        }

        $entryIndent = ([regex]::Match($line, '^(?<indent>\s*)')).Groups['indent'].Value.Length
        if ($entryIndent -le $mapIndent) { break }

        $entryMatch = [regex]::Match($line, '^\s*(?<key>[^:#]+):\s*(?<value>.+?)\s*$')
        if (-not $entryMatch.Success) { continue }

        $entryKey = $entryMatch.Groups['key'].Value.Trim()
        $entryValue = $entryMatch.Groups['value'].Value.Trim().Trim("'", '"')
        if (-not [string]::IsNullOrWhiteSpace($entryKey)) {
            $result[$entryKey] = $entryValue
        }
    }

    return $result
}

function Resolve-ContentRoot {
    param([string]$Root, [string]$DirPattern)

    $resolved = (Resolve-Path $Root).ProviderPath
    $dirs = @(Get-ChildItem -Path $resolved -Directory -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -match $DirPattern })
    if ($dirs.Count -gt 0) { return $resolved }

    $docsPath = Join-Path $resolved 'docs'
    if (Test-Path $docsPath) {
        $docDirs = @(Get-ChildItem -Path $docsPath -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match $DirPattern })
        if ($docDirs.Count -gt 0) { return $docsPath }
    }

    throw "No chapter directories found. root=$resolved pattern=$DirPattern"
}

function Resolve-CoverTemplatePath {
    param([string]$TemplateRoot, [string]$TemplateName)

    $fileName = if ($TemplateName -match '\.md$') { $TemplateName } else { "$TemplateName.md" }
    $path = Join-Path $TemplateRoot $fileName
    Ensure-Path -Path $path -Label 'cover template file'
    return $path
}

function New-CoverFromTemplate {
    param(
        [string]$TemplatePath,
        [string]$DestinationPath,
        [string]$ProjectName,
        [string]$MetadataFile
    )

    $title = Get-YamlScalarValue -Path $MetadataFile -Key 'title'
    $creator = Get-YamlScalarValue -Path $MetadataFile -Key 'creator'
    $subtitle = Get-YamlScalarValue -Path $MetadataFile -Key 'subtitle'
    $publishDate = Get-YamlScalarValue -Path $MetadataFile -Key 'date'

    if ([string]::IsNullOrWhiteSpace($title)) { $title = $ProjectName }
    if ([string]::IsNullOrWhiteSpace($creator)) { $creator = 'Unknown Author' }
    if ([string]::IsNullOrWhiteSpace($subtitle)) { $subtitle = '' }
    if ([string]::IsNullOrWhiteSpace($publishDate)) { $publishDate = (Get-Date -Format 'yyyy-MM-dd') }

    $text = Get-Content -Path $TemplatePath -Raw -Encoding UTF8
    $text = $text.Replace('{{title}}', $title)
    $text = $text.Replace('{{creator}}', $creator)
    $text = $text.Replace('{{subtitle}}', $subtitle)
    $text = $text.Replace('{{date}}', $publishDate)
    $text = $text.Replace('{{projectName}}', $ProjectName)

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($DestinationPath, $text, $utf8NoBom)
}

function Append-FileContent {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$Path,
        [switch]$NumberHeadings,
        [hashtable]$HeadingState,
        [string]$HeadingPrefix,
        [int]$HeadingLevelOffset = 0,
        [int]$NumberBaseLevel = 1
    )

    foreach ($line in (Get-Content -Path $Path -Encoding UTF8)) {
        $effectiveLine = $line

        if ($NumberHeadings -and $null -ne $HeadingState) {
            if ($effectiveLine -match '^\s*```') {
                $HeadingState.InCodeFence = -not [bool]$HeadingState.InCodeFence
                Write-Host "[DEBUG] Code fence toggle. InCodeFence=$($HeadingState.InCodeFence) (file=$Path)" -ForegroundColor Magenta
            }
            elseif (-not [bool]$HeadingState.InCodeFence) {
                $headingMatch = [regex]::Match($effectiveLine, '^(#{1,6})\s+(.+?)\s*$')
                if ($headingMatch.Success) {
                    $level = [Math]::Min($headingMatch.Groups[1].Value.Length + $HeadingLevelOffset, 6)
                    $title = $headingMatch.Groups[2].Value.Trim()

                    if (-not $HeadingState.ContainsKey('Counts')) {
                        $HeadingState.Counts = @(0, 0, 0, 0, 0, 0, 0)
                    }

                    for ($depth = $level + 1; $depth -lt $HeadingState.Counts.Length; $depth++) {
                        $HeadingState.Counts[$depth] = 0
                    }

                    if ($level -gt $NumberBaseLevel) {
                        $HeadingState.Counts[$level] = [int]$HeadingState.Counts[$level] + 1
                    }

                    $number = if ($level -eq $NumberBaseLevel) {
                        $HeadingPrefix
                    }
                    else {
                        $suffixParts = @()
                        for ($depth = $NumberBaseLevel + 1; $depth -le $level; $depth++) {
                            $suffixParts += [string][int]$HeadingState.Counts[$depth]
                        }
                        '{0}.{1}' -f $HeadingPrefix, ($suffixParts -join '.')
                    }

                    $effectiveLine = "{0} {1} {2}" -f ('#' * $level), $number, $title
                    Write-Host "[DEBUG] Renumbered heading in $Path -> $effectiveLine" -ForegroundColor Magenta
                }
            }
        }

        $Lines.Add($effectiveLine)
    }
}

function Get-OrdinalPrefixFromName {
    param([string]$Name, [string]$Kind)

    $match = [regex]::Match($Name, '^(?<ordinal>\d+)-')
    if (-not $match.Success) {
        throw "Unable to determine $Kind ordinal from name: $Name"
    }

    return [int]$match.Groups['ordinal'].Value
}

function Resolve-OptionalFilePath {
    param(
        [string]$PrimaryRoot,
        [string]$FallbackRoot,
        [string]$RelativePath
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath)) { return $null }

    $primary = Join-Path $PrimaryRoot $RelativePath
    if (Test-Path $primary) { return $primary }

    $fallback = Join-Path $FallbackRoot $RelativePath
    if (Test-Path $fallback) { return $fallback }

    return $null
}

function Get-ChapterSectionFiles {
    param(
        [string]$ChapterRoot,
        [string]$FilePattern
    )

    $allMarkdownFiles = @(Get-ChildItem -Path $ChapterRoot -Recurse -File -Filter '*.md' -ErrorAction SilentlyContinue)
    $matchedFiles = New-Object 'System.Collections.Generic.List[object]'

    foreach ($file in $allMarkdownFiles) {
        $relativePath = [System.IO.Path]::GetRelativePath($ChapterRoot, $file.FullName).Replace('\\', '/')
        if ($relativePath -match $FilePattern) {
            $matchedFiles.Add([PSCustomObject]@{
                File = $file
                RelativePath = $relativePath
            })
        }
    }

    return @($matchedFiles.ToArray() | Sort-Object RelativePath)
}

function Get-NormalizedAssetReference {
    param([string]$RawReference)

    if ([string]::IsNullOrWhiteSpace($RawReference)) { return $null }

    $value = $RawReference.Trim()
    if ($value.StartsWith('<') -and $value.EndsWith('>')) {
        $value = $value.Substring(1, $value.Length - 2).Trim()
    }

    $firstToken = ($value -split '\s+', 2)[0].Trim()
    if ([string]::IsNullOrWhiteSpace($firstToken)) { return $null }

    $normalized = $firstToken.Replace('\\', '/').Trim()
    if ($normalized.StartsWith('./')) {
        $normalized = $normalized.Substring(2)
    }

    if ([string]::IsNullOrWhiteSpace($normalized)) { return $null }
    if ($normalized.StartsWith('#')) { return $null }
    if ($normalized -match '^(?i)(https?|data|mailto):') { return $null }
    if ([System.IO.Path]::IsPathRooted($normalized)) { return $null }

    return $normalized
}

function Get-AssetReferencesFromFile {
    param([string]$MarkdownPath)
    $text = Get-Content -Path $MarkdownPath -Raw -Encoding UTF8
    if ($null -eq $text) { $text = '' }
    $results = New-Object 'System.Collections.Generic.List[string]'

    foreach ($match in [regex]::Matches($text, '!\[[^\]]*\]\((?<ref>[^)]+)\)')) {
        $normalized = Get-NormalizedAssetReference -RawReference $match.Groups['ref'].Value
        if ($normalized) { $results.Add($normalized) }
    }

    foreach ($match in [regex]::Matches($text, '<img\b[^>]*\bsrc\s*=\s*[''"''](?<ref>[^''""]+)[''"'']')) {
        $normalized = Get-NormalizedAssetReference -RawReference $match.Groups['ref'].Value
        if ($normalized) { $results.Add($normalized) }
    }

    return @($results.ToArray() | Select-Object -Unique)
}

function Add-AssetReferencesForFile {
    param(
        [string]$MarkdownPath,
        [string]$SourceRootResolved,
        [string]$ContentRootResolved,
        [System.Collections.Generic.Dictionary[string, string]]$AssetMap,
        [System.Collections.Generic.List[object]]$Manifest
    )

    if (-not (Test-Path $MarkdownPath)) { return }

    $baseDir = Split-Path -Parent $MarkdownPath
    foreach ($reference in (Get-AssetReferencesFromFile -MarkdownPath $MarkdownPath)) {
        $resolvedCandidate = [System.IO.Path]::GetFullPath((Join-Path $baseDir $reference))
        Write-Host "[DEBUG] Asset reference found in $MarkdownPath -> reference='$reference' resolved='$resolvedCandidate'" -ForegroundColor DarkCyan

        # Namespace assets by the markdown's path relative to the content root (removes top-level chapter folder)
        # Determine the markdown-relative base path and extract chapter/category if present
        $relativeBaseFull = ''
        $category = ''
        try {
            if (-not [string]::IsNullOrWhiteSpace($ContentRootResolved)) {
                $relativeBaseFull = [System.IO.Path]::GetRelativePath($ContentRootResolved, $baseDir).Replace('\\', '/')
            } else {
                $relativeBaseFull = [System.IO.Path]::GetRelativePath($SourceRootResolved, $baseDir).Replace('\\', '/')
            }
        } catch {
            $relativeBaseFull = ''
        }

        if (-not [string]::IsNullOrWhiteSpace($relativeBaseFull)) {
            $relativeBaseFull = $relativeBaseFull.TrimStart('./')

            $segments = $relativeBaseFull -split '/'
            if ($segments.Length -gt 0 -and $segments[0] -match $chapterDirPattern) {
                # First segment is a chapter dir like '04-ui' -> treat as category
                $category = $segments[0]
                if ($segments.Length -gt 1) {
                    $relativeBase = ($segments[1..($segments.Length - 1)] -join '/') + '/'
                } else {
                    $relativeBase = ''
                }
            } else {
                $category = ''
                $relativeBase = if ($relativeBaseFull -ne '') { $relativeBaseFull + '/' } else { '' }
            }
        } else {
            $relativeBase = ''
            $category = ''
        }

        # Compute output relative path directly from the resolved file path relative to content root
        try {
            $outputRel = [System.IO.Path]::GetRelativePath($ContentRootResolved, $resolvedCandidate).Replace('\', '/')
        } catch {
            $outputRel = "$category/$relativeBase$reference"
        }
        # Strip leading 'images/' so Copy-CollectedAssets places files at ebook-output/images/<rest>
        # Update-ManuscriptLinks will prepend 'images/' back when rewriting manuscript links
        if ($outputRel -match '^images/') {
            $outputRel = $outputRel.Substring(7)
        }

        $manifestEntry = [ordered]@{
            sourceFile = $MarkdownPath
            reference = $reference
            sourcePath = $resolvedCandidate
            outputRelativePath = $outputRel
            status = 'pending'
            reason = ''
        }

        if (-not $resolvedCandidate.StartsWith($SourceRootResolved, [System.StringComparison]::OrdinalIgnoreCase)) {
            $manifestEntry.status = 'skipped'
            $manifestEntry.reason = 'outside-source-root'
            Write-Host "[DEBUG] Skipping asset outside source root: $resolvedCandidate" -ForegroundColor Yellow
            $Manifest.Add([PSCustomObject]$manifestEntry)
            continue
        }

        if (-not (Test-Path $resolvedCandidate -PathType Leaf)) {
            $manifestEntry.status = 'missing'
            $manifestEntry.reason = 'file-not-found'
            Write-Host "[DEBUG] Asset missing: $resolvedCandidate (sourceFile=$MarkdownPath reference=$reference)" -ForegroundColor Red
            $Manifest.Add([PSCustomObject]$manifestEntry)
            continue
        }

        $mapKey = $outputRel

        if ($AssetMap.ContainsKey($mapKey)) {
            if ($AssetMap[$mapKey] -ne $resolvedCandidate) {
                Write-Host "[DEBUG] Asset path collision for output path '$mapKey'. Existing: '$($AssetMap[$mapKey])' Incoming: '$resolvedCandidate'" -ForegroundColor Magenta
                throw "Asset path collision for output path '$mapKey'. Existing: '$($AssetMap[$mapKey])' Incoming: '$resolvedCandidate'"
            }
            $manifestEntry.status = 'duplicate'
            $manifestEntry.reason = 'already-registered'
            Write-Host "[DEBUG] Duplicate asset registration skipped for: $mapKey -> $resolvedCandidate" -ForegroundColor Yellow
            $Manifest.Add([PSCustomObject]$manifestEntry)
            continue
        }

        $AssetMap[$mapKey] = $resolvedCandidate
        $manifestEntry.status = 'resolved'
        Write-Host "[DEBUG] Asset resolved: $mapKey -> $resolvedCandidate" -ForegroundColor Green
        $Manifest.Add([PSCustomObject]$manifestEntry)
    }
}

function Copy-CollectedAssets {
    param(
        [string]$OutputDir,
        [System.Collections.Generic.Dictionary[string, string]]$AssetMap
    )

    $imagesRoot = Join-Path $OutputDir 'images'
    New-Item -ItemType Directory -Path $imagesRoot -Force | Out-Null

    foreach ($pair in $AssetMap.GetEnumerator()) {
        $reference = $pair.Key
        $sourcePath = $pair.Value

        # Place all assets under ebook-output/images, preserving any category prefix present in the reference
        $destination = Join-Path $imagesRoot ($reference -replace '/', '\\')
        $destinationDir = Split-Path -Parent $destination
        if (-not (Test-Path $destinationDir)) {
            New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
        }
        Copy-Item -Path $sourcePath -Destination $destination -Force
    }
}

function Update-ManuscriptLinks {
    param(
        [string]$AssetsPath,
        [string]$ManuscriptPath
    )

    if (-not (Test-Path $AssetsPath)) {
        Write-Warning "Assets manifest not found: $AssetsPath"
        return
    }
    if (-not (Test-Path $ManuscriptPath)) {
        Write-Warning "Manuscript not found: $ManuscriptPath"
        return
    }

    # Normalize to absolute paths to avoid accidental relative-path mismatches
    $AssetsPath = (Resolve-Path $AssetsPath).ProviderPath
    $ManuscriptPath = (Resolve-Path $ManuscriptPath).ProviderPath
    Write-Host "AssetsPath resolved:" $AssetsPath -ForegroundColor DarkCyan
    Write-Host "ManuscriptPath resolved:" $ManuscriptPath -ForegroundColor DarkCyan

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    try {
        $manifest = Get-Content -Raw -Path $AssetsPath -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Write-Warning "Failed to read manifest: $_"
        return
    }

    # Build normalized map: keys and values use forward slashes
    $map = @{}
    foreach ($e in $manifest.entries) {
        $ref = ($e.reference -replace '^[./]+','' -replace '\\','/').Trim()
        $outRel = ($e.outputRelativePath -replace '\\','/').Trim()
        if (-not [string]::IsNullOrWhiteSpace($ref)) { $map[$ref] = $outRel }
    }

    Write-Host "Manifest entries:" $manifest.entries.Count -ForegroundColor Cyan
    Write-Host "Map keys:" $map.Keys.Count -ForegroundColor Cyan
    if ($map.Keys.Count -gt 0) {
        Write-Host "Sample key:" ($map.Keys | Select-Object -First 1) -ForegroundColor Cyan
        Write-Host "First 10 keys:" -ForegroundColor Cyan
        $map.Keys | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" -ForegroundColor Cyan }
    }

    $origText = Get-Content -Raw -Path $ManuscriptPath -Encoding UTF8
    $origExamples = ([regex]::Matches($origText,'examples/').Count)
    Write-Host "Original manuscript 'examples/' occurrences:" $origExamples -ForegroundColor Cyan
    $logTs = (Get-Date).ToString('yyyyMMdd-HHmmss')
    # Only create persistent debug/log artifacts when caller requested preserving temporary files.
    if ($PreserveTemp) {
        $logPath = "$ManuscriptPath.debug.links.$logTs.log"
        Add-Content -Path $logPath -Value "==== Update-ManuscriptLinks run at $logTs ===="
        Add-Content -Path $logPath -Value "Original manuscript 'examples/' occurrences: $origExamples"
    } else {
        $logPath = $null
    }
    $lines = $origText -split "`r?`n", [System.StringSplitOptions]::None
    # 行数を出力する
    Write-Host "Original manuscript lines:" $lines.Count -ForegroundColor Cyan

    # 行ごとにに処理して、イメージリンクの場合パス変換をする。mapのキーが行内に存在する場合、置換対象とする。
    $newLines = New-Object 'System.Collections.Generic.List[string]'
    $replacedCount = 0
    $fallbackCount = 0
    $presentButNoMatchCount = 0
    $linesModified = New-Object 'System.Collections.Generic.List[int]'
    $lineNumber = 0
    foreach ($line in $lines) {
        $lineNumber++
        $modifiedLine = $line

        # 行内に画像ファイル拡張子が含まれていない場合、変換処理は実施しない
        if ($line -notmatch '\.(png|jpg|jpeg|gif|bmp|svg)') {
            $newLines.Add($line)
            continue
        }

        Write-Host "[DEBUG] Line ${lineNumber}: $line" -ForegroundColor DarkYellow

        $matchedAny = $false
        foreach ($key in $map.Keys) {
            Write-Host "[DEBUG] Line ${lineNumber}: checking key='$key', value='$($map[$key])'" -ForegroundColor DarkYellow
            if ($line -match [regex]::Escape($key)) {
                $replacementPath = ($map[$key] -replace '\\','/')
                $replacement = 'images/' + $replacementPath
                $modifiedLine = $modifiedLine -replace ([regex]::Escape($key)), ('images/' + [regex]::Escape($map[$key]))
                $replacedCount++
                $matchedAny = $true
                Write-Host "[DEBUG] Line ${lineNumber}: matched key='$key' -> replacement='$replacement'" -ForegroundColor Magenta
            } else {
                # The manifest entry is present but the key was not found in the manuscript line. This could be a sign of a mismatch.
                $presentButNoMatchCount++
                if ($PreserveTemp) {
                    Add-Content -Path $logPath -Value "Manifest key '$key' not found in line: $line"
                }
            }
        }

        if (-not $matchedAny) {
            Write-Host "[DEBUG] Line ${lineNumber}: no manifest key matched for line" -ForegroundColor DarkYellow
            Write-Host "  >> $line" -ForegroundColor DarkYellow
        }

        if ($modifiedLine -ne $line) {
            $linesModified.Add($newLines.Count)
            if ($logPath) { Add-Content -Path $logPath -Value "Modified line: Original: $line Modified: $modifiedLine" }
            Write-Host "[DEBUG] Line ${lineNumber}: modified" -ForegroundColor Cyan
            Write-Host "  Original: $line" -ForegroundColor Cyan
            Write-Host "  Modified: $modifiedLine" -ForegroundColor Cyan
        }
        $newLines.Add($modifiedLine)
    }

    $ts = (Get-Date).ToString('yyyyMMdd-HHmmss')
    # Create backup only when preserving temporary workspace/artifacts
    if ($PreserveTemp) {
        $backup = "$ManuscriptPath.bak.$ts"
        Copy-Item -Path $ManuscriptPath -Destination $backup -Force
    } else {
        $backup = $null
    }

    # Write to a temp file first, validate content, then atomically move into place.
    $tmpPath = "$ManuscriptPath.tmp.$ts"
    [System.IO.File]::WriteAllText($tmpPath, ($newLines -join [Environment]::NewLine), $utf8NoBom)

    try {
        $written = Get-Content -Path $tmpPath -Raw -Encoding UTF8
        $imagesFound = ([regex]::Matches($written, 'images/').Count)
        Write-Host "Temp manuscript images count: $imagesFound (replaced=$replacedCount fallback=$fallbackCount present-but-unmatched=$presentButNoMatchCount lines-modified=$($linesModified.Count))" -ForegroundColor Cyan

        # Optionally write debug artifacts for inspection when preserving temp workspace
        if ($PreserveTemp) {
            $debugNewPath = "$ManuscriptPath.debug.new.$ts.md"
            Set-Content -Path $debugNewPath -Value $written -Encoding UTF8
            Write-Host "Wrote debug manuscript file: $debugNewPath" -ForegroundColor Magenta

            $countsPath = "$ManuscriptPath.debug.counts.$ts.txt"
            $sb = New-Object System.Text.StringBuilder
            foreach ($e in $manifest.entries) {
                $ref = ($e.reference -replace '^[./]+','' -replace '\\','/').Trim()
                $outRel = $e.outputRelativePath
                $origCount = ([regex]::Matches($origText, [regex]::Escape($ref))).Count
                $newCount = ([regex]::Matches($written, [regex]::Escape('images/' + $outRel))).Count
                $line = "{0} | images/{1} | orig:{2} new:{3}" -f $ref, $outRel, $origCount, $newCount
                [void]$sb.AppendLine($line)
            }
            Set-Content -Path $countsPath -Value $sb.ToString() -Encoding UTF8
            Write-Host "Wrote debug counts file: $countsPath" -ForegroundColor Magenta
        }

        Move-Item -Path $tmpPath -Destination $ManuscriptPath -Force
        Write-Host "Manuscript links updated: $ManuscriptPath" -ForegroundColor Green
        if ($backup) { Write-Host "Backup: $backup" -ForegroundColor Yellow }
    } catch {
        Write-Warning "Failed to validate/write updated manuscript: $_"
        if (Test-Path $tmpPath) { Remove-Item -Path $tmpPath -Force -ErrorAction SilentlyContinue }
        return
    }
}

Write-Host "Verifying SourceRoot and MetadataFile..." -ForegroundColor Cyan
Ensure-Path -Path $SourceRoot -Label 'SourceRoot'
Write-Host "SourceRoot verified: $SourceRoot" -ForegroundColor DarkCyan
Ensure-Path -Path $MetadataFile -Label 'MetadataFile'
Write-Host "MetadataFile verified: $MetadataFile" -ForegroundColor DarkCyan

if ([string]::IsNullOrWhiteSpace($ProjectName)) {
    $ProjectName = Split-Path -Leaf (Resolve-Path $SourceRoot).ProviderPath
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path (Resolve-Path $SourceRoot).ProviderPath 'ebook-output'
}
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$contentRoot = Resolve-ContentRoot -Root $SourceRoot -DirPattern $ChapterDirPattern
$resolvedSourceRoot = (Resolve-Path $SourceRoot).ProviderPath
$chapterTitleMap = Get-YamlIndentedMap -Path $MetadataFile -ParentKey 'chapters' -MapKey 'dir-titles'
$chapterDirs = @(Get-ChildItem -Path $contentRoot -Directory |
    Where-Object { $_.Name -match $ChapterDirPattern } |
    Sort-Object Name)

Write-Host "Content root resolved: $contentRoot" -ForegroundColor Cyan
Write-Host "Found chapter directories: $($chapterDirs.Count)" -ForegroundColor DarkCyan

$chapterFiles = @()
foreach ($chapterDir in $chapterDirs) {
    $chapterFiles += @((Get-ChapterSectionFiles -ChapterRoot $chapterDir.FullName -FilePattern $ChapterFilePattern) |
        ForEach-Object { $_.File })
}

if ($chapterFiles.Count -eq 0) {
    throw "No chapter markdown files found. pattern=$ChapterFilePattern contentRoot=$contentRoot"
}
Write-Host "Found chapter markdown files: $($chapterFiles.Count)" -ForegroundColor DarkCyan

$skillRoot = Split-Path -Parent $PSScriptRoot
$coverTemplateRoot = Join-Path $skillRoot 'assets\cover-templates'

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ebook-step1-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
Write-Host "Created temporary workspace: $tempRoot" -ForegroundColor Yellow

try {
    $coverPath = Join-Path $contentRoot $CoverFile
    $effectiveCoverPath = $coverPath

    switch ($CoverTemplateMode) {
        'file' {
            Ensure-Path -Path $coverPath -Label 'cover markdown file'
        }
        'template' {
            $tplPath = Resolve-CoverTemplatePath -TemplateRoot $coverTemplateRoot -TemplateName $CoverTemplate
            $effectiveCoverPath = Join-Path $tempRoot $CoverFile
            New-CoverFromTemplate -TemplatePath $tplPath -DestinationPath $effectiveCoverPath -ProjectName $ProjectName -MetadataFile $MetadataFile
        }
        default {
            if (-not (Test-Path $coverPath)) {
                $tplPath = Resolve-CoverTemplatePath -TemplateRoot $coverTemplateRoot -TemplateName $CoverTemplate
                $effectiveCoverPath = Join-Path $tempRoot $CoverFile
                New-CoverFromTemplate -TemplatePath $tplPath -DestinationPath $effectiveCoverPath -ProjectName $ProjectName -MetadataFile $MetadataFile
            }
        }
    }

    $manuscriptLines = New-Object 'System.Collections.Generic.List[string]'

    Write-Host "Cover template mode: $CoverTemplateMode; Cover file: $CoverFile" -ForegroundColor Cyan

    $leadPath = Resolve-OptionalFilePath -PrimaryRoot $contentRoot -FallbackRoot $resolvedSourceRoot -RelativePath $ManuscriptLeadFile
    $assetMap = New-Object 'System.Collections.Generic.Dictionary[string, string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $assetManifest = New-Object 'System.Collections.Generic.List[object]'

    if ($leadPath) {
        Write-Host "Appending lead file: $leadPath" -ForegroundColor Green
        Append-FileContent -Lines $manuscriptLines -Path $leadPath
        if ($CollectAssets) {
            Add-AssetReferencesForFile -MarkdownPath $leadPath -SourceRootResolved $resolvedSourceRoot -ContentRootResolved $contentRoot -AssetMap $assetMap -Manifest $assetManifest
        }
        $manuscriptLines.Add('')
    }

    if ((-not $SkipCoverInManuscript) -and (Test-Path $effectiveCoverPath)) {
        Write-Host "Appending cover file: $effectiveCoverPath" -ForegroundColor Green
        Append-FileContent -Lines $manuscriptLines -Path $effectiveCoverPath
        if ($CollectAssets) {
            Add-AssetReferencesForFile -MarkdownPath $effectiveCoverPath -SourceRootResolved $resolvedSourceRoot -ContentRootResolved $contentRoot -AssetMap $assetMap -Manifest $assetManifest
        }
        $manuscriptLines.Add('')
    }

    foreach ($chapterDir in $chapterDirs) {
        Write-Host "Processing chapter directory: $($chapterDir.Name)" -ForegroundColor Cyan
        $chapterOrdinal = Get-OrdinalPrefixFromName -Name $chapterDir.Name -Kind 'chapter'
        $chapterTitle = if ($chapterTitleMap.ContainsKey($chapterDir.Name)) { [string]$chapterTitleMap[$chapterDir.Name] } else { '' }
        $sectionFiles = @(Get-ChapterSectionFiles -ChapterRoot $chapterDir.FullName -FilePattern $ChapterFilePattern)

        if (-not [string]::IsNullOrWhiteSpace($chapterTitle)) {
            $chapterHeading = if ($NumberHeadings) {
                '# {0}. {1}' -f $chapterOrdinal, $chapterTitle
            }
            else {
                '# {0}' -f $chapterTitle
            }
            $manuscriptLines.Add($chapterHeading)
            $manuscriptLines.Add('')
        }

        for ($sectionIndex = 0; $sectionIndex -lt $sectionFiles.Count; $sectionIndex++) {
            $sectionFile = $sectionFiles[$sectionIndex]
            Write-Host "  Appending section: $($sectionFile.File.FullName)" -ForegroundColor DarkCyan
            $sectionOrdinal = $sectionIndex + 1
            $headingState = @{
                Counts = @(0, 0, 0, 0, 0, 0, 0)
                InCodeFence = $false
            }
            $headingPrefix = '{0}.{1}' -f $chapterOrdinal, $sectionOrdinal
            $headingLevelOffset = if ([string]::IsNullOrWhiteSpace($chapterTitle)) { 0 } else { 1 }
            $numberBaseLevel = if ([string]::IsNullOrWhiteSpace($chapterTitle)) { 1 } else { 2 }
            Append-FileContent -Lines $manuscriptLines -Path $sectionFile.File.FullName -NumberHeadings:$NumberHeadings -HeadingState $headingState -HeadingPrefix $headingPrefix -HeadingLevelOffset $headingLevelOffset -NumberBaseLevel $numberBaseLevel
            if ($CollectAssets) {
                Add-AssetReferencesForFile -MarkdownPath $sectionFile.File.FullName -SourceRootResolved $resolvedSourceRoot -ContentRootResolved $contentRoot -AssetMap $assetMap -Manifest $assetManifest
            }
            $manuscriptLines.Add('')
        }
    }

    $manuscriptDest = Join-Path $OutputDir ("$ProjectName.manuscript.md")
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    Write-Host "Writing manuscript to: $manuscriptDest" -ForegroundColor Cyan
    [System.IO.File]::WriteAllText($manuscriptDest, ($manuscriptLines.ToArray() -join [Environment]::NewLine).TrimEnd() + [Environment]::NewLine, $utf8NoBom)

    Write-Host "Manuscript written." -ForegroundColor Green

    if ($CollectAssets) {
        Write-Host "Collecting and copying assets to $OutputDir/images ..." -ForegroundColor Cyan
        Copy-CollectedAssets -OutputDir $OutputDir -AssetMap $assetMap

        # Write assets manifest into temporary workspace so it is removed by cleanup
        $assetsManifestPath = Join-Path $tempRoot ("$ProjectName.assets.json")
        
        $missingCount = 0
        foreach ($entry in $assetManifest) {
            if ($entry.status -eq 'missing') { $missingCount++ }
        }
        
        $entriesArray = $assetManifest.ToArray()
        $generatedAtString = (Get-Date).ToString('s')
        $assetMapCount = $assetMap.Count
        
        $manifestJson = ConvertTo-Json -InputObject @{
            projectName = $ProjectName
            generatedAt = $generatedAtString
            totalResolved = $assetMapCount
            totalMissing = $missingCount
            entries = $entriesArray
        } -Depth 6
        
        [System.IO.File]::WriteAllText($assetsManifestPath, $manifestJson, $utf8NoBom)

        if ($PreserveTemp) {
            $finalAssetsPath = Join-Path $OutputDir ("$ProjectName.assets.json")
            Move-Item -Path $assetsManifestPath -Destination $finalAssetsPath -Force
            Write-Host "Assets manifest written: $finalAssetsPath" -ForegroundColor Green
        } else {
            Write-Host "Assets manifest created in temp workspace (will be removed): $assetsManifestPath" -ForegroundColor DarkCyan
        }

        Write-Host "ASSETS: resolved=$($assetMap.Count), missing=$missingCount" -ForegroundColor Green
        Write-Host "OUTPUT: $(Join-Path $OutputDir 'images')" -ForegroundColor Green
        Write-Host "OUTPUT: $assetsManifestPath" -ForegroundColor Green
        try {
            Write-Host "Updating manuscript links to point to collected images..." -ForegroundColor Cyan
            Update-ManuscriptLinks -AssetsPath $assetsManifestPath -ManuscriptPath $manuscriptDest
            Write-Host "Manuscript links updated." -ForegroundColor Green
        } catch {
            Write-Warning "Update-ManuscriptLinks failed: $_"
        }
    }

    # -----------------------------------------------------------------------
    # Optional: append samples catalog
    # -----------------------------------------------------------------------
    if (-not [string]::IsNullOrWhiteSpace($SamplesRoot) -and (Test-Path $SamplesRoot)) {
        Write-Host "Generating samples catalog from: $SamplesRoot" -ForegroundColor Cyan
        $resolvedSamplesRoot = (Resolve-Path $SamplesRoot).ProviderPath

        $catalogLines = New-Object 'System.Collections.Generic.List[string]'
        $catalogLines.Add('')
        $catalogLines.Add('---')
        $catalogLines.Add('')
        $catalogLines.Add("# $SamplesTitle")
        $catalogLines.Add('')

        $allSampleFiles = @(Get-ChildItem -Path $resolvedSamplesRoot -Recurse -File -Filter '*.md' -ErrorAction SilentlyContinue |
            Sort-Object FullName)

        $allSampleDirectories = @($allSampleFiles |
            ForEach-Object { Split-Path $_.FullName -Parent } |
            Sort-Object -Unique)

        $nonReadmeCount = 0
        foreach ($directoryPath in $allSampleDirectories) {
            $relativeDirectory = $directoryPath.Substring($resolvedSamplesRoot.Length).TrimStart('\', '/').Replace('\', '/')
            if ([string]::IsNullOrWhiteSpace($relativeDirectory)) {
                continue
            }

            $depth = @($relativeDirectory -split '/').Count
            $headingLevel = [Math]::Min(6, 1 + $depth)
            Write-Host "  [DIR] H$headingLevel $relativeDirectory" -ForegroundColor Cyan
            $catalogLines.Add(('#' * $headingLevel) + ' ' + $relativeDirectory)
            $catalogLines.Add('')

            $directoryFiles = @($allSampleFiles |
                Where-Object { (Split-Path $_.FullName -Parent) -eq $directoryPath } |
                Sort-Object Name)

            $readmeFile = $directoryFiles | Where-Object { $_.Name -ieq 'README.md' } | Select-Object -First 1
            if ($readmeFile) {
                Write-Host "    [README] $($readmeFile.Name) -> Markdown body" -ForegroundColor Yellow
                $readmeLines = @(Get-Content -Path $readmeFile.FullName -Encoding UTF8)
                foreach ($line in $readmeLines) { $catalogLines.Add($line) }
                $catalogLines.Add('')
            }

            $nonReadmeFiles = @($directoryFiles | Where-Object { $_.Name -ine 'README.md' })
            foreach ($sampleFile in $nonReadmeFiles) {
                $fileLines = @(Get-Content -Path $sampleFile.FullName -Encoding UTF8)
                $maxBacktickRun = 0
                foreach ($line in $fileLines) {
                    $matches = [regex]::Matches($line, '`{3,}')
                    foreach ($match in $matches) {
                        if ($match.Value.Length -gt $maxBacktickRun) {
                            $maxBacktickRun = $match.Value.Length
                        }
                    }
                }
                $fenceLen = [Math]::Max(4, $maxBacktickRun + 1)
                $openFence = ('`' * $fenceLen) + 'text'
                $closeFence = ('`' * $fenceLen)

                Write-Host "    [FILE] $($sampleFile.Name) (fence=$fenceLen)" -ForegroundColor Gray
                $catalogLines.Add("- $($sampleFile.Name)")
                $catalogLines.Add($openFence)
                foreach ($line in $fileLines) { $catalogLines.Add($line) }
                $catalogLines.Add($closeFence)
                $catalogLines.Add('')
                $nonReadmeCount++
            }
        }

        $catalogText = $catalogLines.ToArray() -join [Environment]::NewLine
        [System.IO.File]::AppendAllText($manuscriptDest, $catalogText, $utf8NoBom)
        Write-Host "SAMPLES CATALOG: $($allSampleFiles.Count) files scanned, $nonReadmeCount files appended as code blocks." -ForegroundColor Green
    }
    elseif (-not [string]::IsNullOrWhiteSpace($SamplesRoot)) {
        Write-Warning "SamplesRoot not found, skipping catalog generation: $SamplesRoot"
    }

    Write-Host "OUTPUT: $manuscriptDest" -ForegroundColor Green
    Write-Host 'Step 1 complete. Review manuscript, then run Step 2 and Step 3.' -ForegroundColor Green
}
finally {
    if ($PreserveTemp) {
        Write-Host "Temporary workspace preserved: $tempRoot" -ForegroundColor Yellow
    }
    else {
        Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}


