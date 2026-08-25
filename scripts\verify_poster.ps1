param(
    [Parameter(Mandatory = $true)]
    [string]$ImagePath,
    [string]$ConfigPath = '',
    [string[]]$FontFamily = @(),
    [int]$ExpectedWidth = 2480,
    [int]$ExpectedHeight = 3508,
    [int]$ExpectedDpi = 300
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$resolvedPath = (Resolve-Path -LiteralPath $ImagePath).Path
$fontNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($name in @($FontFamily)) {
    if (-not [string]::IsNullOrWhiteSpace($name)) { [void]$fontNames.Add($name) }
}

if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
    $resolvedConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path
    $config = Get-Content -Raw -Encoding UTF8 -LiteralPath $resolvedConfigPath | ConvertFrom-Json
    if (-not [string]::IsNullOrWhiteSpace([string]$config.fontFamily)) {
        [void]$fontNames.Add([string]$config.fontFamily)
    }
    foreach ($block in @($config.texts)) {
        if ($null -ne $block -and -not [string]::IsNullOrWhiteSpace([string]$block.fontFamily)) {
            [void]$fontNames.Add([string]$block.fontFamily)
        }
    }
    if ($config.canvas.width) { $ExpectedWidth = [int]$config.canvas.width }
    if ($config.canvas.height) { $ExpectedHeight = [int]$config.canvas.height }
    if ($config.canvas.dpi) { $ExpectedDpi = [int]$config.canvas.dpi }
}

$installedFontNames = @([System.Drawing.FontFamily]::Families.Name)
$missingFonts = @($fontNames | Where-Object { $installedFontNames -notcontains $_ })
$image = [System.Drawing.Image]::FromFile($resolvedPath)
try {
    $checks = [ordered]@{
        FileExists = $true
        Width = $image.Width
        Height = $image.Height
        DpiX = [Math]::Round($image.HorizontalResolution)
        DpiY = [Math]::Round($image.VerticalResolution)
        DimensionsPass = ($image.Width -eq $ExpectedWidth -and $image.Height -eq $ExpectedHeight)
        DpiPass = ([Math]::Round($image.HorizontalResolution) -eq $ExpectedDpi -and [Math]::Round($image.VerticalResolution) -eq $ExpectedDpi)
        DeclaredFonts = @($fontNames) -join '; '
        MissingFonts = $missingFonts -join '; '
        FontsAvailablePass = ($missingFonts.Count -eq 0)
        Bytes = (Get-Item -LiteralPath $resolvedPath).Length
        SHA256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedPath).Hash
    }
    $checks['Passed'] = $checks.DimensionsPass -and $checks.DpiPass -and $checks.FontsAvailablePass
    [pscustomobject]$checks | Format-List
    if (-not $checks.Passed) { exit 1 }
}
finally {
    $image.Dispose()
}
