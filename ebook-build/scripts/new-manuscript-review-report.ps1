[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,
    [Parameter()]
    [string]$ProjectName,
    [Parameter()]
    [string]$OutputDir = './ebook-output',
    [Parameter()]
    [string]$Reviewer = 'automated-baseline',
    [Parameter()]
    [ValidateSet('Approve', 'Reject')]
    [string]$Decision = 'Approve',
    [Parameter()]
    [int]$CriticalCount = 0,
    [Parameter()]
    [int]$MajorCount = 0,
    [Parameter()]
    [int]$MinorCount = 0,
    [Parameter()]
    [string]$TemplatePath,
    [Parameter()]
    [string]$ReportPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-ConfiguredPath {
    param(
        [Parameter(Mandatory = $true)] [string]$BasePath,
        [Parameter(Mandatory = $true)] [string]$Value
    )

    if ([System.IO.Path]::IsPathRooted($Value)) {
        return $Value
    }

    return (Join-Path $BasePath $Value)
}

function Get-ArtifactStatus {
    param([Parameter(Mandatory = $true)] [string]$Path)
    if (Test-Path $Path) {
        return 'OK'
    }
    return 'MISSING'
}

$resolvedRepoRoot = (Resolve-Path $RepoRoot).Path
if ([string]::IsNullOrWhiteSpace($ProjectName)) {
    $ProjectName = Split-Path -Leaf $resolvedRepoRoot
}

$resolvedOutputDir = Resolve-ConfiguredPath -BasePath $resolvedRepoRoot -Value $OutputDir
if ([string]::IsNullOrWhiteSpace($TemplatePath)) {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    $TemplatePath = Join-Path (Split-Path -Parent $scriptRoot) 'assets/review-templates/manuscript-review-report.template.md'
}

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Join-Path $resolvedOutputDir ("$ProjectName.manuscript.review.md")
}

$manuscriptPath = Join-Path $resolvedOutputDir ("$ProjectName.manuscript.md")
if (-not (Test-Path $manuscriptPath)) {
    throw "manuscript artifact not found: $manuscriptPath"
}

$template = Get-Content -Path $TemplatePath -Raw -Encoding UTF8
$manuscriptBytes = (Get-Item $manuscriptPath).Length
$manuscriptLines = (Get-Content -Path $manuscriptPath -Encoding UTF8 | Measure-Object -Line).Lines
$anchorMatches = (
    Select-String -Path $manuscriptPath -Pattern '\[.+?\]\(#.+?\)' -AllMatches |
    ForEach-Object { $_.Matches.Count } |
    Measure-Object -Sum
).Sum
if (-not $anchorMatches) {
    $anchorMatches = 0
}

$map = @{
    '{{projectName}}' = $ProjectName
    '{{reviewer}}' = $Reviewer
    '{{reviewedAt}}' = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    '{{decision}}' = $Decision
    '{{criticalCount}}' = [string]$CriticalCount
    '{{majorCount}}' = [string]$MajorCount
    '{{minorCount}}' = [string]$MinorCount
    '{{manuscriptBytes}}' = [string]$manuscriptBytes
    '{{manuscriptLines}}' = [string]$manuscriptLines
    '{{anchorLinkCount}}' = [string]$anchorMatches
    '{{manuscriptArtifactStatus}}' = Get-ArtifactStatus -Path (Join-Path $resolvedOutputDir ("$ProjectName.manuscript.md"))
    '{{epubArtifactStatus}}' = Get-ArtifactStatus -Path (Join-Path $resolvedOutputDir ("$ProjectName.epub"))
    '{{pdfArtifactStatus}}' = Get-ArtifactStatus -Path (Join-Path $resolvedOutputDir ("$ProjectName.pdf"))
    '{{kdpArtifactStatus}}' = Get-ArtifactStatus -Path (Join-Path $resolvedOutputDir ("$ProjectName-kdp-registration.md"))
    '{{coverPdfStatus}}' = Get-ArtifactStatus -Path (Join-Path $resolvedOutputDir 'cover.pdf')
    '{{coverJpgStatus}}' = Get-ArtifactStatus -Path (Join-Path $resolvedOutputDir 'cover.jpg')
}

$content = $template
foreach ($k in $map.Keys) {
    $content = $content.Replace($k, $map[$k])
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($ReportPath, $content, $utf8NoBom)

Write-Host "Generated manuscript review report: $ReportPath" -ForegroundColor Green