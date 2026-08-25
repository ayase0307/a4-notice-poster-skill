# Layout configuration

Use UTF-8 JSON. Coordinates and font sizes are pixels on the final canvas. Relative paths resolve from the JSON file's directory.

## Schema

```json
{
  "canvas": { "width": 2480, "height": 3508, "dpi": 300 },
  "background": "./background.png",
  "output": "./poster.png",
  "fontFamily": "Noto Sans TC",
  "viewingDistanceMeters": 1,
  "strictTextBounds": true,
  "preview": { "output": "./poster-preview.jpg", "width": 1000, "quality": 92 },
  "roundedRectangles": [
    { "x": 1260, "y": 3225, "width": 1020, "height": 190, "radius": 36, "fill": "#10314C" }
  ],
  "texts": [
    {
      "id": "title",
      "role": "title",
      "text": "城市週末\n書市",
      "fontFamily": "Noto Sans TC Black",
      "x": 125,
      "y": 295,
      "width": 1240,
      "height": 460,
      "size": 190,
      "lineHeight": 1.05,
      "color": "#10314C",
      "align": "near",
      "valign": "center",
      "style": "Regular"
    }
  ]
}
```

## Fields

- `canvas`: defaults to A4 portrait at 300 DPI. Change it only when the requested format differs.
- `background`: required text-free source image. The renderer scales it to the canvas, so inspect the result for distortion or cropping before approval.
- `output`: required PNG output path.
- `fontFamily`: default installed font family. Every final text block should still declare its intended family explicitly so omissions cannot silently inherit the wrong role.
- `viewingDistanceMeters`: required intended viewing distance in meters. The renderer uses it with each block's `role` to enforce minimum type sizes.
- `strictTextBounds`: when true, stop if measured text exceeds its rectangle. Keep it true for final rendering.
- `preview`: optional JPG preview settings. `width` preserves aspect ratio. `quality` accepts `1-100`.
- `roundedRectangles`: optional opaque or translucent fills drawn before text. `fill` accepts `#RRGGBB` or `#AARRGGBB`.
- `texts`: ordered text blocks drawn after rectangles.
- `id`: stable label used by the canvas and overflow errors.
- `role`: required `title`, `body`, `detail`, or `legal`. `title` uses the title minimum; the other roles use the body minimum.
- `text`: exact UTF-8 text. Use `\n` for intentional line breaks.
- `fontFamily`: optional per-block installed font family. It overrides the top-level default.
- `x`, `y`, `width`, `height`: destination rectangle.
- `size`: font size in pixels.
- `lineHeight`: optional line-height multiplier. Defaults to `1.15`. The production renderer measures and draws explicit lines with this value.
- `color`: `#RRGGBB` or `#AARRGGBB`.
- `align`: `near`, `center`, or `far`.
- `valign`: `near`, `center`, or `far`.
- `style`: `Regular`, `Bold`, `Italic`, or `Bold, Italic`. For a naturally heavy family, use `Regular` to preserve its designed proportions.
- `minimumSizeOverrideReason`: optional non-empty explanation that explicitly exempts one block from the viewing-distance minimum. Use only after user approval, normally for unavoidable legal text.
- `maxBackgroundLuminanceStdDev`: optional per-block override for the verifier's background-noise warning threshold. Default is `0.12`.

## Viewing-distance minimums

The renderer interpolates between these values. Distances beyond `5 m` continue the same slope.

| Viewing distance | Title minimum | Body/detail/legal minimum |
|---|---:|---:|
| `1 m` | `120 px` | `50 px` |
| `3 m` | `200 px` | `80 px` |
| `5 m` | `280 px` | `110 px` |

These are A4 `300 DPI` production pixels. Set the real viewing distance from intake instead of applying one fixed minimum to every poster.

## Chinese line-break rules

Because wrapping is disabled, every manual line is checked before drawing:

- a line may not start with `。，、）」』？！：；】》〉〕］｝`;
- a line may not end with `（「『【《〈〔［｛`.

Fix the explicit line break instead of disabling the check.

## Font and bounds contract

The production renderer treats the config as an executable contract. It stops instead of silently substituting when:

- the requested family cannot be resolved by `FontFamily` (preventing GDI+ fallback);
- the requested style is unavailable for that family;
- the family lacks any non-whitespace character required by that block;
- the block rectangle extends beyond the canvas;
- measured text exceeds the declared rectangle while `strictTextBounds` is true.
- a manual line violates Chinese line-break rules;
- a block is smaller than the minimum for `viewingDistanceMeters` and its `role`.

Use a naturally bold family such as `Noto Sans TC Black` with `style: Regular`. Do not request synthetic `Bold` unless that exact family exposes a bold style. A font being installed does not prove that it contains every required glyph.

The render report shows `requested -> resolved` family names. A valid English alias may resolve to a localized family name, for example `Microsoft JhengHei -> 微軟正黑體`; this is not a substitution. A nonexistent family must fail before drawing.

## Contrast and background-noise verification

`verify_poster.ps1` reconstructs the background beneath each text block from the text-free background plus renderer-drawn shapes. It does not sample the final text pixels.

Pass `-ReportPath <path>.json` when automation or CI needs structured results. The report is written before a failing verification throws, so the exact failed check remains inspectable.

- It samples each text rectangle and reports average contrast plus the 10th-percentile contrast ratio.
- The 10th percentile must reach `4.5:1` for ordinary text or `3:1` for large text. This catches isolated light or dark patches that an average alone can hide.
- It reports background luminance standard deviation. Values above `0.12` produce a heuristic warning because detailed photography, gradients, or illustration may reduce readability even when color contrast passes.
- Contrast failure makes verification fail. Noise remains a warning that requires pixel review because it can produce false positives.

## Review-canvas workflow

1. Build the HTML canvas:

   ```powershell
   ./scripts/build_poster_canvas.ps1 -ConfigPath ./poster-config.json
   ```

2. Open the reported HTML path in Codex's in-app browser. Select a text block and compare installed fonts, style, size, line height, position, alignment, and line breaks.
3. Record the selected values in the JSON config. Browser changes are temporary until the downloaded or reported JSON is saved back to the config.
4. Render a review PNG with the production renderer and show it in Codex. Inspect the full page and 100% crops of every text region. Approval 3 must use this exact render because browser and `System.Drawing` font metrics may differ.
5. After Approval 3, export and verify the final deliverables.

## Measuring generated backgrounds

If the source background has dimensions `sourceWidth x sourceHeight`, convert measured source coordinates to the final canvas with:

```text
canvasX = sourceX * canvasWidth / sourceWidth
canvasY = sourceY * canvasHeight / sourceHeight
```

For each card, measure its visible `top` and `bottom`, calculate the final `centerY`, then build text rectangles symmetrically around that center with `valign: center`.

For wave footers, inspect the final-resolution crop. Use the highest boundary across the text's complete horizontal span, not only its left edge.
