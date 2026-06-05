# Shared ebook-build dispatcher.
# Consumer repositories call this script from their own thin invoke-build.ps1 wrapper.
#
# Build steps:
#   step1 — Merge chapter markdown into a single manuscript file
#            INPUT : source docs, metadata.yaml
#            OUTPUT: ebook-output/<projectName>.manuscript.md
#
#   step2 — Generate cover artwork
#            INPUT : cover markdown / cover template, metadata.yaml
#            OUTPUT: ebook-output/cover.pdf, ebook-output/cover.jpg
#
#   step3 — Render Mermaid diagrams and produce final ebook files
#            INPUT : step1 + step2 outputs, metadata.yaml
#            OUTPUT: ebook-output/<projectName>.epub, .pdf, -kdp-registration.md

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $true)]
    [string]$ConfigFile,

    [Parameter(Mandatory = $true)]
    [ValidateSet('step1', 'step2', 'step3')]
    [string]$BuildStep
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Print-ScriptInvocation {
    param(
        [string]$ScriptPath,
        [hashtable]$ParamHash
    )

    Write-Host "Print-ScriptInvocation called with:" -ForegroundColor Cyan
    if ($PSBoundParameters.Keys.Count -gt 0) {
        foreach ($p in $PSBoundParameters.Keys) {
            $val = $PSBoundParameters[$p]
            if ($p -eq 'ParamHash' -and $val -is [hashtable]) {
                Write-Host "  $p = Hashtable:"
                foreach ($hk in $val.Keys) {
                    $hv = $val[$hk]
                    Write-Host "    $hk = $hv"
                }
            } else {
                Write-Host "  $p = $val"
            }
        }
    } else {
        Write-Host "  (no parameters passed)"
    }

    Write-Host "Invoking script: $ScriptPath"
    if ($null -ne $ParamHash -and $ParamHash.Keys.Count -gt 0) {
        Write-Host "Arguments:"
        foreach ($k in $ParamHash.Keys) {
            $v = $ParamHash[$k]
            Write-Host "  -$k $v"
        }
    }
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

    Join-Path $BasePath $Value
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

    $property.Value
}

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------

$configPath = Resolve-ConfiguredPath -BasePath $RepoRoot -Value $ConfigFile
$config     = Get-Content -Path $configPath -Raw -Encoding UTF8 | ConvertFrom-Json

$scriptsDir = $PSScriptRoot

# ---------------------------------------------------------------------------
# Read all config values
# ---------------------------------------------------------------------------

$projectNameValue                  = Get-ConfigValue -Config $config -Name 'projectName'
$sourceRootValue                   = Get-ConfigValue -Config $config -Name 'sourceRoot'
$outputDirValue                    = Get-ConfigValue -Config $config -Name 'outputDir'
$metadataFileValue                 = Get-ConfigValue -Config $config -Name 'metadataFile'
$kdpMetadataFileValue              = Get-ConfigValue -Config $config -Name 'kdpMetadataFile'
$styleFileValue                    = Get-ConfigValue -Config $config -Name 'styleFile'
$coverStyleFileValue               = Get-ConfigValue -Config $config -Name 'coverStyleFile'
$formatsValue                      = Get-ConfigValue -Config $config -Name 'formats'
$chapterDirPatternValue            = Get-ConfigValue -Config $config -Name 'chapterDirPattern'
$chapterFilePatternValue           = Get-ConfigValue -Config $config -Name 'chapterFilePattern'
$coverFileValue                    = Get-ConfigValue -Config $config -Name 'coverFile'
$manuscriptLeadFileValue           = Get-ConfigValue -Config $config -Name 'manuscriptLeadFile'
$skipCoverInManuscriptValue        = Get-ConfigValue -Config $config -Name 'skipCoverInManuscript'
$coverTemplateModeValue            = Get-ConfigValue -Config $config -Name 'coverTemplateMode'
$coverTemplateValue                = Get-ConfigValue -Config $config -Name 'coverTemplate'
$requireManuscriptApprovalValue    = Get-ConfigValue -Config $config -Name 'requireManuscriptApproval'
$approvalTokenFileValue            = Get-ConfigValue -Config $config -Name 'approvalTokenFile'
$mermaidModeValue                  = Get-ConfigValue -Config $config -Name 'mermaidMode'
$mermaidFormatValue                = Get-ConfigValue -Config $config -Name 'mermaidFormat'
$failOnMermaidErrorValue           = Get-ConfigValue -Config $config -Name 'failOnMermaidError'
$mermaidConfigFileValue            = Get-ConfigValue -Config $config -Name 'mermaidConfigFile'
$mermaidPuppeteerConfigFileValue   = Get-ConfigValue -Config $config -Name 'mermaidPuppeteerConfigFile'
$generateManuscriptReviewReportValue = Get-ConfigValue -Config $config -Name 'generateManuscriptReviewReport'
$manuscriptReviewReviewerValue     = Get-ConfigValue -Config $config -Name 'manuscriptReviewReviewer'
$manuscriptReviewDecisionValue     = Get-ConfigValue -Config $config -Name 'manuscriptReviewDecision'
$normalizeManuscriptValue          = Get-ConfigValue -Config $config -Name 'normalizeManuscript'
$headingNumberingValue             = Get-ConfigValue -Config $config -Name 'headingNumbering'
$tocDepthValue                     = Get-ConfigValue -Config $config -Name 'tocDepth'
$samplesRootValue                  = Get-ConfigValue -Config $config -Name 'samplesRoot'
$samplesTitleValue                 = Get-ConfigValue -Config $config -Name 'samplesTitle'
$collectAssetsValue               = Get-ConfigValue -Config $config -Name 'collectAssets'
$preserveTempValue                 = Get-ConfigValue -Config $config -Name 'preserveTemp'

# ---------------------------------------------------------------------------
# Resolve effective values (config → sensible defaults)
# ---------------------------------------------------------------------------

$sharedSkillRoot = Split-Path -Parent $PSScriptRoot

$projectName = if ($projectNameValue) { [string]$projectNameValue } else { Split-Path -Leaf $RepoRoot }

$sourceRoot = Resolve-ConfiguredPath -BasePath $RepoRoot -Value $sourceRootValue
if (-not $sourceRoot) { $sourceRoot = Join-Path $RepoRoot 'docs' }

$outputDir = Resolve-ConfiguredPath -BasePath $RepoRoot -Value $outputDirValue
if (-not $outputDir) { $outputDir = Join-Path $RepoRoot 'ebook-output' }

$metadataFile = Resolve-ConfiguredPath -BasePath $RepoRoot -Value $metadataFileValue
if (-not $metadataFile) { $metadataFile = Join-Path $RepoRoot ".github/skills-config/ebook-build/$projectName.metadata.yaml" }

$kdpMetadataFile = Resolve-ConfiguredPath -BasePath $RepoRoot -Value $kdpMetadataFileValue
if (-not $kdpMetadataFile) {
    $defaultKdpMetadataFile = Join-Path $RepoRoot ".github/skills-config/ebook-build/$projectName.kdp.yaml"
    if (Test-Path $defaultKdpMetadataFile) {
        $kdpMetadataFile = $defaultKdpMetadataFile
    }
}

$styleFile = Resolve-ConfiguredPath -BasePath $RepoRoot -Value $styleFileValue
if (-not $styleFile) { $styleFile = Join-Path $sharedSkillRoot 'assets/style.css' }

$coverStyleFile = Resolve-ConfiguredPath -BasePath $RepoRoot -Value $coverStyleFileValue
if (-not $coverStyleFile) { $coverStyleFile = Join-Path $sharedSkillRoot 'assets/cover.css' }

$formats            = @(if ($null -ne $formatsValue) { $formatsValue } else { 'epub', 'pdf', 'kdp-markdown' })
$chapterDirPattern  = [string]$(if ($chapterDirPatternValue)  { $chapterDirPatternValue }  else { '^\d{2}-' })
$chapterFilePattern = [string]$(if ($chapterFilePatternValue) { $chapterFilePatternValue } else { '^\d{2}-.*\.md$' })
$coverFile          = [string]$(if ($coverFileValue)          { $coverFileValue }          else { '00-COVER.md' })
$manuscriptLeadFile = [string]$(if ($manuscriptLeadFileValue) { $manuscriptLeadFileValue } else { '' })
$skipCoverInManuscript      = [bool]$(if ($null -ne $skipCoverInManuscriptValue)      { $skipCoverInManuscriptValue }      else { $false })
$coverTemplateMode          = [string]$(if ($coverTemplateModeValue)                  { $coverTemplateModeValue }          else { 'auto' })
$coverTemplate              = [string]$(if ($coverTemplateValue)                      { $coverTemplateValue }              else { 'classic' })
$mermaidMode                = [string]$(if ($mermaidModeValue)                        { $mermaidModeValue }                else { 'required' })
$mermaidFormat              = [string]$(if ($mermaidFormatValue)                      { $mermaidFormatValue }              else { 'svg' })
$failOnMermaidError         = [bool]$(if ($null -ne $failOnMermaidErrorValue)         { $failOnMermaidErrorValue }         else { $true })
$mermaidConfigFile          = Resolve-ConfiguredPath -BasePath $RepoRoot -Value $mermaidConfigFileValue
$mermaidPuppeteerConfigFile = Resolve-ConfiguredPath -BasePath $RepoRoot -Value $mermaidPuppeteerConfigFileValue
$requireManuscriptApproval  = [bool]$(if ($null -ne $requireManuscriptApprovalValue)  { $requireManuscriptApprovalValue }  else { $false })
$approvalTokenFile          = Resolve-ConfiguredPath -BasePath $RepoRoot -Value $approvalTokenFileValue
$manuscriptReviewReviewer   = [string]$(if ($manuscriptReviewReviewerValue)           { $manuscriptReviewReviewerValue }   else { 'automated-baseline' })
$manuscriptReviewDecision   = [string]$(if ($manuscriptReviewDecisionValue)           { $manuscriptReviewDecisionValue }   else { 'Approve' })
$normalizeManuscript        = [bool]$(if ($null -ne $normalizeManuscriptValue)        { $normalizeManuscriptValue }        else { $false })
$headingNumbering           = [bool]$(if ($null -ne $headingNumberingValue)           { $headingNumberingValue }           else { $false })
$tocDepth = if ($null -ne $tocDepthValue) { [int]$tocDepthValue } else { 0 }
$samplesRoot   = Resolve-ConfiguredPath -BasePath $RepoRoot -Value $samplesRootValue
$samplesTitle  = if ($samplesTitleValue) { [string]$samplesTitleValue } else { 'Samples Catalog' }
$collectAssets = if ($null -ne $collectAssetsValue) { 
    if ($collectAssetsValue -is [bool]) { 
        $collectAssetsValue 
    } else {
        [System.Convert]::ToBoolean($collectAssetsValue)
    }
} else { 
    $false 
}
$preserveTemp  = [bool]$(if ($null -ne $preserveTempValue) { $preserveTempValue } else { $false })

# ---------------------------------------------------------------------------
# Dispatch to the appropriate step script
# ---------------------------------------------------------------------------

switch ($BuildStep) {

    'step1' {
        # INPUT : source docs, metadata.yaml
        # OUTPUT: $outputDir/$projectName.manuscript.md
        $script = Join-Path $scriptsDir 'invoke-ebook-step1-manuscript.ps1'
        
        $step1Params = @{
            SourceRoot         = $sourceRoot
            OutputDir          = $outputDir
            ProjectName        = $projectName
            MetadataFile       = $metadataFile
            KindleTemplateDir  = $scriptsDir
            StyleFile          = $styleFile
            ChapterDirPattern  = $chapterDirPattern
            ChapterFilePattern = $chapterFilePattern
            CoverFile          = $coverFile
            ManuscriptLeadFile = $manuscriptLeadFile
            CoverTemplateMode  = $coverTemplateMode
            CoverTemplate      = $coverTemplate
            CollectAssets      = $collectAssets
            SamplesTitle       = $samplesTitle
        }
        
        if ($skipCoverInManuscript) { $step1Params.SkipCoverInManuscript = $true }
        if ($headingNumbering)      { $step1Params.NumberHeadings = $true }
        if ($preserveTemp)          { $step1Params.PreserveTemp = $true }
        if ($samplesRoot)           { $step1Params.SamplesRoot = $samplesRoot }

        Print-ScriptInvocation -ScriptPath $script -ParamHash $step1Params
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $script @step1Params
        if ($LASTEXITCODE -ne 0) { throw "Step 1 failed with exit code $LASTEXITCODE" }

        if ($normalizeManuscript) {
            $manuscriptPath = Join-Path $outputDir ("$projectName.manuscript.md")
            $normalizeScript = Join-Path $scriptsDir 'normalize-manuscript.ps1'

            if (-not (Test-Path $normalizeScript -PathType Leaf)) {
                throw "Normalization script not found: $normalizeScript"
            }
            if (-not (Test-Path $manuscriptPath -PathType Leaf)) {
                throw "Manuscript not found for normalization: $manuscriptPath"
            }

            Write-Host "Post-processing manuscript: $manuscriptPath"
            & $normalizeScript -ManuscriptPath $manuscriptPath
            if ($LASTEXITCODE -ne 0) {
                throw "Manuscript normalization failed with exit code $LASTEXITCODE"
            }
        }

        Write-Host "generateManuscriptReviewReportValue = $generateManuscriptReviewReportValue"
        if ($generateManuscriptReviewReportValue) {
            Write-Host "Manuscript review report enabled — invoking review script..."
            $reviewScript = Join-Path $scriptsDir 'new-manuscript-review-report.ps1'
            Write-Host "Invoking script: $reviewScript"
            Write-Host "Arguments:"
            Write-Host "  -RepoRoot    $RepoRoot"
            Write-Host "  -ProjectName $projectName"
            Write-Host "  -OutputDir   $outputDir"
            Write-Host "  -Reviewer    $manuscriptReviewReviewer"
            Write-Host "  -Decision    $manuscriptReviewDecision"
            & pwsh -NoProfile -ExecutionPolicy Bypass -File $reviewScript `
                -RepoRoot    $RepoRoot `
                -ProjectName $projectName `
                -OutputDir   $outputDir `
                -Reviewer    $manuscriptReviewReviewer `
                -Decision    $manuscriptReviewDecision
            if ($LASTEXITCODE -ne 0) { throw "Manuscript review report generation failed with exit code $LASTEXITCODE" }
        } else {
            Write-Host "Manuscript review report generation skipped. (generateManuscriptReviewReportValue = $generateManuscriptReviewReportValue)"
        }
    }

    'step2' {
        # INPUT : cover markdown / cover template, metadata.yaml
        # OUTPUT: $outputDir/cover.pdf, $outputDir/cover.jpg
        $script = Join-Path $scriptsDir 'invoke-ebook-step2-cover.ps1'
        Write-Host "Invoking script: $script"
        Write-Host "Arguments:"
        Write-Host "  -SourceRoot        $sourceRoot"
        Write-Host "  -OutputDir         $outputDir"
        Write-Host "  -ProjectName       $projectName"
        Write-Host "  -MetadataFile      $metadataFile"
        Write-Host "  -KindleTemplateDir $scriptsDir"
        Write-Host "  -StyleFile         $styleFile"
        Write-Host "  -CoverStyleFile    $coverStyleFile"
        Write-Host "  -CoverFile         $coverFile"
        Write-Host "  -CoverTemplateMode $coverTemplateMode"
        Write-Host "  -CoverTemplate     $coverTemplate"
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $script `
            -SourceRoot        $sourceRoot `
            -OutputDir         $outputDir `
            -ProjectName       $projectName `
            -MetadataFile      $metadataFile `
            -KindleTemplateDir $scriptsDir `
            -StyleFile         $styleFile `
            -CoverStyleFile    $coverStyleFile `
            -CoverFile         $coverFile `
            -CoverTemplateMode $coverTemplateMode `
            -CoverTemplate     $coverTemplate
        if ($LASTEXITCODE -ne 0) { throw "Step 2 failed with exit code $LASTEXITCODE" }
    }

    'step3' {
        # INPUT : step1 + step2 outputs, metadata.yaml
        # OUTPUT: $outputDir/$projectName.epub, .pdf, -kdp-registration.md
        $script = Join-Path $scriptsDir 'invoke-ebook-step3-finalize.ps1'
        $step3Params = @{
            OutputDir                = $outputDir
            ProjectName              = $projectName
            MetadataFile             = $metadataFile
            KindleTemplateDir        = $scriptsDir
            StyleFile                = $styleFile
            Formats                  = $formats
            ChapterDirPattern        = $chapterDirPattern
            ChapterFilePattern       = $chapterFilePattern
            CoverFile                = $coverFile
            MermaidMode              = $mermaidMode
            MermaidFormat            = $mermaidFormat
            FailOnMermaidError       = $failOnMermaidError
            RequireManuscriptApproval = $requireManuscriptApproval
            TocDepth                 = $tocDepth
        }
        if ($kdpMetadataFile)            { $step3Params.KdpMetadataFile            = $kdpMetadataFile }
        if ($approvalTokenFile)          { $step3Params.ApprovalTokenFile          = $approvalTokenFile }
        if ($mermaidConfigFile)          { $step3Params.MermaidConfigFile          = $mermaidConfigFile }
        if ($mermaidPuppeteerConfigFile) { $step3Params.MermaidPuppeteerConfigFile = $mermaidPuppeteerConfigFile }
        if ($preserveTemp)               { $step3Params.PreserveTemp               = $true }
        Print-ScriptInvocation -ScriptPath $script -ParamHash $step3Params
        & $script @step3Params
        if ($LASTEXITCODE -ne 0) { throw "Step 3 failed with exit code $LASTEXITCODE" }
    }
}
