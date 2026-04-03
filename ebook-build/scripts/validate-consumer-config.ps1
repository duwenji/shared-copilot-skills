[CmdletBinding()]
param(
    [Parameter()]
    [string[]]$RepoRoot = @('.')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ConfigPropertyValue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Config,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $property = $Config.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Resolve-ConfigPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    if ([System.IO.Path]::IsPathRooted($Value)) {
        return $Value
    }

    return (Join-Path $BasePath $Value)
}

$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$checkedConfigs = 0

foreach ($repoRootInput in $RepoRoot) {
    $resolvedRepoRoot = (Resolve-Path $repoRootInput).Path
    $configDir = Join-Path $resolvedRepoRoot '.github/skills-config/ebook-build'

    if (-not (Test-Path $configDir)) {
        $warnings.Add("[$resolvedRepoRoot] ebook-build config directory not found; skipping.")
        continue
    }

    $buildFiles = @(Get-ChildItem -Path $configDir -File -Filter '*.build.json' | Sort-Object Name)
    if ($buildFiles.Count -eq 0) {
        $warnings.Add("[$resolvedRepoRoot] no '*.build.json' files found in $configDir")
        continue
    }

    foreach ($buildFile in $buildFiles) {
        $checkedConfigs += 1
        $configLabel = "$resolvedRepoRoot :: $($buildFile.Name)"

        try {
            $config = Get-Content -Path $buildFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        catch {
            $errors.Add("[$configLabel] invalid JSON: $($_.Exception.Message)")
            continue
        }

        $requiredKeys = @(
            'sourceRoot',
            'outputDir',
            'projectName',
            'metadataFile',
            'chapterDirPattern',
            'chapterFilePattern',
            'coverFile'
        )

        foreach ($key in $requiredKeys) {
            $value = Get-ConfigPropertyValue -Config $config -Name $key
            if ([string]::IsNullOrWhiteSpace([string]$value)) {
                $errors.Add("[$configLabel] missing required key '$key'")
            }
        }

        foreach ($pathKey in @('sourceRoot', 'outputDir', 'metadataFile')) {
            $pathValue = Get-ConfigPropertyValue -Config $config -Name $pathKey
            if ($null -ne $pathValue -and [string]$pathValue -match '\\') {
                $errors.Add("[$configLabel] '$pathKey' uses backslashes. Use forward slashes ('./...') in canonical config.")
            }
        }

        $styleFileValue = Get-ConfigPropertyValue -Config $config -Name 'styleFile'
        if (-not [string]::IsNullOrWhiteSpace([string]$styleFileValue)) {
            $warnings.Add("[$configLabel] styleFile is explicitly set. Prefer omitting it unless a custom stylesheet is required.")
            if ([string]$styleFileValue -match '\\') {
                $warnings.Add("[$configLabel] styleFile uses backslashes. Prefer forward slashes if you keep the override.")
            }
        }

        $metadataFileValue = Get-ConfigPropertyValue -Config $config -Name 'metadataFile'
        if (-not [string]::IsNullOrWhiteSpace([string]$metadataFileValue) -and [string]$metadataFileValue -notmatch '^\./\.github/skills-config/ebook-build/.+\.metadata\.yaml$') {
            $warnings.Add("[$configLabel] metadataFile does not follow the canonical './.github/skills-config/ebook-build/<project>.metadata.yaml' format.")
        }

        $chapterFilePattern = [string](Get-ConfigPropertyValue -Config $config -Name 'chapterFilePattern')
        $chapterDirPattern = [string](Get-ConfigPropertyValue -Config $config -Name 'chapterDirPattern')
        $coverFile = [string](Get-ConfigPropertyValue -Config $config -Name 'coverFile')
        if ($chapterFilePattern -eq '^.*\.md$' -and -not ($chapterDirPattern -eq '^docs$' -and $coverFile -eq 'README.md')) {
            $warnings.Add("[$configLabel] chapterFilePattern is intentionally broad ('^.*\\.md$'). Keep this only for flat docs repositories.")
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$metadataFileValue)) {
            $resolvedMetadataPath = Resolve-ConfigPath -BasePath $resolvedRepoRoot -Value ([string]$metadataFileValue)
            if (-not (Test-Path $resolvedMetadataPath)) {
                $errors.Add("[$configLabel] metadata file not found: $resolvedMetadataPath")
                continue
            }

            $metadataText = Get-Content -Path $resolvedMetadataPath -Raw -Encoding UTF8
            $metadataLabel = "$resolvedRepoRoot :: $([System.IO.Path]::GetFileName($resolvedMetadataPath))"

            if ($metadataText -match '(?m)^author\s*:') {
                $errors.Add("[$metadataLabel] legacy key 'author' found. Use 'creator' instead.")
            }

            if ($metadataText -notmatch '(?m)^creator\s*:') {
                $errors.Add("[$metadataLabel] missing required metadata key 'creator'.")
            }

            if ($metadataText -notmatch '(?m)^language\s*:') {
                $errors.Add("[$metadataLabel] missing required metadata key 'language'.")
            }
            elseif ($metadataText -match '(?m)^language\s*:\s*[a-z]{2}\s*$') {
                $warnings.Add("[$metadataLabel] language uses a bare ISO code. Prefer a BCP 47 tag such as 'ja-JP' or 'en-US'.")
            }

            if ($metadataText -notmatch '(?m)^identifier\s*:') {
                $warnings.Add("[$metadataLabel] missing recommended metadata key 'identifier'.")
            }

            if ($metadataText -notmatch '(?m)^toc-depth\s*:\s*2\s*$') {
                $warnings.Add("[$metadataLabel] missing recommended 'toc-depth: 2' setting.")
            }
        }
    }
}

Write-Host "Checked $checkedConfigs ebook-build config file(s)."

if ($warnings.Count -gt 0) {
    Write-Host ''
    Write-Host 'Warnings:' -ForegroundColor Yellow
    foreach ($warning in $warnings) {
        Write-Host " - $warning" -ForegroundColor Yellow
    }
}

if ($errors.Count -gt 0) {
    Write-Host ''
    Write-Host 'Errors:' -ForegroundColor Red
    foreach ($errorMessage in $errors) {
        Write-Host " - $errorMessage" -ForegroundColor Red
    }
    exit 1
}

Write-Host ''
Write-Host 'Consumer ebook-build config validation passed.' -ForegroundColor Green
