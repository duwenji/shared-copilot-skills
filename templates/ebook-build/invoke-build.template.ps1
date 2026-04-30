# Consumer repository wrapper for ebook-build skill
# Copy to: .github/skills-config/ebook-build/invoke-build.ps1
# Replace <repo-name> with the actual repository/project name.
#
# Build steps:
#   step1 - Merge chapter markdown into a single manuscript file
#   step2 - Generate cover artwork
#   step3 - Render Mermaid diagrams and produce final ebook files

[CmdletBinding()]
param(
    [string]$ConfigFile = '.github/skills-config/ebook-build/<repo-name>.build.json',
    [Parameter(Mandatory = $true)]
    [ValidateSet('step1', 'step2', 'step3')]
    [string]$BuildStep
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
    (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
}

function Resolve-ConfiguredPath {
    param([string]$BasePath, [string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    if ([System.IO.Path]::IsPathRooted($Value)) { return $Value }
    Join-Path $BasePath $Value
}

function Get-ConfigValue {
    param([object]$Config, [string]$Name)
    if ($null -eq $Config) { return $null }
    $property = $Config.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    $property.Value
}

function Get-SharedSkillRoot {
    param([string]$RepoRoot)
    $candidates = @(
        (Join-Path $RepoRoot '../shared-copilot-skills/ebook-build'),
        (Join-Path $RepoRoot '.github/skills/shared-skills/ebook-build'),
        (Join-Path $RepoRoot '.github/skills/shared-copilot-skills/ebook-build')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return (Resolve-Path $candidate).Path }
    }
    throw "Shared ebook-build skill not found. Checked: $($candidates -join ', ')"
}

$repoRoot = Resolve-RepoRoot
$configPath = Resolve-ConfiguredPath -BasePath $repoRoot -Value $ConfigFile
$config = Get-Content -Path $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$sharedSkillRoot = Get-SharedSkillRoot -RepoRoot $repoRoot
$scriptsDir = Join-Path $sharedSkillRoot 'scripts'

$projectName = [string](Get-ConfigValue -Config $config -Name 'projectName')
if (-not $projectName) { $projectName = Split-Path -Leaf $repoRoot }

$sourceRoot = Resolve-ConfiguredPath -BasePath $repoRoot -Value (Get-ConfigValue -Config $config -Name 'sourceRoot')
if (-not $sourceRoot) { $sourceRoot = Join-Path $repoRoot 'docs' }

$outputDir = Resolve-ConfiguredPath -BasePath $repoRoot -Value (Get-ConfigValue -Config $config -Name 'outputDir')
if (-not $outputDir) { $outputDir = Join-Path $repoRoot 'ebook-output' }

$metadataFile = Resolve-ConfiguredPath -BasePath $repoRoot -Value (Get-ConfigValue -Config $config -Name 'metadataFile')
if (-not $metadataFile) { $metadataFile = Join-Path $repoRoot ".github/skills-config/ebook-build/$projectName.metadata.yaml" }

$kdpMetadataFileValue = Get-ConfigValue -Config $config -Name 'kdpMetadataFile'
$kdpMetadataFile = Resolve-ConfiguredPath -BasePath $repoRoot -Value $kdpMetadataFileValue
if (-not $kdpMetadataFile) {
    $defaultKdp = Join-Path $repoRoot ".github/skills-config/ebook-build/$projectName.kdp.yaml"
    if (Test-Path $defaultKdp) { $kdpMetadataFile = $defaultKdp }
}

$styleFileValue = Get-ConfigValue -Config $config -Name 'styleFile'
$styleFile = Resolve-ConfiguredPath -BasePath $repoRoot -Value $styleFileValue
if (-not $styleFile) { $styleFile = Join-Path $sharedSkillRoot 'assets/style.css' }

$formats = @(if ($null -ne (Get-ConfigValue -Config $config -Name 'formats')) { Get-ConfigValue -Config $config -Name 'formats' } else { 'epub', 'pdf', 'kdp-markdown' })
$chapterDirPattern = [string](if (Get-ConfigValue -Config $config -Name 'chapterDirPattern') { Get-ConfigValue -Config $config -Name 'chapterDirPattern' } else { '^\d{2}-' })
$chapterFilePattern = [string](if (Get-ConfigValue -Config $config -Name 'chapterFilePattern') { Get-ConfigValue -Config $config -Name 'chapterFilePattern' } else { '^\d{2}-.*\.md$' })
$coverFile = [string](if (Get-ConfigValue -Config $config -Name 'coverFile') { Get-ConfigValue -Config $config -Name 'coverFile' } else { '00-COVER.md' })
$coverTemplateMode = [string](if (Get-ConfigValue -Config $config -Name 'coverTemplateMode') { Get-ConfigValue -Config $config -Name 'coverTemplateMode' } else { 'auto' })
$coverTemplate = [string](if (Get-ConfigValue -Config $config -Name 'coverTemplate') { Get-ConfigValue -Config $config -Name 'coverTemplate' } else { 'classic' })
$mermaidMode = [string](if (Get-ConfigValue -Config $config -Name 'mermaidMode') { Get-ConfigValue -Config $config -Name 'mermaidMode' } else { 'required' })
$mermaidFormat = [string](if (Get-ConfigValue -Config $config -Name 'mermaidFormat') { Get-ConfigValue -Config $config -Name 'mermaidFormat' } else { 'svg' })
$failOnMermaidError = [bool](if ($null -ne (Get-ConfigValue -Config $config -Name 'failOnMermaidError')) { Get-ConfigValue -Config $config -Name 'failOnMermaidError' } else { $true })
$requireManuscriptApproval = [bool](if ($null -ne (Get-ConfigValue -Config $config -Name 'requireManuscriptApproval')) { Get-ConfigValue -Config $config -Name 'requireManuscriptApproval' } else { $false })
$approvalTokenFile = Resolve-ConfiguredPath -BasePath $repoRoot -Value (Get-ConfigValue -Config $config -Name 'approvalTokenFile')

$generateManuscriptReviewReport = [bool](if ($null -ne (Get-ConfigValue -Config $config -Name 'generateManuscriptReviewReport')) { Get-ConfigValue -Config $config -Name 'generateManuscriptReviewReport' } else { $false })
$manuscriptReviewReviewer = [string](if (Get-ConfigValue -Config $config -Name 'manuscriptReviewReviewer') { Get-ConfigValue -Config $config -Name 'manuscriptReviewReviewer' } else { 'automated-baseline' })
$manuscriptReviewDecision = [string](if (Get-ConfigValue -Config $config -Name 'manuscriptReviewDecision') { Get-ConfigValue -Config $config -Name 'manuscriptReviewDecision' } else { 'Approve' })

switch ($BuildStep) {
    'step1' {
        $script = Join-Path $scriptsDir 'invoke-ebook-step1-manuscript.ps1'
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $script `
            -SourceRoot $sourceRoot `
            -OutputDir $outputDir `
            -ProjectName $projectName `
            -MetadataFile $metadataFile `
            -KindleTemplateDir $scriptsDir `
            -StyleFile $styleFile `
            -ChapterDirPattern $chapterDirPattern `
            -ChapterFilePattern $chapterFilePattern `
            -CoverFile $coverFile `
            -CoverTemplateMode $coverTemplateMode `
            -CoverTemplate $coverTemplate
        if ($LASTEXITCODE -ne 0) { throw "Step 1 failed with exit code $LASTEXITCODE" }

        if ($generateManuscriptReviewReport) {
            $reviewScript = Join-Path $scriptsDir 'new-manuscript-review-report.ps1'
            & pwsh -NoProfile -ExecutionPolicy Bypass -File $reviewScript `
                -RepoRoot $repoRoot `
                -ProjectName $projectName `
                -OutputDir $outputDir `
                -Reviewer $manuscriptReviewReviewer `
                -Decision $manuscriptReviewDecision
            if ($LASTEXITCODE -ne 0) { throw "Manuscript review report generation failed with exit code $LASTEXITCODE" }
        }
    }

    'step2' {
        $script = Join-Path $scriptsDir 'invoke-ebook-step2-cover.ps1'
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $script `
            -SourceRoot $sourceRoot `
            -OutputDir $outputDir `
            -ProjectName $projectName `
            -MetadataFile $metadataFile `
            -KindleTemplateDir $scriptsDir `
            -StyleFile $styleFile `
            -CoverFile $coverFile `
            -CoverTemplateMode $coverTemplateMode `
            -CoverTemplate $coverTemplate
        if ($LASTEXITCODE -ne 0) { throw "Step 2 failed with exit code $LASTEXITCODE" }
    }

    'step3' {
        $script = Join-Path $scriptsDir 'invoke-ebook-step3-finalize.ps1'
        $params = @{
            OutputDir = $outputDir
            ProjectName = $projectName
            MetadataFile = $metadataFile
            KindleTemplateDir = $scriptsDir
            StyleFile = $styleFile
            Formats = $formats
            ChapterDirPattern = $chapterDirPattern
            ChapterFilePattern = $chapterFilePattern
            CoverFile = $coverFile
            MermaidMode = $mermaidMode
            MermaidFormat = $mermaidFormat
            FailOnMermaidError = $failOnMermaidError
            RequireManuscriptApproval = $requireManuscriptApproval
        }
        if ($kdpMetadataFile) { $params.KdpMetadataFile = $kdpMetadataFile }
        if ($approvalTokenFile) { $params.ApprovalTokenFile = $approvalTokenFile }
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $script @params
        if ($LASTEXITCODE -ne 0) { throw "Step 3 failed with exit code $LASTEXITCODE" }
    }
}