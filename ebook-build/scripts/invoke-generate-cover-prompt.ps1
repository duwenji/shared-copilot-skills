<#
.SYNOPSIS
  Generate a cover image prompt file from manuscript and metadata using OpenAI API.
  Skips silently if the output file already exists or OPENAI_API_KEY is not set.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$ManuscriptFile,

    [Parameter(Mandatory = $true)]
    [string]$MetadataFile,

    [Parameter(Mandatory = $true)]
    [string]$CoverImagePromptFile,

    [string]$ProjectName = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Import-DotEnv {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }
    foreach ($line in (Get-Content $Path -Encoding UTF8)) {
        if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
        if ($line -match '^\s*(?<key>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?<val>.*)$') {
            $key = $Matches['key']
            $val = $Matches['val'].Trim().Trim('"').Trim("'")
            [System.Environment]::SetEnvironmentVariable($key, $val, 'Process')
        }
    }
}

$sharedSkillRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-DotEnv (Join-Path $sharedSkillRoot '.baoyu-skills\.env')
Import-DotEnv (Join-Path $env:USERPROFILE '.baoyu-skills\.env')

Write-Host "Generate cover prompt: checking prerequisites..." -ForegroundColor Cyan

if (Test-Path $CoverImagePromptFile) {
    Write-Host "Cover image prompt file already exists — skipping generation: $CoverImagePromptFile" -ForegroundColor Yellow
    exit 0
}

$apiKey = $env:OPENAI_API_KEY
if ([string]::IsNullOrWhiteSpace($apiKey)) {
    Write-Warning "OPENAI_API_KEY not set — skipping cover prompt generation. Set the environment variable and re-run step1 to generate."
    exit 0
}

foreach ($req in @($MetadataFile, $ManuscriptFile)) {
    if (-not (Test-Path $req)) {
        Write-Warning "Required file not found, skipping cover prompt generation: $req"
        exit 0
    }
}

Write-Host "Reading manuscript structure and metadata..." -ForegroundColor Cyan

$metadataContent = Get-Content -Path $MetadataFile -Raw -Encoding UTF8

$manuscriptLines  = Get-Content -Path $ManuscriptFile -Encoding UTF8
$headingLines     = @($manuscriptLines | Where-Object { $_ -match '^#{1,3}\s+' } | Select-Object -First 80)
$headings         = $headingLines -join "`n"

$manuscriptRaw = Get-Content -Path $ManuscriptFile -Raw -Encoding UTF8
$excerpt = if ($manuscriptRaw.Length -gt 3000) {
    $manuscriptRaw.Substring(0, 3000) + "`n[...]"
} else {
    $manuscriptRaw
}

$systemPrompt = @'
You are a cover design brief writer for technical ebooks in Japanese. Generate a cover image prompt file in the exact structured format shown below. The file is used as a creative brief for AI image generation (DALL-E or similar).

Output ONLY the file content starting directly with ---. Do not wrap in code fences or add any explanation.

---
type: cover
palette: <palette>
rendering: flat-vector
---

# Content Context
Article title: <title>
Content summary: <2-3 sentences in Japanese summarizing the book's core value>
Keywords: <comma-separated English keywords from the book>

# Visual Design
Cover theme: <visual metaphor phrase — abstract geometric theme>
Type: conceptual
Palette: <palette>
Rendering: flat-vector
Font: clean
Text level: title-subtitle
Mood: balanced
Aspect ratio: 9:16
Language: ja

# Text Elements
Title: <book title>
Subtitle: <Japanese subtitle>

# Mood Application
<1-2 sentences describing visual mood and emotional tone to convey>

# Font Application
<1-2 sentences on typography style — sans-serif choices, weight for title vs subtitle>

# Composition
Type composition:
- <overall conceptual layout description>
- <information hierarchy — how title zone relates to illustration zone>
- <abstract shapes or metaphors that represent core concepts>
- <background zone treatment>

Visual composition:
- Main visual: <description of primary illustration element>
- Center: <focal element or hub concept>
- Layout: <portrait proportions — title zone upper %, illustration lower %>
- Decorative: <accent shapes, patterns, textures>

Color scheme:
- Primary 1: <Color Name> #RRGGBB — <usage description>
- Primary 2: <Color Name> #RRGGBB — <usage description>
- Primary 3: <Color Name> #RRGGBB — <usage description>
- Background: <Color Name> #RRGGBB — <usage description>
- Background Alt: <Color Name> #RRGGBB — <usage description>
- Accent 1: <Color Name> #RRGGBB — <usage description>
- Accent 2: <Color Name> #RRGGBB — <usage description>

Color constraint: Color values (#hex) and color names are rendering guidance only — do NOT display color names, hex codes, or palette labels as visible text in the image.

Rendering notes: <sentence on stroke style, fill style, line endings, and shape treatment>

Type notes: <sentence on abstract shape vocabulary and visual information hierarchy>

Palette notes: <sentence on palette character and surface texture>

---

Palette selection guide (choose the most fitting for the content):
- cool-tech: blues, teals, slate grays — ideal for developer tools, systems, and infrastructure content
- macaron: soft pastels — ideal for educational, beginner-friendly, or community content
- warm-craft: warm yellows, oranges, earthy browns — ideal for creative or artisanal developer content
- mono-ink: black, white, grays with one accent color — ideal for formal, professional, or serious content
- retro-pop: vibrant retro colors — ideal for fun, energetic, or community-facing content
- neon-dark: dark background with neon accents — ideal for cutting-edge, modern tech content

Design rule: The cover theme must be a visual metaphor using abstract geometric shapes. No literal illustrations (no screenshots, no people, no logos).
'@

$userMessage = @"
Generate a cover image prompt file for the following ebook.

## metadata.yaml
$metadataContent

## Chapter structure (headings extracted from manuscript)
$headings

## Opening content excerpt
$excerpt
"@

Write-Host "Calling OpenAI API (gpt-4o) to generate cover image prompt..." -ForegroundColor Cyan

$requestBody = [ordered]@{
    model      = 'gpt-4o'
    max_tokens = 3000
    messages   = @(
        [ordered]@{ role = 'system'; content = $systemPrompt }
        [ordered]@{ role = 'user';   content = $userMessage }
    )
} | ConvertTo-Json -Depth 10

$headers = @{
    'Authorization' = "Bearer $apiKey"
}

try {
    $response = Invoke-RestMethod `
        -Uri         'https://api.openai.com/v1/chat/completions' `
        -Method      Post `
        -Headers     $headers `
        -Body        $requestBody `
        -ContentType 'application/json' `
        -TimeoutSec  120
} catch {
    $statusCode = $null
    try { $statusCode = $_.Exception.Response.StatusCode.value__ } catch {}
    Write-Warning "OpenAI API call failed$(if ($statusCode) { " (HTTP $statusCode)" }): $($_.Exception.Message)"
    exit 0
}

$generated = $response.choices[0].message.content
if ([string]::IsNullOrWhiteSpace($generated)) {
    Write-Warning "OpenAI API returned no content — skipping cover prompt generation."
    exit 0
}

$generated = $generated.Trim()

# Strip markdown code fences if the model wrapped the output
if ($generated -match '^```') {
    $generated = ($generated -replace '^```[a-z]*\r?\n', '' -replace '\r?\n```\s*$', '').Trim()
}

$promptDir = Split-Path -Parent $CoverImagePromptFile
if (-not [string]::IsNullOrWhiteSpace($promptDir) -and -not (Test-Path $promptDir)) {
    New-Item -ItemType Directory -Path $promptDir -Force | Out-Null
    Write-Host "Created prompts directory: $promptDir" -ForegroundColor DarkCyan
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($CoverImagePromptFile, $generated + [Environment]::NewLine, $utf8NoBom)

Write-Host "Cover image prompt generated: $CoverImagePromptFile" -ForegroundColor Green
