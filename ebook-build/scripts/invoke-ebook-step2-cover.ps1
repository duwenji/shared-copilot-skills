<#
.SYNOPSIS
  Step 2 - Generate cover artwork.
  CoverMode "markdown" (default): pandoc + headless browser → cover.jpg + cover.pdf
  CoverMode "ai-image"          : baoyu-image-gen → cover.png + cover.pdf
#>
param(
    [string]$RepoRoot,
    [string]$SourceRoot,
    [string]$OutputDir,
    [string]$ProjectName,
    [string]$MetadataFile,
    [string]$KindleTemplateDir,
    [string]$StyleFile,
    [string]$CoverStyleFile,
    [string]$CoverFile            = '00-COVER.md',
    [ValidateSet('auto', 'file', 'template')]
    [string]$CoverTemplateMode    = 'auto',
    [string]$CoverTemplate        = 'classic',
    [ValidateSet('markdown', 'ai-image')]
    [string]$CoverMode            = 'markdown',
    [string]$CoverImageProvider   = 'openai',
    [string]$CoverImageSize       = '1600x2560',
    [string]$CoverImagePromptFile = '',
    [ValidateSet('png', 'jpg', 'jpeg')]
    [string]$CoverImageFormat     = 'jpg',
    [switch]$PreserveTemp
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Load KEY=VALUE pairs from a .env file into the current process environment.
# Skips blank lines and comments. Does not override already-set variables.
function Import-DotEnv {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }
    foreach ($line in (Get-Content $Path -Encoding UTF8)) {
        if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
        if ($line -match '^\s*(?<key>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?<val>.*)$') {
            $key = $Matches['key']
            $val = $Matches['val'].Trim().Trim('"').Trim("'")
            # Always set from .env at Process scope so it overrides inherited stale User/Machine env vars.
            # If the user wants to use a different key for a specific run, set $env:KEY after this
            # script is loaded (i.e., pass it via CLI args to the npm script).
            [System.Environment]::SetEnvironmentVariable($key, $val, 'Process')
        }
    }
}

# Load .env files in the same priority order as baoyu-image-gen:
#   project-level  →  user home
Import-DotEnv (Join-Path $PSScriptRoot '..\..\..\.baoyu-skills\.env')
Import-DotEnv (Join-Path $env:USERPROFILE '.baoyu-skills\.env')

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

# ---------------------------------------------------------------------------
# Common setup
# ---------------------------------------------------------------------------

if ([string]::IsNullOrWhiteSpace($ProjectName)) {
    $ProjectName = Split-Path -Leaf (Resolve-Path $SourceRoot).ProviderPath
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path (Resolve-Path $SourceRoot).ProviderPath 'ebook-output'
}
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# Derive RepoRoot if not supplied (parent of SourceRoot or OutputDir)
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent (Resolve-Path $SourceRoot).ProviderPath
}

# ---------------------------------------------------------------------------
# ai-image mode: baoyu-image-gen → cover.png + cover.pdf
# ---------------------------------------------------------------------------

if ($CoverMode -eq 'ai-image') {

    $coverExt = if ($CoverImageFormat -eq 'jpg' -or $CoverImageFormat -eq 'jpeg') { 'jpg' } else { 'png' }
    $coverPng = Join-Path $OutputDir "cover.$coverExt"
    $coverPdf = Join-Path $OutputDir 'cover.pdf'

    # Validate API key for known providers
    $providerKeyMap = @{
        'openai'     = 'OPENAI_API_KEY'
        'google'     = 'GOOGLE_API_KEY'
        'azure'      = 'AZURE_OPENAI_API_KEY'
        'dashscope'  = 'DASHSCOPE_API_KEY'
        'openrouter' = 'OPENROUTER_API_KEY'
    }
    if ($providerKeyMap.ContainsKey($CoverImageProvider)) {
        $keyName = $providerKeyMap[$CoverImageProvider]
        if (-not [System.Environment]::GetEnvironmentVariable($keyName, 'Process')) {
            Write-Host ""
            Write-Host "ERROR: $keyName is not set." -ForegroundColor Red
            Write-Host ""
            Write-Host "Set it for the current session:" -ForegroundColor Yellow
            Write-Host "  `$env:$keyName = `"<your-key>`""
            Write-Host ""
            Write-Host "Or set it permanently (user scope):" -ForegroundColor Yellow
            Write-Host "  [System.Environment]::SetEnvironmentVariable('$keyName', '<your-key>', 'User')"
            Write-Host ""
            throw "$keyName is required for coverMode=ai-image with provider=$CoverImageProvider."
        }
    }

    # Locate baoyu-image-gen skill
    $skillCandidates = @(
        (Join-Path $RepoRoot '..\.claude\skills\baoyu-image-gen'),
        (Join-Path $env:USERPROFILE '.claude\skills\baoyu-image-gen')
    )
    $imageGenRoot = $null
    foreach ($c in $skillCandidates) {
        try {
            $r = (Resolve-Path $c -ErrorAction SilentlyContinue).Path
            if ($r -and (Test-Path (Join-Path $r 'scripts\main.ts'))) { $imageGenRoot = $r; break }
        } catch { }
    }
    if (-not $imageGenRoot) {
        throw "baoyu-image-gen skill not found. Checked:`n  $($skillCandidates -join "`n  ")"
    }

    # Resolve prompt file (fall back to a discoverable default)
    $effectivePromptFile = $CoverImagePromptFile
    if ([string]::IsNullOrWhiteSpace($effectivePromptFile)) {
        $effectivePromptFile = Join-Path $OutputDir 'prompts\01-cover-*.md' |
            Resolve-Path -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty Path
    }
    if ([string]::IsNullOrWhiteSpace($effectivePromptFile) -or -not (Test-Path $effectivePromptFile)) {
        throw "CoverImagePromptFile not set and no prompt file found under $OutputDir\prompts\."
    }

    Write-Host "`n=== Step 2 (ai-image): Generate PNG cover ===" -ForegroundColor Cyan
    Write-Host "  Skill    : $imageGenRoot"
    Write-Host "  Provider : $CoverImageProvider"
    Write-Host "  Size     : $CoverImageSize"
    Write-Host "  Prompt   : $effectivePromptFile"
    Write-Host "  Output   : $coverPng"

    $mainTs  = Join-Path $imageGenRoot 'scripts\main.ts'
    $imgArgs = @('--promptfiles', $effectivePromptFile,
                 '--image',       $coverPng,
                 '--size',        $CoverImageSize,
                 '--provider',    $CoverImageProvider,
                 '--quality',     '2k')

    if (Get-Command bun -ErrorAction SilentlyContinue) {
        & bun $mainTs @imgArgs
    } else {
        & npx '-y' 'bun' $mainTs @imgArgs
    }
    if ($LASTEXITCODE -ne 0) { throw "cover.$coverExt generation failed (exit $LASTEXITCODE)" }

    Write-Host "`n=== Step 2 (ai-image): Convert $($coverExt.ToUpper()) -> PDF ===" -ForegroundColor Cyan
    Write-Host "  Output   : $coverPdf"

    $scriptsDir      = $PSScriptRoot
    $pngToPdfScript  = Join-Path $scriptsDir 'png-to-pdf.mjs'
    $pdfLibInShared  = Join-Path $scriptsDir 'node_modules\pdf-lib'

    if (-not (Test-Path $pdfLibInShared)) {
        Write-Host "  Installing pdf-lib in shared scripts..."
        Push-Location $scriptsDir
        try { npm install --silent } finally { Pop-Location }
    }

    & node $pngToPdfScript $coverPng $coverPdf
    if ($LASTEXITCODE -ne 0) { throw "PNG->PDF conversion failed (exit $LASTEXITCODE)" }

    Write-Host "`nOUTPUT: $coverPng" -ForegroundColor Green
    Write-Host "OUTPUT: $coverPdf"   -ForegroundColor Green
    Write-Host 'Step 2 complete. Run Step 3 to finalize the ebook.' -ForegroundColor Green

# ---------------------------------------------------------------------------
# markdown mode (default): pandoc + headless browser → cover.jpg + cover.pdf
# ---------------------------------------------------------------------------

} else {

    Ensure-Path -Path $SourceRoot -Label 'SourceRoot'
    Ensure-Path -Path $MetadataFile -Label 'MetadataFile'
    Ensure-Path -Path $StyleFile -Label 'StyleFile'

    $effectiveCoverStyleFile = $CoverStyleFile
    if (-not $effectiveCoverStyleFile) {
        $effectiveCoverStyleFile = Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\cover.css'
    }
    if (-not (Test-Path $effectiveCoverStyleFile)) {
        Write-Warning "Cover style file not found ($effectiveCoverStyleFile), falling back to StyleFile."
        $effectiveCoverStyleFile = $StyleFile
    }
    Ensure-Path -Path $effectiveCoverStyleFile -Label 'CoverStyleFile'

    if (-not (Get-Command pandoc -ErrorAction SilentlyContinue)) {
        throw 'pandoc is required but was not found in PATH.'
    }

    $sharedSkillRoot   = Split-Path -Parent $PSScriptRoot
    $coverTemplateRoot = Join-Path $sharedSkillRoot 'assets\cover-templates'

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ebook-step2-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    try {
        $contentRoot      = Resolve-ContentRoot -Root $SourceRoot
        $coverPath        = Join-Path $contentRoot $CoverFile
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
        $coverJpg  = Join-Path $OutputDir 'cover.jpg'
        $coverPdf  = Join-Path $OutputDir 'cover.pdf'

        Push-Location (Split-Path -Parent $effectiveCoverPath)
        try {
            $pandocArgs = @(
                "--from=markdown",
                "--to=html5",
                "--standalone",
                "--metadata-file=$MetadataFile",
                "--css=$effectiveCoverStyleFile",
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

        $browser  = Get-BrowserExecutable
        $coverUrl = 'file:///' + ($coverHtml -replace '\\', '/')

        Invoke-HeadlessBrowser -Browser $browser -ExpectedOutput $coverJpg -Arguments @(
            '--headless=new', '--disable-gpu', '--allow-file-access-from-files',
            '--run-all-compositor-stages-before-draw', '--virtual-time-budget=3000',
            '--no-first-run', '--no-default-browser-check', '--hide-scrollbars',
            '--default-background-color=ffffff', '--window-size=1600,2400',
            "--screenshot=$coverJpg", $coverUrl
        )

        Invoke-HeadlessBrowser -Browser $browser -ExpectedOutput $coverPdf -Arguments @(
            '--headless=new', '--disable-gpu', '--allow-file-access-from-files',
            '--run-all-compositor-stages-before-draw', '--virtual-time-budget=3000',
            '--no-first-run', '--no-default-browser-check',
            '--print-to-pdf-no-header', '--no-pdf-header-footer',
            "--print-to-pdf=$coverPdf", $coverUrl
        )

        Write-Host "OUTPUT: $coverPdf" -ForegroundColor Green
        Write-Host "OUTPUT: $coverJpg" -ForegroundColor Green
        Write-Host 'Step 2 complete. Run Step 3 to finalize the ebook.' -ForegroundColor Green
    }
    finally {
        if ($PreserveTemp) {
            Write-Host "Temporary workspace preserved: $tempRoot" -ForegroundColor Yellow
        } else {
            Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
