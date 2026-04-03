param(
    [string]$ConfigFile,
    [string]$SourceRoot,
    [string]$OutputDir,
    [string]$ProjectName,
    [string]$KindleTemplateDir,
    [string]$MetadataFile,
    [string]$StyleFile,
    [string[]]$Formats,
    [string]$ChapterDirPattern = '^\d{2}-',
    [string]$ChapterFilePattern = '^\d{2}-.*\.md$',
    [string]$CoverFile = '00-COVER.md',
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

$config = Get-ConfigMap -Path $ConfigFile

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).ProviderPath
$defaultKindleTemplateDir = $PSScriptRoot

$SourceRoot = Resolve-Value -Name 'SourceRoot' -CurrentValue $SourceRoot -DefaultValue $repoRoot -Config $config -Bound $scriptBound
$KindleTemplateDir = Resolve-Value -Name 'KindleTemplateDir' -CurrentValue $KindleTemplateDir -DefaultValue $defaultKindleTemplateDir -Config $config -Bound $scriptBound
$ChapterDirPattern = Resolve-Value -Name 'ChapterDirPattern' -CurrentValue $ChapterDirPattern -DefaultValue '^\d{2}-' -Config $config -Bound $scriptBound
$ChapterFilePattern = Resolve-Value -Name 'ChapterFilePattern' -CurrentValue $ChapterFilePattern -DefaultValue '^\d{2}-.*\.md$' -Config $config -Bound $scriptBound
$CoverFile = Resolve-Value -Name 'CoverFile' -CurrentValue $CoverFile -DefaultValue '00-COVER.md' -Config $config -Bound $scriptBound

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
$unsupportedFormats = @($Formats | Where-Object { $_ -ne 'epub' })
if ($unsupportedFormats.Count -gt 0) {
    throw "Unsupported format requested. This workflow only supports epub. formats=$($Formats -join ',')"
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
$defaultStyleFile = Join-Path $repoRoot '.github\skills\ebook-build\assets\style.css'
$MetadataFile = Resolve-Value -Name 'MetadataFile' -CurrentValue $MetadataFile -DefaultValue $defaultMetadataFile -Config $config -Bound $scriptBound
$StyleFile = Resolve-Value -Name 'StyleFile' -CurrentValue $StyleFile -DefaultValue $defaultStyleFile -Config $config -Bound $scriptBound
$MetadataFile = Resolve-ConfiguredPath -PathValue $MetadataFile -RepoRoot $repoRoot
$StyleFile = Resolve-ConfiguredPath -PathValue $StyleFile -RepoRoot $repoRoot

if (-not $OutputDir) {
    if ($config.ContainsKey('outputDir') -and -not [string]::IsNullOrWhiteSpace([string]$config['outputDir'])) {
        $OutputDir = [string]$config['outputDir']
    } else {
        $OutputDir = Join-Path $resolvedSourceRoot 'ebook-output'
    }
}
$OutputDir = Resolve-ConfiguredPath -PathValue $OutputDir -RepoRoot $repoRoot

Ensure-Path -Path $KindleTemplateDir -Label 'Kindle template directory'
Ensure-Path -Path (Join-Path $KindleTemplateDir 'convert-to-kindle.ps1') -Label 'convert-to-kindle.ps1'
Ensure-Path -Path $MetadataFile -Label 'metadata file'
Ensure-Path -Path $StyleFile -Label 'style file'

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
if (Test-Path $coverPath) {
    Copy-Item -Path $coverPath -Destination (Join-Path $stageBookRoot $CoverFile) -Force
}

$readmePath = Join-Path $contentRoot 'README.md'
if (Test-Path $readmePath) {
    Copy-Item -Path $readmePath -Destination (Join-Path $stageBookRoot 'README.md') -Force
}

Copy-Item -Path (Join-Path $KindleTemplateDir 'convert-to-kindle.ps1') -Destination (Join-Path $stageKindle 'convert-to-kindle.ps1') -Force
Copy-Item -Path $MetadataFile -Destination (Join-Path $stageKindle 'metadata.yaml') -Force
Copy-Item -Path $StyleFile -Destination (Join-Path $stageKindle 'style.css') -Force

$stageConvertScript = Join-Path $stageKindle 'convert-to-kindle.ps1'
$convertRaw = Get-Content -Path $stageConvertScript -Raw -Encoding UTF8

$convertRaw = $convertRaw -replace '\$response = Read-Host', "`$response = 'n'"
$convertRaw = $convertRaw -replace 'Invoke-Item \$outputDir', '# output auto-open disabled by ebook-build skill runner'

# Windows PowerShell on GitHub Actions can misread UTF-8 without BOM after rewriting
# the staged script. Write a UTF-8 BOM so Unicode strings parse reliably in CI.
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($stageConvertScript, $convertRaw, $utf8Bom)

Write-Host 'Running staged converter...' -ForegroundColor Cyan
Push-Location $stageKindle
try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $stageConvertScript
    if ($LASTEXITCODE -ne 0) {
        throw "Converter failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

Write-Host 'Collecting artifacts...' -ForegroundColor Cyan
$producedEpub = Get-ChildItem -Path $stageOutput -Filter '*.epub' -File -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $producedEpub) {
    throw 'EPUB artifact was not produced by the converter.'
}

$destinationPath = Join-Path $OutputDir ("$ProjectName.epub")
Copy-Item -Path $producedEpub.FullName -Destination $destinationPath -Force
Write-Host "Generated: $destinationPath" -ForegroundColor Green

if ($PreserveTemp) {
    Write-Host "Temporary workspace preserved: $tempRoot" -ForegroundColor Yellow
} else {
    Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'ebook-build skill execution completed.' -ForegroundColor Green
