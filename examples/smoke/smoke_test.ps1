$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$renderer = Join-Path $repoRoot 'scripts\render_a4_poster.ps1'
$verifier = Join-Path $repoRoot 'scripts\verify_poster.ps1'
$canvasBuilder = Join-Path $repoRoot 'scripts\build_poster_canvas.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("a4-poster-smoke-$([guid]::NewGuid().ToString('N'))")

function Assert-ExpectedRenderFailure([string]$ConfigName, [string]$ExpectedMessage) {
    try {
        & $renderer -ConfigPath (Join-Path $testRoot $ConfigName) | Out-Null
        throw "Expected '$ConfigName' to fail, but it rendered successfully."
    }
    catch {
        if ($_.Exception.Message -notlike "*$ExpectedMessage*") {
            throw "'$ConfigName' failed for the wrong reason: $($_.Exception.Message)"
        }
    }
}

function Invoke-VerifierWithReport(
    [string]$ConfigPath,
    [string]$ImagePath,
    [string]$ReportPath,
    [bool]$ExpectPass
) {
    $failed = $false
    try {
        & $verifier -ImagePath $ImagePath -ConfigPath $ConfigPath -ReportPath $ReportPath | Out-Null
    }
    catch {
        $failed = $true
        if ($ExpectPass) { throw }
        if ($_.Exception.Message -notlike '*Poster verification failed*') {
            throw "Verifier failed for the wrong reason: $($_.Exception.Message)"
        }
    }

    if ($ExpectPass -and $failed) { throw "Expected verifier to pass '$ConfigPath'." }
    if (-not $ExpectPass -and -not $failed) { throw "Expected verifier to reject '$ConfigPath'." }
    if (-not (Test-Path -LiteralPath $ReportPath)) { throw "Verifier did not write report: $ReportPath" }
    return Get-Content -Raw -Encoding UTF8 -LiteralPath $ReportPath | ConvertFrom-Json
}

function Assert-ViewingDistanceMinimum([float]$Distance, [string]$Role, [float]$Expected) {
    $actual = Get-PosterMinimumFontSize $Distance $Role
    if ([Math]::Abs($actual - $Expected) -gt 0.01) {
        throw "Viewing-distance table mismatch for $Distance m $Role. Expected $Expected px, got $actual px."
    }
}

New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
try {
    foreach ($name in @(
        'background.png',
        'poster-config.json',
        'overflow-config.json',
        'missing-font-config.json',
        'low-contrast-config.json',
        'kinsoku-config.json',
        'viewing-distance-config.json'
    )) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $testRoot
    }

    & $renderer -ConfigPath (Join-Path $testRoot 'poster-config.json') | Out-Null
    $validPoster = Join-Path $testRoot 'output\poster.png'
    $validReportPath = Join-Path $testRoot 'output\poster-report.json'
    $validReport = Invoke-VerifierWithReport -ConfigPath (Join-Path $testRoot 'poster-config.json') -ImagePath $validPoster -ReportPath $validReportPath -ExpectPass $true

    if (-not [bool]$validReport.Passed -or -not [bool]$validReport.ContrastPass) {
        throw 'Valid poster did not pass the complete verifier report.'
    }
    if ([string]$validReport.ResolvedFontBlocks -notlike '*Microsoft JhengHei->*' -or [string]$validReport.ResolvedFontBlocks -like '*Microsoft Sans Serif*') {
        throw "English font alias did not resolve to the installed localized family: $($validReport.ResolvedFontBlocks)"
    }

    Add-Type -AssemblyName System.Drawing
    $image = [System.Drawing.Image]::FromFile($validPoster)
    try {
        if ($image.Width -ne 2480 -or $image.Height -ne 3508) {
            throw "Unexpected dimensions: $($image.Width)x$($image.Height)."
        }
        if ([Math]::Round($image.HorizontalResolution) -ne 300 -or [Math]::Round($image.VerticalResolution) -ne 300) {
            throw "Unexpected PNG DPI: $($image.HorizontalResolution)x$($image.VerticalResolution)."
        }
    }
    finally { $image.Dispose() }

    $previewPath = Join-Path $testRoot 'output\poster-preview.jpg'
    $preview = [System.Drawing.Image]::FromFile($previewPath)
    try {
        if ([Math]::Round($preview.HorizontalResolution) -ne 300 -or [Math]::Round($preview.VerticalResolution) -ne 300) {
            throw "Unexpected JPG preview DPI: $($preview.HorizontalResolution)x$($preview.VerticalResolution)."
        }
    }
    finally { $preview.Dispose() }

    $canvasPath = Join-Path $testRoot 'poster-canvas.html'
    & $canvasBuilder -ConfigPath (Join-Path $testRoot 'poster-config.json') -OutputPath $canvasPath | Out-Null
    $canvasHtml = Get-Content -Raw -Encoding UTF8 -LiteralPath $canvasPath
    if ($canvasHtml -notmatch 'white-space:pre;') {
        throw 'HTML canvas allows automatic wrapping instead of preserving explicit line breaks.'
    }
    $fontPayloadMatch = [regex]::Match($canvasHtml, "fonts=decode\('([^']+)'\)")
    if (-not $fontPayloadMatch.Success) { throw 'Could not locate the font payload in the HTML canvas.' }
    $fontJson = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($fontPayloadMatch.Groups[1].Value))
    # Cast, do not wrap: Windows PowerShell 5.1 emits a JSON array as one object,
    # so @(...) would produce a single-element array holding every font name.
    $canvasFonts = [string[]]($fontJson | ConvertFrom-Json)
    if ($canvasFonts -notcontains 'Microsoft JhengHei') {
        throw 'HTML canvas dropped the configured English font alias from its selector.'
    }

    . (Join-Path $repoRoot 'scripts\layout_checks.ps1')
    Assert-ViewingDistanceMinimum 1 'title' 120
    Assert-ViewingDistanceMinimum 1 'body' 50
    Assert-ViewingDistanceMinimum 3 'title' 200
    Assert-ViewingDistanceMinimum 3 'body' 80
    Assert-ViewingDistanceMinimum 5 'title' 280
    Assert-ViewingDistanceMinimum 5 'body' 110

    Assert-ExpectedRenderFailure 'overflow-config.json' 'Text bounds check failed'
    Assert-ExpectedRenderFailure 'missing-font-config.json' 'Font family did not resolve'
    Assert-ExpectedRenderFailure 'kinsoku-config.json' 'Chinese line-break rules failed'
    Assert-ExpectedRenderFailure 'viewing-distance-config.json' 'below the 110 px minimum'

    & $renderer -ConfigPath (Join-Path $testRoot 'low-contrast-config.json') | Out-Null
    $lowContrastReport = Invoke-VerifierWithReport -ConfigPath (Join-Path $testRoot 'low-contrast-config.json') -ImagePath (Join-Path $testRoot 'output\low-contrast.png') -ReportPath (Join-Path $testRoot 'output\low-contrast-report.json') -ExpectPass $false
    if ([bool]$lowContrastReport.ContrastPass -or [string]::IsNullOrWhiteSpace([string]$lowContrastReport.ContrastWarnings)) {
        throw 'Low-contrast fixture failed without a populated contrast failure report.'
    }
    foreach ($checkName in @('DimensionsPass', 'DpiPass', 'FontResolutionAndGlyphsPass', 'ViewingDistancePass', 'KinsokuPass')) {
        if (-not [bool]$lowContrastReport.$checkName) {
            throw "Low-contrast fixture also failed unrelated check '$checkName'."
        }
    }

    $noiseBackgroundPath = Join-Path $testRoot 'noise-background.png'
    $noiseBitmap = [System.Drawing.Bitmap]::new(2480, 3508)
    $noiseBitmap.SetResolution(300, 300)
    $noiseGraphics = [System.Drawing.Graphics]::FromImage($noiseBitmap)
    $noiseBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(140, 140, 140))
    try {
        $noiseGraphics.Clear([System.Drawing.Color]::Black)
        $cell = 80
        for ($y = 0; $y -lt 3508; $y += $cell) {
            for ($x = 0; $x -lt 2480; $x += $cell) {
                if ((($x / $cell) + ($y / $cell)) % 2 -eq 0) {
                    $noiseGraphics.FillRectangle($noiseBrush, $x, $y, $cell, $cell)
                }
            }
        }
        $noiseBitmap.Save($noiseBackgroundPath, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $noiseBrush.Dispose()
        $noiseGraphics.Dispose()
        $noiseBitmap.Dispose()
    }

    $noiseConfig = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $testRoot 'low-contrast-config.json') | ConvertFrom-Json
    $noiseConfig.background = './noise-background.png'
    $noiseConfig.output = './output/noise.png'
    $noiseConfig.texts[0].id = 'intentional-noise-warning'
    $noiseConfig.texts[0].text = '高雜訊背景'
    $noiseConfig.texts[0].color = '#FFFFFF'
    $noiseConfigPath = Join-Path $testRoot 'noise-config.json'
    $noiseConfig | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 -LiteralPath $noiseConfigPath
    & $renderer -ConfigPath $noiseConfigPath | Out-Null
    $noiseReport = Invoke-VerifierWithReport -ConfigPath $noiseConfigPath -ImagePath (Join-Path $testRoot 'output\noise.png') -ReportPath (Join-Path $testRoot 'output\noise-report.json') -ExpectPass $true
    if ([bool]$noiseReport.BackgroundNoiseHeuristicPass -or [string]::IsNullOrWhiteSpace([string]$noiseReport.BackgroundNoiseWarnings)) {
        throw 'High-noise fixture did not produce the expected background-noise warning.'
    }
    if (-not [bool]$noiseReport.ContrastPass) {
        throw 'High-noise fixture should retain sufficient large-text contrast.'
    }

    [pscustomobject]@{
        Passed = $true
        ValidRender = '2480x3508 @ 300 DPI'
        PreviewDpi = '300 DPI'
        LocalizedFontAlias = 'resolved and present in canvas'
        OverflowGuard = 'blocked'
        MissingFontGuard = 'blocked'
        KinsokuGuard = 'blocked'
        ViewingDistanceGuard = '1m/3m/5m table verified'
        ContrastGuard = 'isolated failure verified'
        BackgroundNoise = 'warning without hard failure verified'
    } | Format-List
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
