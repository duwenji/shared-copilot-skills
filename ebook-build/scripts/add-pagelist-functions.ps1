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
    $pageNum = 1

    foreach ($xhtmlFile in $xhtmlFiles) {
        $content = Get-Content -Path $xhtmlFile.FullName -Raw -Encoding UTF8
        $matches = [regex]::Matches($content, 'id=[''\"]([^''\">]+)[''\"]')
        $relativeHref = Get-RelativeEpubHref -BaseDirectory $navDirectory -TargetPath $xhtmlFile.FullName

        foreach ($match in $matches) {
            $anchorId = $match.Groups[1].Value
            if (-not [string]::IsNullOrWhiteSpace($anchorId)) {
                $pageLinks += @{
                    Href = "$relativeHref#$anchorId"
                    Number = $pageNum
                }
                $pageNum++
            }
        }
    }

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
        $pageLinks | ForEach-Object { $pageListXml += "        <li><a href=`"$($_.Href)`">$($_.Number)</a></li>`n" }
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
