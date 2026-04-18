param(
    [string]$ConfigFile,
    [ValidateSet('full', 'manuscript-only', 'continue')] [string]$BuildPhase = 'full',
    [bool]$RequireManuscriptApproval = $false,
    [string]$ApprovalTokenFile,
    [string]$SourceRoot,
    [string]$OutputDir,
    [string]$ProjectName,
    [string]$KindleTemplateDir,
    [string]$MetadataFile,
    [string]$KdpMetadataFile,
    [string]$StyleFile,
    [string[]]$Formats,
    [string]$ChapterDirPattern = '^\d{2}-',
    [string]$ChapterFilePattern = '^\d{2}-.*\.md$',
    [string]$CoverFile = '00-COVER.md',
    [ValidateSet('auto', 'file', 'template')] [string]$CoverTemplateMode = 'auto',
    [string]$CoverTemplate = 'classic',
    [ValidateSet('off', 'auto', 'required')] [string]$MermaidMode = 'required',
    [ValidateSet('svg', 'png')] [string]$MermaidFormat = 'svg',
    [bool]$FailOnMermaidError = $true,
    [switch]$PreserveTemp
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptBound = $PSBoundParameters

function Get-ConfigMap {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return @{}
    }

    if (-not (Test-Path $Path)) {
        throw "Config file not found: $Path"
    }

    $json = Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $map = @{}
    foreach ($property in $json.PSObject.Properties) {
        $map[$property.Name] = $property.Value
    }

    return $map
}

function Resolve-Value {
    param(
        [string]$Name,
        $CurrentValue,
        $DefaultValue,
        [hashtable]$Config,
        [hashtable]$Bound
    )
    if ($Bound.ContainsKey($Name)) {
        return $CurrentValue
    }

    if ($Config.ContainsKey($Name) -and $null -ne $Config[$Name]) {
        return $Config[$Name]
    }

    return $DefaultValue
}

function Resolve-ConfiguredPath {
    param(
        [AllowNull()] [string]$PathValue,
        [string]$RepoRoot
    )

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $PathValue
    }

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return $PathValue
    }

    return Join-Path $RepoRoot $PathValue
}

function Resolve-DefaultMetadataFile {
    param(
        [string]$RepoRoot,
        [string]$ProjectName
    )

    $preferredDir = Join-Path $RepoRoot '.github\skills-config\ebook-build'
    $legacyDir = Join-Path $RepoRoot '.github\skills\ebook-build\configs'

    $preferredCandidate = Join-Path $preferredDir ("$ProjectName.metadata.yaml")
    if (Test-Path $preferredCandidate) {
        return $preferredCandidate
    }

    $legacyCandidate = Join-Path $legacyDir ("$ProjectName.metadata.yaml")
    if (Test-Path $legacyCandidate) {
        return $legacyCandidate
    }

    $metadataCandidates = @()
    if (Test-Path $preferredDir) {
        $metadataCandidates += Get-ChildItem -Path $preferredDir -File -Filter '*.metadata.yaml' -ErrorAction SilentlyContinue
    }
    if (Test-Path $legacyDir) {
        $metadataCandidates += Get-ChildItem -Path $legacyDir -File -Filter '*.metadata.yaml' -ErrorAction SilentlyContinue
    }

    $metadataCandidates = @($metadataCandidates | Sort-Object FullName -Unique)
    if ($metadataCandidates.Count -eq 1) {
        Write-Warning "Project metadata not found for '$ProjectName'. Falling back to $($metadataCandidates[0].FullName)."
        return $metadataCandidates[0].FullName
    }

    return $preferredCandidate
}

function Resolve-DefaultKdpMetadataFile {
    param(
        [string]$RepoRoot,
        [string]$ProjectName
    )

    $preferredDir = Join-Path $RepoRoot '.github\skills-config\ebook-build'
    $legacyDir = Join-Path $RepoRoot '.github\skills\ebook-build\configs'

    foreach ($candidate in @(
        (Join-Path $preferredDir ("$ProjectName.kdp.yaml")),
        (Join-Path $legacyDir ("$ProjectName.kdp.yaml"))
    )) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

function Resolve-ContentRoot {
    param(
        [string]$Root,
        [string]$DirPattern
    )

    $candidateA = (Resolve-Path $Root).ProviderPath
    $dirsA = @(Get-ChildItem -Path $candidateA -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $DirPattern })
    if ($dirsA.Count -gt 0) {
        return $candidateA
    }

    $candidateB = Join-Path $candidateA 'docs'
    if (Test-Path $candidateB) {
        $dirsB = @(Get-ChildItem -Path $candidateB -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $DirPattern })
        if ($dirsB.Count -gt 0) {
            return $candidateB
        }
    }

    throw "No chapter directories found. root=$candidateA pattern=$DirPattern"
}

function Ensure-Path {
    param(
        [string]$Path,
        [string]$Label
    )

    if (-not (Test-Path $Path)) {
        throw "$Label not found: $Path"
    }
}

function Get-YamlScalarValue {
    param(
        [Parameter(Mandatory=$true)] [string]$Path,
        [Parameter(Mandatory=$true)] [string]$Key
    )

    if (-not (Test-Path $Path)) {
        return $null
    }

    $pattern = "(?m)^\s*$([regex]::Escape($Key))\s*:\s*(?<value>.+?)\s*$"
    $text = Get-Content -Path $Path -Raw -Encoding UTF8
    $match = [regex]::Match($text, $pattern)
    if (-not $match.Success) {
        return $null
    }

    $value = $match.Groups['value'].Value.Trim()
    $value = $value.Trim("'", '"')
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $null
    }

    return $value
}

function Resolve-CoverTemplatePath {
    param(
        [Parameter(Mandatory=$true)] [string]$TemplateRoot,
        [Parameter(Mandatory=$true)] [string]$TemplateName
    )

    $templateFileName = if ($TemplateName -match '\.md$') { $TemplateName } else { "$TemplateName.md" }
    $templatePath = Join-Path $TemplateRoot $templateFileName
    Ensure-Path -Path $templatePath -Label 'cover template file'
    return $templatePath
}

function New-CoverFromTemplate {
    param(
        [Parameter(Mandatory=$true)] [string]$TemplatePath,
        [Parameter(Mandatory=$true)] [string]$DestinationPath,
        [Parameter(Mandatory=$true)] [string]$ProjectName,
        [Parameter(Mandatory=$true)] [string]$MetadataFile
    )

    $title = Get-YamlScalarValue -Path $MetadataFile -Key 'title'
    $creator = Get-YamlScalarValue -Path $MetadataFile -Key 'creator'
    $subtitle = Get-YamlScalarValue -Path $MetadataFile -Key 'subtitle'
    $publishDate = Get-YamlScalarValue -Path $MetadataFile -Key 'date'

    if ([string]::IsNullOrWhiteSpace($title)) { $title = $ProjectName }
    if ([string]::IsNullOrWhiteSpace($creator)) { $creator = 'Unknown Author' }
    if ([string]::IsNullOrWhiteSpace($subtitle)) { $subtitle = '' }
    if ([string]::IsNullOrWhiteSpace($publishDate)) { $publishDate = (Get-Date -Format 'yyyy-MM-dd') }

    $templateText = Get-Content -Path $TemplatePath -Raw -Encoding UTF8
    $resolved = $templateText
    $resolved = $resolved.Replace('{{title}}', $title)
    $resolved = $resolved.Replace('{{creator}}', $creator)
    $resolved = $resolved.Replace('{{subtitle}}', $subtitle)
    $resolved = $resolved.Replace('{{date}}', $publishDate)
    $resolved = $resolved.Replace('{{projectName}}', $ProjectName)

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($DestinationPath, $resolved, $utf8NoBom)
}

function Get-TextHash {
    param([Parameter(Mandatory=$true)] [string]$Text)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hashBytes = $sha.ComputeHash($bytes)
    } finally {
        $sha.Dispose()
    }

    return ([System.BitConverter]::ToString($hashBytes)).Replace('-', '').ToLowerInvariant().Substring(0, 16)
}

function Get-MermaidCommandSpec {
    $mmdc = Get-Command mmdc -ErrorAction SilentlyContinue
    if ($mmdc) {
        return @{
            Command = $mmdc.Source
            Arguments = @()
            Label = 'mmdc'
        }
    }

    $npx = Get-Command npx -ErrorAction SilentlyContinue
    if ($npx) {
        return @{
            Command = $npx.Source
            Arguments = @('--yes', '@mermaid-js/mermaid-cli')
            Label = 'npx @mermaid-js/mermaid-cli'
        }
    }

    return $null
}

function Invoke-MermaidRender {
    param(
        [Parameter(Mandatory=$true)] [hashtable]$CommandSpec,
        [Parameter(Mandatory=$true)] [string]$DiagramText,
        [Parameter(Mandatory=$true)] [string]$OutputPath,
        [Parameter(Mandatory=$true)] [ValidateSet('svg', 'png')] [string]$Format
    )

    if (Test-Path $OutputPath) {
        return $true
    }

    $inputPath = [System.IO.Path]::ChangeExtension($OutputPath, '.mmd')
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($inputPath, $DiagramText, $utf8NoBom)

    try {
        $renderArgs = @()
        if ($CommandSpec.ContainsKey('Arguments') -and $null -ne $CommandSpec['Arguments']) {
            $renderArgs += @($CommandSpec['Arguments'])
        }

        $renderArgs += @(
            '-i', $inputPath,
            '-o', $OutputPath,
            '-e', $Format,
            '-b', 'transparent'
        )

        & $CommandSpec['Command'] @renderArgs
        return ($LASTEXITCODE -eq 0 -and (Test-Path $OutputPath))
    } finally {
        Remove-Item -Path $inputPath -Force -ErrorAction SilentlyContinue
    }
}

function Convert-MermaidBlocksInMarkdown {
    param(
        [Parameter(Mandatory=$true)] [string]$Path,
        [Parameter(Mandatory=$true)] [string]$StageBookRoot,
        [Parameter(Mandatory=$true)] [hashtable]$CommandSpec,
        [Parameter(Mandatory=$true)] [ValidateSet('auto', 'required')] [string]$Mode,
        [Parameter(Mandatory=$true)] [ValidateSet('svg', 'png')] [string]$Format,
        [bool]$FailOnError = $false
    )

    $sourceLines = Get-Content -Path $Path -Encoding UTF8
    $resultLines = New-Object 'System.Collections.Generic.List[string]'
    $originalMermaidLines = New-Object 'System.Collections.Generic.List[string]'
    $mermaidBuffer = New-Object 'System.Collections.Generic.List[string]'

    $imagesRoot = Join-Path $StageBookRoot 'images\mermaid'
    New-Item -ItemType Directory -Path $imagesRoot -Force | Out-Null

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
                $hash = Get-TextHash -Text "$Format`n$diagramText"
                $imageFileName = "mermaid-$hash.$Format"
                $imagePath = Join-Path $imagesRoot $imageFileName
                $imageMarkdownPath = "images/mermaid/$imageFileName"

                $rendered = $false
                if (-not [string]::IsNullOrWhiteSpace($diagramText)) {
                    $rendered = Invoke-MermaidRender -CommandSpec $CommandSpec -DiagramText $diagramText -OutputPath $imagePath -Format $Format
                }

                if ($rendered) {
                    $resultLines.Add("$mermaidIndent![Mermaid diagram]($imageMarkdownPath)")
                    $renderedCount += 1
                    $fileChanged = $true
                } else {
                    $message = "Mermaid render failed for $Path"
                    if ($Mode -eq 'required' -or $FailOnError) {
                        throw $message
                    }

                    Write-Warning "$message. Leaving the source block unchanged."
                    foreach ($originalLine in $originalMermaidLines.ToArray()) {
                        $resultLines.Add($originalLine)
                    }
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
            $candidateMarker = $Matches['marker']
            $candidateChar = $candidateMarker.Substring(0, 1)
            $candidateLength = $candidateMarker.Length

            if (-not $insideFence) {
                $insideFence = $true
                $fenceChar = $candidateChar
                $fenceLength = $candidateLength
            } elseif ($candidateChar -eq $fenceChar -and $candidateLength -ge $fenceLength) {
                $insideFence = $false
                $fenceChar = $null
                $fenceLength = 0
            }
        }

        $resultLines.Add($line)
    }

    if ($insideMermaid) {
        foreach ($originalLine in $originalMermaidLines.ToArray()) {
            $resultLines.Add($originalLine)
        }
    }

    if ($fileChanged) {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($Path, ($resultLines.ToArray() -join [Environment]::NewLine), $utf8NoBom)
    }

    return [PSCustomObject]@{
        Path = $Path
        Blocks = $blockCount
        Rendered = $renderedCount
        Changed = $fileChanged
    }
}

function Invoke-MermaidPreprocessing {
    param(
        [Parameter(Mandatory=$true)] [string]$StageBookRoot,
        [ValidateSet('off', 'auto', 'required')] [string]$Mode = 'required',
        [ValidateSet('svg', 'png')] [string]$Format = 'svg',
        [bool]$FailOnError = $true
    )

    if ($Mode -eq 'off') {
        return
    }

    $markdownFiles = @(Get-ChildItem -Path $StageBookRoot -Recurse -File -Filter '*.md' -ErrorAction SilentlyContinue)
    if ($markdownFiles.Count -eq 0) {
        return
    }

    $hasMermaid = $false
    foreach ($markdownFile in $markdownFiles) {
        if (Select-String -Path $markdownFile.FullName -Pattern '^\s*(`{3,}|~{3,})\s*mermaid(?:\s+.*)?\s*$' -Quiet) {
            $hasMermaid = $true
            break
        }
    }

    if (-not $hasMermaid) {
        return
    }

    $commandSpec = Get-MermaidCommandSpec
    if ($null -eq $commandSpec) {
        $message = 'Mermaid CLI not found. Install mmdc or ensure npx is available to render Mermaid diagrams during ebook builds.'
        if ($Mode -eq 'required' -or $FailOnError) {
            throw $message
        }

        Write-Warning "$message Mermaid blocks will remain as source text."
        return
    }

    Write-Host "Preprocessing Mermaid diagrams using $($commandSpec['Label'])..." -ForegroundColor Cyan

    $totalBlocks = 0
    $totalRendered = 0
    foreach ($markdownFile in $markdownFiles) {
        $stats = Convert-MermaidBlocksInMarkdown -Path $markdownFile.FullName -StageBookRoot $StageBookRoot -CommandSpec $commandSpec -Mode $Mode -Format $Format -FailOnError $FailOnError
        $totalBlocks += $stats.Blocks
        $totalRendered += $stats.Rendered
    }

    if ($totalBlocks -eq 0) {
        return
    }

    if ($totalRendered -gt 0) {
        Write-Host "Rendered $totalRendered Mermaid diagram(s) for EPUB output." -ForegroundColor Green
    } elseif ($Mode -eq 'auto') {
        Write-Warning 'Mermaid blocks were detected but could not be rendered. Leaving the source blocks unchanged.'
    }
}

$config = Get-ConfigMap -Path $ConfigFile

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).ProviderPath
$defaultKindleTemplateDir = $PSScriptRoot

$SourceRoot = Resolve-Value -Name 'SourceRoot' -CurrentValue $SourceRoot -DefaultValue $repoRoot -Config $config -Bound $scriptBound
$KindleTemplateDir = Resolve-Value -Name 'KindleTemplateDir' -CurrentValue $KindleTemplateDir -DefaultValue $defaultKindleTemplateDir -Config $config -Bound $scriptBound
$ChapterDirPattern = Resolve-Value -Name 'ChapterDirPattern' -CurrentValue $ChapterDirPattern -DefaultValue '^\d{2}-' -Config $config -Bound $scriptBound
$ChapterFilePattern = Resolve-Value -Name 'ChapterFilePattern' -CurrentValue $ChapterFilePattern -DefaultValue '^\d{2}-.*\.md$' -Config $config -Bound $scriptBound
$CoverFile = Resolve-Value -Name 'CoverFile' -CurrentValue $CoverFile -DefaultValue '00-COVER.md' -Config $config -Bound $scriptBound
$CoverTemplateMode = [string](Resolve-Value -Name 'CoverTemplateMode' -CurrentValue $CoverTemplateMode -DefaultValue 'auto' -Config $config -Bound $scriptBound)
$CoverTemplate = [string](Resolve-Value -Name 'CoverTemplate' -CurrentValue $CoverTemplate -DefaultValue 'classic' -Config $config -Bound $scriptBound)
$MermaidMode = [string](Resolve-Value -Name 'MermaidMode' -CurrentValue $MermaidMode -DefaultValue 'required' -Config $config -Bound $scriptBound)
$MermaidFormat = [string](Resolve-Value -Name 'MermaidFormat' -CurrentValue $MermaidFormat -DefaultValue 'svg' -Config $config -Bound $scriptBound)
$FailOnMermaidError = [System.Convert]::ToBoolean((Resolve-Value -Name 'FailOnMermaidError' -CurrentValue $FailOnMermaidError -DefaultValue $true -Config $config -Bound $scriptBound))
$BuildPhase = [string](Resolve-Value -Name 'BuildPhase' -CurrentValue $BuildPhase -DefaultValue 'full' -Config $config -Bound $scriptBound)
$RequireManuscriptApproval = [System.Convert]::ToBoolean((Resolve-Value -Name 'RequireManuscriptApproval' -CurrentValue $RequireManuscriptApproval -DefaultValue $false -Config $config -Bound $scriptBound))
$ApprovalTokenFile = [string](Resolve-Value -Name 'ApprovalTokenFile' -CurrentValue $ApprovalTokenFile -DefaultValue '' -Config $config -Bound $scriptBound)

if ([string]::IsNullOrWhiteSpace($MermaidMode)) {
    $MermaidMode = 'required'
}
if ([string]::IsNullOrWhiteSpace($MermaidFormat)) {
    $MermaidFormat = 'svg'
}

$MermaidMode = $MermaidMode.ToLowerInvariant()
$MermaidFormat = $MermaidFormat.ToLowerInvariant()
$CoverTemplateMode = $CoverTemplateMode.ToLowerInvariant()
$BuildPhase = $BuildPhase.ToLowerInvariant()
if (@('off', 'auto', 'required') -notcontains $MermaidMode) {
    throw "Unsupported MermaidMode requested: $MermaidMode"
}
if (@('svg', 'png') -notcontains $MermaidFormat) {
    throw "Unsupported MermaidFormat requested: $MermaidFormat"
}
if (@('auto', 'file', 'template') -notcontains $CoverTemplateMode) {
    throw "Unsupported CoverTemplateMode requested: $CoverTemplateMode"
}
if (@('full', 'manuscript-only', 'continue') -notcontains $BuildPhase) {
    throw "Unsupported BuildPhase requested: $BuildPhase"
}

if (-not $Formats -or $Formats.Count -eq 0) {
    if ($scriptBound.ContainsKey('Formats')) {
        $Formats = @($Formats)
    } elseif ($config.ContainsKey('formats') -and $null -ne $config['formats']) {
        $Formats = @($config['formats'])
    } else {
        $Formats = @('epub')
    }
}
$Formats = @($Formats | ForEach-Object { $_.ToString().ToLowerInvariant() } | Select-Object -Unique)
$supportedFormats = @('epub', 'pdf', 'kdp-markdown')
$unsupportedFormats = @($Formats | Where-Object { $supportedFormats -notcontains $_ })
if ($unsupportedFormats.Count -gt 0) {
    throw "Unsupported format requested. supported=$($supportedFormats -join ',') formats=$($Formats -join ',')"
}
$SourceRoot = Resolve-ConfiguredPath -PathValue $SourceRoot -RepoRoot $repoRoot
$KindleTemplateDir = Resolve-ConfiguredPath -PathValue $KindleTemplateDir -RepoRoot $repoRoot

$resolvedSourceRoot = (Resolve-Path $SourceRoot).ProviderPath
if (-not $ProjectName) {
    if ($config.ContainsKey('projectName') -and -not [string]::IsNullOrWhiteSpace([string]$config['projectName'])) {
        $ProjectName = [string]$config['projectName']
    } else {
        $ProjectName = Split-Path -Leaf $resolvedSourceRoot
    }
}

$defaultMetadataFile = Resolve-DefaultMetadataFile -RepoRoot $repoRoot -ProjectName $ProjectName
$defaultKdpMetadataFile = Resolve-DefaultKdpMetadataFile -RepoRoot $repoRoot -ProjectName $ProjectName
$defaultStyleFile = Join-Path (Split-Path $KindleTemplateDir -Parent) 'assets\style.css'
$MetadataFile = Resolve-Value -Name 'MetadataFile' -CurrentValue $MetadataFile -DefaultValue $defaultMetadataFile -Config $config -Bound $scriptBound
$KdpMetadataFile = Resolve-Value -Name 'KdpMetadataFile' -CurrentValue $KdpMetadataFile -DefaultValue $defaultKdpMetadataFile -Config $config -Bound $scriptBound
$StyleFile = Resolve-Value -Name 'StyleFile' -CurrentValue $StyleFile -DefaultValue $defaultStyleFile -Config $config -Bound $scriptBound
$MetadataFile = Resolve-ConfiguredPath -PathValue $MetadataFile -RepoRoot $repoRoot
$KdpMetadataFile = Resolve-ConfiguredPath -PathValue $KdpMetadataFile -RepoRoot $repoRoot
$StyleFile = Resolve-ConfiguredPath -PathValue $StyleFile -RepoRoot $repoRoot

if (-not $OutputDir) {
    if ($config.ContainsKey('outputDir') -and -not [string]::IsNullOrWhiteSpace([string]$config['outputDir'])) {
        $OutputDir = [string]$config['outputDir']
    } else {
        $OutputDir = Join-Path $resolvedSourceRoot 'ebook-output'
    }
}
$OutputDir = Resolve-ConfiguredPath -PathValue $OutputDir -RepoRoot $repoRoot
if ([string]::IsNullOrWhiteSpace($ApprovalTokenFile)) {
    $ApprovalTokenFile = Join-Path $OutputDir ("$ProjectName.manuscript.approved")
} else {
    $ApprovalTokenFile = Resolve-ConfiguredPath -PathValue $ApprovalTokenFile -RepoRoot $repoRoot
}

if ($BuildPhase -eq 'continue' -and $RequireManuscriptApproval -and -not (Test-Path $ApprovalTokenFile)) {
    throw "Manuscript approval token not found: $ApprovalTokenFile"
}

$printStyleFile = Join-Path (Split-Path $KindleTemplateDir -Parent) 'assets\print.css'
$kdpPackageScript = Join-Path $KindleTemplateDir 'generate-kdp-package.ps1'
$pdfRenderScript = Join-Path $KindleTemplateDir 'render-html-to-pdf.cjs'
$coverTemplateRoot = Join-Path (Split-Path $KindleTemplateDir -Parent) 'assets\cover-templates'

Ensure-Path -Path $KindleTemplateDir -Label 'Kindle template directory'
Ensure-Path -Path (Join-Path $KindleTemplateDir 'convert-to-kindle.ps1') -Label 'convert-to-kindle.ps1'
Ensure-Path -Path $MetadataFile -Label 'metadata file'
Ensure-Path -Path $StyleFile -Label 'style file'
Ensure-Path -Path $printStyleFile -Label 'print style file'
Ensure-Path -Path $kdpPackageScript -Label 'generate-kdp-package.ps1'
Ensure-Path -Path $pdfRenderScript -Label 'render-html-to-pdf.cjs'
if (-not [string]::IsNullOrWhiteSpace($KdpMetadataFile)) {
    Ensure-Path -Path $KdpMetadataFile -Label 'KDP metadata file'
}

$contentRoot = Resolve-ContentRoot -Root $resolvedSourceRoot -DirPattern $ChapterDirPattern
$chapterDirs = @(Get-ChildItem -Path $contentRoot -Directory | Where-Object { $_.Name -match $ChapterDirPattern } | Sort-Object Name)
$chapterFiles = @(
    foreach ($directory in $chapterDirs) {
        Get-ChildItem -Path $directory.FullName -File -Filter '*.md' | Where-Object { $_.Name -match $ChapterFilePattern }
    }
)
if ($chapterFiles.Count -eq 0) {
    throw "No markdown section files found. pattern=$ChapterFilePattern contentRoot=$contentRoot"
}

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ebook-build-" + [Guid]::NewGuid().ToString('N'))
$stageBookRoot = Join-Path $tempRoot 'book'
$stageKindle = Join-Path $stageBookRoot 'kindle'
$stageOutput = Join-Path $stageKindle 'output'

New-Item -ItemType Directory -Path $stageBookRoot -Force | Out-Null
New-Item -ItemType Directory -Path $stageKindle -Force | Out-Null

Write-Host "Staging source from: $contentRoot" -ForegroundColor Cyan
foreach ($directory in $chapterDirs) {
    Copy-Item -Path $directory.FullName -Destination (Join-Path $stageBookRoot $directory.Name) -Recurse -Force
}

$imagesPath = Join-Path $contentRoot 'images'
if (Test-Path $imagesPath) {
    Copy-Item -Path $imagesPath -Destination (Join-Path $stageBookRoot 'images') -Recurse -Force
}

$coverPath = Join-Path $contentRoot $CoverFile
$stageCoverPath = Join-Path $stageBookRoot $CoverFile
if ($CoverTemplateMode -eq 'file') {
    Ensure-Path -Path $coverPath -Label 'cover markdown file'
    Copy-Item -Path $coverPath -Destination $stageCoverPath -Force
} elseif ($CoverTemplateMode -eq 'template') {
    $templatePath = Resolve-CoverTemplatePath -TemplateRoot $coverTemplateRoot -TemplateName $CoverTemplate
    New-CoverFromTemplate -TemplatePath $templatePath -DestinationPath $stageCoverPath -ProjectName $ProjectName -MetadataFile $MetadataFile
} else {
    if (Test-Path $coverPath) {
        Copy-Item -Path $coverPath -Destination $stageCoverPath -Force
    } else {
        $templatePath = Resolve-CoverTemplatePath -TemplateRoot $coverTemplateRoot -TemplateName $CoverTemplate
        New-CoverFromTemplate -TemplatePath $templatePath -DestinationPath $stageCoverPath -ProjectName $ProjectName -MetadataFile $MetadataFile
    }
}

$readmePath = Join-Path $contentRoot 'README.md'
if (Test-Path $readmePath) {
    Copy-Item -Path $readmePath -Destination (Join-Path $stageBookRoot 'README.md') -Force
}

Invoke-MermaidPreprocessing -StageBookRoot $stageBookRoot -Mode $MermaidMode -Format $MermaidFormat -FailOnError $FailOnMermaidError

# PDF は staged `kindle/*.html` をブラウザで直接描画するため、
# 相対参照される画像群も `kindle/images/...` 側に揃えておく。
$stageImagesPath = Join-Path $stageBookRoot 'images'
if (Test-Path $stageImagesPath) {
    Copy-Item -Path $stageImagesPath -Destination (Join-Path $stageKindle 'images') -Recurse -Force
}

Copy-Item -Path (Join-Path $KindleTemplateDir 'convert-to-kindle.ps1') -Destination (Join-Path $stageKindle 'convert-to-kindle.ps1') -Force
Copy-Item -Path $MetadataFile -Destination (Join-Path $stageKindle 'metadata.yaml') -Force
Copy-Item -Path $StyleFile -Destination (Join-Path $stageKindle 'style.css') -Force
Copy-Item -Path $printStyleFile -Destination (Join-Path $stageKindle 'print.css') -Force
Copy-Item -Path $pdfRenderScript -Destination (Join-Path $stageKindle 'render-html-to-pdf.cjs') -Force

$stageConvertScript = Join-Path $stageKindle 'convert-to-kindle.ps1'
$convertRaw = Get-Content -Path $stageConvertScript -Raw -Encoding UTF8

$convertRaw = $convertRaw -replace '\$response = Read-Host', "`$response = 'n'"
$convertRaw = $convertRaw -replace 'Invoke-Item \$outputDir', '# output auto-open disabled by ebook-build skill runner'

function Copy-ArtifactSafely {
    param(
        [Parameter(Mandatory=$true)] [string]$SourcePath,
        [Parameter(Mandatory=$true)] [string]$DestinationPath,
        [Parameter(Mandatory=$true)] [string]$ArtifactLabel
    )

    try {
        Copy-Item -Path $SourcePath -Destination $DestinationPath -Force
        return $DestinationPath
    }
    catch [System.IO.IOException] {
        $destinationDirectory = Split-Path -Parent $DestinationPath
        $destinationBaseName = [System.IO.Path]::GetFileNameWithoutExtension($DestinationPath)
        $destinationExtension = [System.IO.Path]::GetExtension($DestinationPath)
        $alternatePath = Join-Path $destinationDirectory ("{0}-{1}{2}" -f $destinationBaseName, (Get-Date -Format 'yyyyMMdd-HHmmss'), $destinationExtension)

        Copy-Item -Path $SourcePath -Destination $alternatePath -Force
        Write-Warning ("{0} could not overwrite '{1}' because it is in use. Saved the new artifact to '{2}' instead." -f $ArtifactLabel, $DestinationPath, $alternatePath)
        return $alternatePath
    }
}

# pwsh on GitHub Actions can misread UTF-8 without BOM after rewriting
# the staged script. Write a UTF-8 BOM so Unicode strings parse reliably in CI.
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($stageConvertScript, $convertRaw, $utf8Bom)

$documentFormats = @($Formats | Where-Object { $_ -in @('epub', 'pdf') })
$converterFormats = @(if ($BuildPhase -eq 'manuscript-only') { @('epub') } else { $documentFormats })
if ($converterFormats.Count -gt 0) {
    Write-Host 'Running staged converter...' -ForegroundColor Cyan
    Push-Location $stageKindle
    try {
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $stageConvertScript `
            -Formats ($converterFormats -join ',') `
            -KdpMetadataFile $KdpMetadataFile `
            -ChapterDirPattern $ChapterDirPattern `
            -ChapterFilePattern $ChapterFilePattern `
            -CoverFile $CoverFile
        if ($LASTEXITCODE -ne 0) {
            throw "Converter failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
}

Write-Host 'Collecting artifacts...' -ForegroundColor Cyan
$copiedArtifacts = New-Object 'System.Collections.Generic.List[string]'

if ($BuildPhase -eq 'manuscript-only') {
    $producedManuscriptOnly = Get-ChildItem -Path $stageOutput -Filter '*.manuscript.md' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $producedManuscriptOnly) {
        throw 'Merged manuscript artifact was not produced by the converter.'
    }

    $manuscriptOnlyDestinationPath = Join-Path $OutputDir ("$ProjectName.manuscript.md")
    $manuscriptOnlyDestinationPath = Copy-ArtifactSafely -SourcePath $producedManuscriptOnly.FullName -DestinationPath $manuscriptOnlyDestinationPath -ArtifactLabel 'Merged manuscript artifact'
    $copiedArtifacts.Add($manuscriptOnlyDestinationPath)
    Write-Host "Generated: $manuscriptOnlyDestinationPath" -ForegroundColor Green
    Write-Host "Build phase manuscript-only completed. Review and approve manuscript, then run with BuildPhase=continue." -ForegroundColor Yellow

    if ($PreserveTemp) {
        Write-Host "Temporary workspace preserved: $tempRoot" -ForegroundColor Yellow
    } else {
        Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host 'ebook-build skill execution completed.' -ForegroundColor Green
    exit 0
}

if ($documentFormats -contains 'epub') {
    $producedEpub = Get-ChildItem -Path $stageOutput -Filter '*.epub' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $producedEpub) {
        throw 'EPUB artifact was not produced by the converter.'
    }

    $epubDestinationPath = Join-Path $OutputDir ("$ProjectName.epub")
    $epubDestinationPath = Copy-ArtifactSafely -SourcePath $producedEpub.FullName -DestinationPath $epubDestinationPath -ArtifactLabel 'EPUB artifact'
    $copiedArtifacts.Add($epubDestinationPath)
    Write-Host "Generated: $epubDestinationPath" -ForegroundColor Green
}

if ($documentFormats -contains 'pdf') {
    $producedPdf = Get-ChildItem -Path $stageOutput -Filter '*.pdf' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'cover.pdf' } |
        Select-Object -First 1
    if ($null -eq $producedPdf) {
        throw 'PDF artifact was not produced by the converter.'
    }

    $pdfDestinationPath = Join-Path $OutputDir ("$ProjectName.pdf")
    $pdfDestinationPath = Copy-ArtifactSafely -SourcePath $producedPdf.FullName -DestinationPath $pdfDestinationPath -ArtifactLabel 'PDF artifact'
    $copiedArtifacts.Add($pdfDestinationPath)
    Write-Host "Generated: $pdfDestinationPath" -ForegroundColor Green

    $coverPdfSourcePath = Join-Path $stageOutput 'cover.pdf'
    if (-not (Test-Path $coverPdfSourcePath)) {
        throw 'cover.pdf artifact was not produced by the converter.'
    }

    $coverPdfDestinationPath = Join-Path $OutputDir 'cover.pdf'
    $coverPdfDestinationPath = Copy-ArtifactSafely -SourcePath $coverPdfSourcePath -DestinationPath $coverPdfDestinationPath -ArtifactLabel 'Cover PDF artifact'
    $copiedArtifacts.Add($coverPdfDestinationPath)
    Write-Host "Generated: $coverPdfDestinationPath" -ForegroundColor Green

    $coverJpgSourcePath = Join-Path $stageOutput 'cover.jpg'
    if (-not (Test-Path $coverJpgSourcePath)) {
        throw 'cover.jpg artifact was not produced by the converter.'
    }

    $coverJpgDestinationPath = Join-Path $OutputDir 'cover.jpg'
    $coverJpgDestinationPath = Copy-ArtifactSafely -SourcePath $coverJpgSourcePath -DestinationPath $coverJpgDestinationPath -ArtifactLabel 'Cover JPEG artifact'
    $copiedArtifacts.Add($coverJpgDestinationPath)
    Write-Host "Generated: $coverJpgDestinationPath" -ForegroundColor Green
}

if ($documentFormats.Count -gt 0) {
    $producedManuscript = Get-ChildItem -Path $stageOutput -Filter '*.manuscript.md' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $producedManuscript) {
        throw 'Merged manuscript artifact was not produced by the converter.'
    }

    $manuscriptDestinationPath = Join-Path $OutputDir ("$ProjectName.manuscript.md")
    $manuscriptDestinationPath = Copy-ArtifactSafely -SourcePath $producedManuscript.FullName -DestinationPath $manuscriptDestinationPath -ArtifactLabel 'Merged manuscript artifact'
    $copiedArtifacts.Add($manuscriptDestinationPath)
    Write-Host "Generated: $manuscriptDestinationPath" -ForegroundColor Green
}

if ($Formats -contains 'kdp-markdown') {
    $kdpOutputPath = Join-Path $OutputDir ("$ProjectName-kdp-registration.md")
    $epubDestinationPath = if ($documentFormats -contains 'epub') { Join-Path $OutputDir ("$ProjectName.epub") } else { $null }
    $pdfDestinationPath = if ($documentFormats -contains 'pdf') { Join-Path $OutputDir ("$ProjectName.pdf") } else { $null }

    & $kdpPackageScript -ProjectName $ProjectName -MetadataFile $MetadataFile -OutputPath $kdpOutputPath -KdpMetadataFile $KdpMetadataFile -EpubPath $epubDestinationPath -PdfPath $pdfDestinationPath
    Ensure-Path -Path $kdpOutputPath -Label 'KDP registration markdown'
    $copiedArtifacts.Add($kdpOutputPath)
}

if ($copiedArtifacts.Count -eq 0) {
    Write-Warning 'No output artifacts were requested by the current format selection.'
}

if ($PreserveTemp) {
    Write-Host "Temporary workspace preserved: $tempRoot" -ForegroundColor Yellow
} else {
    Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'ebook-build skill execution completed.' -ForegroundColor Green
