# ============================================
# 番号付き Markdown コンテンツを EPUB に変換
# PowerShell スクリプト
# ============================================
# 
# 使用方法:
#   1. このスクリプトを実行
#   2. EPUB を生成
#   3. output フォルダに配置
#

param(
    [string]$projectRoot,
    [string]$outputDir,
    [string]$metadataFile,
    [string]$styleFile,
    [string[]]$Formats = @('epub'),
    [string]$PrintStyleFile,
    [string]$KdpMetadataFile,
    [string]$ChapterDirPattern = '^\d{2}-',
    [string]$ChapterFilePattern = '^\d{2}-.*\.md$',
    [string]$CoverFile = '00-COVER.md'
)

# 設定
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $projectRoot) { $projectRoot = Split-Path -Parent $scriptDir }
if (-not $outputDir) { $outputDir = Join-Path $scriptDir "output" }
if (-not $metadataFile) { $metadataFile = Join-Path $scriptDir "metadata.yaml" }
if (-not $styleFile) { $styleFile = Join-Path $scriptDir "style.css" }
if (-not $PrintStyleFile) { $PrintStyleFile = Join-Path $scriptDir "print.css" }
if (-not $Formats -or $Formats.Count -eq 0) { $Formats = @('epub') }
$Formats = @(
    $Formats |
        ForEach-Object { $_.ToString().Split(',') } |
        ForEach-Object { $_.Trim().ToLowerInvariant() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique
)

# UTF-8 BOM なしエンコーディング（共通）
$Script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# ============================================
# タイトル解決ユーティリティ
#   フォルダ名/ファイル名スラグを章節タイトルの唯一の決定源にする
# ============================================

function Convert-SlugToTitle {
    param(
        [Parameter(Mandatory=$true)] [string]$Name
    )

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($Name)
    $baseName = $baseName -replace '^\d{2}-', ''
    $baseName = $baseName -replace '\busecase\b', 'use case'
    $baseName = $baseName -replace '[_-]+', ' '
    $baseName = ($baseName -replace '\s+', ' ').Trim()

    if ([string]::IsNullOrWhiteSpace($baseName)) {
        return ""
    }

    $textInfo = (Get-Culture).TextInfo
    $wordOverrides = @{
        'cover' = 'Cover'
        'di' = 'DI'
        'dto' = 'DTO'
        'sns' = 'SNS'
    }
    $lowercaseWords = @('a', 'an', 'and', 'for', 'in', 'of', 'on', 'or', 'the', 'to')

    $words = @()
    $wordIndex = 0
    foreach ($word in $baseName.Split(' ')) {
        if ([string]::IsNullOrWhiteSpace($word)) {
            continue
        }

        $normalizedWord = $word.ToLowerInvariant()
        if ($wordOverrides.ContainsKey($normalizedWord)) {
            $words += $wordOverrides[$normalizedWord]
        }
        elseif ($wordIndex -gt 0 -and $lowercaseWords -contains $normalizedWord) {
            $words += $normalizedWord
        }
        elseif ($word.Length -le 2 -and $word -cmatch '^[A-Za-z]+$') {
            $words += $word.ToUpperInvariant()
        }
        elseif ($word -cmatch '^[A-Z0-9]+$') {
            $words += $word
        }
        else {
            $words += $textInfo.ToTitleCase($normalizedWord)
        }

        $wordIndex += 1
    }

    return ($words -join ' ')
}

function Get-PlainDisplayTitle {
    param(
        [Parameter(Mandatory=$true)] [string]$Name
    )

    $title = Convert-SlugToTitle -Name $Name
    if ([string]::IsNullOrWhiteSpace($title)) {
        $title = [System.IO.Path]::GetFileNameWithoutExtension($Name)
    }

    return $title
}

function Get-NumberedDisplayTitle {
    param(
        [Parameter(Mandatory=$true)] [string]$Name
    )

    $prefix = ''
    if ($Name -match '^(\d{2})-') {
        $prefix = "$($Matches[1]). "
    }

    return "$prefix$(Get-PlainDisplayTitle -Name $Name)"
}

function Get-ChapterReadmePath {
    param(
        [Parameter(Mandatory=$true)] [System.IO.DirectoryInfo]$ChapterDirectory
    )

    $chapterReadmePath = Join-Path $ChapterDirectory.FullName 'README.md'
    if (Test-Path $chapterReadmePath) {
        return $chapterReadmePath
    }

    return $null
}

function Get-BookChapterTitle {
    param(
        [Parameter(Mandatory=$true)] $ChapterEntry
    )

    return Get-PlainDisplayTitle -Name $ChapterEntry.Directory.Name
}

function Get-BookSectionTitle {
    param(
        [Parameter(Mandatory=$true)] [System.IO.FileInfo]$ChapterFile
    )

    return Get-PlainDisplayTitle -Name $ChapterFile.Name
}

function Get-EpubChapterTitle {
    param(
        [Parameter(Mandatory=$true)] $ChapterEntry
    )

    return Get-PlainDisplayTitle -Name $ChapterEntry.Directory.Name
}

function Get-EpubSectionTitle {
    param(
        [Parameter(Mandatory=$true)] [System.IO.FileInfo]$ChapterFile
    )

    return Get-PlainDisplayTitle -Name $ChapterFile.Name
}

function New-AnchorId {
    param(
        [Parameter(Mandatory=$true)] [string]$Prefix,
        [Parameter(Mandatory=$true)] [string[]]$Segments
    )

    $normalizedSegments = @()
    foreach ($segment in $Segments) {
        if ([string]::IsNullOrWhiteSpace($segment)) {
            continue
        }

        $normalizedSegment = $segment.ToLowerInvariant()
        $normalizedSegment = $normalizedSegment -replace '\.md$', ''
        $normalizedSegment = $normalizedSegment -replace '[^a-z0-9]+', '-'
        $normalizedSegment = $normalizedSegment.Trim('-')

        if (-not [string]::IsNullOrWhiteSpace($normalizedSegment)) {
            $normalizedSegments += $normalizedSegment
        }
    }

    if ($normalizedSegments.Count -eq 0) {
        $normalizedSegments = @([System.Guid]::NewGuid().ToString('N'))
    }

    return "$Prefix-$($normalizedSegments -join '-')"
}

function Get-CoverAnchorId {
    return New-AnchorId -Prefix 'cover' -Segments @('00-COVER')
}

function Get-ChapterAnchorId {
    param(
        [Parameter(Mandatory=$true)] $ChapterEntry
    )

    return New-AnchorId -Prefix 'chapter' -Segments @($ChapterEntry.Directory.Name)
}

function Get-SectionAnchorId {
    param(
        [Parameter(Mandatory=$true)] [System.IO.FileInfo]$ChapterFile
    )

    return New-AnchorId -Prefix 'section' -Segments @((Split-Path -Leaf $ChapterFile.DirectoryName), $ChapterFile.BaseName)
}

function Get-NormalizedPathKey {
    param(
        [Parameter(Mandatory=$true)] [string]$Path
    )

    return $Path.TrimEnd([char[]]@('\', '/')).ToLowerInvariant()
}

function New-BookLinkMap {
    param(
        [Parameter(Mandatory=$true)] [array]$ChapterEntries,
        [Parameter(Mandatory=$true)] [string]$CoverPath
    )

    $linkMap = @{}
    if (Test-Path $CoverPath) {
        $linkMap[(Get-NormalizedPathKey -Path (Resolve-Path $CoverPath -ErrorAction Stop).ProviderPath)] = "#$(Get-CoverAnchorId)"
    }

    foreach ($chapter in $ChapterEntries) {
        $chapterAnchor = "#$(Get-ChapterAnchorId -ChapterEntry $chapter)"
        $linkMap[(Get-NormalizedPathKey -Path $chapter.Directory.FullName)] = $chapterAnchor

        $chapterReadmePath = Get-ChapterReadmePath -ChapterDirectory $chapter.Directory
        if ($chapterReadmePath) {
            $linkMap[(Get-NormalizedPathKey -Path (Resolve-Path $chapterReadmePath -ErrorAction Stop).ProviderPath)] = $chapterAnchor
        }

        foreach ($chapterFile in $chapter.Files) {
            $linkMap[(Get-NormalizedPathKey -Path (Resolve-Path $chapterFile.FullName -ErrorAction Stop).ProviderPath)] = "#$(Get-SectionAnchorId -ChapterFile $chapterFile)"
        }
    }

    return $linkMap
}

function Resolve-LocalLinkPath {
    param(
        [Parameter(Mandatory=$true)] [string]$SourcePath,
        [Parameter(Mandatory=$true)] [string]$LinkTarget
    )

    if ([string]::IsNullOrWhiteSpace($LinkTarget) -or $LinkTarget.StartsWith('#')) {
        return $null
    }

    if ($LinkTarget -match '^(?:https?|mailto|tel):') {
        return $null
    }

    $pathPart = $LinkTarget
    if ($LinkTarget -match '^(?<path>[^#]+)#.+$') {
        $pathPart = $Matches['path']
    }

    if ([string]::IsNullOrWhiteSpace($pathPart)) {
        return $null
    }

    $candidatePath = Join-Path (Split-Path -Parent $SourcePath) $pathPart
    try {
        return (Resolve-Path $candidatePath -ErrorAction Stop).ProviderPath
    } catch {
        return $null
    }
}

function Rewrite-MarkdownLinks {
    param(
        [Parameter(Mandatory=$true)] [AllowEmptyString()] [string]$Line,
        [Parameter(Mandatory=$true)] [string]$SourcePath,
        [Parameter(Mandatory=$true)] [hashtable]$LinkMap
    )

    return [System.Text.RegularExpressions.Regex]::Replace(
        $Line,
        '(?<!!)\[(?<label>[^\]]+)\]\((?<target>[^)]+)\)',
        [System.Text.RegularExpressions.MatchEvaluator]{
            param($match)

            $targetValue = $match.Groups['target'].Value.Trim()
            if ($targetValue -match '^<(?<inner>.+)>$') {
                $targetValue = $Matches['inner']
            }

            if ($targetValue -match '^(?<url>[^\s]+)\s+".*"$') {
                $targetValue = $Matches['url']
            }

            $resolvedPath = Resolve-LocalLinkPath -SourcePath $SourcePath -LinkTarget $targetValue
            if (-not $resolvedPath) {
                return $match.Value
            }

            $anchorTarget = $LinkMap[(Get-NormalizedPathKey -Path $resolvedPath)]
            if (-not $anchorTarget) {
                return $match.Value
            }

            return "[$($match.Groups['label'].Value)]($anchorTarget)"
        }
    )
}

function Shift-MarkdownHeadingLine {
    param(
        [Parameter(Mandatory=$true)] [string]$Line
    )

    if ($Line -notmatch '^(?<indent>\s*)(?<markers>#{1,6})(?<spacing>\s+)(?<title>.+)$') {
        return $Line
    }

    $shiftedLevel = [Math]::Min(6, $Matches['markers'].Length + 1)
    $shiftedMarkers = '#' * $shiftedLevel
    return "$($Matches['indent'])$shiftedMarkers$($Matches['spacing'])$($Matches['title'])"
}

function Get-SectionBodyLines {
    param(
        [Parameter(Mandatory=$true)] [string]$Path,
        [Parameter(Mandatory=$true)] [hashtable]$LinkMap
    )

    $sourceLines = Get-Content -Path $Path -Encoding UTF8
    $bodyLines = New-Object 'System.Collections.Generic.List[string]'
    $removedFirstHeading = $false
    $insideFence = $false

    foreach ($line in $sourceLines) {
        if ($line -match '^\s*(`{3,}|~{3,})') {
            $insideFence = -not $insideFence
            $bodyLines.Add($line)
            continue
        }

        if (-not $insideFence -and -not $removedFirstHeading -and $line -match '^\s*#\s+') {
            $removedFirstHeading = $true
            continue
        }

        if (-not $insideFence -and $line -match '^\s*#{2,6}\s+') {
            $line = Shift-MarkdownHeadingLine -Line $line
        }

        if (-not $insideFence) {
            $line = Rewrite-MarkdownLinks -Line $line -SourcePath $Path -LinkMap $LinkMap
        }

        $bodyLines.Add($line)
    }

    return @($bodyLines.ToArray())
}

function Get-CoverBodyLines {
    param(
        [Parameter(Mandatory=$true)] [string]$Path,
        [Parameter(Mandatory=$true)] [hashtable]$LinkMap
    )

    $sourceLines = Get-Content -Path $Path -Encoding UTF8
    $bodyLines = New-Object 'System.Collections.Generic.List[string]'
    $insideFence = $false

    foreach ($line in $sourceLines) {
        if ($line -match '^\s*(`{3,}|~{3,})') {
            $insideFence = -not $insideFence
            $bodyLines.Add($line)
            continue
        }

        # Cover の下位見出しは TOC 汚染を避けるため段落化する。
        if (-not $insideFence -and $line -match '^\s*#{2,6}\s+(?<title>.+)$') {
            $line = "**$($Matches['title'])**"
        }

        if (-not $insideFence) {
            $line = Rewrite-MarkdownLinks -Line $line -SourcePath $Path -LinkMap $LinkMap
        }

        $bodyLines.Add($line)
    }

    return @($bodyLines.ToArray())
}

function New-BookManuscript {
    param(
        [Parameter(Mandatory=$true)] [string]$RootPath,
        [Parameter(Mandatory=$true)] [array]$ChapterEntries,
        [Parameter(Mandatory=$true)] [string]$CoverPath
    )

    $manuscriptLines = New-Object 'System.Collections.Generic.List[string]'
    $linkMap = New-BookLinkMap -ChapterEntries $ChapterEntries -CoverPath $CoverPath
    $coverAnchorId = Get-CoverAnchorId

    if (Test-Path $CoverPath) {
        $coverHeadingAssigned = $false
        foreach ($coverLine in (Get-CoverBodyLines -Path $CoverPath -LinkMap $linkMap)) {
            $resolvedCoverLine = Rewrite-MarkdownLinks -Line $coverLine -SourcePath $CoverPath -LinkMap $linkMap
            if (-not $coverHeadingAssigned -and $resolvedCoverLine -match '^\s*#\s+.+$') {
                $resolvedCoverLine = "$resolvedCoverLine {#$coverAnchorId}"
                $coverHeadingAssigned = $true
            }

            $manuscriptLines.Add($resolvedCoverLine)
        }

        if ($manuscriptLines.Count -gt 0 -and $manuscriptLines[$manuscriptLines.Count - 1] -ne '') {
            $manuscriptLines.Add('')
        }
    }

    foreach ($chapter in $ChapterEntries) {
        $chapterTitle = Get-EpubChapterTitle -ChapterEntry $chapter
        $chapterAnchorId = Get-ChapterAnchorId -ChapterEntry $chapter
        $manuscriptLines.Add("# $chapterTitle {#$chapterAnchorId}")
        $manuscriptLines.Add('')

        foreach ($chapterFile in $chapter.Files) {
            $sectionTitle = Get-EpubSectionTitle -ChapterFile $chapterFile
            $sectionAnchorId = Get-SectionAnchorId -ChapterFile $chapterFile
            $manuscriptLines.Add("## $sectionTitle {#$sectionAnchorId}")
            $manuscriptLines.Add('')

            foreach ($bodyLine in (Get-SectionBodyLines -Path $chapterFile.FullName -LinkMap $linkMap)) {
                $manuscriptLines.Add($bodyLine)
            }

            $manuscriptLines.Add('')
        }
    }

    $manuscriptPath = Join-Path ([System.IO.Path]::GetTempPath()) ("clean-architecture.manuscript.$([System.Guid]::NewGuid().ToString('N')).md")
    [System.IO.File]::WriteAllText($manuscriptPath, ($manuscriptLines -join [Environment]::NewLine), $Script:Utf8NoBom)
    Write-Host "🛠 書籍用の一時原稿を生成: $manuscriptPath" -ForegroundColor Green

    return $manuscriptPath
}

function Get-ChapterEntries {
    param(
        [Parameter(Mandatory=$true)] [string]$RootPath,
        [string]$ChapterDirPattern = '^\d{2}-',
        [string]$ChapterFilePattern = '^\d{2}-.*\.md$'
    )

    $chapterDirs = Get-ChildItem -Path $RootPath -Directory |
        Where-Object { $_.Name -match $ChapterDirPattern } |
        Sort-Object Name

    $entries = @()
    foreach ($chapterDir in $chapterDirs) {
        $chapterFiles = Get-ChildItem -Path $chapterDir.FullName -File -Filter '*.md' |
            Where-Object { $_.Name -match $ChapterFilePattern } |
            Sort-Object Name

        $entries += [PSCustomObject]@{
            Directory = $chapterDir
            Files = @($chapterFiles)
        }
    }

    return @($entries)
}

function Get-ConversionFiles {
    param(
        [Parameter(Mandatory=$true)] [string]$RootPath,
        [Parameter(Mandatory=$true)] [array]$ChapterEntries,
        [string]$CoverFile = '00-COVER.md'
    )

    $conversionFiles = @()

    $coverPath = Join-Path $RootPath $CoverFile
    if (Test-Path $coverPath) {
        $conversionFiles += (Resolve-Path $coverPath -ErrorAction Stop).ProviderPath
    }

    foreach ($chapter in $ChapterEntries) {
        foreach ($chapterFile in $chapter.Files) {
            $conversionFiles += (Resolve-Path $chapterFile.FullName -ErrorAction Stop).ProviderPath
        }
    }

    return $conversionFiles
}

function New-ReadmeTocLines {
    param(
        [Parameter(Mandatory=$true)] [array]$ChapterEntries,
        [Parameter(Mandatory=$true)] [string]$CoverPath
    )

    $lines = @('<!-- AUTO-TOC:START -->')

    if (Test-Path $CoverPath) {
        $coverItem = Get-Item $CoverPath
        $coverTitle = Get-PlainDisplayTitle -Name $coverItem.Name
        $lines += "- [$coverTitle](./$($coverItem.Name))"
    }

    foreach ($chapter in $ChapterEntries) {
        $chapterName = $chapter.Directory.Name
        $chapterTitle = Get-PlainDisplayTitle -Name $chapterName
        $lines += "- [$chapterTitle](./$chapterName/)"

        foreach ($chapterFile in $chapter.Files) {
            $fileTitle = Get-PlainDisplayTitle -Name $chapterFile.Name
            $lines += "  - [$fileTitle](./$chapterName/$($chapterFile.Name))"
        }
    }

    $lines += '<!-- AUTO-TOC:END -->'
    return $lines
}

function Update-ReadmeToc {
    param(
        [Parameter(Mandatory=$true)] [string]$ReadmePath,
        [Parameter(Mandatory=$true)] [array]$ChapterEntries,
        [Parameter(Mandatory=$true)] [string]$CoverPath
    )

    if (-not (Test-Path $ReadmePath)) {
        Write-Host "⚠️ README が見つからないため目次更新をスキップ: $ReadmePath" -ForegroundColor Yellow
        return
    }

    $rawReadme = Get-Content -Path $ReadmePath -Raw -Encoding UTF8
    $tocPattern = '(?s)<!-- AUTO-TOC:START -->.*?<!-- AUTO-TOC:END -->'
    if ($rawReadme -notmatch $tocPattern) {
        Write-Host "⚠️ README に AUTO-TOC マーカーがないため目次更新をスキップしました" -ForegroundColor Yellow
        return
    }

    $newTocBlock = (New-ReadmeTocLines -ChapterEntries $ChapterEntries -CoverPath $CoverPath) -join [Environment]::NewLine
    $updatedReadme = [System.Text.RegularExpressions.Regex]::Replace(
        $rawReadme,
        $tocPattern,
        [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $newTocBlock },
        1
    )

    [System.IO.File]::WriteAllText($ReadmePath, $updatedReadme, $Script:Utf8NoBom)
    Write-Host "📝 README の目次を更新: $ReadmePath" -ForegroundColor Green
}

# ============================================
# 前処理・検証ユーティリティ
# ============================================

function Test-ValidPath {
    param(
        [Parameter(Mandatory=$true)] [string]$Path,
        [Parameter(Mandatory=$true)] [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "$Name が空です。"
    }

    $invalidChars = [System.IO.Path]::GetInvalidPathChars()
    if ($Path.IndexOfAny($invalidChars) -ge 0) {
        throw "$Name に不正な文字が含まれています: $Path"
    }

    if (-not (Test-Path $Path)) {
        throw "$Name が見つかりません: $Path"
    }
}

function Convert-SimpleYamlToMap {
    param([string]$Path)

    $result = @{}
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path $Path)) {
        return $result
    }

    $lines = Get-Content -Path $Path -Encoding UTF8
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        $trimmed = $line.Trim()
        if ($trimmed -eq '---' -or $trimmed.StartsWith('#')) { continue }

        if ($line -notmatch '^(?<key>[A-Za-z0-9_-]+)\s*:\s*(?<value>.*)$') {
            continue
        }

        $key = $Matches['key']
        $value = $Matches['value'].Trim()

        if ($value -eq '>' -or $value -eq '|') {
            $buffer = New-Object 'System.Collections.Generic.List[string]'
            while (($i + 1) -lt $lines.Count -and $lines[$i + 1] -match '^\s{2,}.+$') {
                $i += 1
                $buffer.Add($lines[$i].Trim())
            }

            if ($value -eq '>') {
                $result[$key] = ($buffer.ToArray() -join ' ').Trim()
            } else {
                $result[$key] = ($buffer.ToArray() -join [Environment]::NewLine).Trim()
            }
            continue
        }

        $normalizedValue = $value.Trim().Trim('"').Trim("'")
        if (-not [string]::IsNullOrWhiteSpace($normalizedValue)) {
            $result[$key] = $normalizedValue
        }
    }

    return $result
}

function Get-StringValue {
    param(
        [hashtable]$Map,
        [string[]]$Keys,
        [string]$Default = ''
    )

    foreach ($key in $Keys) {
        if (-not $Map.ContainsKey($key)) {
            continue
        }

        $value = $Map[$key]
        if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
            return ([string]$value).Trim()
        }
    }

    return $Default
}

function Format-InvariantNumber {
    param([double]$Value)

    return [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0:0.###}', $Value)
}

function Get-PdfPageCount {
    param([Parameter(Mandatory=$true)] [string]$PdfPath)

    if (-not (Test-Path $PdfPath)) {
        return 0
    }

    $pdfBytes = [System.IO.File]::ReadAllBytes($PdfPath)
    $pdfText = [System.Text.Encoding]::ASCII.GetString($pdfBytes)
    $pageMatches = [System.Text.RegularExpressions.Regex]::Matches($pdfText, '/Type\s*/Page\b')
    if ($pageMatches.Count -gt 0) {
        return $pageMatches.Count
    }

    $countMatch = [System.Text.RegularExpressions.Regex]::Match($pdfText, '/Count\s+(?<count>\d+)')
    if ($countMatch.Success) {
        return [int]$countMatch.Groups['count'].Value
    }

    return 0
}

function Convert-TrimSizeToInches {
    param([string]$TrimSize)

    if ([string]::IsNullOrWhiteSpace($TrimSize)) {
        $normalized = '6in x 9in'
    } else {
        $normalized = $TrimSize.Trim().ToLowerInvariant()
    }

    $normalized = $normalized -replace '×', 'x'
    $normalized = $normalized -replace '”|″|inches|inch', 'in'

    if ($normalized -match '^(?<width>\d+(?:\.\d+)?)\s*mm\s*x\s*(?<height>\d+(?:\.\d+)?)\s*mm$') {
        return [PSCustomObject]@{
            WidthInches = [double]$Matches['width'] / 25.4
            HeightInches = [double]$Matches['height'] / 25.4
        }
    }

    if ($normalized -match '^(?<width>\d+(?:\.\d+)?)\s*(?:in)?\s*x\s*(?<height>\d+(?:\.\d+)?)\s*(?:in)?$') {
        return [PSCustomObject]@{
            WidthInches = [double]$Matches['width']
            HeightInches = [double]$Matches['height']
        }
    }

    throw "Trim size format is not supported: $TrimSize"
}

function Get-SpineWidthPerPage {
    param([string]$PaperHint)

    $normalized = if ([string]::IsNullOrWhiteSpace($PaperHint)) { '' } else { $PaperHint.ToLowerInvariant() }
    if ($normalized -match 'cream') {
        return 0.0025
    }

    if ($normalized -match 'color|premium') {
        return 0.002347
    }

    return 0.002252
}

function Get-CoverLayoutSpec {
    param(
        [string]$KdpMetadataFile,
        [string]$PdfPath
    )

    $kdpMetadata = Convert-SimpleYamlToMap -Path $KdpMetadataFile
    $trimSize = Get-StringValue -Map $kdpMetadata -Keys @('trimSize') -Default '6in x 9in'
    $paperHint = Get-StringValue -Map $kdpMetadata -Keys @('paperType', 'paperColor', 'interiorType', 'inkAndPaperType') -Default 'black & white on white paper'
    $trim = Convert-TrimSizeToInches -TrimSize $trimSize
    $pageCount = Get-PdfPageCount -PdfPath $PdfPath
    $outerMargin = 0.125
    $spineWidth = [Math]::Round(($pageCount * (Get-SpineWidthPerPage -PaperHint $paperHint)), 3)

    return [PSCustomObject]@{
        TrimSizeLabel = $trimSize
        PageCount = $pageCount
        TrimWidthInches = [double]$trim.WidthInches
        TrimHeightInches = [double]$trim.HeightInches
        SpineWidthInches = [double]$spineWidth
        OuterMarginInches = [double]$outerMargin
        TotalWidthInches = [double]([Math]::Round((($trim.WidthInches * 2) + $spineWidth + ($outerMargin * 2)), 3))
        TotalHeightInches = [double]([Math]::Round(($trim.HeightInches + ($outerMargin * 2)), 3))
    }
}

# ============================================
# 変換処理
# ============================================

function Get-PreferredBrowserExecutable {
    $candidates = New-Object 'System.Collections.Generic.List[string]'

    foreach ($name in @('chrome', 'msedge', 'chromium', 'google-chrome')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command -and -not [string]::IsNullOrWhiteSpace($command.Source)) {
            $candidates.Add($command.Source)
        }
    }

    foreach ($pathCandidate in @(
        'C:\Program Files\Google\Chrome\Application\chrome.exe',
        'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe',
        'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
        'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
    )) {
        $candidates.Add($pathCandidate)
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    return $null
}

function Convert-ToPrintHtml {
    param(
        [Parameter(Mandatory=$true)] [string]$ManuscriptPath,
        [Parameter(Mandatory=$true)] [string]$EffectiveMetadataFile,
        [Parameter(Mandatory=$true)] [string]$StyleFile,
        [Parameter(Mandatory=$true)] [string]$PrintStyleFile,
        [Parameter(Mandatory=$true)] [string]$HtmlOutput,
        [bool]$IncludeTableOfContents = $true
    )

    $resourceSeparator = [System.IO.Path]::PathSeparator
    $resourcePaths = @(
        $projectRoot,
        (Join-Path $projectRoot 'images'),
        (Join-Path $projectRoot 'images\mermaid'),
        $scriptDir
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path $_) } | Select-Object -Unique

    $pandocArgs = @(
        $ManuscriptPath,
        '--from=markdown+auto_identifiers',
        '--to=html5',
        "--metadata-file=$EffectiveMetadataFile",
        '--css=style.css',
        '--standalone',
        '--embed-resources',
        "--resource-path=$($resourcePaths -join $resourceSeparator)",
        "--output=$HtmlOutput",
        '--top-level-division=chapter'
    )

    if ($IncludeTableOfContents) {
        $pandocArgs += '--table-of-contents'
    }

    if (Test-Path $PrintStyleFile) {
        $pandocArgs += '--css=print.css'
    }

    & pandoc @pandocArgs
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $HtmlOutput)) {
        throw 'HTML render for PDF generation failed.'
    }
}

function Invoke-BrowserRender {
    param(
        [Parameter(Mandatory=$true)] [ValidateSet('pdf', 'image')] [string]$Mode,
        [Parameter(Mandatory=$true)] [string]$InputHtml,
        [Parameter(Mandatory=$true)] [string]$OutputPath,
        [Parameter(Mandatory=$true)] [string]$BrowserExecutable,
        [Parameter(Mandatory=$true)] [string]$NodeExecutable,
        [int]$Width = 1600,
        [int]$Height = 2400
    )

    $renderScript = Join-Path $scriptDir 'render-html-to-pdf.cjs'
    if (-not (Test-Path $renderScript)) {
        throw "render-html-to-pdf.cjs が見つかりません: $renderScript"
    }

    $renderArgs = @($renderScript, $Mode, $InputHtml, $OutputPath, $BrowserExecutable)
    if ($Mode -eq 'image') {
        $renderArgs += @($Width.ToString(), $Height.ToString())
    }

    & $NodeExecutable @renderArgs
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $OutputPath)) {
        throw "ブラウザベースの描画に失敗しました。mode=$Mode output=$OutputPath"
    }
}

function Convert-ImageToJpeg {
    param(
        [Parameter(Mandatory=$true)] [string]$InputPath,
        [Parameter(Mandatory=$true)] [string]$OutputPath,
        [int]$Quality = 90
    )

    Add-Type -AssemblyName System.Drawing
    Remove-Item -Path $OutputPath -Force -ErrorAction SilentlyContinue

    $image = $null
    try {
        $image = [System.Drawing.Image]::FromFile($InputPath)
        $jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
            Where-Object { $_.MimeType -eq 'image/jpeg' } |
            Select-Object -First 1

        if ($null -ne $jpegCodec) {
            $encoder = [System.Drawing.Imaging.Encoder]::Quality
            $encoderParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
            $encoderParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter($encoder, [long]$Quality)
            $image.Save($OutputPath, $jpegCodec, $encoderParams)
        } else {
            $image.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Jpeg)
        }
    } finally {
        if ($null -ne $image) {
            $image.Dispose()
        }
    }

    if (-not (Test-Path $OutputPath)) {
        throw "JPEG 変換に失敗しました: $OutputPath"
    }
}

function New-CoverPdfHtml {
    param(
        [Parameter(Mandatory=$true)] [string]$ImagePath,
        [Parameter(Mandatory=$true)] [string]$HtmlOutput,
        [Parameter(Mandatory=$true)] [double]$PageWidthInches,
        [Parameter(Mandatory=$true)] [double]$PageHeightInches,
        [Parameter(Mandatory=$true)] [double]$TrimWidthInches,
        [Parameter(Mandatory=$true)] [double]$TrimHeightInches,
        [Parameter(Mandatory=$true)] [double]$SpineWidthInches,
        [double]$OuterMarginInches = 0.125,
        [string]$DocumentTitle = 'Cover'
    )

    $imageFileName = [System.IO.Path]::GetFileName($ImagePath)
    $safeTitle = [System.Net.WebUtility]::HtmlEncode($DocumentTitle)
    $pageWidthCss = Format-InvariantNumber -Value $PageWidthInches
    $pageHeightCss = Format-InvariantNumber -Value $PageHeightInches
    $trimWidthCss = Format-InvariantNumber -Value $TrimWidthInches
    $trimHeightCss = Format-InvariantNumber -Value $TrimHeightInches
    $outerMarginCss = Format-InvariantNumber -Value $OuterMarginInches
    $spineWidthCss = Format-InvariantNumber -Value $SpineWidthInches
    $frontLeftCss = Format-InvariantNumber -Value ($OuterMarginInches + $TrimWidthInches + $SpineWidthInches)
    $spineLeftCss = Format-InvariantNumber -Value ($OuterMarginInches + $TrimWidthInches)

    $html = @"
<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="utf-8" />
<title>$safeTitle</title>
<style>
@page {
    size: ${pageWidthCss}in ${pageHeightCss}in;
    margin: 0;
}
html, body {
    margin: 0;
    padding: 0;
    width: ${pageWidthCss}in;
    height: ${pageHeightCss}in;
    background: #ffffff;
}
body {
    overflow: hidden;
}
.cover-sheet {
    position: relative;
    width: ${pageWidthCss}in;
    height: ${pageHeightCss}in;
    background: #ffffff;
}
.back-panel {
    position: absolute;
    left: ${outerMarginCss}in;
    top: ${outerMarginCss}in;
    width: ${trimWidthCss}in;
    height: ${trimHeightCss}in;
    background: #ffffff;
}
.spine-panel {
    position: absolute;
    left: ${spineLeftCss}in;
    top: ${outerMarginCss}in;
    width: ${spineWidthCss}in;
    height: ${trimHeightCss}in;
    background: #ffffff;
}
.front-panel {
    position: absolute;
    left: ${frontLeftCss}in;
    top: ${outerMarginCss}in;
    width: ${trimWidthCss}in;
    height: ${trimHeightCss}in;
    background: #ffffff;
    display: flex;
    align-items: stretch;
    justify-content: stretch;
}
.front-panel img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    object-position: center center;
    display: block;
    background: #ffffff;
}
</style>
</head>
<body>
    <div class="cover-sheet">
        <div class="back-panel" aria-hidden="true"></div>
        <div class="spine-panel" aria-hidden="true"></div>
        <div class="front-panel">
            <img src="$imageFileName" alt="Cover preview" />
        </div>
    </div>
</body>
</html>
"@

    [System.IO.File]::WriteAllText($HtmlOutput, $html, $Script:Utf8NoBom)
}

function New-CoverArtifacts {
    param(
        [Parameter(Mandatory=$true)] [string]$ManuscriptPath,
        [Parameter(Mandatory=$true)] [string]$CoverPath,
        [Parameter(Mandatory=$true)] [string]$EffectiveMetadataFile,
        [Parameter(Mandatory=$true)] [string]$StyleFile,
        [Parameter(Mandatory=$true)] [string]$PrintStyleFile,
        [Parameter(Mandatory=$true)] [string]$CoverPdfOutput,
        [Parameter(Mandatory=$true)] [string]$CoverJpgOutput,
        [Parameter(Mandatory=$true)] [string]$PdfPath,
        [string]$KdpMetadataFile
    )

    Write-Host '🖼 表紙アセットを生成中...' -ForegroundColor Cyan

    $browserExecutable = Get-PreferredBrowserExecutable
    if (-not $browserExecutable) {
        throw 'Chrome または Edge が見つかりません。表紙アセット生成にはいずれかのブラウザが必要です。'
    }

    $nodeCommand = Get-Command node -ErrorAction SilentlyContinue
    if (-not $nodeCommand) {
        throw 'Node.js が見つかりません。表紙アセット生成には Node.js が必要です。'
    }

    $coverSourcePath = $CoverPath
    if (-not (Test-Path $coverSourcePath)) {
        Write-Warning "Cover source not found: $CoverPath. Falling back to the assembled manuscript."
        $coverSourcePath = $ManuscriptPath
    }

    $coverLayout = Get-CoverLayoutSpec -KdpMetadataFile $KdpMetadataFile -PdfPath $PdfPath
    Write-Host ("ℹ cover.pdf size target: {0}in x {1}in (trim={2}, pages={3}, spine={4}in)" -f (Format-InvariantNumber -Value $coverLayout.TotalWidthInches), (Format-InvariantNumber -Value $coverLayout.TotalHeightInches), $coverLayout.TrimSizeLabel, $coverLayout.PageCount, (Format-InvariantNumber -Value $coverLayout.SpineWidthInches)) -ForegroundColor DarkCyan

    $coverHtmlOutput = Join-Path $scriptDir ("$projectName.cover.html")
    $coverScreenshotPath = Join-Path $scriptDir ("$projectName.cover.png")
    $coverPdfHtml = Join-Path (Split-Path $CoverJpgOutput -Parent) ("$projectName.cover-sheet.html")

    try {
        Convert-ToPrintHtml -ManuscriptPath $coverSourcePath -EffectiveMetadataFile $EffectiveMetadataFile -StyleFile $StyleFile -PrintStyleFile $PrintStyleFile -HtmlOutput $coverHtmlOutput -IncludeTableOfContents $false
        Invoke-BrowserRender -Mode 'image' -InputHtml $coverHtmlOutput -OutputPath $coverScreenshotPath -BrowserExecutable $browserExecutable -NodeExecutable $nodeCommand.Source -Width 1600 -Height 2400
        Convert-ImageToJpeg -InputPath $coverScreenshotPath -OutputPath $CoverJpgOutput -Quality 92
        New-CoverPdfHtml -ImagePath $CoverJpgOutput -HtmlOutput $coverPdfHtml -PageWidthInches $coverLayout.TotalWidthInches -PageHeightInches $coverLayout.TotalHeightInches -TrimWidthInches $coverLayout.TrimWidthInches -TrimHeightInches $coverLayout.TrimHeightInches -SpineWidthInches $coverLayout.SpineWidthInches -OuterMarginInches $coverLayout.OuterMarginInches -DocumentTitle "$projectName cover"
        Invoke-BrowserRender -Mode 'pdf' -InputHtml $coverPdfHtml -OutputPath $CoverPdfOutput -BrowserExecutable $browserExecutable -NodeExecutable $nodeCommand.Source
        Write-Host "✅ 表紙アセット作成成功: $CoverPdfOutput / $CoverJpgOutput" -ForegroundColor Green
    } finally {
        Remove-Item -Path $coverHtmlOutput, $coverScreenshotPath, $coverPdfHtml -Force -ErrorAction SilentlyContinue
    }
}

function Convert-ToPdf {
    param(
        [Parameter(Mandatory=$true)] [string]$ManuscriptPath,
        [Parameter(Mandatory=$true)] [string]$EffectiveMetadataFile,
        [Parameter(Mandatory=$true)] [string]$StyleFile,
        [Parameter(Mandatory=$true)] [string]$PrintStyleFile,
        [Parameter(Mandatory=$true)] [string]$PdfOutput,
        [Parameter(Mandatory=$true)] [string]$CoverPath,
        [Parameter(Mandatory=$true)] [string]$CoverPdfOutput,
        [Parameter(Mandatory=$true)] [string]$CoverJpgOutput,
        [string]$KdpMetadataFile
    )

    Write-Host '🔄 PDF 形式に変換中...' -ForegroundColor Cyan

    $htmlOutput = Join-Path $scriptDir ("$projectName.print.html")
    try {
        Convert-ToPrintHtml -ManuscriptPath $ManuscriptPath -EffectiveMetadataFile $EffectiveMetadataFile -StyleFile $StyleFile -PrintStyleFile $PrintStyleFile -HtmlOutput $htmlOutput -IncludeTableOfContents $true

        $browserExecutable = Get-PreferredBrowserExecutable
        if (-not $browserExecutable) {
            throw 'Chrome または Edge が見つかりません。PDF 生成にはいずれかのブラウザが必要です。'
        }

        $nodeCommand = Get-Command node -ErrorAction SilentlyContinue
        if (-not $nodeCommand) {
            throw 'Node.js が見つかりません。PDF 生成には Node.js が必要です。'
        }

        Invoke-BrowserRender -Mode 'pdf' -InputHtml $htmlOutput -OutputPath $PdfOutput -BrowserExecutable $browserExecutable -NodeExecutable $nodeCommand.Source
        Write-Host "✅ PDF 作成成功: $PdfOutput" -ForegroundColor Green

        New-CoverArtifacts -ManuscriptPath $ManuscriptPath -CoverPath $CoverPath -EffectiveMetadataFile $EffectiveMetadataFile -StyleFile $StyleFile -PrintStyleFile $PrintStyleFile -CoverPdfOutput $CoverPdfOutput -CoverJpgOutput $CoverJpgOutput -PdfPath $PdfOutput -KdpMetadataFile $KdpMetadataFile
    } catch {
        Write-Host "❌ PDF 作成エラー: $_" -ForegroundColor Red
    } finally {
        Remove-Item -Path $htmlOutput -Force -ErrorAction SilentlyContinue
    }

    Write-Host ''
}

function Convert-ToEpub {
    param(
        [Parameter(Mandatory=$true)] [string]$ManuscriptPath,
        [Parameter(Mandatory=$true)] [string]$EffectiveMetadataFile,
        [Parameter(Mandatory=$true)] [string]$StyleFile,
        [Parameter(Mandatory=$true)] [string]$EpubOutput
    )

    Write-Host "🔄 EPUB 形式に変換中..." -ForegroundColor Cyan

    # 目次深度は metadata.yaml (toc-depth) を使用して一元管理する
    $resourceSeparator = [System.IO.Path]::PathSeparator
    $resourcePaths = @(
        $projectRoot,
        (Join-Path $projectRoot 'images'),
        (Join-Path $projectRoot 'images\mermaid'),
        $scriptDir
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path $_) } | Select-Object -Unique

    $pandocArgs = @(
        $ManuscriptPath,
        "--from=markdown+auto_identifiers",
        "--to=epub3",
        "--metadata-file=$EffectiveMetadataFile",
        "--css=$StyleFile",
        "--resource-path=$($resourcePaths -join $resourceSeparator)",
        "--standalone",
        "--output=$EpubOutput",
        "--top-level-division=chapter",
        "--table-of-contents"
    )

    try {
        & pandoc @pandocArgs
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ EPUB 作成成功: $EpubOutput" -ForegroundColor Green
        } else {
            Write-Host "❌ EPUB 作成失敗 (エラーコード: $LASTEXITCODE)" -ForegroundColor Red
        }
    } catch {
        Write-Host "❌ EPUB 作成エラー: $_" -ForegroundColor Red
    }

    Write-Host ""
}

# ============================================
# エントリポイント
# ============================================

function Main {
    # 出力フォルダを作成
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir | Out-Null
        Write-Host "📁 出力フォルダを作成: $outputDir" -ForegroundColor Green
    }

    # フォルダ/ファイル構造から変換対象を生成
    $chapterEntries = Get-ChapterEntries -RootPath $projectRoot -ChapterDirPattern $ChapterDirPattern -ChapterFilePattern $ChapterFilePattern
    $files = Get-ConversionFiles -RootPath $projectRoot -ChapterEntries $chapterEntries -CoverFile $CoverFile

    if ($files.Count -eq 0) {
        Write-Host "❌ エラー: 変換対象の markdown ファイルが見つかりません" -ForegroundColor Red
        exit 1
    }

    # README の自動 TOC 更新は行わない
    $coverPath = Join-Path $projectRoot $CoverFile

    $manuscriptPath = New-BookManuscript -RootPath $projectRoot -ChapterEntries $chapterEntries -CoverPath $coverPath

    # metadata.yaml が cover-image: null などを含むとPandocがopenBinaryFileエラーを出す場合があるためクリーンコピーを作成
    $effectiveMetadataFile = $metadataFile
    $hasNullCover = Select-String -Path $metadataFile -Pattern '^\s*(cover-image|epub-cover-image):\s*null\s*$' -Quiet
    if ($hasNullCover) {
        $cleanLines = Get-Content $metadataFile | Where-Object { $_ -notmatch '^\s*(cover-image|epub-cover-image):\s*null\s*$' }
        $effectiveMetadataFile = Join-Path $outputDir "metadata.cleaned.yaml"
        $cleanLines | Set-Content -Path $effectiveMetadataFile -Encoding UTF8
        Write-Host "ℹ️ メタデータファイルをクリーンコピーして処理: $effectiveMetadataFile" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "📚 処理するファイル数: $($files.Count)" -ForegroundColor Cyan
    Write-Host ""

    # Pandoc がインストールされているかチェック
    $pandocPath = Get-Command pandoc -ErrorAction SilentlyContinue
    if (-not $pandocPath) {
        Write-Host "❌ エラー: Pandoc がインストールされていません" -ForegroundColor Red
        Write-Host "   以下から Pandoc をダウンロードしてください:" -ForegroundColor Yellow
        Write-Host "   https://pandoc.org/installing.html" -ForegroundColor Cyan
        exit 1
    }

    try {
        Test-ValidPath -Path $metadataFile -Name 'metadata.yaml'
        Test-ValidPath -Path $styleFile -Name 'style.css'
        if ($Formats -contains 'pdf') {
            Test-ValidPath -Path $PrintStyleFile -Name 'print.css'
            Test-ValidPath -Path (Join-Path $scriptDir 'render-html-to-pdf.cjs') -Name 'render-html-to-pdf.cjs'
        }
        $files | ForEach-Object { Test-ValidPath -Path $_ -Name "入力ファイル" }
        Test-ValidPath -Path $manuscriptPath -Name '一時原稿'
    } catch {
        Write-Host "❌ ファイルパス検証エラー: $_" -ForegroundColor Red
        exit 1
    }

    Write-Host "✅ Pandoc を検出しました: $(pandoc --version | Select-Object -First 1)" -ForegroundColor Green
    Write-Host ""

    # 動的にプロジェクト名を取得して出力ファイル名を生成
    $projectName = (Split-Path -Leaf $projectRoot).ToLowerInvariant()
    $epubOutput = Join-Path $outputDir "$projectName.epub"
    $pdfOutput = Join-Path $outputDir "$projectName.pdf"
    $coverPdfOutput = Join-Path $outputDir 'cover.pdf'
    $coverJpgOutput = Join-Path $outputDir 'cover.jpg'

    if ($Formats -contains 'epub') {
        Convert-ToEpub -ManuscriptPath $manuscriptPath -EffectiveMetadataFile $effectiveMetadataFile -StyleFile $styleFile -EpubOutput $epubOutput
    }

    if ($Formats -contains 'pdf') {
        Convert-ToPdf -ManuscriptPath $manuscriptPath -EffectiveMetadataFile $effectiveMetadataFile -StyleFile $styleFile -PrintStyleFile $PrintStyleFile -PdfOutput $pdfOutput -CoverPath $coverPath -CoverPdfOutput $coverPdfOutput -CoverJpgOutput $coverJpgOutput -KdpMetadataFile $KdpMetadataFile
    }

    # ============================================
    # 完了報告
    # ============================================
    $separator = '=' * 60
    Write-Host $separator -ForegroundColor Cyan
    Write-Host "✅ 変換処理が完了しました" -ForegroundColor Green
    Write-Host $separator -ForegroundColor Cyan

    Write-Host ""
    Write-Host "Generated files:" -ForegroundColor Cyan
    $outputs = @(Get-ChildItem $outputDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.epub', '.pdf', '.jpg') })

    if ($outputs -and $outputs.Count -gt 0) {
        $outputs | ForEach-Object {
            $sizeKB = [math]::Round($_.Length / 1KB, 2)
            $message = "  - {0} ({1} KB)" -f $_.Name, $sizeKB
            Write-Host $message -ForegroundColor Green
        }
    } else {
        Write-Host "  (Check the output folder)" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Output folder: $outputDir" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Review the generated EPUB/PDF contents"
    Write-Host "  2. Validate against VALIDATION_CHECKLIST.md"
    Write-Host ""

    # Open the output folder only for interactive local runs.
    if ($outputs -and -not $env:CI) {
        Write-Host "Open the output folder? (Y/n)" -ForegroundColor Cyan
        $response = Read-Host
        if ($response -ne 'n' -and $response -ne 'N') {
            Invoke-Item $outputDir
        }
    }
}

Main
