param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath
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

function Convert-Alignment([string]$Value) {
    $normalized = if ([string]::IsNullOrWhiteSpace($Value)) { 'near' } else { $Value.ToLowerInvariant() }
    switch ($normalized) {
        'near' { return [System.Drawing.StringAlignment]::Near }
        'center' { return [System.Drawing.StringAlignment]::Center }
        'far' { return [System.Drawing.StringAlignment]::Far }
        default { throw "Unsupported alignment '$Value'." }
    }
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
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    try {
        if ($Width -le 0 -or $Height -le 0) {
            throw "Rounded rectangle width and height must be greater than zero. Received ${Width}x${Height}."
        }
        $diameter = [Math]::Min([Math]::Max(1, $Radius * 2), [Math]::Min($Width, $Height))
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

function Get-PosterTextMetrics(
    [System.Drawing.Graphics]$Graphics,
    [System.Drawing.Font]$Font,
    [string]$Text,
    [float]$LineHeight
) {
    $normalized = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    $lines = @($normalized.Split([char]10))
    if ($lines.Count -eq 0) { $lines = @('') }
    $lineList = [System.Collections.Generic.List[string]]::new()
    foreach ($lineValue in $lines) { $lineList.Add([string]$lineValue) }
    $format = [System.Drawing.StringFormat]::GenericTypographic.Clone()
    try {
        $format.FormatFlags = $format.FormatFlags -bor [System.Drawing.StringFormatFlags]::MeasureTrailingSpaces -bor [System.Drawing.StringFormatFlags]::NoWrap -bor [System.Drawing.StringFormatFlags]::NoClip
        $maxWidth = 0.0
        foreach ($line in $lines) {
            if ($line.Length -eq 0) { continue }
            $measured = $Graphics.MeasureString($line, $Font, 100000, $format)
            $maxWidth = [Math]::Max($maxWidth, $measured.Width)
        }
        $lineAdvance = $Font.GetHeight($Graphics) * $LineHeight
        return [pscustomobject]@{
            Lines = $lineList
            Width = [float]$maxWidth
            Height = [float]($lineAdvance * $lines.Count)
            LineAdvance = [float]$lineAdvance
        }
    }
    finally {
        $format.Dispose()
    }
}

function Draw-PosterText(
    [System.Drawing.Graphics]$Graphics,
    [System.Drawing.Font]$Font,
    [System.Drawing.Brush]$Brush,
    [System.Drawing.Brush]$StrokeBrush,
    [float]$StrokeWidth,
    [string]$Text,
    [pscustomobject]$Metrics,
    [System.Drawing.RectangleF]$Bounds,
    [string]$HorizontalAlignment,
    [string]$VerticalAlignment
) {
    $format = [System.Drawing.StringFormat]::GenericTypographic.Clone()
    try {
        $format.FormatFlags = $format.FormatFlags -bor [System.Drawing.StringFormatFlags]::MeasureTrailingSpaces -bor [System.Drawing.StringFormatFlags]::NoWrap -bor [System.Drawing.StringFormatFlags]::NoClip
        $format.Alignment = Convert-Alignment $HorizontalAlignment
        $format.LineAlignment = [System.Drawing.StringAlignment]::Near
        $normalizedVerticalAlignment = if ([string]::IsNullOrWhiteSpace($VerticalAlignment)) { 'near' } else { $VerticalAlignment.ToLowerInvariant() }
        $startY = switch ($normalizedVerticalAlignment) {
            'near' { $Bounds.Y }
            'center' { $Bounds.Y + (($Bounds.Height - $Metrics.Height) / 2) }
            'far' { $Bounds.Bottom - $Metrics.Height }
            default { throw "Unsupported alignment '$VerticalAlignment'." }
        }
        $normalizedText = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
        $drawLines = @($normalizedText.Split([char]10))
        for ($index = 0; $index -lt $drawLines.Count; $index++) {
            $line = [string]$drawLines[$index]
            if ($line.Length -eq 0) { continue }
            $lineY = [float]($startY + ($index * $Metrics.LineAdvance))
            $lineDrawingHeight = [float][Math]::Max($Metrics.LineAdvance, $Bounds.Bottom - $lineY)
            $lineBounds = [System.Drawing.RectangleF]::new(
                $Bounds.X,
                $lineY,
                $Bounds.Width,
                $lineDrawingHeight
            )
            if ($null -ne $StrokeBrush -and $StrokeWidth -gt 0) {
                $strokeSteps = [Math]::Max(16, [int][Math]::Ceiling($StrokeWidth * 2))
                for ($strokeIndex = 0; $strokeIndex -lt $strokeSteps; $strokeIndex++) {
                    $angle = (2.0 * [Math]::PI * $strokeIndex) / $strokeSteps
                    $strokeBounds = [System.Drawing.RectangleF]::new(
                        [float]($lineBounds.X + ([Math]::Cos($angle) * $StrokeWidth)),
                        [float]($lineBounds.Y + ([Math]::Sin($angle) * $StrokeWidth)),
                        $lineBounds.Width,
                        $lineBounds.Height
                    )
                    $Graphics.DrawString($line, $Font, $StrokeBrush, $strokeBounds, $format)
                }
            }
            $Graphics.DrawString($line, $Font, $Brush, $lineBounds, $format)
        }
    }
    finally {
        $format.Dispose()
    }
}

$configFullPath = (Resolve-Path -LiteralPath $ConfigPath).Path
$baseDirectory = Split-Path -Parent $configFullPath
$config = Get-Content -Raw -Encoding UTF8 -LiteralPath $configFullPath | ConvertFrom-Json

$width = if ($config.canvas.width) { [int]$config.canvas.width } else { 2480 }
$height = if ($config.canvas.height) { [int]$config.canvas.height } else { 3508 }
$dpi = if ($config.canvas.dpi) { [int]$config.canvas.dpi } else { 300 }
$backgroundPath = Resolve-ConfigPath ([string]$config.background) $baseDirectory
$outputPath = Resolve-ConfigPath ([string]$config.output) $baseDirectory
$fontFamily = [string]$config.fontFamily
$strictTextBounds = if ($null -eq $config.strictTextBounds) { $true } else { [bool]$config.strictTextBounds }
$viewingDistanceMeters = if ($config.viewingDistanceMeters) { [float]$config.viewingDistanceMeters } else { throw 'Config must set viewingDistanceMeters so minimum type sizes can be verified.' }
if ($viewingDistanceMeters -le 0) { throw 'viewingDistanceMeters must be greater than zero.' }

if (-not (Test-Path -LiteralPath $backgroundPath)) {
    throw "Background not found: $backgroundPath"
}
$configuredFontNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
if (-not [string]::IsNullOrWhiteSpace($fontFamily)) {
    [void]$configuredFontNames.Add($fontFamily)
}
foreach ($block in @($config.texts)) {
    if ($null -ne $block -and -not [string]::IsNullOrWhiteSpace([string]$block.fontFamily)) {
        [void]$configuredFontNames.Add([string]$block.fontFamily)
    }
}
if ($configuredFontNames.Count -eq 0) {
    throw 'No font family is configured. Set top-level fontFamily or a fontFamily on every text block.'
}

$outputDirectory = Split-Path -Parent $outputPath
if ($outputDirectory) {
    New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
}

$bitmap = [System.Drawing.Bitmap]::new($width, $height)
$bitmap.SetResolution($dpi, $dpi)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)

try {
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    $background = [System.Drawing.Image]::FromFile($backgroundPath)
    try {
        $graphics.DrawImage($background, [System.Drawing.Rectangle]::new(0, 0, $width, $height))
    }
    finally {
        $background.Dispose()
    }

    foreach ($shape in @($config.roundedRectangles)) {
        if ($null -eq $shape) { continue }
        $brush = [System.Drawing.SolidBrush]::new((Convert-HexColor ([string]$shape.fill)))
        try {
            Fill-RoundedRectangle $graphics $brush ([float]$shape.x) ([float]$shape.y) ([float]$shape.width) ([float]$shape.height) ([float]$shape.radius)
        }
        finally {
            $brush.Dispose()
        }
    }

    $overflows = [System.Collections.Generic.List[string]]::new()
    $fontResolutions = [System.Collections.Generic.List[string]]::new()
    foreach ($block in @($config.texts)) {
        if ($null -eq $block) { continue }
        $blockFontFamily = if ($block.fontFamily) { [string]$block.fontFamily } else { $fontFamily }
        if ([string]::IsNullOrWhiteSpace($blockFontFamily)) {
            $id = if ($block.id) { [string]$block.id } else { '<unnamed>' }
            throw "No font family configured for text block: $id"
        }
        $id = if ($block.id) { [string]$block.id } else { '<unnamed>' }
        $kinsokuIssues = @(Get-PosterKinsokuIssues ([string]$block.text) $id)
        if ($kinsokuIssues.Count -gt 0) {
            throw "Chinese line-break rules failed:`n$($kinsokuIssues -join "`n")"
        }
        $viewingDistanceIssue = Get-PosterViewingDistanceIssue $viewingDistanceMeters $block $id
        if ($viewingDistanceIssue) { throw $viewingDistanceIssue }
        $bounds = [System.Drawing.RectangleF]::new([float]$block.x, [float]$block.y, [float]$block.width, [float]$block.height)
        if ($bounds.X -lt 0 -or $bounds.Y -lt 0 -or $bounds.Width -le 0 -or $bounds.Height -le 0 -or $bounds.Right -gt $width -or $bounds.Bottom -gt $height) {
            throw "Text block '$id' has invalid or out-of-canvas bounds: x=$($block.x), y=$($block.y), width=$($block.width), height=$($block.height), canvas=${width}x${height}."
        }
        $styleName = if ($block.style) { [string]$block.style } else { 'Regular' }
        $font = New-VerifiedPosterFont $blockFontFamily ([float]$block.size) $styleName
        $brush = [System.Drawing.SolidBrush]::new((Convert-HexColor ([string]$block.color)))
        $strokeWidth = if ($null -ne $block.strokeWidth) { [float]$block.strokeWidth } else { 0 }
        if ($strokeWidth -lt 0) { throw "Text block '$id' strokeWidth cannot be negative." }
        if ($strokeWidth -gt 0 -and [string]::IsNullOrWhiteSpace([string]$block.strokeColor)) {
            throw "Text block '$id' must set strokeColor when strokeWidth is greater than zero."
        }
        $strokeBrush = if ($strokeWidth -gt 0) { [System.Drawing.SolidBrush]::new((Convert-HexColor ([string]$block.strokeColor))) } else { $null }
        try {
            $text = [string]$block.text
            Assert-PosterFontGlyphs $graphics $font $text $id
            $lineHeight = if ($block.lineHeight) { [float]$block.lineHeight } else { 1.15 }
            if ($lineHeight -le 0) { throw "Text block '$id' lineHeight must be greater than zero." }
            $metrics = Get-PosterTextMetrics $graphics $font $text $lineHeight
            $drawBounds = if ($strokeWidth -gt 0) {
                [System.Drawing.RectangleF]::new(
                    [float]($bounds.X + $strokeWidth),
                    [float]($bounds.Y + $strokeWidth),
                    [float]($bounds.Width - (2 * $strokeWidth)),
                    [float]($bounds.Height - (2 * $strokeWidth))
                )
            } else { $bounds }
            if ($drawBounds.Width -le 0 -or $drawBounds.Height -le 0) {
                throw "Text block '$id' strokeWidth leaves no drawable area inside its bounds."
            }
            if ($metrics.Width -gt ($drawBounds.Width + 2) -or $metrics.Height -gt ($drawBounds.Height + 2)) {
                $overflows.Add("$id measured $([Math]::Ceiling($metrics.Width + (2 * $strokeWidth)))x$([Math]::Ceiling($metrics.Height + (2 * $strokeWidth))) including stroke exceeds $($block.width)x$($block.height)")
            }
            Draw-PosterText $graphics $font $brush $strokeBrush $strokeWidth $text $metrics $drawBounds ([string]$block.align) ([string]$block.valign)
            $strokeReport = if ($strokeWidth -gt 0) { "/stroke=$([string]$block.strokeColor),$strokeWidth" } else { '' }
            $fontResolutions.Add("$id=$blockFontFamily->$($font.FontFamily.Name)/$styleName$strokeReport")
        }
        finally {
            if ($null -ne $strokeBrush) { $strokeBrush.Dispose() }
            $brush.Dispose()
            $font.Dispose()
        }
    }

    if ($strictTextBounds -and $overflows.Count -gt 0) {
        throw "Text bounds check failed:`n$($overflows -join "`n")"
    }
    foreach ($warning in $overflows) {
        Write-Warning $warning
    }

    $bitmap.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)

    if ($config.preview -and $config.preview.output) {
        $previewPath = Resolve-ConfigPath ([string]$config.preview.output) $baseDirectory
        $previewDirectory = Split-Path -Parent $previewPath
        if ($previewDirectory) {
            New-Item -ItemType Directory -Force -Path $previewDirectory | Out-Null
        }
        $previewWidth = if ($config.preview.width) { [int]$config.preview.width } else { 1000 }
        $previewHeight = [int][Math]::Round($height * $previewWidth / $width)
        $preview = [System.Drawing.Bitmap]::new($previewWidth, $previewHeight)
        $preview.SetResolution($dpi, $dpi)
        $previewGraphics = [System.Drawing.Graphics]::FromImage($preview)
        try {
            $previewGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $previewGraphics.DrawImage($bitmap, 0, 0, $previewWidth, $previewHeight)
            $quality = if ($config.preview.quality) { [long]$config.preview.quality } else { 92L }
            $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
            $encoderParameter = [System.Drawing.Imaging.EncoderParameter]::new([System.Drawing.Imaging.Encoder]::Quality, $quality)
            $encoderParameters = [System.Drawing.Imaging.EncoderParameters]::new(1)
            try {
                $encoderParameters.Param[0] = $encoderParameter
                $preview.Save($previewPath, $codec, $encoderParameters)
            }
            finally {
                $encoderParameter.Dispose()
                $encoderParameters.Dispose()
            }
        }
        finally {
            $previewGraphics.Dispose()
            $preview.Dispose()
        }
    }
}
finally {
    $graphics.Dispose()
    $bitmap.Dispose()
}

$result = [System.Drawing.Image]::FromFile($outputPath)
try {
    [pscustomobject]@{
        Path = $outputPath
        Width = $result.Width
        Height = $result.Height
        DpiX = [Math]::Round($result.HorizontalResolution)
        DpiY = [Math]::Round($result.VerticalResolution)
        Fonts = @($configuredFontNames) -join '; '
        FontBlocks = $fontResolutions -join '; '
        ViewingDistanceMeters = $viewingDistanceMeters
        Bytes = (Get-Item -LiteralPath $outputPath).Length
        SHA256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $outputPath).Hash
    } | Format-List
}
finally {
    $result.Dispose()
}
