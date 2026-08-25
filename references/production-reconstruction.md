# Production reconstruction

Use this workflow only after the user approves the complete generated poster concept.

## 1. Audit the generated text before touching the image

Text removal is the destructive step. Decide what actually has to be removed first.

Crop the concept at 1:1 and read the characters:

```powershell
# Whole poster, tiled so nothing small is missed
./scripts/crop_text_regions.ps1 -ImagePath ./concept.png -Grid 2x3 -Scale 2

# Or specific areas, in source-image pixels
./scripts/crop_text_regions.ps1 -ImagePath ./concept.png -Regions "title:80,60,900,320; footer:60,1240,940,180" -Scale 2
```

`-Scale` enlarges with nearest neighbour, so a blurred source stays visibly blurred and cannot be mistaken for clean type.

Classify every block:

| | Keep | Replace |
|---|---|---|
| Characters | all correct and cleanly formed | any wrong, missing, invented, doubled, mirrored, broken, melted, blurred, or clipped character |
| Role | display type carrying the design: title, subtitle, large numeral, logotype, styled word | body, detail, legal, contact, footer, dense or small text |
| Result | pixels stay as final artwork | inpainted out, then redrawn with an installed font |

Uncertain means Replace. Present the crops with the decision and get user confirmation. After cleaning, a kept character can no longer be corrected.

Record the exact wording of every Keep block in the approval record. It never enters the layout config, so final verification has to re-read it from the image.

## 2. Establish the production master

- Preserve the approved aspect ratio and composition.
- Target the requested final pixel dimensions from the start of production. The default A4 portrait canvas is `2480 x 3508` at `300 DPI`.
- Prefer a high-resolution image-generation or image-editing result. When the approved concept is smaller, upscale it before text removal so all later edits and measurements happen on the same final-resolution grid.
- Record the concept dimensions, production dimensions, scale factors, and upscaling method. Pixel dimensions alone do not prove newly recovered detail, so describe deterministic enlargement as upscaling rather than native high-resolution generation.
- Never stretch the image to a different aspect ratio. Crop or extend deliberately and obtain approval if the composition changes.
- Kept text is upscaled along with the artwork. Re-crop it at final resolution and confirm the strokes survived before continuing.

## 3. Remove the Replace text in place

Use the approved production master as the edit target. Ask the image editor to remove only the letters, numbers, punctuation, and text-like marks inside the Replace regions while preserving every other element.

Repeat these invariants in the edit request:

- keep composition, crop, imagery, people, objects, shapes, panels, borders, texture, lighting, shadows, and color unchanged;
- leave the Keep text untouched, naming those regions explicitly;
- reconstruct the material directly behind each removed text region;
- do not add replacement words, symbols, pseudo-text, new decoration, or a new layout;
- keep intended text fields visually usable.

When one edit affects too much of the poster, remove text region by region. Prefer several controlled edits over one broad edit that changes the design. Region-by-region editing is also the safest way to protect Keep text.

## 4. Validate the cleaned master

Inspect the full page and 1:1 crops for every former text region. The cleaned master fails when it contains:

- readable remnants, partial glyphs, fake letters, or watermark-like marks;
- blur patches, repeated texture, broken gradients, or mismatched grain;
- bent panel edges, damaged borders, shifted objects, altered faces, or new decoration;
- any change inside a Keep region, including softened strokes or shifted baselines;
- insufficient contrast or space for the approved type hierarchy.

Compare against the approved concept side by side. Only Replace-region pixels and the reconstructed material behind them should differ.

## 5. Rebuild the type system

Translate the concept's typography character into installed fonts rather than copying generated glyph shapes literally. Preserve the approved hierarchy through family, weight, size, line break, alignment, color, and spatial rhythm.

- Use the actual approved copy from the approval record.
- Include only Replace blocks in `texts`. A Keep block has no config entry and no rectangle.
- Match the Replace type to the kept display type so the page still reads as one design.
- Give every block an explicit `fontFamily` and `style`.
- Use final-output pixel coordinates and explicit line breaks.
- Keep title, supporting copy, date, location, call to action, and footer as separate blocks when their spacing or font role differs.
- Render through the production renderer and inspect the resulting pixels. The HTML canvas is only a positioning aid.

## 6. Produce review evidence

Before Approval 3, show:

- the complete production-rendered poster;
- 1:1 crops of the title, each information group, and footer, produced with `crop_text_regions.ps1 -ConfigPath` for rendered blocks and `-Regions` for kept blocks;
- the requested and resolved family for every rendered block;
- the Keep or Replace decision for every text region;
- any part that was upscaled, extended, or repaired.

Do not describe the poster as high-resolution, font-verified, or text-correct without the corresponding file and checks.
