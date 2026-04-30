<#
.SYNOPSIS
  Step 2 - Generate cover artwork (PDF + JPEG).
#>
param(
    [string]$SourceRoot,
    [string]$OutputDir,
    [string]$ProjectName,
    [string]$MetadataFile,
    [string]$KindleTemplateDir,
    [string]$StyleFile,
    [string]$CoverFile         = '00-COVER.md',
    [ValidateSet('auto', 'file', 'template')]
    [string]$CoverTemplateMode = 'auto',
    [string]$CoverTemplate     = 'classic',
    [switch]$PreserveTemp
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

function Resolve-CoverTemplatePath {
    param([string]$TemplateRoot, [string]$TemplateName)
    $fileName = if ($TemplateName -match '\.md$') { $TemplateName } else { "$TemplateName.md" }
    $path = Join-Path $TemplateRoot $fileName
    Ensure-Path -Path $path -Label 'cover template file'
    return $path
}

function New-CoverFromTemplate {
    param([string]$TemplatePath, [string]$DestinationPath, [string]$ProjectName, [string]$MetadataFile)

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

function Resolve-ContentRoot {
    param([string]$Root)

    $resolved = (Resolve-Path $Root).ProviderPath
    $coverAtRoot = Join-Path $resolved $CoverFile
    if (Test-Path $coverAtRoot) { return $resolved }

    $docsPath = Join-Path $resolved 'docs'
    $coverAtDocs = Join-Path $docsPath $CoverFile
    if (Test-Path $coverAtDocs) { return $docsPath }

    return $resolved
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
    if ($LASTEXITCODE -eq 0) {
        for ($i = 0; $i -lt 20; $i++) {
            if (Test-Path $ExpectedOutput) { return }
            Start-Sleep -Milliseconds 200
        }
    }

    $fallbackArgs = @('--headless') + @($Arguments | Where-Object { $_ -ne '--headless=new' -and $_ -ne '--headless' })
    & $Browser @fallbackArgs
    if ($LASTEXITCODE -eq 0) {
        for ($i = 0; $i -lt 20; $i++) {
            if (Test-Path $ExpectedOutput) { return }
            Start-Sleep -Milliseconds 200
        }
    }

    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $ExpectedOutput)) {
        throw "Headless render failed: $ExpectedOutput"
    }
}

Ensure-Path -Path $SourceRoot -Label 'SourceRoot'
Ensure-Path -Path $MetadataFile -Label 'MetadataFile'
Ensure-Path -Path $StyleFile -Label 'StyleFile'

if (-not (Get-Command pandoc -ErrorAction SilentlyContinue)) {
    throw 'pandoc is required but was not found in PATH.'
}

if ([string]::IsNullOrWhiteSpace($ProjectName)) {
    $ProjectName = Split-Path -Leaf (Resolve-Path $SourceRoot).ProviderPath
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path (Resolve-Path $SourceRoot).ProviderPath 'ebook-output'
}
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$skillRoot = Split-Path -Parent $PSScriptRoot
$printStyleFile = Join-Path $skillRoot 'assets\print.css'
$coverTemplateRoot = Join-Path $skillRoot 'assets\cover-templates'
Ensure-Path -Path $printStyleFile -Label 'print.css'

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ebook-step2-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
    $contentRoot = Resolve-ContentRoot -Root $SourceRoot
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

    $coverHtml = Join-Path $tempRoot "$ProjectName.cover.html"
    $coverJpg = Join-Path $OutputDir 'cover.jpg'
    $coverPdf = Join-Path $OutputDir 'cover.pdf'

    Push-Location (Split-Path -Parent $effectiveCoverPath)
    try {
        $pandocArgs = @(
            "--from=markdown",
            "--to=html5",
            "--standalone",
            "--metadata-file=$MetadataFile",
            "--css=$StyleFile",
            "--css=$printStyleFile",
            "--output=$coverHtml",
            (Split-Path -Leaf $effectiveCoverPath)
        )
        & pandoc @pandocArgs
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $coverHtml)) {
            throw 'Failed to render cover HTML with pandoc.'
        }
    }
    finally {
        Pop-Location
    }

    $browser = Get-BrowserExecutable
    $coverUrl = 'file:///' + ($coverHtml -replace '\\', '/')

    Invoke-HeadlessBrowser -Browser $browser -ExpectedOutput $coverJpg -Arguments @(
        '--headless=new',
        '--disable-gpu',
        '--allow-file-access-from-files',
        '--run-all-compositor-stages-before-draw',
        '--virtual-time-budget=3000',
        '--no-first-run',
        '--no-default-browser-check',
        '--hide-scrollbars',
        '--default-background-color=ffffff',
        '--window-size=1600,2400',
        "--screenshot=$coverJpg",
        $coverUrl
    )

    Invoke-HeadlessBrowser -Browser $browser -ExpectedOutput $coverPdf -Arguments @(
        '--headless=new',
        '--disable-gpu',
        '--allow-file-access-from-files',
        '--run-all-compositor-stages-before-draw',
        '--virtual-time-budget=3000',
        '--no-first-run',
        '--no-default-browser-check',
        '--print-to-pdf-no-header',
        "--print-to-pdf=$coverPdf",
        $coverUrl
    )

    Write-Host "OUTPUT: $coverPdf" -ForegroundColor Green
    Write-Host "OUTPUT: $coverJpg" -ForegroundColor Green
    Write-Host 'Step 2 complete. Run Step 3 to finalize the ebook.' -ForegroundColor Green
}
finally {
    if ($PreserveTemp) {
        Write-Host "Temporary workspace preserved: $tempRoot" -ForegroundColor Yellow
    }
    else {
        Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
