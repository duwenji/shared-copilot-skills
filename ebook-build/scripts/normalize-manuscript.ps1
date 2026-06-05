[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ManuscriptPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ManuscriptPath -PathType Leaf)) {
    throw "Manuscript not found: $ManuscriptPath"
}

$lines = [System.Collections.Generic.List[string]]::new()
foreach ($l in (Get-Content -Path $ManuscriptPath -Encoding UTF8)) {
    $lines.Add([string]$l)
}

$out = [System.Collections.Generic.List[string]]::new()
$i = 0

function Test-FrontMatterBody {
    param([string[]]$Body)

    if ($Body.Count -eq 0) { return $false }
    foreach ($line in $Body) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match '^\s*#') { continue }
        if ($line -notmatch '^\s*[A-Za-z0-9_-]+\s*:\s*.+$') {
            return $false
        }
    }
    return $true
}

while ($i -lt $lines.Count) {
    $line = $lines[$i]

    # Remove per-section front matter blocks: --- ... ---
    if ($line -eq '---') {
        $j = $i + 1
        $body = [System.Collections.Generic.List[string]]::new()
        $foundEnd = $false

        while ($j -lt $lines.Count -and ($j - $i) -le 30) {
            if ($lines[$j] -eq '---') {
                $foundEnd = $true
                break
            }
            $body.Add($lines[$j])
            $j++
        }

        if ($foundEnd -and (Test-FrontMatterBody -Body $body.ToArray())) {
            $i = $j + 1
            continue
        }
    }

    # Remove in-page navigation lines from source docs
    if ($line -match '^\s*\[' -and ($line -match '前へ' -or $line -match '次へ')) {
        $i++
        continue
    }

    $out.Add($line)
    $i++
}

# Normalize excessive blank lines
$normalized = [System.Collections.Generic.List[string]]::new()
$blankRun = 0
foreach ($line in $out) {
    if ([string]::IsNullOrWhiteSpace($line)) {
        $blankRun++
        if ($blankRun -le 2) {
            $normalized.Add('')
        }
    }
    else {
        $blankRun = 0
        $normalized.Add($line)
    }
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($ManuscriptPath, (($normalized.ToArray()) -join [Environment]::NewLine).TrimEnd() + [Environment]::NewLine, $utf8NoBom)

Write-Host "Normalized manuscript: $ManuscriptPath" -ForegroundColor Green