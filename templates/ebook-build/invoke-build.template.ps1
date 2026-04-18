# Consumer repository wrapper for ebook-build skill
# Copy to: .github/skills-config/ebook-build/invoke-build.ps1
# Replace <repo-name> with the actual repository/project name.

[CmdletBinding()]
param(
    [string]$ConfigFile = '.github/skills-config/ebook-build/<repo-name>.build.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
    (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
}

function Resolve-ConfiguredPath {
    param(
        [string]$BasePath,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }
    if ([System.IO.Path]::IsPathRooted($Value)) {
        return $Value
    }
    (Join-Path $BasePath $Value)
}

function Get-ConfigValue {
    param(
        [object]$Config,
        [string]$Name
    )

    if ($null -eq $Config) {
        return $null
    }

    $property = $Config.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Get-SharedSkillRoot {
    param([string]$RepoRoot)

    $candidates = @(
        (Join-Path $RepoRoot '../shared-copilot-skills/ebook-build'),
        (Join-Path $RepoRoot '.github/skills/shared-skills/ebook-build'),
        (Join-Path $RepoRoot '.github/skills/shared-copilot-skills/ebook-build')
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return (Resolve-Path $candidate).Path
        }
    }

    throw "Shared ebook-build skill not found. Checked: $($candidates -join ', ')"
}

$repoRoot = Resolve-RepoRoot
$configPath = Resolve-ConfiguredPath -BasePath $repoRoot -Value $ConfigFile
$config = Get-Content -Path $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$sharedSkillRoot = Get-SharedSkillRoot -RepoRoot $repoRoot

$projectNameValue      = Get-ConfigValue -Config $config -Name 'projectName'
$sourceRootValue       = Get-ConfigValue -Config $config -Name 'sourceRoot'
$outputDirValue        = Get-ConfigValue -Config $config -Name 'outputDir'
$metadataFileValue     = Get-ConfigValue -Config $config -Name 'metadataFile'
$kdpMetadataFileValue  = Get-ConfigValue -Config $config -Name 'kdpMetadataFile'
$styleFileValue        = Get-ConfigValue -Config $config -Name 'styleFile'
$formatsValue          = Get-ConfigValue -Config $config -Name 'formats'
$chapterDirPatternValue  = Get-ConfigValue -Config $config -Name 'chapterDirPattern'
$chapterFilePatternValue = Get-ConfigValue -Config $config -Name 'chapterFilePattern'
$coverFileValue        = Get-ConfigValue -Config $config -Name 'coverFile'
$coverTemplateModeValue = Get-ConfigValue -Config $config -Name 'coverTemplateMode'
$coverTemplateValue = Get-ConfigValue -Config $config -Name 'coverTemplate'
$buildPhaseValue = Get-ConfigValue -Config $config -Name 'buildPhase'
$requireManuscriptApprovalValue = Get-ConfigValue -Config $config -Name 'requireManuscriptApproval'
$approvalTokenFileValue = Get-ConfigValue -Config $config -Name 'approvalTokenFile'
$mermaidModeValue = Get-ConfigValue -Config $config -Name 'mermaidMode'
$mermaidFormatValue = Get-ConfigValue -Config $config -Name 'mermaidFormat'
$failOnMermaidErrorValue = Get-ConfigValue -Config $config -Name 'failOnMermaidError'
$generateManuscriptReviewReportValue = Get-ConfigValue -Config $config -Name 'generateManuscriptReviewReport'
$manuscriptReviewReviewerValue = Get-ConfigValue -Config $config -Name 'manuscriptReviewReviewer'
$manuscriptReviewDecisionValue = Get-ConfigValue -Config $config -Name 'manuscriptReviewDecision'

$projectName = if ($projectNameValue) { [string]$projectNameValue } else { Split-Path -Leaf $repoRoot }
$sourceRoot  = Resolve-ConfiguredPath -BasePath $repoRoot -Value $sourceRootValue
if (-not $sourceRoot) { $sourceRoot = $repoRoot }
$outputDir   = Resolve-ConfiguredPath -BasePath $repoRoot -Value $outputDirValue
if (-not $outputDir) { $outputDir = Join-Path $repoRoot 'ebook-output' }

$metadataFile = Resolve-ConfiguredPath -BasePath $repoRoot -Value $metadataFileValue
if (-not $metadataFile) { $metadataFile = Join-Path $repoRoot ".github/skills-config/ebook-build/$projectName.metadata.yaml" }

$kdpMetadataFile = Resolve-ConfiguredPath -BasePath $repoRoot -Value $kdpMetadataFileValue
if (-not $kdpMetadataFile) {
    $defaultKdpMetadataFile = Join-Path $repoRoot ".github/skills-config/ebook-build/$projectName.kdp.yaml"
    if (Test-Path $defaultKdpMetadataFile) {
        $kdpMetadataFile = $defaultKdpMetadataFile
    }
}

$styleFile = Resolve-ConfiguredPath -BasePath $repoRoot -Value $styleFileValue
if (-not $styleFile) { $styleFile = Join-Path $sharedSkillRoot 'assets/style.css' }

$invokeScript      = Join-Path $sharedSkillRoot 'scripts/invoke-ebook-build.ps1'
$kindleTemplateDir = Join-Path $sharedSkillRoot 'scripts'

$formats          = if ($null -ne $formatsValue) { @($formatsValue) } else { @('epub', 'pdf', 'kdp-markdown') }
$chapterDirPattern  = if ($chapterDirPatternValue)  { [string]$chapterDirPatternValue }  else { '^\d{2}-' }
$chapterFilePattern = if ($chapterFilePatternValue) { [string]$chapterFilePatternValue } else { '^\d{2}-.*\.md$' }
$coverFile        = if ($coverFileValue) { [string]$coverFileValue } else { '00-COVER.md' }
$coverTemplateMode = if ($coverTemplateModeValue) { [string]$coverTemplateModeValue } else { 'auto' }
$coverTemplate = if ($coverTemplateValue) { [string]$coverTemplateValue } else { 'classic' }
$buildPhase = if ($buildPhaseValue) { [string]$buildPhaseValue } else { 'full' }
$requireManuscriptApproval = if ($null -ne $requireManuscriptApprovalValue) { [bool]$requireManuscriptApprovalValue } else { $false }
$approvalTokenFile = Resolve-ConfiguredPath -BasePath $repoRoot -Value $approvalTokenFileValue
$mermaidMode = if ($mermaidModeValue) { [string]$mermaidModeValue } else { 'required' }
$mermaidFormat = if ($mermaidFormatValue) { [string]$mermaidFormatValue } else { 'svg' }
$failOnMermaidError = if ($null -ne $failOnMermaidErrorValue) { [bool]$failOnMermaidErrorValue } else { $true }
$generateManuscriptReviewReport = if ($null -ne $generateManuscriptReviewReportValue) { [bool]$generateManuscriptReviewReportValue } else { $false }
$manuscriptReviewReviewer = if ($manuscriptReviewReviewerValue) { [string]$manuscriptReviewReviewerValue } else { 'automated-baseline' }
$manuscriptReviewDecision = if ($manuscriptReviewDecisionValue) { [string]$manuscriptReviewDecisionValue } else { 'Approve' }

$params = @{
    SourceRoot         = $sourceRoot
    OutputDir          = $outputDir
    ProjectName        = $projectName
    KindleTemplateDir  = $kindleTemplateDir
    MetadataFile       = $metadataFile
    KdpMetadataFile    = $kdpMetadataFile
    StyleFile          = $styleFile
    Formats            = $formats
    ChapterDirPattern  = $chapterDirPattern
    ChapterFilePattern = $chapterFilePattern
    CoverFile          = $coverFile
    CoverTemplateMode  = $coverTemplateMode
    CoverTemplate      = $coverTemplate
    BuildPhase         = $buildPhase
    RequireManuscriptApproval = $requireManuscriptApproval
    ApprovalTokenFile  = $approvalTokenFile
    MermaidMode        = $mermaidMode
    MermaidFormat      = $mermaidFormat
    FailOnMermaidError = $failOnMermaidError
}

& $invokeScript @params

if ($LASTEXITCODE -ne 0) {
    throw "ebook build failed with exit code $LASTEXITCODE"
}

if ($generateManuscriptReviewReport) {
    $reviewScript = Join-Path $sharedSkillRoot 'scripts/new-manuscript-review-report.ps1'
    if (-not (Test-Path $reviewScript)) {
        throw "manuscript review report script not found: $reviewScript"
    }

    & pwsh -NoProfile -ExecutionPolicy Bypass -File $reviewScript `
        -RepoRoot $repoRoot `
        -ProjectName $projectName `
        -OutputDir $outputDir `
        -Reviewer $manuscriptReviewReviewer `
        -Decision $manuscriptReviewDecision

    if ($LASTEXITCODE -ne 0) {
        throw "manuscript review report generation failed with exit code $LASTEXITCODE"
    }
}

