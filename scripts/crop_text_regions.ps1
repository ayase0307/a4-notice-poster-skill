param(
    [Parameter(Mandatory = $true)]
    [string]$ImagePath,
    [string]$ConfigPath = '',
    [string]$Regions = '',
    [string]$Grid = '',
    [int]$Padding = 24,
    [double]$Scale = 1,
    [string]$OutputDirectory = ''
)

# Produces 1:1 crops of text regions so generated or rendered characters can be
# read instead of estimated. Never invents detail: enlargement is nearest
# neighbour, so a blurred source stays visibly blurred.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

function Resolve-CropPath([string]$Value, [string]$BaseDirectory) {
    if ([System.IO.Path]::IsPathRooted($Value)) {
        return [System.IO.Path]::GetFullPath($Value)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $BaseDirectory $Value))
}

$imageFullPath = (Resolve-Path -LiteralPath $ImagePath).Path
if ($Scale -le 0) { throw 'Scale must be greater than zero.' }

$modes = @($ConfigPath, $Regions, $Grid) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
if ($modes.Count -ne 1) {
    throw 'Choose exactly one source of regions: -ConfigPath, -Regions, or -Grid.'
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path (Split-Path -Parent $imageFullPath) 'crops'
}
$OutputDirectory = Resolve-CropPath $OutputDirectory (Get-Location).Path
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

$source = [System.Drawing.Image]::FromFile($imageFullPath)
try {
    $imageWidth = $source.Width
    $imageHeight = $source.Height

    $requests = [System.Collections.Generic.List[pscustomobject]]::new()

    if ($ConfigPath) {
        $configFullPath = (Resolve-Path -LiteralPath $ConfigPath).Path
        $config = Get-Content -Raw -Encoding UTF8 -LiteralPath $configFullPath | ConvertFrom-Json
        $canvasWidth = if ($config.canvas.width) { [double]$config.canvas.width } else { 2480.0 }
        $canvasHeight = if ($config.canvas.height) { [double]$config.canvas.height } else { 3508.0 }
        # Config coordinates are final-canvas pixels; the image may be the concept
        # or a preview at another size, so map through the ratio instead of assuming.
        $scaleX = $imageWidth / $canvasWidth
        $scaleY = $imageHeight / $canvasHeight
        $index = 0
        foreach ($block in @($config.texts)) {
            if ($null -eq $block) { continue }
            $index++
            $id = if ($block.id) { [string]$block.id } else { "text$index" }
            $requests.Add([pscustomobject]@{
                    Id = $id
                    X = ([double]$block.x - $Padding) * $scaleX
                    Y = ([double]$block.y - $Padding) * $scaleY
                    Width = ([double]$block.width + (2 * $Padding)) * $scaleX
                    Height = ([double]$block.height + (2 * $Padding)) * $scaleY
                })
        }
        if ($requests.Count -eq 0) { throw "Config has no texts to crop: $configFullPath" }
    }
    elseif ($Regions) {
        foreach ($entry in $Regions.Split(';')) {
            $trimmed = $entry.Trim()
            if ($trimmed.Length -eq 0) { continue }
            $parts = $trimmed.Split(':', 2)
            if ($parts.Count -ne 2) { throw "Region must look like 'id:x,y,width,height'. Received '$trimmed'." }
            $numbers = @($parts[1].Split(',') | ForEach-Object { $_.Trim() })
            if ($numbers.Count -ne 4) { throw "Region '$trimmed' needs exactly four numbers: x,y,width,height." }
            $requests.Add([pscustomobject]@{
                    Id = $parts[0].Trim()
                    X = [double]$numbers[0]
                    Y = [double]$numbers[1]
                    Width = [double]$numbers[2]
                    Height = [double]$numbers[3]
                })
        }
        if ($requests.Count -eq 0) { throw 'No usable region was parsed from -Regions.' }
    }
    else {
        $gridParts = @($Grid.ToLowerInvariant().Split('x') | ForEach-Object { $_.Trim() })
        if ($gridParts.Count -ne 2) { throw "Grid must look like '2x3' (columns x rows). Received '$Grid'." }
        $columns = [int]$gridParts[0]
        $rows = [int]$gridParts[1]
        if ($columns -lt 1 -or $rows -lt 1) { throw 'Grid columns and rows must be at least 1.' }
        # Overlap the tiles so a line of text is never split across two crops.
        $tileWidth = $imageWidth / $columns
        $tileHeight = $imageHeight / $rows
        $overlapX = [Math]::Min($tileWidth * 0.08, 120)
        $overlapY = [Math]::Min($tileHeight * 0.08, 120)
        for ($row = 0; $row -lt $rows; $row++) {
            for ($column = 0; $column -lt $columns; $column++) {
                $requests.Add([pscustomobject]@{
                        Id = "r$($row + 1)c$($column + 1)"
                        X = ($column * $tileWidth) - $overlapX
                        Y = ($row * $tileHeight) - $overlapY
                        Width = $tileWidth + (2 * $overlapX)
                        Height = $tileHeight + (2 * $overlapY)
                    })
            }
        }
    }

    $results = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($request in $requests) {
        $left = [int][Math]::Floor([Math]::Max(0, $request.X))
        $top = [int][Math]::Floor([Math]::Max(0, $request.Y))
        $right = [int][Math]::Ceiling([Math]::Min($imageWidth, $request.X + $request.Width))
        $bottom = [int][Math]::Ceiling([Math]::Min($imageHeight, $request.Y + $request.Height))
        $cropWidth = $right - $left
        $cropHeight = $bottom - $top
        if ($cropWidth -le 0 -or $cropHeight -le 0) {
            throw "Region '$($request.Id)' lies outside the ${imageWidth}x${imageHeight} image."
        }

        $outputWidth = [int][Math]::Max(1, [Math]::Round($cropWidth * $Scale))
        $outputHeight = [int][Math]::Max(1, [Math]::Round($cropHeight * $Scale))
        $safeId = ($request.Id -replace '[^\w\-]', '_')
        $outputPath = Join-Path $OutputDirectory "$safeId.png"

        $bitmap = [System.Drawing.Bitmap]::new($outputWidth, $outputHeight)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
            $graphics.DrawImage(
                $source,
                [System.Drawing.Rectangle]::new(0, 0, $outputWidth, $outputHeight),
                [System.Drawing.Rectangle]::new($left, $top, $cropWidth, $cropHeight),
                [System.Drawing.GraphicsUnit]::Pixel
            )
        }
        finally {
            $graphics.Dispose()
        }
        $bitmap.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $bitmap.Dispose()

        $results.Add([pscustomobject]@{
                Id = $request.Id
                SourceRect = "$left,$top,${cropWidth}x$cropHeight"
                Output = "$outputWidth x $outputHeight"
                Path = $outputPath
            })
    }

    [pscustomobject]@{
        Image = $imageFullPath
        ImageSize = "${imageWidth}x${imageHeight}"
        Scale = $Scale
        Crops = $results.Count
        OutputDirectory = $OutputDirectory
    } | Format-List
    $results | Format-Table -AutoSize
}
finally {
    $source.Dispose()
}
