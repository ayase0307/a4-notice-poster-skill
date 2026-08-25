# Layout configuration

Use UTF-8 JSON. Coordinates and font sizes are pixels on the final canvas. Relative paths resolve from the JSON file's directory.

## Schema

```json
{
  "canvas": { "width": 2480, "height": 3508, "dpi": 300 },
  "background": "./background.png",
  "output": "./poster.png",
  "fontFamily": "華康黑體 Std W12",
  "strictTextBounds": true,
  "preview": { "output": "./poster-preview.jpg", "width": 1000, "quality": 92 },
  "roundedRectangles": [
    { "x": 1260, "y": 3225, "width": 1020, "height": 190, "radius": 36, "fill": "#10314C" }
  ],
  "texts": [
    {
      "id": "title",
      "text": "電子病歷\n正式實施",
      "fontFamily": "華康黑體 Std W12",
      "x": 125,
      "y": 295,
      "width": 1240,
      "height": 460,
      "size": 190,
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
- `fontFamily`: required default installed font family. A text block may override it.
- `strictTextBounds`: when true, stop if measured text exceeds its rectangle. Keep it true for final rendering.
- `preview`: optional JPG preview settings. `width` preserves aspect ratio. `quality` accepts `1-100`.
- `roundedRectangles`: optional opaque or translucent fills drawn before text. `fill` accepts `#RRGGBB` or `#AARRGGBB`.
- `texts`: ordered text blocks drawn after rectangles.
- `id`: stable label used by the canvas and overflow errors.
- `text`: exact UTF-8 text. Use `\n` for intentional line breaks.
- `fontFamily`: optional per-block installed font family. It overrides the top-level default.
- `x`, `y`, `width`, `height`: destination rectangle.
- `size`: font size in pixels.
- `color`: `#RRGGBB` or `#AARRGGBB`.
- `align`: `near`, `center`, or `far`.
- `valign`: `near`, `center`, or `far`.
- `style`: `Regular`, `Bold`, `Italic`, or `Bold, Italic`. For a naturally heavy family, use `Regular` to preserve its designed proportions.

## Review-canvas workflow

1. Build the HTML canvas:

   ```powershell
   ./scripts/build_poster_canvas.ps1 -ConfigPath ./poster-config.json
   ```

2. Open the reported HTML path in Codex's in-app browser. Select a text block and compare installed fonts, size, position, alignment, and line breaks.
3. Record the selected values in the JSON config. Browser changes are temporary until the downloaded or reported JSON is saved back to the config.
4. Render a review PNG with the production renderer and show it in Codex. Approval 3 must use this exact render because browser and `System.Drawing` font metrics may differ.
5. After Approval 3, export and verify the final deliverables.

## Measuring generated backgrounds

If the source background has dimensions `sourceWidth x sourceHeight`, convert measured source coordinates to the final canvas with:

```text
canvasX = sourceX * canvasWidth / sourceWidth
canvasY = sourceY * canvasHeight / sourceHeight
```

For each card, measure its visible `top` and `bottom`, calculate the final `centerY`, then build text rectangles symmetrically around that center with `valign: center`.

For wave footers, inspect the final-resolution crop. Use the highest boundary across the text's complete horizontal span, not only its left edge.
