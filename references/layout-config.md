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

1. Build the HTML canvas. Always pass `-ConceptPath` so the approved concept can be compared against the typesetting:

   ```powershell
   ./scripts/build_poster_canvas.ps1 -ConfigPath ./poster-config.json -ConceptPath ./concept.png
   ```

2. Open the reported HTML path in Codex's in-app browser. Click a block to select it; its `id` appears on a badge above the box. Compare installed fonts, style, size, line height, position, alignment, and line breaks.
3. Correct placement directly on the canvas instead of guessing coordinates from the image. Drag a block to move it, drag the blue handle on its bottom-right corner to resize it, and nudge the selected block with the arrow keys by `1 px` or with `Shift` plus an arrow key by `10 px`. The `X`, `Y`, `寬度`, and `高度` fields update live.
4. Use measure mode to read real geometry instead of estimating it. Tick `量測模式`, drag a rectangle over the visible panel interior, wave crest, or cleared text area, and the readout gives its `x`, `y`, `width`, and `height` in final-canvas pixels. `套用到選取方框` writes those four numbers straight into the selected block. This is how panel interiors get measured; do not type coordinates read off the image by eye.
5. Use the concept overlay to verify placement against the approved design. The slider cross-fades the concept over the current typesetting. Difference mode subtracts the two, so matching pixels turn black and every displaced or resized block glows. Both are measurements of the actual rendered positions; do not replace them with a visual estimate of where a block "looks right".
6. Record the selected values in the JSON config. `複製 JSON` puts the whole edited config on the clipboard; `下載` writes `poster-config-reviewed.json`. Browser changes are temporary until that JSON is saved back to the config file.
7. Render a review PNG with the production renderer and show it in Codex. Inspect the full page and 1:1 crops of every text region. Approval 3 must use this exact render because browser and `System.Drawing` font metrics may differ.
8. After Approval 3, export and verify the final deliverables.

## Reading text at 1:1

`crop_text_regions.ps1` produces the crops that the text audit and Approval 3 both require. It never invents detail: `-Scale` enlarges with nearest neighbour, so blurred pixels stay visibly blurred.

```powershell
# Every rendered block, taken from the config, with 24 canvas px of padding
./scripts/crop_text_regions.ps1 -ImagePath ./poster.png -ConfigPath ./poster-config.json -Scale 2

# Areas that are not in the config, such as kept generated text, in image pixels
./scripts/crop_text_regions.ps1 -ImagePath ./concept.png -Regions "title:80,60,900,320" -Scale 2

# Sweep a whole poster when the text regions are not known yet
./scripts/crop_text_regions.ps1 -ImagePath ./concept.png -Grid 2x3 -Scale 2
```

`-ConfigPath` maps config coordinates through the image-to-canvas ratio, so it works on the concept, a preview, and the final render alike. `-Grid` tiles overlap so a line of text is never split across two crops.

## Measuring generated backgrounds

Measure mode on the review canvas already reports final-canvas pixels, so prefer it. Use the formulas below only for numbers taken from a source image at a different size.

If the source background has dimensions `sourceWidth x sourceHeight`, convert measured source coordinates to the final canvas with:

```text
canvasX = sourceX * canvasWidth / sourceWidth
canvasY = sourceY * canvasHeight / sourceHeight
```

For each card, measure its visible `top` and `bottom`, calculate the final `centerY`, then build text rectangles symmetrically around that center with `valign: center`.

For wave footers, inspect the final-resolution crop. Use the highest boundary across the text's complete horizontal span, not only its left edge.
