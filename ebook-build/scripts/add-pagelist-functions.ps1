# ============================================
# EPUB3 pageList 追加機能
# ============================================

function Get-EpubPackageRoot {
    param([Parameter(Mandatory=$true)] [string]$ExtractedRoot)

    $contentOpf = Get-ChildItem -Path $ExtractedRoot -Recurse -Filter 'content.opf' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($contentOpf) {
        return Split-Path -Parent $contentOpf.FullName
    }

    return $ExtractedRoot
}

function Get-RelativeEpubHref {
    param(
        [Parameter(Mandatory=$true)] [string]$BaseDirectory,
        [Parameter(Mandatory=$true)] [string]$TargetPath
    )

    $basePath = (Resolve-Path $BaseDirectory -ErrorAction Stop).ProviderPath
    if (-not $basePath.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $basePath += [System.IO.Path]::DirectorySeparatorChar
    }

    $targetResolvedPath = (Resolve-Path $TargetPath -ErrorAction Stop).ProviderPath
    $baseUri = [System.Uri]$basePath
    $targetUri = [System.Uri]$targetResolvedPath
    return [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($targetUri).ToString())
}

function Convert-HtmlToPlainText {
    param([AllowNull()] [string]$Html)

    if ([string]::IsNullOrWhiteSpace($Html)) {
        return ''
    }

    $text = [regex]::Replace($Html, '<[^>]+>', ' ')
    $text = [System.Net.WebUtility]::HtmlDecode($text)
    $text = [regex]::Replace($text, '\s+', ' ').Trim()
    return $text
}

function Test-IgnoredAnchorId {
    param([string]$AnchorId)

    if ([string]::IsNullOrWhiteSpace($AnchorId)) {
        return $true
    }

    return $AnchorId -match '^(fn|footnote|note|nav|toc|id_\d+-fn|id_\d+-note)'
}

function Get-HeadingTargetsFromXhtml {
    param([Parameter(Mandatory=$true)] [string]$Content)

    $results = @()

    # Pandoc frequently puts the anchor id on <section> and the visible title in the first heading.
    $sectionPattern = '<section[^>]*id=[''\"]([^''\">]+)[''\"][^>]*>'
    $sectionMatches = [regex]::Matches($Content, $sectionPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    foreach ($sectionMatch in $sectionMatches) {
        $anchorId = $sectionMatch.Groups[1].Value
        if (Test-IgnoredAnchorId -AnchorId $anchorId) {
            continue
        }

        $snippetLength = [Math]::Min(800, $Content.Length - $sectionMatch.Index)
        $snippet = $Content.Substring($sectionMatch.Index, $snippetLength)
        $headingMatch = [regex]::Match($snippet, '<h([1-3])[^>]*>(.*?)</h\1>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if (-not $headingMatch.Success) {
            continue
        }

        $title = Convert-HtmlToPlainText -Html $headingMatch.Groups[2].Value
        if ([string]::IsNullOrWhiteSpace($title)) {
            continue
        }

        $results += @{
            AnchorId = $anchorId
            Title = $title
        }
    }

    if ($results.Count -gt 0) {
        return $results
    }

    $headingPattern = '<h([1-3])([^>]*)>(.*?)</h\1>'
    $matches = [regex]::Matches($Content, $headingPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline)

    foreach ($match in $matches) {
        $attrs = $match.Groups[2].Value
        $innerHtml = $match.Groups[3].Value
        $idMatch = [regex]::Match($attrs, 'id=[''\"]([^''\">]+)[''\"]', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if (-not $idMatch.Success) {
            continue
        }

        $anchorId = $idMatch.Groups[1].Value
        if (Test-IgnoredAnchorId -AnchorId $anchorId) {
            continue
        }

        $title = Convert-HtmlToPlainText -Html $innerHtml
        if ([string]::IsNullOrWhiteSpace($title)) {
            continue
        }

        $results += @{
            AnchorId = $anchorId
            Title = $title
        }
    }

    return $results
}

function Get-FallbackTargetsFromXhtml {
    param([Parameter(Mandatory=$true)] [string]$Content)

    $results = @()
    $matches = [regex]::Matches($Content, 'id=[''\"]([^''\">]+)[''\"]')
    foreach ($match in $matches) {
        $anchorId = $match.Groups[1].Value
        if (Test-IgnoredAnchorId -AnchorId $anchorId) {
            continue
        }

        $results += @{
            AnchorId = $anchorId
            Title = "Section"
        }
    }

    return $results
}

function Get-PageLocationFromExtractedEpub {
    param(
        [Parameter(Mandatory=$true)] [string]$ExtractedRoot,
        [Parameter(Mandatory=$true)] [string]$NavFilePath
    )

    $packageRoot = Get-EpubPackageRoot -ExtractedRoot $ExtractedRoot
    $navDirectory = Split-Path -Parent $NavFilePath
    $xhtmlFiles = @(
        Get-ChildItem -Path $packageRoot -Recurse -Filter '*.xhtml' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -ne $NavFilePath -and $_.Name -notmatch 'nav|toc' } |
            Sort-Object FullName
    )

    Write-Host "  ℹ️  XHTMLファイル: $($xhtmlFiles.Count)個 in $packageRoot" -ForegroundColor Gray

    $pageLinks = @()
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    $pageNum = 1
    $headingTargetCount = 0
    $fallbackTargetCount = 0

    foreach ($xhtmlFile in $xhtmlFiles) {
        $content = Get-Content -Path $xhtmlFile.FullName -Raw -Encoding UTF8
        $relativeHref = Get-RelativeEpubHref -BaseDirectory $navDirectory -TargetPath $xhtmlFile.FullName

        $targets = Get-HeadingTargetsFromXhtml -Content $content
        if ($targets.Count -eq 0) {
            $targets = Get-FallbackTargetsFromXhtml -Content $content
            $fallbackTargetCount += $targets.Count
        } else {
            $headingTargetCount += $targets.Count
        }

        foreach ($target in $targets) {
            $href = "$relativeHref#$($target.AnchorId)"
            if ($seen.Add($href)) {
                $pageLinks += @{
                    Href = $href
                    Number = $pageNum
                    Title = $target.Title
                }
                $pageNum++
            }
        }
    }

    Write-Host "  ℹ️  見出しアンカー: $headingTargetCount / fallback: $fallbackTargetCount" -ForegroundColor Gray
    Write-Host "  ℹ️  抽出ポイント: $($pageLinks.Count)個" -ForegroundColor Gray
    return $pageLinks
}

function Get-PageLocationFromEpub {
    param([Parameter(Mandatory=$true)] [string]$EpubPath)

    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempDir | Out-Null

    try {
        $epubAsZip = $EpubPath -replace '\.epub$', '.zip'
        Copy-Item -Path $EpubPath -Destination $epubAsZip -Force | Out-Null
        Expand-Archive -Path $epubAsZip -DestinationPath $tempDir -Force | Out-Null

        $packageRoot = Get-EpubPackageRoot -ExtractedRoot $tempDir
        $navFile = Get-ChildItem -Path $packageRoot -Recurse -Filter 'nav.xhtml' -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $navFile) {
            return @()
        }

        return Get-PageLocationFromExtractedEpub -ExtractedRoot $tempDir -NavFilePath $navFile.FullName
    } finally {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $epubAsZip) { Remove-Item -Path $epubAsZip -Force -ErrorAction SilentlyContinue }
    }
}

function Add-PageListToEpub {
    param([Parameter(Mandatory=$true)] [string]$EpubPath)

    Write-Host "📖 EPUB3 pageList を追加中..." -ForegroundColor Cyan

    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    try {
        $epubAsZip = $EpubPath -replace '\.epub$', '.zip'
        Copy-Item -Path $EpubPath -Destination $epubAsZip -Force | Out-Null
        Expand-Archive -Path $epubAsZip -DestinationPath $tempDir -Force | Out-Null

        $packageRoot = Get-EpubPackageRoot -ExtractedRoot $tempDir
        $navFile = Get-ChildItem -Path $packageRoot -Recurse -Filter 'nav.xhtml' -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $navFile) {
            Write-Host "⚠️  nav.xhtml未検出 in $packageRoot" -ForegroundColor Yellow
            return
        }

        $pageLinks = Get-PageLocationFromExtractedEpub -ExtractedRoot $tempDir -NavFilePath $navFile.FullName
        if ($pageLinks.Count -eq 0) {
            Write-Host "⚠️  参照ポイント未検出" -ForegroundColor Yellow
            return
        }

        $navContent = Get-Content -Path $navFile.FullName -Raw -Encoding UTF8
        if ($navContent -match 'page-list') {
            Write-Host "ℹ️  pageList既存" -ForegroundColor Green
            return
        }

        $pageListXml = "<nav epub:type=`"page-list`"><h2>ページリスト</h2><ol>`n"
        $pageLinks | ForEach-Object {
            $title = if ([string]::IsNullOrWhiteSpace($_.Title)) { "Section" } else { $_.Title }
            $safeTitle = [System.Security.SecurityElement]::Escape($title)
            $pageListXml += "        <li><a href=`"$($_.Href)`">$($_.Number). $safeTitle</a></li>`n"
        }
        $pageListXml += "    </ol></nav>"

        $updatedNav = $navContent -replace '(</body>)(?!.*</body>)', "$pageListXml`n`$1"
        [System.IO.File]::WriteAllText($navFile.FullName, $updatedNav, $Utf8NoBom)

        Remove-Item -Path $epubAsZip -Force -ErrorAction SilentlyContinue
        Compress-Archive -Path "$tempDir\*" -DestinationPath $epubAsZip -Force | Out-Null
        Remove-Item -Path $EpubPath -Force
        Rename-Item -Path $epubAsZip -NewName (Split-Path -Leaf $EpubPath) -Force -ErrorAction SilentlyContinue

        Write-Host "✅ pageList追加: $($pageLinks.Count)ポイント" -ForegroundColor Green
    } catch {
        Write-Host "❌ pageListエラー: $_" -ForegroundColor Red
    } finally {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $epubAsZip) { Remove-Item -Path $epubAsZip -Force -ErrorAction SilentlyContinue }
    }
}
