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

# 設定
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$outputDir = Join-Path $scriptDir "output"
$metadataFile = Join-Path $scriptDir "metadata.yaml"
$styleFile = Join-Path $scriptDir "style.css"

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

    return Get-NumberedDisplayTitle -Name $ChapterEntry.Directory.Name
}

function Get-EpubSectionTitle {
    param(
        [Parameter(Mandatory=$true)] [System.IO.FileInfo]$ChapterFile
    )

    return Get-NumberedDisplayTitle -Name $ChapterFile.Name
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
        [Parameter(Mandatory=$true)] [string]$RootPath
    )

    $chapterDirs = Get-ChildItem -Path $RootPath -Directory |
        Where-Object { $_.Name -match '^\d{2}-' } |
        Sort-Object Name

    $entries = @()
    foreach ($chapterDir in $chapterDirs) {
        $chapterFiles = Get-ChildItem -Path $chapterDir.FullName -File -Filter '*.md' |
            Where-Object { $_.Name -match '^\d{2}-.*\.md$' } |
            Sort-Object Name

        $entries += [PSCustomObject]@{
            Directory = $chapterDir
            Files = @($chapterFiles)
        }
    }

    return $entries
}

function Get-ConversionFiles {
    param(
        [Parameter(Mandatory=$true)] [string]$RootPath,
        [Parameter(Mandatory=$true)] [array]$ChapterEntries
    )

    $conversionFiles = @()

    $coverPath = Join-Path $RootPath '00-COVER.md'
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
        $coverTitle = Get-NumberedDisplayTitle -Name $coverItem.Name
        $lines += "- [$coverTitle](./$($coverItem.Name))"
    }

    foreach ($chapter in $ChapterEntries) {
        $chapterName = $chapter.Directory.Name
        $chapterTitle = Get-NumberedDisplayTitle -Name $chapterName
        $lines += "- [$chapterTitle](./$chapterName/)"

        foreach ($chapterFile in $chapter.Files) {
            $fileTitle = Get-NumberedDisplayTitle -Name $chapterFile.Name
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

# ============================================
# 変換処理
# ============================================

function Convert-ToEpub {
    param(
        [Parameter(Mandatory=$true)] [string]$ManuscriptPath,
        [Parameter(Mandatory=$true)] [string]$EffectiveMetadataFile,
        [Parameter(Mandatory=$true)] [string]$StyleFile,
        [Parameter(Mandatory=$true)] [string]$EpubOutput
    )

    Write-Host "🔄 EPUB 形式に変換中..." -ForegroundColor Cyan

    # 目次深度は metadata.yaml (toc-depth) を使用して一元管理する
    $pandocArgs = @(
        $ManuscriptPath,
        "--from=markdown+auto_identifiers",
        "--to=epub3",
        "--metadata-file=$EffectiveMetadataFile",
        "--css=$StyleFile",
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
    $chapterEntries = Get-ChapterEntries -RootPath $projectRoot
    $files = Get-ConversionFiles -RootPath $projectRoot -ChapterEntries $chapterEntries

    if ($files.Count -eq 0) {
        Write-Host "❌ エラー: 変換対象の markdown ファイルが見つかりません" -ForegroundColor Red
        exit 1
    }

    # 走査結果と同じソースから README の目次も更新
    $readmePath = Join-Path $projectRoot 'README.md'
    $coverPath = Join-Path $projectRoot '00-COVER.md'
    Update-ReadmeToc -ReadmePath $readmePath -ChapterEntries $chapterEntries -CoverPath $coverPath

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

    Convert-ToEpub -ManuscriptPath $manuscriptPath -EffectiveMetadataFile $effectiveMetadataFile -StyleFile $styleFile -EpubOutput $epubOutput

    # ============================================
    # 完了報告
    # ============================================
    $separator = '=' * 60
    Write-Host $separator -ForegroundColor Cyan
    Write-Host "✅ 変換処理が完了しました" -ForegroundColor Green
    Write-Host $separator -ForegroundColor Cyan

    Write-Host ""
    Write-Host "📦 生成されたファイル:" -ForegroundColor Cyan
    $outputs = @(Get-ChildItem $outputDir -Filter '*.epub' -File -ErrorAction SilentlyContinue)

    if ($outputs -and $outputs.Count -gt 0) {
        $outputs | ForEach-Object {
            $sizeKB = [math]::Round($_.Length / 1KB, 2)
            Write-Host "  ✓ $($_.Name) ($sizeKB KB)" -ForegroundColor Green
        }
    } else {
        Write-Host "  (出力フォルダを確認してください)" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "📂 出力フォルダ: $outputDir" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "📖 次のステップ:" -ForegroundColor Cyan
    Write-Host "  1. EPUB ファイルで内容確認"
    Write-Host "  2. VALIDATION_CHECKLIST.md に沿って構造確認"
    Write-Host ""

    # 出力フォルダをエクスプローラーで開く
    if ($outputs) {
        Write-Host "📂 出力フォルダを開きますか? (Y/n)" -ForegroundColor Cyan
        $response = Read-Host
        if ($response -ne 'n' -and $response -ne 'N') {
            Invoke-Item $outputDir
        }
    }
}

Main
