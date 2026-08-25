$ErrorActionPreference = 'Stop'

function Get-PosterKinsokuIssues([string]$Text, [string]$BlockId) {
    if ([string]::IsNullOrEmpty($Text)) { return @() }

    $forbiddenAtLineStart = '。，、）」』？！：；】》〉〕］｝'
    $forbiddenAtLineEnd = '（「『【《〈〔［｛'
    $normalized = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    $lines = @($normalized.Split([char]10))
    $issues = [System.Collections.Generic.List[string]]::new()

    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = ([string]$lines[$index]).Trim()
        if ($line.Length -eq 0) { continue }
        $lineNumber = $index + 1
        if ($forbiddenAtLineStart.IndexOf($line[0]) -ge 0) {
            $issues.Add("$BlockId line $lineNumber starts with forbidden punctuation '$($line[0])'.")
        }
        if ($forbiddenAtLineEnd.IndexOf($line[$line.Length - 1]) -ge 0) {
            $issues.Add("$BlockId line $lineNumber ends with forbidden opening punctuation '$($line[$line.Length - 1])'.")
        }
    }
    return @($issues)
}

function Get-PosterMinimumFontSize([float]$ViewingDistanceMeters, [string]$Role) {
    if ($ViewingDistanceMeters -le 0) {
        throw 'viewingDistanceMeters must be greater than zero.'
    }

    $normalizedRole = if ([string]::IsNullOrWhiteSpace($Role)) { '' } else { $Role.ToLowerInvariant() }
    if ($normalizedRole -notin @('title', 'body', 'detail', 'legal')) {
        throw "Unsupported or missing text role '$Role'. Use title, body, detail, or legal."
    }

    $isTitle = $normalizedRole -eq 'title'
    $points = @(
        [pscustomobject]@{ Distance = 1.0; Title = 120.0; Body = 50.0 },
        [pscustomobject]@{ Distance = 3.0; Title = 200.0; Body = 80.0 },
        [pscustomobject]@{ Distance = 5.0; Title = 280.0; Body = 110.0 }
    )

    if ($ViewingDistanceMeters -le 1) {
        $minimumAtOneMeter = if ($isTitle) { $points[0].Title } else { $points[0].Body }
        return [float]$minimumAtOneMeter
    }
    for ($index = 0; $index -lt $points.Count - 1; $index++) {
        $left = $points[$index]
        $right = $points[$index + 1]
        if ($ViewingDistanceMeters -le $right.Distance) {
            $fraction = ($ViewingDistanceMeters - $left.Distance) / ($right.Distance - $left.Distance)
            $leftSize = if ($isTitle) { $left.Title } else { $left.Body }
            $rightSize = if ($isTitle) { $right.Title } else { $right.Body }
            return [float]($leftSize + (($rightSize - $leftSize) * $fraction))
        }
    }

    $last = $points[-1]
    $slope = if ($isTitle) { 40.0 } else { 15.0 }
    $lastSize = if ($isTitle) { $last.Title } else { $last.Body }
    return [float]($lastSize + (($ViewingDistanceMeters - $last.Distance) * $slope))
}

function Get-PosterViewingDistanceIssue(
    [float]$ViewingDistanceMeters,
    [pscustomobject]$Block,
    [string]$BlockId
) {
    if (-not [string]::IsNullOrWhiteSpace([string]$Block.minimumSizeOverrideReason)) {
        return $null
    }
    $minimum = Get-PosterMinimumFontSize $ViewingDistanceMeters ([string]$Block.role)
    $actual = [float]$Block.size
    if ($actual -lt $minimum) {
        return "$BlockId size $actual px is below the $([Math]::Round($minimum)) px minimum for role '$($Block.role)' at $ViewingDistanceMeters m."
    }
    return $null
}
