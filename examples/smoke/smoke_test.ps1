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
    foreach ($editorMarker in @(
        'id="gridToggle"',
        'id="previewToggle"',
        'id="snapThreshold"',
        'function scheduleDraft',
        'function snapBox'
    )) {
        if ($canvasHtml -notlike "*$editorMarker*") {
            throw "HTML canvas is missing the editor assist feature: $editorMarker"
        }
    }

    # Serve mode: the reviewer's edit must round-trip back to disk, and a malformed
    # payload must never overwrite the config.
    $probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $probe.Start()
    $servePort = $probe.LocalEndpoint.Port
    $probe.Stop()

    $serveConfigPath = Join-Path $testRoot 'poster-config.json'
    $reviewedPath = Join-Path $testRoot 'reviewed-config.json'
    $reviewed = Get-Content -Raw -Encoding UTF8 -LiteralPath $serveConfigPath | ConvertFrom-Json
    $reviewed.texts[0].x = 999
    $reviewedBody = $reviewed | ConvertTo-Json -Depth 20

    $serveDraftPath = Join-Path $testRoot 'serve-draft.json'
    $preSave = Get-Content -Raw -Encoding UTF8 -LiteralPath $serveConfigPath | ConvertFrom-Json
    $preSave.texts[0].x = 888
    $preSaveBody = $preSave | ConvertTo-Json -Depth 20

    $poster = Start-Job -ArgumentList "http://localhost:$servePort", $reviewedBody, $preSaveBody, $serveDraftPath -ScriptBlock {
        param($BaseUrl, $Body, $AutosaveBody, $DraftPath)
        for ($attempt = 0; $attempt -lt 60; $attempt++) {
            try { Invoke-WebRequest -Uri "$BaseUrl/" -UseBasicParsing -TimeoutSec 5 | Out-Null; break }
            catch { Start-Sleep -Milliseconds 500 }
        }
        $rejected = $false
        try { Invoke-WebRequest -Uri "$BaseUrl/save" -Method Post -Body 'not json' -ContentType 'application/json' -UseBasicParsing | Out-Null }
        catch { $rejected = $true }
        Invoke-WebRequest -Uri "$BaseUrl/autosave" -Method Post -Body ([Text.Encoding]::UTF8.GetBytes($AutosaveBody)) -ContentType 'application/json' -UseBasicParsing | Out-Null
        if (-not (Test-Path -LiteralPath $DraftPath)) { throw 'Autosave did not write its draft payload.' }
        Invoke-WebRequest -Uri "$BaseUrl/save" -Method Post -Body ([Text.Encoding]::UTF8.GetBytes($Body)) -ContentType 'application/json' -UseBasicParsing | Out-Null
        return $rejected
    }

    & $canvasBuilder -ConfigPath $serveConfigPath -OutputPath (Join-Path $testRoot 'serve-canvas.html') -Serve -Port $servePort -TimeoutMinutes 2 -SaveConfigPath $reviewedPath -DraftPath $serveDraftPath -NoBrowser | Out-Null
    $rejectedGarbage = [bool](Receive-Job -Job $poster -Wait)
    Remove-Job -Job $poster -Force

    if (-not $rejectedGarbage) { throw 'Serve mode accepted a payload that was not valid JSON.' }
    if (-not (Test-Path -LiteralPath $reviewedPath)) { throw 'Serve mode did not write the reviewed config back to disk.' }
    $savedBack = Get-Content -Raw -Encoding UTF8 -LiteralPath $reviewedPath | ConvertFrom-Json
    if ([int]$savedBack.texts[0].x -ne 999) { throw "Serve mode lost the reviewer's edit: x is $($savedBack.texts[0].x)." }
    $untouched = Get-Content -Raw -Encoding UTF8 -LiteralPath $serveConfigPath | ConvertFrom-Json
    if ([int]$untouched.texts[0].x -eq 999) { throw 'Serve mode overwrote the source config despite -SaveConfigPath.' }
    if (Test-Path -LiteralPath $serveDraftPath) { throw 'A completed save left its transient canvas draft behind.' }

    # Autosave must survive the browser tab and be loaded by the next canvas build.
    $draftConfigPath = Join-Path $testRoot 'draft-config.json'
    Copy-Item -LiteralPath $serveConfigPath -Destination $draftConfigPath
    $draftPath = Join-Path $testRoot 'draft-config.canvas-draft.json'
    $draftReviewedPath = Join-Path $testRoot 'draft-reviewed.json'
    $drafted = Get-Content -Raw -Encoding UTF8 -LiteralPath $draftConfigPath | ConvertFrom-Json
    $drafted.texts[0].x = 777
    $draftedBody = $drafted | ConvertTo-Json -Depth 20

    $draftProbe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $draftProbe.Start()
    $draftPort = $draftProbe.LocalEndpoint.Port
    $draftProbe.Stop()
    $draftPoster = Start-Job -ArgumentList "http://localhost:$draftPort", $draftedBody -ScriptBlock {
        param($BaseUrl, $Body)
        for ($attempt = 0; $attempt -lt 60; $attempt++) {
            try { Invoke-WebRequest -Uri "$BaseUrl/" -UseBasicParsing -TimeoutSec 5 | Out-Null; break }
            catch { Start-Sleep -Milliseconds 500 }
        }
        Invoke-WebRequest -Uri "$BaseUrl/autosave" -Method Post -Body ([Text.Encoding]::UTF8.GetBytes($Body)) -ContentType 'application/json' -UseBasicParsing | Out-Null
        Invoke-WebRequest -Uri "$BaseUrl/cancel" -Method Post -UseBasicParsing | Out-Null
    }
    & $canvasBuilder -ConfigPath $draftConfigPath -OutputPath (Join-Path $testRoot 'draft-canvas.html') -Serve -Port $draftPort -TimeoutMinutes 2 -SaveConfigPath $draftReviewedPath -DraftPath $draftPath -NoBrowser | Out-Null
    Receive-Job -Job $draftPoster -Wait | Out-Null
    Remove-Job -Job $draftPoster -Force
    if (-not (Test-Path -LiteralPath $draftPath)) { throw 'Cancel mode discarded the reviewer draft.' }
    $savedDraft = Get-Content -Raw -Encoding UTF8 -LiteralPath $draftPath | ConvertFrom-Json
    if ([int]$savedDraft.texts[0].x -ne 777) { throw 'Autosave lost the reviewer edit.' }

    $reloadCanvasPath = Join-Path $testRoot 'draft-reload-canvas.html'
    & $canvasBuilder -ConfigPath $draftConfigPath -OutputPath $reloadCanvasPath -DraftPath $draftPath | Out-Null
    $reloadHtml = Get-Content -Raw -Encoding UTF8 -LiteralPath $reloadCanvasPath
    $storedDraftMatch = [regex]::Match($reloadHtml, "const storedDraftEncoded='([^']*)'")
    if (-not $storedDraftMatch.Success) { throw 'Reloaded canvas omitted the stored draft slot.' }
    if ([string]::IsNullOrWhiteSpace($storedDraftMatch.Groups[1].Value)) { throw 'Reloaded canvas did not embed the stored draft.' }
    $reloadedDraft = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($storedDraftMatch.Groups[1].Value)) | ConvertFrom-Json
    if ([int]$reloadedDraft.texts[0].x -ne 777) { throw 'Reloaded canvas did not restore the stored draft.' }

    # Detached mode keeps the listener alive independently of the calling command.
    $detachConfigPath = Join-Path $testRoot 'detach-config.json'
    Copy-Item -LiteralPath $serveConfigPath -Destination $detachConfigPath
    $detachReviewedPath = Join-Path $testRoot 'detach-reviewed.json'
    $detachDraftPath = Join-Path $testRoot 'detach-draft.json'
    $detachReadyPath = Join-Path $testRoot 'detach-ready.json'
    $detachResultPath = Join-Path $testRoot 'detach-result.json'
    $detachProbe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $detachProbe.Start()
    $detachPort = $detachProbe.LocalEndpoint.Port
    $detachProbe.Stop()

    $detached = & $canvasBuilder -ConfigPath $detachConfigPath -OutputPath (Join-Path $testRoot 'detach-canvas.html') -Detach -Port $detachPort -TimeoutMinutes 2 -SaveConfigPath $detachReviewedPath -DraftPath $detachDraftPath -ReadyPath $detachReadyPath -ResultPath $detachResultPath -NoBrowser
    if ($detached.Mode -ne 'detached') { throw "Expected detached serve metadata, got mode '$($detached.Mode)'." }
    $deadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath $detachReadyPath)) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path -LiteralPath $detachReadyPath)) { throw 'Detached canvas did not report readiness.' }

    try {
        $detachedEdited = Get-Content -Raw -Encoding UTF8 -LiteralPath $detachConfigPath | ConvertFrom-Json
        $detachedEdited.texts[0].x = 1234
        $detachedBody = $detachedEdited | ConvertTo-Json -Depth 20
        Invoke-WebRequest -Uri "$($detached.Url)save" -Method Post -Body ([Text.Encoding]::UTF8.GetBytes($detachedBody)) -ContentType 'application/json' -UseBasicParsing | Out-Null
        $deadline = (Get-Date).AddSeconds(10)
        while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath $detachResultPath)) { Start-Sleep -Milliseconds 100 }
        if (-not (Test-Path -LiteralPath $detachResultPath)) { throw 'Detached canvas did not return its result.' }
        $detachResult = Get-Content -Raw -Encoding UTF8 -LiteralPath $detachResultPath | ConvertFrom-Json
        if ([string]$detachResult.status -ne 'saved') { throw "Detached result status was '$($detachResult.status)'." }
        if (-not ($detachResult.PSObject.Properties.Name -contains 'changes') -or @($detachResult.changes).Count -ne 1) { throw 'Detached result omitted the machine-readable field changes.' }
        if (-not (Test-Path -LiteralPath $detachReviewedPath)) { throw 'Detached canvas did not write the reviewed config.' }
        $detachedSaved = Get-Content -Raw -Encoding UTF8 -LiteralPath $detachReviewedPath | ConvertFrom-Json
        if ([int]$detachedSaved.texts[0].x -ne 1234) { throw "Detached save lost the reviewer edit: x is $($detachedSaved.texts[0].x)." }
    }
    finally {
        if ($detached.ProcessId -and (Get-Process -Id $detached.ProcessId -ErrorAction SilentlyContinue)) {
            Stop-Process -Id $detached.ProcessId -Force
        }
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
        ServeRoundTrip = 'edit saved back, bad payload rejected'
        EditorAssist = 'snap guides, grid, preview, and autosave controls verified'
        DraftPersistence = 'autosave restored on reload and cleared on final save'
        DetachedServe = 'listener survived command return and saved back'
    } | Format-List
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
