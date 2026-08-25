param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

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
        $diameter = [Math]::Max(1, $Radius * 2)
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

if (-not (Test-Path -LiteralPath $backgroundPath)) {
    throw "Background not found: $backgroundPath"
}
$installedFontNames = @([System.Drawing.FontFamily]::Families.Name)
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
foreach ($configuredFontName in $configuredFontNames) {
    if ($installedFontNames -notcontains $configuredFontName) {
        throw "Font family is not installed: $configuredFontName"
    }
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
    foreach ($block in @($config.texts)) {
        if ($null -eq $block) { continue }
        $blockFontFamily = if ($block.fontFamily) { [string]$block.fontFamily } else { $fontFamily }
        if ([string]::IsNullOrWhiteSpace($blockFontFamily)) {
            $id = if ($block.id) { [string]$block.id } else { '<unnamed>' }
            throw "No font family configured for text block: $id"
        }
        $styleName = if ($block.style) { [string]$block.style } else { 'Regular' }
        $style = [System.Enum]::Parse([System.Drawing.FontStyle], $styleName, $true)
        $font = [System.Drawing.Font]::new($blockFontFamily, [float]$block.size, $style, [System.Drawing.GraphicsUnit]::Pixel)
        $brush = [System.Drawing.SolidBrush]::new((Convert-HexColor ([string]$block.color)))
        $format = [System.Drawing.StringFormat]::new(
            [System.Drawing.StringFormatFlags]::NoClip -bor [System.Drawing.StringFormatFlags]::NoWrap
        )
        try {
            $format.Alignment = Convert-Alignment ([string]$block.align)
            $format.LineAlignment = Convert-Alignment ([string]$block.valign)
            $format.Trimming = [System.Drawing.StringTrimming]::None
            $text = [string]$block.text
            $measured = $graphics.MeasureString($text, $font, 100000, $format)
            if ($measured.Width -gt ([float]$block.width + 2) -or $measured.Height -gt ([float]$block.height + 2)) {
                $id = if ($block.id) { [string]$block.id } else { $text.Substring(0, [Math]::Min(20, $text.Length)) }
                $overflows.Add("$id measured $([Math]::Ceiling($measured.Width))x$([Math]::Ceiling($measured.Height)) exceeds $($block.width)x$($block.height)")
            }
            $graphics.DrawString(
                $text,
                $font,
                $brush,
                [System.Drawing.RectangleF]::new([float]$block.x, [float]$block.y, [float]$block.width, [float]$block.height),
                $format
            )
        }
        finally {
            $format.Dispose()
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
        Bytes = (Get-Item -LiteralPath $outputPath).Length
        SHA256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $outputPath).Hash
    } | Format-List
}
finally {
    $result.Dispose()
}
