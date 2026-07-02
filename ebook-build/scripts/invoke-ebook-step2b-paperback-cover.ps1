<#
.SYNOPSIS
  Step 2b - Generate KDP Paperback full-wrap cover PDF.

  Reads page count from the finalized project.pdf (Step 3 must be complete).
  Assembles back cover + spine + front cover into a single print-ready PDF
  following KDP Paperback specifications:
    - 0.125" (3.2mm) bleed on all four edges
    - Spine width calculated from page count and paper type
    - 300+ DPI (derived from the EPUB cover image dimensions)
    - RGB PDF output; optional CMYK via Ghostscript if installed

  OUTPUT: ebook-output/paperback-cover.pdf
          ebook-output/paperback-cover-cmyk.pdf  (only when Ghostscript found)
#>
param(
    [string]$OutputDir,
    [string]$ProjectName,
    [string]$MetadataFile,
    [string]$KdpMetadataFile,
    [string]$BackColor   = '#0b1220',
    [string]$SpineColor  = '',
    [string]$FontPath    = '',
    [switch]$PreserveTemp
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Helpers (duplicated from step2 to keep each step self-contained)
# ---------------------------------------------------------------------------

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

function Resolve-PythonExecutable {
    $candidates = @(
        $env:PYTHON,
        $env:PYTHON_EXE,
        (Get-Command python  -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1),
        (Get-Command python3 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1),
        'C:\Python314\python.exe',
        'C:\Python313\python.exe',
        'C:\Python312\python.exe',
        'C:\Python311\python.exe',
        'C:\Python310\python.exe'
    )
    foreach ($c in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($c) -and (Test-Path $c)) { return $c }
    }
    throw 'Python 3 is required for paperback cover generation but was not found in PATH.'
}

# ---------------------------------------------------------------------------
# 1. Read kdp.yaml
# ---------------------------------------------------------------------------

Write-Host "`n=== Step 2b: KDP Paperback Cover ===" -ForegroundColor Cyan

if ([string]::IsNullOrWhiteSpace($KdpMetadataFile) -or -not (Test-Path $KdpMetadataFile)) {
    throw "KdpMetadataFile not found: $KdpMetadataFile`nSet kdpMetadataFile in your build.json."
}

$trimSizeRaw = Get-YamlScalarValue -Path $KdpMetadataFile -Key 'trimSize'
$paperType   = Get-YamlScalarValue -Path $KdpMetadataFile -Key 'paperType'
if (-not $trimSizeRaw) { throw "trimSize is required in: $KdpMetadataFile" }
if (-not $paperType)   { $paperType = 'white' }

# Parse "6in x 9in" (also accepts "6 x 9 in", "6×9 in", etc.)
if ($trimSizeRaw -match '(?i)([\d.]+)\s*in?\s*[xX×]\s*([\d.]+)\s*in?') {
    $trimWidth  = [double]$Matches[1]
    $trimHeight = [double]$Matches[2]
} else {
    throw "Cannot parse trimSize '$trimSizeRaw'. Expected format: '6in x 9in'"
}

Write-Host "  Trim size   : ${trimWidth}in × ${trimHeight}in"
Write-Host "  Paper type  : $paperType"

# ---------------------------------------------------------------------------
# 2. Count PDF pages from finalized project.pdf
# ---------------------------------------------------------------------------

$sourcePdf = Join-Path $OutputDir "$ProjectName.pdf"
if (-not (Test-Path $sourcePdf)) {
    throw "Source PDF not found: $sourcePdf`nPlease run Step 3 before Step 2b."
}

$countScript = Join-Path $PSScriptRoot 'count-pages.mjs'
$pageCountRaw = & node $countScript $sourcePdf 2>&1
if ($LASTEXITCODE -ne 0 -or $pageCountRaw -notmatch '^\s*\d+\s*$') {
    throw "Failed to count pages in '$sourcePdf': $pageCountRaw"
}
$pageCount = [int]($pageCountRaw.Trim())
Write-Host "  Page count  : $pageCount"

# ---------------------------------------------------------------------------
# 3. Calculate spine width
# ---------------------------------------------------------------------------

$spineFactors = @{
    'white'          = 0.002252
    'cream'          = 0.002500
    'color-standard' = 0.002252
    'color-premium'  = 0.002347
}
$factor = if ($spineFactors.ContainsKey($paperType.ToLower())) {
    $spineFactors[$paperType.ToLower()]
} else {
    Write-Warning "Unknown paperType '$paperType' — defaulting to 'white' factor."
    0.002252
}

$spineWidthIn = [Math]::Round($pageCount * $factor, 6)
$spineWidthMm = [Math]::Round($spineWidthIn * 25.4, 2)
Write-Host "  Spine width : $spineWidthIn in ($spineWidthMm mm)"

if ($pageCount -lt 79) {
    Write-Warning "KDP requires ≥ 79 pages for spine text. Spine will be blank."
}

# ---------------------------------------------------------------------------
# 4. Read title and creator from metadata.yaml
# ---------------------------------------------------------------------------

$title  = Get-YamlScalarValue -Path $MetadataFile -Key 'title'
$author = Get-YamlScalarValue -Path $MetadataFile -Key 'creator'
if (-not $title)  { $title  = $ProjectName }
if (-not $author) { $author = '' }

# ---------------------------------------------------------------------------
# 5. Locate front cover image (cover.jpg preferred, cover.png fallback)
# ---------------------------------------------------------------------------

$coverJpg = Join-Path $OutputDir 'cover.jpg'
$coverPng = Join-Path $OutputDir 'cover.png'
$inputImage = if     (Test-Path $coverJpg) { $coverJpg }
              elseif (Test-Path $coverPng) { $coverPng }
              else   { throw "Cover image not found in '$OutputDir'. Run Step 2 first." }

Write-Host "  Input cover : $inputImage"

# ---------------------------------------------------------------------------
# 6. Generate full-wrap PNG via Python
# ---------------------------------------------------------------------------

$wrapPng = Join-Path $OutputDir 'paperback-cover.png'
$wrapPdf = Join-Path $OutputDir 'paperback-cover.pdf'

$pythonExe   = Resolve-PythonExecutable
$coverScript = Join-Path $PSScriptRoot 'paperback-cover.py'
$pdfScript   = Join-Path $PSScriptRoot 'paperback-to-pdf.mjs'

Write-Host "`n--- Assembling full-wrap PNG ---" -ForegroundColor DarkCyan
Write-Host "  Output : $wrapPng"

$pyArgs = @(
    $coverScript,
    '--input-image',  $inputImage,
    '--output-image', $wrapPng,
    '--trim-width',   $trimWidth,
    '--trim-height',  $trimHeight,
    '--spine-width',  $spineWidthIn,
    '--back-color',   $BackColor
)
if ($SpineColor)              { $pyArgs += @('--spine-color',  $SpineColor) }
if ($FontPath)                { $pyArgs += @('--font-path',    $FontPath) }
if ($pageCount -ge 79) {
    $pyArgs += @('--spine-title', $title)
    if ($author) { $pyArgs += @('--spine-author', $author) }
}

$pyOutput = & $pythonExe @pyArgs 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "paperback-cover.py failed (exit $LASTEXITCODE):`n$pyOutput"
}

# Parse physical dimensions from script stdout
$wrapWidthIn  = $null
$wrapHeightIn = $null
foreach ($line in ($pyOutput -split "`r?`n")) {
    if ($line -match '^WRAP_WIDTH_IN=([\d.]+)')  { $wrapWidthIn  = [double]$Matches[1] }
    if ($line -match '^WRAP_HEIGHT_IN=([\d.]+)') { $wrapHeightIn = [double]$Matches[1] }
    if ($line -match '^WARNING:') { Write-Warning $line }
}

if (-not $wrapWidthIn -or -not $wrapHeightIn) {
    throw "Could not parse wrap dimensions from paperback-cover.py.`nOutput was:`n$pyOutput"
}

$wrapWidthIn  = [Math]::Round($wrapWidthIn,  6)
$wrapHeightIn = [Math]::Round($wrapHeightIn, 6)
Write-Host "  Wrap size : ${wrapWidthIn}in × ${wrapHeightIn}in"

# ---------------------------------------------------------------------------
# 7. Convert PNG → PDF with correct physical page dimensions
# ---------------------------------------------------------------------------

Write-Host "`n--- Converting PNG → PDF ---" -ForegroundColor DarkCyan
Write-Host "  Output : $wrapPdf"

& node $pdfScript $wrapPng $wrapPdf $wrapWidthIn $wrapHeightIn
if ($LASTEXITCODE -ne 0) { throw "paperback-to-pdf.mjs failed (exit $LASTEXITCODE)" }

# ---------------------------------------------------------------------------
# 8. Optional CMYK conversion via Ghostscript
# ---------------------------------------------------------------------------

$gs = Get-Command gs -ErrorAction SilentlyContinue
if ($gs) {
    $wrapCmykPdf = Join-Path $OutputDir 'paperback-cover-cmyk.pdf'
    Write-Host "`n--- CMYK conversion (Ghostscript) ---" -ForegroundColor DarkCyan
    Write-Host "  Output : $wrapCmykPdf"

    & ($gs.Source) `
        -dBATCH -dNOPAUSE -dQUIET `
        -sDEVICE=pdfwrite `
        -sColorConversionStrategy=CMYK `
        -dProcessColorModel=/DeviceCMYK `
        "-sOutputFile=$wrapCmykPdf" `
        $wrapPdf

    if ($LASTEXITCODE -eq 0 -and (Test-Path $wrapCmykPdf)) {
        Write-Host "OUTPUT: $wrapCmykPdf" -ForegroundColor Green
    } else {
        Write-Warning "Ghostscript CMYK conversion failed — RGB PDF is kept."
    }
} else {
    Write-Host ""
    Write-Host "[Note] Ghostscript not found in PATH." -ForegroundColor Yellow
    Write-Host "       paperback-cover.pdf is RGB. For KDP print accuracy install" -ForegroundColor Yellow
    Write-Host "       Ghostscript (https://www.ghostscript.com) or convert in Adobe Acrobat." -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Cleanup intermediate PNG
# ---------------------------------------------------------------------------

if (-not $PreserveTemp -and (Test-Path $wrapPng)) {
    Remove-Item $wrapPng -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "OUTPUT: $wrapPdf" -ForegroundColor Green
Write-Host "Step 2b complete." -ForegroundColor Green
Write-Host ""
Write-Host "Next steps for KDP Paperback submission:" -ForegroundColor Cyan
Write-Host "  1. Upload paperback-cover.pdf (or -cmyk.pdf if available) as the Cover File"
Write-Host "  2. Upload $ProjectName.pdf as the Interior File"
Write-Host "  3. KDP will auto-place the barcode on the back cover"
