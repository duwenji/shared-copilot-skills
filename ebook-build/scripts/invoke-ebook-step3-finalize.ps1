<#
.SYNOPSIS
  Step 3 - Render Mermaid diagrams and finalize ebook files (EPUB / PDF / KDP).
#>
param(
    [string]$OutputDir,
    [string]$ProjectName,
    [string]$MetadataFile,
    [string]$KdpMetadataFile,
    [string]$KindleTemplateDir,
    [string]$StyleFile,
    [string[]]$Formats             = @('epub', 'pdf', 'kdp-markdown'),
    [string]$ChapterDirPattern     = '^\d{2}-',
    [string]$ChapterFilePattern    = '^\d{2}-.*\.md$',
    [string]$CoverFile             = '00-COVER.md',
    [ValidateSet('off', 'auto', 'required')]
    [string]$MermaidMode           = 'required',
    [ValidateSet('svg', 'png')]
    [string]$MermaidFormat         = 'svg',
    [bool]$FailOnMermaidError      = $true,
    [string]$MermaidConfigFile     = '',
    [string]$MermaidPuppeteerConfigFile = '',
    [bool]$RequireManuscriptApproval = $false,
    [string]$ApprovalTokenFile,
    [int]$TocDepth                 = 0,
    [switch]$PreserveTemp
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Ensure-Path {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path $Path)) { throw "$Label not found: $Path" }
}

function Copy-ArtifactSafely {
    param([string]$SourcePath, [string]$DestinationPath, [string]$ArtifactLabel)
    try {
        Copy-Item -Path $SourcePath -Destination $DestinationPath -Force
        return $DestinationPath
    }
    catch [System.IO.IOException] {
        $dir  = Split-Path -Parent $DestinationPath
        $base = [System.IO.Path]::GetFileNameWithoutExtension($DestinationPath)
        $ext  = [System.IO.Path]::GetExtension($DestinationPath)
        $alt  = Join-Path $dir ("{0}-{1}{2}" -f $base, (Get-Date -Format 'yyyyMMdd-HHmmss'), $ext)
        Copy-Item -Path $SourcePath -Destination $alt -Force
        Write-Warning "$ArtifactLabel could not overwrite '$DestinationPath' (in use). Saved to '$alt'."
        return $alt
    }
}

function Get-TextHash {
    param([string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hashBytes = $sha.ComputeHash($bytes)
    }
    finally { $sha.Dispose() }

    return ([System.BitConverter]::ToString($hashBytes)).Replace('-', '').ToLowerInvariant().Substring(0, 16)
}

function Get-FileTextHashOrEmpty {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path $Path)) {
        return ''
    }

    return Get-TextHash -Text ([System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8))
}

function Get-MermaidCommandSpec {
    $mmdc = Get-Command mmdc -ErrorAction SilentlyContinue
    if ($mmdc) {
        return @{ Command = $mmdc.Source; Arguments = @(); Label = 'mmdc' }
    }

    $npx  = Get-Command npx  -ErrorAction SilentlyContinue
    if ($npx) {
        return @{ Command = $npx.Source; Arguments = @('--yes', '@mermaid-js/mermaid-cli'); Label = 'npx @mermaid-js/mermaid-cli' }
    }

    return $null
}

function Invoke-MermaidRender {
    param(
        [hashtable]$CommandSpec,
        [string]$DiagramText,
        [string]$OutputPath,
        [ValidateSet('svg', 'png')] [string]$Format,
        [string]$ConfigFile = '',
        [string]$PuppeteerConfigFile = ''
    )

    if (Test-Path $OutputPath) { return $true }

    $inputPath = [System.IO.Path]::ChangeExtension($OutputPath, '.mmd')
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($inputPath, $DiagramText, $utf8NoBom)

    try {
        $renderArgs = @()
        if ($CommandSpec.ContainsKey('Arguments') -and $null -ne $CommandSpec['Arguments']) {
            $renderArgs += @($CommandSpec['Arguments'])
        }

        $renderArgs += @('-i', $inputPath, '-o', $OutputPath, '-e', $Format, '-b', 'white')
        if (-not [string]::IsNullOrWhiteSpace($ConfigFile) -and (Test-Path $ConfigFile)) {
            $renderArgs += @('-c', $ConfigFile)
        }
        if (-not [string]::IsNullOrWhiteSpace($PuppeteerConfigFile) -and (Test-Path $PuppeteerConfigFile)) {
            $renderArgs += @('-p', $PuppeteerConfigFile)
        }
        & $CommandSpec['Command'] @renderArgs
        return ($LASTEXITCODE -eq 0 -and (Test-Path $OutputPath))
    }
    finally {
        Remove-Item -Path $inputPath -Force -ErrorAction SilentlyContinue
    }
}

function Convert-MermaidBlocksInMarkdown {
    param(
        [string]$Path,
        [string]$StageBookRoot,
        [hashtable]$CommandSpec,
        [ValidateSet('auto', 'required')] [string]$Mode,
        [ValidateSet('svg', 'png')] [string]$Format,
        [bool]$FailOnError = $false,
        [string]$ConfigFile = '',
        [string]$PuppeteerConfigFile = ''
    )

    $sourceLines = Get-Content -Path $Path -Encoding UTF8
    $resultLines = New-Object 'System.Collections.Generic.List[string]'
    $originalMermaidLines = New-Object 'System.Collections.Generic.List[string]'
    $mermaidBuffer = New-Object 'System.Collections.Generic.List[string]'
    $imagesRoot = Join-Path $StageBookRoot 'images\mermaid'
    New-Item -ItemType Directory -Path $imagesRoot -Force | Out-Null
    $configHash = Get-FileTextHashOrEmpty -Path $ConfigFile

    $insideFence = $false
    $fenceChar = $null
    $fenceLength = 0
    $insideMermaid = $false
    $mermaidFenceChar = $null
    $mermaidFenceLength = 0
    $mermaidIndent = ''
    $blockCount = 0
    $renderedCount = 0
    $fileChanged = $false

    foreach ($line in $sourceLines) {
        if ($insideMermaid) {
            $originalMermaidLines.Add($line)
            if ($line -match "^\s*$([regex]::Escape($mermaidFenceChar)){$mermaidFenceLength,}\s*$") {
                $blockCount += 1
                $diagramText = ($mermaidBuffer.ToArray() -join [Environment]::NewLine).Trim()
                $hash = Get-TextHash -Text "$Format`n$configHash`n$diagramText"
                $imageFileName = "mermaid-$hash.$Format"
                $imagePath = Join-Path $imagesRoot $imageFileName
                $imageMarkdownPath = "images/mermaid/$imageFileName"

                $rendered = $false
                if (-not [string]::IsNullOrWhiteSpace($diagramText)) {
                    $rendered = Invoke-MermaidRender -CommandSpec $CommandSpec -DiagramText $diagramText -OutputPath $imagePath -Format $Format -ConfigFile $ConfigFile -PuppeteerConfigFile $PuppeteerConfigFile
                }

                if ($rendered) {
                    $resultLines.Add("$mermaidIndent![]($imageMarkdownPath)")
                    $renderedCount += 1
                    $fileChanged = $true
                }
                else {
                    $message = "Mermaid render failed for $Path"
                    if ($Mode -eq 'required' -or $FailOnError) { throw $message }
                    Write-Warning "$message. Leaving source block unchanged."
                    foreach ($original in $originalMermaidLines.ToArray()) { $resultLines.Add($original) }
                }

                $insideMermaid = $false
                $mermaidFenceChar = $null
                $mermaidFenceLength = 0
                $mermaidIndent = ''
                $mermaidBuffer.Clear()
                $originalMermaidLines.Clear()
                continue
            }

            $mermaidBuffer.Add($line)
            continue
        }

        if (-not $insideFence -and $line -match '^(?<indent>\s*)(?<marker>`{3,}|~{3,})\s*mermaid(?:\s+.*)?\s*$') {
            $insideMermaid = $true
            $mermaidFenceChar = $Matches['marker'].Substring(0, 1)
            $mermaidFenceLength = $Matches['marker'].Length
            $mermaidIndent = $Matches['indent']
            $originalMermaidLines.Add($line)
            $mermaidBuffer.Clear()
            continue
        }

        if ($line -match '^\s*(?<marker>`{3,}|~{3,}).*$') {
            $candidateChar = $Matches['marker'].Substring(0, 1)
            $candidateLength = $Matches['marker'].Length
            if (-not $insideFence) {
                $insideFence = $true
                $fenceChar = $candidateChar
                $fenceLength = $candidateLength
            }
            elseif ($candidateChar -eq $fenceChar -and $candidateLength -ge $fenceLength) {
                $insideFence = $false
                $fenceChar = $null
                $fenceLength = 0
            }
        }

        $resultLines.Add($line)
    }

    if ($insideMermaid) {
        foreach ($original in $originalMermaidLines.ToArray()) { $resultLines.Add($original) }
    }

    if ($fileChanged) {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($Path, ($resultLines.ToArray() -join [Environment]::NewLine), $utf8NoBom)
    }

    return [PSCustomObject]@{ Path = $Path; Blocks = $blockCount; Rendered = $renderedCount; Changed = $fileChanged }
}

function Invoke-MermaidPreprocessing {
    param(
        [string]$StageBookRoot,
        [ValidateSet('off', 'auto', 'required')] [string]$Mode = 'required',
        [ValidateSet('svg', 'png')] [string]$Format = 'svg',
        [bool]$FailOnError = $true,
        [string]$ConfigFile = '',
        [string]$PuppeteerConfigFile = ''
    )

    if ($Mode -eq 'off') { return }

    $markdownFiles = @(Get-ChildItem -Path $StageBookRoot -Recurse -File -Filter '*.md' -ErrorAction SilentlyContinue)
    if ($markdownFiles.Count -eq 0) { return }

    $hasMermaid = $false
    foreach ($file in $markdownFiles) {
        if (Select-String -Path $file.FullName -Pattern '^\s*(`{3,}|~{3,})\s*mermaid(?:\s+.*)?\s*$' -Quiet) {
            $hasMermaid = $true
            break
        }
    }
    if (-not $hasMermaid) { return }

    $commandSpec = Get-MermaidCommandSpec
    if ($null -eq $commandSpec) {
        $message = 'Mermaid CLI not found. Install mmdc or ensure npx is available.'
        if ($Mode -eq 'required' -or $FailOnError) { throw $message }
        Write-Warning "$message Mermaid blocks will remain as source text."
        return
    }

    Write-Host "Rendering Mermaid diagrams using $($commandSpec['Label'])..." -ForegroundColor Cyan
    foreach ($file in $markdownFiles) {
        [void](Convert-MermaidBlocksInMarkdown -Path $file.FullName -StageBookRoot $StageBookRoot -CommandSpec $commandSpec -Mode $Mode -Format $Format -FailOnError $FailOnError -ConfigFile $ConfigFile -PuppeteerConfigFile $PuppeteerConfigFile)
    }
}

function Get-BrowserExecutable {
    $candidates = @(
        'msedge',
        'chrome',
        'chromium',
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles(x86)\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe"
    )

    foreach ($candidate in $candidates) {
        if ($candidate -match '\.exe$') {
            if (Test-Path $candidate) { return $candidate }
            continue
        }

        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }

    throw 'No browser executable found for headless render (Edge/Chrome required).'
}

function Invoke-HeadlessBrowser {
    param(
        [string]$Browser,
        [string[]]$Arguments,
        [string]$ExpectedOutput
    )

    if (Test-Path $ExpectedOutput) {
        Remove-Item -Path $ExpectedOutput -Force -ErrorAction SilentlyContinue
    }

    & $Browser @Arguments
    for ($i = 0; $i -lt 150; $i++) {
        if (Test-Path $ExpectedOutput) { return }
        Start-Sleep -Milliseconds 200
    }

    # Fallback: some browsers (Edge) return non-zero exit code even on success;
    # retry with legacy --headless flag with minimal flags before giving up.
    $printToPdfArg = $Arguments | Where-Object { $_ -like '--print-to-pdf=*' } | Select-Object -First 1
    $urlArg = $Arguments | Select-Object -Last 1
    $fallbackArgs = @('--headless', '--disable-gpu', '--no-sandbox')
    if ($printToPdfArg) { $fallbackArgs += $printToPdfArg }
    $fallbackArgs += $urlArg
    & $Browser @fallbackArgs
    for ($i = 0; $i -lt 150; $i++) {
        if (Test-Path $ExpectedOutput) { return }
        Start-Sleep -Milliseconds 200
    }

    if (-not (Test-Path $ExpectedOutput)) {
        throw "Headless render failed: $ExpectedOutput"
    }
}

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
            }
            else {
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
            }
            else {
                $result[$key] = ''
            }
            continue
        }

        $normalizedValue = $value.Trim().Trim('"').Trim("'")
        if ($normalizedValue -eq 'null') {
            $result[$key] = $null
        }
        elseif ($normalizedValue -eq 'true') {
            $result[$key] = $true
        }
        elseif ($normalizedValue -eq 'false') {
            $result[$key] = $false
        }
        else {
            $result[$key] = $normalizedValue
        }
    }

    return $result
}

function Merge-Maps {
    param([hashtable]$BaseMap, [hashtable]$OverrideMap)

    $merged = @{}
    foreach ($entry in $BaseMap.GetEnumerator()) { $merged[$entry.Key] = $entry.Value }
    foreach ($entry in $OverrideMap.GetEnumerator()) {
        if ($null -ne $entry.Value -and -not [string]::IsNullOrWhiteSpace([string]$entry.Value)) {
            $merged[$entry.Key] = $entry.Value
        }
    }

    return $merged
}

function Get-StringValue {
    param([hashtable]$Map, [string[]]$Keys, [string]$Default = '')

    foreach ($key in $Keys) {
        if ($Map.ContainsKey($key)) {
            $value = $Map[$key]
            if ($value -is [System.Array]) {
                if ($value.Count -gt 0) {
                    return (($value | ForEach-Object { [string]$_ }) -join ', ').Trim()
                }
            }
            elseif ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
                return ([string]$value).Trim()
            }
        }
    }

    return $Default
}

function Get-ArrayValue {
    param([hashtable]$Map, [string[]]$Keys, [string[]]$Default = @())

    foreach ($key in $Keys) {
        if (-not $Map.ContainsKey($key)) { continue }

        $value = $Map[$key]
        if ($value -is [System.Array]) {
            $items = @($value | ForEach-Object { ([string]$_).Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            if ($items.Count -gt 0) { return $items }
        }
        elseif ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
            $items = @(([string]$value) -split '[;,|]' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            if ($items.Count -gt 0) { return $items }
        }
    }

    return $Default
}

function Resolve-TocDepth {
    param(
        [int]$RequestedDepth,
        [string]$MetadataFile,
        [int]$DefaultDepth = 3
    )

    $resolvedDepth = $RequestedDepth
    if ($resolvedDepth -le 0) {
        $metadata = Convert-SimpleYamlToMap -Path $MetadataFile
        if ($metadata.ContainsKey('toc-depth')) {
            $parsedDepth = 0
            if ([int]::TryParse([string]$metadata['toc-depth'], [ref]$parsedDepth)) {
                $resolvedDepth = $parsedDepth
            }
        }
    }

    if ($resolvedDepth -le 0) {
        $resolvedDepth = $DefaultDepth
    }

    return [Math]::Min(6, [Math]::Max(1, $resolvedDepth))
}

function Join-MarkdownList {
    param([string[]]$Items)

    if ($null -eq $Items -or $Items.Count -eq 0) { return '- TBD' }
    return (($Items | ForEach-Object { '- ' + $_ }) -join [Environment]::NewLine)
}

function New-KdpPackageMarkdown {
    param(
        [string]$ProjectName,
        [string]$MetadataFile,
        [string]$OutputPath,
        [string]$KdpMetadataFile,
        [string]$EpubPath,
        [string]$PdfPath
    )

    $baseMetadata = Convert-SimpleYamlToMap -Path $MetadataFile
    $kdpMetadata = Convert-SimpleYamlToMap -Path $KdpMetadataFile
    $metadata = Merge-Maps -BaseMap $baseMetadata -OverrideMap $kdpMetadata

    $title = Get-StringValue -Map $metadata -Keys @('title') -Default $ProjectName
    $subtitle = Get-StringValue -Map $metadata -Keys @('subtitle') -Default 'TBD'
    $creator = Get-StringValue -Map $metadata -Keys @('creator', 'author') -Default 'TBD'
    $language = Get-StringValue -Map $metadata -Keys @('language') -Default 'ja-JP'
    $publisher = Get-StringValue -Map $metadata -Keys @('publisher') -Default 'Self Published'
    $rights = Get-StringValue -Map $metadata -Keys @('rights') -Default 'Rights review required'
    $identifier = Get-StringValue -Map $metadata -Keys @('identifier', 'asin') -Default 'TBD'
    $date = Get-StringValue -Map $metadata -Keys @('date') -Default ((Get-Date).ToString('yyyy-MM-dd'))
    $description = Get-StringValue -Map $metadata -Keys @('description', 'abstract', 'summary') -Default 'TODO: finalize KDP product description.'
    $keywords = @(Get-ArrayValue -Map $metadata -Keys @('keywords', 'keyword', 'subject') -Default @('TBD'))
    if (@($keywords).Count -gt 7) { $keywords = @($keywords | Select-Object -First 7) }
    $categories = @(Get-ArrayValue -Map $metadata -Keys @('categories', 'category') -Default @('TBD'))
    if (@($categories).Count -gt 3) { $categories = @($categories | Select-Object -First 3) }

    $territories = Get-StringValue -Map $metadata -Keys @('territories', 'distributionTerritories') -Default 'Worldwide'
    $royaltyPlan = Get-StringValue -Map $metadata -Keys @('royaltyPlan', 'royalty') -Default '70% (validate constraints)'
    $listPrice = Get-StringValue -Map $metadata -Keys @('listPrice', 'price', 'priceJpy') -Default 'TBD'
    $kdpSelect = Get-StringValue -Map $metadata -Keys @('kdpSelect', 'enrollInKdpSelect') -Default 'Optional'
    $isbn = Get-StringValue -Map $metadata -Keys @('isbn') -Default 'Typically not required for Kindle only'

    $artifacts = New-Object 'System.Collections.Generic.List[string]'
    if (-not [string]::IsNullOrWhiteSpace($EpubPath)) { $artifacts.Add("- EPUB: $EpubPath") }
    if (-not [string]::IsNullOrWhiteSpace($PdfPath)) { $artifacts.Add("- PDF: $PdfPath") }
    if ($artifacts.Count -eq 0) { $artifacts.Add('- Check artifacts under ebook-output directory') }

    $content = @"
# KDP Registration Package: $title

- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
- Project: $ProjectName
- Metadata: $MetadataFile
- KDP Metadata: $(if ($KdpMetadataFile) { $KdpMetadataFile } else { 'Not provided' })

## 1. Bibliographic Information

| Field | Value |
|---|---|
| Title | $title |
| Subtitle | $subtitle |
| Author | $creator |
| Language | $language |
| Publisher | $publisher |
| Rights | $rights |
| Identifier | $identifier |
| Publication Date | $date |
| ISBN | $isbn |

## 2. Product Description

> $description

## 3. Keywords (up to 7)

$(Join-MarkdownList -Items $keywords)

## 4. Categories (up to 3)

$(Join-MarkdownList -Items $categories)

## 5. Pricing and Distribution

| Field | Value |
|---|---|
| List Price | $listPrice |
| Royalty | $royaltyPlan |
| Territories | $territories |
| KDP Select | $kdpSelect |

## 6. Upload Files

$($artifacts.ToArray() -join [Environment]::NewLine)
"@

    $outputDirectory = Split-Path -Parent $OutputPath
    if (-not (Test-Path $outputDirectory)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($OutputPath, $content.Trim() + [Environment]::NewLine, $utf8NoBom)
}

$manuscriptInputPath = Join-Path $OutputDir ("$ProjectName.manuscript.md")
$coverJpgInputPath = Join-Path $OutputDir 'cover.jpg'
$coverPdfInputPath = Join-Path $OutputDir 'cover.pdf'

Ensure-Path -Path $manuscriptInputPath -Label "Step 1 output - $ProjectName.manuscript.md"
Ensure-Path -Path $coverJpgInputPath -Label 'Step 2 output - cover.jpg'
Ensure-Path -Path $coverPdfInputPath -Label 'Step 2 output - cover.pdf'
Ensure-Path -Path $MetadataFile -Label 'MetadataFile'
Ensure-Path -Path $StyleFile -Label 'StyleFile'

$resolvedTocDepth = Resolve-TocDepth -RequestedDepth $TocDepth -MetadataFile $MetadataFile
Write-Host "TOC depth resolved to: $resolvedTocDepth" -ForegroundColor Cyan

$skillRoot = Split-Path -Parent $PSScriptRoot
$printStyleFile = Join-Path $skillRoot 'assets\print.css'
Ensure-Path -Path $printStyleFile -Label 'print.css'

if (-not (Get-Command pandoc -ErrorAction SilentlyContinue)) {
    throw 'pandoc is required but was not found in PATH.'
}

if (-not [string]::IsNullOrWhiteSpace($KdpMetadataFile)) {
    Ensure-Path -Path $KdpMetadataFile -Label 'KdpMetadataFile'
}

if ($RequireManuscriptApproval) {
    if ([string]::IsNullOrWhiteSpace($ApprovalTokenFile)) {
        $ApprovalTokenFile = Join-Path $OutputDir ("$ProjectName.manuscript.approved")
    }
    if (-not (Test-Path $ApprovalTokenFile)) {
        throw "Manuscript approval token not found: $ApprovalTokenFile"
    }
}

$Formats = @($Formats | ForEach-Object { $_.ToString().ToLowerInvariant() } | Select-Object -Unique)
$supportedFormats = @('epub', 'pdf', 'kdp-markdown')
$unsupportedFormats = @($Formats | Where-Object { $supportedFormats -notcontains $_ })
if ($unsupportedFormats.Count -gt 0) {
    throw "Unsupported format(s): $($unsupportedFormats -join ', '). Supported: $($supportedFormats -join ', ')"
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ebook-step3-" + [Guid]::NewGuid().ToString('N'))
$stageBookRoot = Join-Path $tempRoot 'book'
$stageOutput = Join-Path $tempRoot 'output'
New-Item -ItemType Directory -Path $stageBookRoot -Force | Out-Null
New-Item -ItemType Directory -Path $stageOutput -Force | Out-Null

try {
    $stagedManuscriptPath = Join-Path $stageBookRoot ("$ProjectName.manuscript.md")
    Copy-Item -Path $manuscriptInputPath -Destination $stagedManuscriptPath -Force

    $outputImages = Join-Path $OutputDir 'images'
    if (Test-Path $outputImages) {
        Copy-Item -Path $outputImages -Destination (Join-Path $stageBookRoot 'images') -Recurse -Force
    }

    # Clear staged mermaid images before re-rendering to ensure fresh generation with current config
    $stagedMermaidDir = Join-Path $stageBookRoot 'images\mermaid'
    if (Test-Path $stagedMermaidDir) {
        Remove-Item -Path "$stagedMermaidDir\*" -Force -Recurse -ErrorAction SilentlyContinue
    }

    Write-Host 'Step 3 - Rendering Mermaid diagrams...' -ForegroundColor Cyan
    Invoke-MermaidPreprocessing -StageBookRoot $stageBookRoot -Mode $MermaidMode -Format $MermaidFormat -FailOnError $FailOnMermaidError -ConfigFile $MermaidConfigFile -PuppeteerConfigFile $MermaidPuppeteerConfigFile

    $copiedArtifacts = New-Object 'System.Collections.Generic.List[string]'

    if ($Formats -contains 'epub') {
        Write-Host 'Step 3 - Building EPUB...' -ForegroundColor Cyan
        $epubStaged = Join-Path $stageOutput "$ProjectName.epub"

        Push-Location $stageBookRoot
        try {
            & pandoc `
                "--from=markdown" `
                "--to=epub3" `
                "--toc" `
                "--toc-depth=$resolvedTocDepth" `
                "--metadata-file=$MetadataFile" `
                "--css=$StyleFile" `
                "--output=$epubStaged" `
                (Split-Path -Leaf $stagedManuscriptPath)
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path $epubStaged)) {
                throw 'EPUB artifact was not produced by pandoc.'
            }
        }
        finally {
            Pop-Location
        }

        $epubDest = Copy-ArtifactSafely -SourcePath $epubStaged -DestinationPath (Join-Path $OutputDir "$ProjectName.epub") -ArtifactLabel 'EPUB'
        $copiedArtifacts.Add($epubDest)
        Write-Host "OUTPUT: $epubDest" -ForegroundColor Green
    }

    if ($Formats -contains 'pdf') {
        Write-Host 'Step 3 - Building PDF...' -ForegroundColor Cyan
        $browser = Get-BrowserExecutable
        $resolvedOutputDir = (Resolve-Path $OutputDir).ProviderPath
        $printHtml = Join-Path $resolvedOutputDir "$ProjectName.print.html"
        $pdfDest   = Join-Path $resolvedOutputDir "$ProjectName.pdf"

        Push-Location $stageBookRoot
        try {
            & pandoc `
                "--from=markdown" `
                "--to=html5" `
                "--standalone" `
                "--toc" `
                "--toc-depth=$resolvedTocDepth" `
                "--metadata-file=$MetadataFile" `
                "--css=$StyleFile" `
                "--css=$printStyleFile" `
                "--output=$printHtml" `
                (Split-Path -Leaf $stagedManuscriptPath)
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path $printHtml)) {
                throw 'Failed to produce print HTML for PDF.'
            }
        }
        finally {
            Pop-Location
        }

        $htmlUrl = 'file:///' + ($printHtml -replace '\\', '/')
        Invoke-HeadlessBrowser -Browser $browser -ExpectedOutput $pdfDest -Arguments @(
            '--headless=new',
            '--disable-gpu',
            '--no-sandbox',
            '--disable-extensions',
            '--disable-background-networking',
            '--no-pdf-header-footer',
            '--print-to-pdf-no-header',
            '--allow-file-access-from-files',
            '--no-first-run',
            '--no-default-browser-check',
            "--print-to-pdf=$pdfDest",
            $htmlUrl
        )

        $copiedArtifacts.Add($pdfDest)
        Write-Host "OUTPUT: $pdfDest" -ForegroundColor Green
        Write-Host "OUTPUT: $printHtml" -ForegroundColor Green
    }

    $stagedMermaidDir = Join-Path $stageBookRoot 'images\mermaid'
    if (Test-Path $stagedMermaidDir) {
        $outputMermaidDir = Join-Path $OutputDir 'images\mermaid'
        if (Test-Path $outputMermaidDir) {
            Remove-Item -Path $outputMermaidDir -Recurse -Force
        }
        Copy-Item -Path $stagedMermaidDir -Destination $outputMermaidDir -Recurse -Force
        Write-Host "OUTPUT: $outputMermaidDir" -ForegroundColor Green
    }

    if ($Formats -contains 'kdp-markdown') {
        $kdpOutputPath = Join-Path $OutputDir "$ProjectName-kdp-registration.md"
        $epubPath = if ($Formats -contains 'epub') { Join-Path $OutputDir "$ProjectName.epub" } else { $null }
        $pdfPath = if ($Formats -contains 'pdf') { Join-Path $OutputDir "$ProjectName.pdf" } else { $null }

        New-KdpPackageMarkdown -ProjectName $ProjectName -MetadataFile $MetadataFile -OutputPath $kdpOutputPath -KdpMetadataFile $KdpMetadataFile -EpubPath $epubPath -PdfPath $pdfPath
        Ensure-Path -Path $kdpOutputPath -Label 'KDP registration markdown'
        $copiedArtifacts.Add($kdpOutputPath)
        Write-Host "OUTPUT: $kdpOutputPath" -ForegroundColor Green
    }

    if ($copiedArtifacts.Count -eq 0) {
        Write-Warning 'No output artifacts were requested by the current format selection.'
    }

    Write-Host 'Step 3 complete. Ebook build finished.' -ForegroundColor Green
}
finally {
    if ($PreserveTemp) {
        Write-Host "Temporary workspace preserved: $tempRoot" -ForegroundColor Yellow
    }
    else {
        Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
