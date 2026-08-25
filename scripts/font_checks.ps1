$ErrorActionPreference = 'Stop'

if (-not ('PosterNativeFontMethods' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class PosterNativeFontMethods
{
    [DllImport("gdi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern uint GetGlyphIndices(
        IntPtr hdc,
        string text,
        int count,
        [Out] ushort[] glyphIndices,
        uint flags
    );

    [DllImport("gdi32.dll")]
    public static extern IntPtr SelectObject(IntPtr hdc, IntPtr handle);

    [DllImport("gdi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool DeleteObject(IntPtr handle);
}
'@
}

function Convert-PosterFontStyle([string]$Value) {
    $styleName = if ([string]::IsNullOrWhiteSpace($Value)) { 'Regular' } else { $Value }
    try {
        return [System.Enum]::Parse([System.Drawing.FontStyle], $styleName, $true)
    }
    catch {
        throw "Unsupported font style '$Value'. Use Regular, Bold, Italic, or Bold, Italic."
    }
}

function New-VerifiedPosterFont(
    [string]$FamilyName,
    [float]$Size,
    [string]$StyleName = 'Regular'
) {
    if ([string]::IsNullOrWhiteSpace($FamilyName)) {
        throw 'Font family cannot be empty.'
    }
    if ($Size -le 0) {
        throw "Font size must be greater than zero for '$FamilyName'."
    }

    try {
        $family = [System.Drawing.FontFamily]::new($FamilyName)
    }
    catch {
        throw "Font family did not resolve: '$FamilyName'. $($_.Exception.Message)"
    }
    $style = Convert-PosterFontStyle $StyleName
    if (-not $family.IsStyleAvailable($style)) {
        $family.Dispose()
        throw "Font style '$StyleName' is not available for family '$FamilyName'."
    }

    $font = [System.Drawing.Font]::new($family, $Size, $style, [System.Drawing.GraphicsUnit]::Pixel)
    $family.Dispose()
    return $font
}

function Get-MissingPosterGlyphs(
    [System.Drawing.Graphics]$Graphics,
    [System.Drawing.Font]$Font,
    [string]$Text
) {
    if ([string]::IsNullOrEmpty($Text)) { return @() }

    $elements = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $enumerator = [System.Globalization.StringInfo]::GetTextElementEnumerator($Text)
    while ($enumerator.MoveNext()) {
        $element = [string]$enumerator.GetTextElement()
        if (-not [string]::IsNullOrWhiteSpace($element)) {
            [void]$elements.Add($element)
        }
    }

    $missing = [System.Collections.Generic.List[string]]::new()
    $hdc = [IntPtr]::Zero
    $hfont = [IntPtr]::Zero
    $previous = [IntPtr]::Zero
    try {
        $hdc = $Graphics.GetHdc()
        $hfont = $Font.ToHfont()
        $previous = [PosterNativeFontMethods]::SelectObject($hdc, $hfont)
        foreach ($element in $elements) {
            # [uint16], not [ushort]: Windows PowerShell 5.1 has no ushort accelerator.
            $glyphs = [uint16[]]::new($element.Length)
            $result = [PosterNativeFontMethods]::GetGlyphIndices($hdc, $element, $element.Length, $glyphs, 1)
            if ($result -eq [uint32]::MaxValue -or ($glyphs | Where-Object { $_ -eq 0xFFFF }).Count -gt 0) {
                $codePoints = [System.Collections.Generic.List[string]]::new()
                for ($index = 0; $index -lt $element.Length; $index++) {
                    $codePoint = [char]::ConvertToUtf32($element, $index)
                    if ([char]::IsHighSurrogate($element[$index])) { $index++ }
                    $codePoints.Add(('U+{0:X4}' -f $codePoint))
                }
                $missing.Add("$element ($($codePoints -join '+'))")
            }
        }
    }
    finally {
        if ($hdc -ne [IntPtr]::Zero -and $previous -ne [IntPtr]::Zero) {
            [void][PosterNativeFontMethods]::SelectObject($hdc, $previous)
        }
        if ($hfont -ne [IntPtr]::Zero) {
            [void][PosterNativeFontMethods]::DeleteObject($hfont)
        }
        if ($hdc -ne [IntPtr]::Zero) {
            $Graphics.ReleaseHdc($hdc)
        }
    }
    return @($missing)
}

function Assert-PosterFontGlyphs(
    [System.Drawing.Graphics]$Graphics,
    [System.Drawing.Font]$Font,
    [string]$Text,
    [string]$BlockId
) {
    $missing = @(Get-MissingPosterGlyphs $Graphics $Font $Text)
    if ($missing.Count -gt 0) {
        throw "Font '$($Font.FontFamily.Name)' lacks required glyphs for text block '$BlockId': $($missing -join ', ')"
    }
}
