param(
    [Parameter(Mandatory = $true)]
    [string]$ImagePath,

    [string]$ConfigPath = '',

    [string[]]$FontFamily = @(),

    [int]$ExpectedWidth = 2480,

    [int]$ExpectedHeight = 3508,

    [int]$ExpectedDpi = 300,

    [double]$MaxBackgroundLuminanceStdDev = 0.12,

    [string]$ReportPath = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'font_checks.ps1')
. (Join-Path $PSScriptRoot 'layout_checks.ps1')

function Resolve-ConfigPath([string]$Value, [string]$BaseDirectory) {
    if ([System.IO.Path]::IsPathRooted($Value)) {
        return [System.IO.Path]::GetFullPath($Value)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $BaseDirectory $Value))
}

function Convert-HexColor([string]$Value) {
    $hex = $Value.Trim().TrimStart('#')
    if ($hex.Length -eq 6) {
        return [System.Drawing.Color]::FromArgb(
            255,
            [Convert]::ToInt32($hex.Substring(0, 2), 16),
            [Convert]::ToInt32($hex.Substring(2, 2), 16),
            [Convert]::ToInt32($hex.Substring(4, 2), 16)
        )
    }
    if ($hex.Length -eq 8) {
        return [System.Drawing.Color]::FromArgb(
            [Convert]::ToInt32($hex.Substring(0, 2), 16),
            [Convert]::ToInt32($hex.Substring(2, 2), 16),
            [Convert]::ToInt32($hex.Substring(4, 2), 16),
            [Convert]::ToInt32($hex.Substring(6, 2), 16)
        )
    }
    throw "Unsupported color '$Value'. Use #RRGGBB or #AARRGGBB."
}

function Fill-RoundedRectangle(
    [System.Drawing.Graphics]$Graphics,
    [System.Drawing.Brush]$Brush,
    [float]$X,
    [float]$Y,
    [float]$Width,
    [float]$Height,
    [float]$Radius
) {
    if ($Width -le 0 -or $Height -le 0) { throw 'Rounded rectangle dimensions must be greater than zero.' }
    $diameter = [Math]::Min([Math]::Max(1, $Radius * 2), [Math]::Min($Width, $Height))
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    try {
        $path.AddArc($X, $Y, $diameter, $diameter, 180, 90)
        $path.AddArc($X + $Width - $diameter, $Y, $diameter, $diameter, 270, 90)
        $path.AddArc($X + $Width - $diameter, $Y + $Height - $diameter, $diameter, $diameter, 0, 90)
        $path.AddArc($X, $Y + $Height - $diameter, $diameter, $diameter, 90, 90)
        $path.CloseFigure()
        $Graphics.FillPath($Brush, $path)
    }
    finally {
        $path.Dispose()
    }
}

function Get-LinearChannel([byte]$Value) {
    $normalized = $Value / 255.0
    if ($normalized -le 0.04045) { return $normalized / 12.92 }
    return [Math]::Pow((($normalized + 0.055) / 1.055), 2.4)
}

function Get-RelativeLuminance([System.Drawing.Color]$Color) {
    return (0.2126 * (Get-LinearChannel $Color.R)) +
        (0.7152 * (Get-LinearChannel $Color.G)) +
        (0.0722 * (Get-LinearChannel $Color.B))
}

function Get-ContrastRatio([double]$FirstLuminance, [double]$SecondLuminance) {
    $lighter = [Math]::Max($FirstLuminance, $SecondLuminance)
    $darker = [Math]::Min($FirstLuminance, $SecondLuminance)
    return ($lighter + 0.05) / ($darker + 0.05)
}

function Get-EffectiveTextColor([System.Drawing.Color]$TextColor, [System.Drawing.Color]$BackgroundColor) {
    if ($TextColor.A -eq 255) { return $TextColor }
    $alpha = $TextColor.A / 255.0
    return [System.Drawing.Color]::FromArgb(
        255,
        [int](($TextColor.R * $alpha) + ($BackgroundColor.R * (1 - $alpha))),
        [int](($TextColor.G * $alpha) + ($BackgroundColor.G * (1 - $alpha))),
        [int](($TextColor.B * $alpha) + ($BackgroundColor.B * (1 - $alpha)))
    )
}

function Get-TextRegionImageStats(
    [System.Drawing.Bitmap]$BackgroundBitmap,
    [pscustomobject]$Block,
    [double]$DefaultNoiseThreshold
) {
    $id = if ($Block.id) { [string]$Block.id } else { '<unnamed>' }
    $x = [int][Math]::Floor([double]$Block.x)
    $y = [int][Math]::Floor([double]$Block.y)
    $width = [int][Math]::Ceiling([double]$Block.width)
    $height = [int][Math]::Ceiling([double]$Block.height)
    if ($x -lt 0 -or $y -lt 0 -or $width -le 0 -or $height -le 0 -or ($x + $width) -gt $BackgroundBitmap.Width -or ($y + $height) -gt $BackgroundBitmap.Height) {
        throw "Text block '$id' has invalid or out-of-canvas bounds."
    }

    $textColor = Convert-HexColor ([string]$Block.color)
    $sampleStepX = [Math]::Max(1, [int][Math]::Ceiling($width / 120.0))
    $sampleStepY = [Math]::Max(1, [int][Math]::Ceiling($height / 120.0))
    $luminances = [System.Collections.Generic.List[double]]::new()
    $contrasts = [System.Collections.Generic.List[double]]::new()

    for ($sampleY = $y; $sampleY -lt ($y + $height); $sampleY += $sampleStepY) {
        for ($sampleX = $x; $sampleX -lt ($x + $width); $sampleX += $sampleStepX) {
            $backgroundColor = $BackgroundBitmap.GetPixel($sampleX, $sampleY)
            $backgroundLuminance = Get-RelativeLuminance $backgroundColor
            $effectiveTextColor = Get-EffectiveTextColor $textColor $backgroundColor
            $textLuminance = Get-RelativeLuminance $effectiveTextColor
            $luminances.Add($backgroundLuminance)
            $contrasts.Add((Get-ContrastRatio $textLuminance $backgroundLuminance))
        }
    }

    $averageLuminance = ($luminances | Measure-Object -Average).Average
    $sumSquaredDifference = 0.0
    foreach ($value in $luminances) {
        $sumSquaredDifference += [Math]::Pow(($value - $averageLuminance), 2)
    }
    $standardDeviation = [Math]::Sqrt($sumSquaredDifference / [Math]::Max(1, $luminances.Count))
    $averageContrast = ($contrasts | Measure-Object -Average).Average
    $sortedContrasts = @($contrasts | Sort-Object)
    $percentileIndex = [Math]::Min($sortedContrasts.Count - 1, [Math]::Floor($sortedContrasts.Count * 0.10))
    $tenthPercentileContrast = $sortedContrasts[$percentileIndex]

    $style = if ($Block.style) { [string]$Block.style } else { 'Regular' }
    $family = [string]$Block.fontFamily
    $looksHeavy = $style -match 'Bold' -or $family -match '(?i)Black|Heavy|W9|W12|粗|特黑|超黑'
    $isLargeText = ([double]$Block.size -ge 75) -or ($looksHeavy -and [double]$Block.size -ge 58)
    $minimumContrast = if ($isLargeText) { 3.0 } else { 4.5 }
    $noiseThreshold = if ($Block.maxBackgroundLuminanceStdDev) { [double]$Block.maxBackgroundLuminanceStdDev } else { $DefaultNoiseThreshold }

    return [pscustomobject]@{
        Id = $id
        Samples = $luminances.Count
        AverageBackgroundLuminance = [Math]::Round($averageLuminance, 3)
        BackgroundLuminanceStdDev = [Math]::Round($standardDeviation, 3)
        AverageContrast = [Math]::Round($averageContrast, 2)
        TenthPercentileContrast = [Math]::Round($tenthPercentileContrast, 2)
        MinimumContrast = $minimumContrast
        ContrastPass = $tenthPercentileContrast -ge $minimumContrast
        NoiseThreshold = $noiseThreshold
        BackgroundNoiseWarning = $standardDeviation -gt $noiseThreshold
    }
}

$resolvedPath = (Resolve-Path -LiteralPath $ImagePath).Path
$config = $null
$resolvedConfigPath = $null
$baseDirectory = $null
$fontNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($name in @($FontFamily)) {
    if (-not [string]::IsNullOrWhiteSpace($name)) { [void]$fontNames.Add($name) }
}

if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
    $resolvedConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path
    $baseDirectory = Split-Path -Parent $resolvedConfigPath
    $config = Get-Content -Raw -Encoding UTF8 -LiteralPath $resolvedConfigPath | ConvertFrom-Json
    if (-not [string]::IsNullOrWhiteSpace([string]$config.fontFamily)) { [void]$fontNames.Add([string]$config.fontFamily) }
    foreach ($block in @($config.texts)) {
        if ($null -ne $block -and -not [string]::IsNullOrWhiteSpace([string]$block.fontFamily)) { [void]$fontNames.Add([string]$block.fontFamily) }
    }
    if ($config.canvas.width) { $ExpectedWidth = [int]$config.canvas.width }
    if ($config.canvas.height) { $ExpectedHeight = [int]$config.canvas.height }
    if ($config.canvas.dpi) { $ExpectedDpi = [int]$config.canvas.dpi }
}

$fontValidationErrors = [System.Collections.Generic.List[string]]::new()
$resolvedFontBlocks = [System.Collections.Generic.List[string]]::new()
$kinsokuIssues = [System.Collections.Generic.List[string]]::new()
$viewingDistanceIssues = [System.Collections.Generic.List[string]]::new()
$contrastReports = [System.Collections.Generic.List[string]]::new()
$contrastWarnings = [System.Collections.Generic.List[string]]::new()
$noiseWarnings = [System.Collections.Generic.List[string]]::new()

$viewingDistanceConfigured = $null -ne $config -and $null -ne $config.viewingDistanceMeters -and [double]$config.viewingDistanceMeters -gt 0
if ($null -ne $config -and -not $viewingDistanceConfigured) {
    $viewingDistanceIssues.Add('Config must set viewingDistanceMeters greater than zero.')
}

$fontBitmap = [System.Drawing.Bitmap]::new(8, 8)
$fontGraphics = [System.Drawing.Graphics]::FromImage($fontBitmap)
try {
    if ($config) {
        foreach ($block in @($config.texts)) {
            if ($null -eq $block) { continue }
            $id = if ($block.id) { [string]$block.id } else { '<unnamed>' }
            $familyName = if ($block.fontFamily) { [string]$block.fontFamily } else { [string]$config.fontFamily }
            $styleName = if ($block.style) { [string]$block.style } else { 'Regular' }
            try {
                $font = New-VerifiedPosterFont $familyName ([Math]::Max(12, [float]$block.size)) $styleName
                try {
                    Assert-PosterFontGlyphs $fontGraphics $font ([string]$block.text) $id
                    $resolvedFontBlocks.Add("$id=$familyName->$($font.FontFamily.Name)/$styleName")
                }
                finally { $font.Dispose() }
            }
            catch { $fontValidationErrors.Add("$id`: $($_.Exception.Message)") }

            foreach ($issue in @(Get-PosterKinsokuIssues ([string]$block.text) $id)) { $kinsokuIssues.Add($issue) }
            if ($viewingDistanceConfigured) {
                try {
                    $issue = Get-PosterViewingDistanceIssue ([float]$config.viewingDistanceMeters) $block $id
                    if ($issue) { $viewingDistanceIssues.Add($issue) }
                }
                catch { $viewingDistanceIssues.Add("$id`: $($_.Exception.Message)") }
            }
        }
    }
    else {
        foreach ($familyName in $fontNames) {
            try {
                $font = New-VerifiedPosterFont $familyName 12 'Regular'
                try { $resolvedFontBlocks.Add("$familyName->$($font.FontFamily.Name)") }
                finally { $font.Dispose() }
            }
            catch { $fontValidationErrors.Add($_.Exception.Message) }
        }
    }
}
finally {
    $fontGraphics.Dispose()
    $fontBitmap.Dispose()
}

if ($config) {
    $backgroundPath = Resolve-ConfigPath ([string]$config.background) $baseDirectory
    if (-not (Test-Path -LiteralPath $backgroundPath)) { throw "Background not found: $backgroundPath" }
    $analysisBitmap = [System.Drawing.Bitmap]::new($ExpectedWidth, $ExpectedHeight)
    $analysisGraphics = [System.Drawing.Graphics]::FromImage($analysisBitmap)
    try {
        $analysisGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $background = [System.Drawing.Image]::FromFile($backgroundPath)
        try { $analysisGraphics.DrawImage($background, [System.Drawing.Rectangle]::new(0, 0, $ExpectedWidth, $ExpectedHeight)) }
        finally { $background.Dispose() }
        foreach ($shape in @($config.roundedRectangles)) {
            if ($null -eq $shape) { continue }
            $brush = [System.Drawing.SolidBrush]::new((Convert-HexColor ([string]$shape.fill)))
            try { Fill-RoundedRectangle $analysisGraphics $brush ([float]$shape.x) ([float]$shape.y) ([float]$shape.width) ([float]$shape.height) ([float]$shape.radius) }
            finally { $brush.Dispose() }
        }
    }
    finally { $analysisGraphics.Dispose() }

    try {
        foreach ($block in @($config.texts)) {
            if ($null -eq $block) { continue }
            $stats = Get-TextRegionImageStats $analysisBitmap $block $MaxBackgroundLuminanceStdDev
            $contrastReports.Add("$($stats.Id): p10=$($stats.TenthPercentileContrast):1 avg=$($stats.AverageContrast):1 min=$($stats.MinimumContrast):1 noiseSD=$($stats.BackgroundLuminanceStdDev)")
            if (-not $stats.ContrastPass) {
                $contrastWarnings.Add("$($stats.Id) p10 contrast $($stats.TenthPercentileContrast):1 is below $($stats.MinimumContrast):1.")
            }
            if ($stats.BackgroundNoiseWarning) {
                $noiseWarnings.Add("$($stats.Id) background luminance SD $($stats.BackgroundLuminanceStdDev) exceeds $($stats.NoiseThreshold).")
            }
        }
    }
    finally { $analysisBitmap.Dispose() }
}

$image = [System.Drawing.Image]::FromFile($resolvedPath)
try {
    $checks = [ordered]@{
        FileExists = $true
        ConfigProvidedPass = ($null -ne $config)
        Width = $image.Width
        Height = $image.Height
        DpiX = [Math]::Round($image.HorizontalResolution)
        DpiY = [Math]::Round($image.VerticalResolution)
        DimensionsPass = ($image.Width -eq $ExpectedWidth -and $image.Height -eq $ExpectedHeight)
        DpiPass = ([Math]::Round($image.HorizontalResolution) -eq $ExpectedDpi -and [Math]::Round($image.VerticalResolution) -eq $ExpectedDpi)
        DeclaredFonts = @($fontNames) -join '; '
        ResolvedFontBlocks = $resolvedFontBlocks -join '; '
        FontValidationErrors = $fontValidationErrors -join '; '
        FontResolutionAndGlyphsPass = ($fontValidationErrors.Count -eq 0)
        ViewingDistanceMeters = if ($viewingDistanceConfigured) { [double]$config.viewingDistanceMeters } else { '' }
        ViewingDistanceIssues = $viewingDistanceIssues -join '; '
        ViewingDistancePass = ($viewingDistanceIssues.Count -eq 0 -and $viewingDistanceConfigured)
        KinsokuIssues = $kinsokuIssues -join '; '
        KinsokuPass = ($kinsokuIssues.Count -eq 0)
        ContrastReports = $contrastReports -join '; '
        ContrastWarnings = $contrastWarnings -join '; '
        ContrastPass = ($null -ne $config -and $contrastWarnings.Count -eq 0)
        BackgroundNoiseWarnings = $noiseWarnings -join '; '
        BackgroundNoiseHeuristicPass = ($noiseWarnings.Count -eq 0)
        Bytes = (Get-Item -LiteralPath $resolvedPath).Length
        SHA256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedPath).Hash
    }
    $checks['Passed'] = $checks.ConfigProvidedPass -and $checks.DimensionsPass -and $checks.DpiPass -and
        $checks.FontResolutionAndGlyphsPass -and $checks.ViewingDistancePass -and $checks.KinsokuPass -and $checks.ContrastPass

    $report = [pscustomobject]$checks
    if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
        $resolvedReportPath = if ([System.IO.Path]::IsPathRooted($ReportPath)) {
            [System.IO.Path]::GetFullPath($ReportPath)
        }
        elseif ($baseDirectory) {
            [System.IO.Path]::GetFullPath((Join-Path $baseDirectory $ReportPath))
        }
        else {
            [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $ReportPath))
        }
        $reportDirectory = Split-Path -Parent $resolvedReportPath
        if ($reportDirectory) { New-Item -ItemType Directory -Force -Path $reportDirectory | Out-Null }
        $report | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -LiteralPath $resolvedReportPath
    }
    foreach ($warning in $contrastWarnings) { Write-Warning $warning }
    foreach ($warning in $noiseWarnings) { Write-Warning $warning }
    $report | Format-List
    if (-not $checks.Passed) { throw 'Poster verification failed. Review the failed checks above.' }
}
finally {
    $image.Dispose()
}
