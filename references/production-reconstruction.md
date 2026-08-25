# Production reconstruction

Use this workflow only after the user approves the complete generated poster concept.

## 1. Establish the production master

- Preserve the approved aspect ratio and composition.
- Target the requested final pixel dimensions from the start of production. The default A4 portrait canvas is `2480 x 3508` at `300 DPI`.
- Prefer a high-resolution image-generation or image-editing result. When the approved concept is smaller, upscale it before text removal so all later edits and measurements happen on the same final-resolution grid.
- Record the concept dimensions, production dimensions, scale factors, and upscaling method. Pixel dimensions alone do not prove newly recovered detail, so describe deterministic enlargement as upscaling rather than native high-resolution generation.
- Never stretch the image to a different aspect ratio. Crop or extend deliberately and obtain approval if the composition changes.

## 2. Remove generated text in place

Use the approved production master as the edit target. Ask the image editor to remove only letters, numbers, punctuation, and text-like marks while preserving every non-text element.

Repeat these invariants in the edit request:

- keep composition, crop, imagery, people, objects, shapes, panels, borders, texture, lighting, shadows, and color unchanged;
- reconstruct the material directly behind each text region;
- do not add replacement words, symbols, pseudo-text, new decoration, or a new layout;
- keep intended text fields visually usable.

When one edit affects too much of the poster, remove text region by region. Prefer several controlled edits over one broad edit that changes the design.

## 3. Validate the cleaned master

Inspect the full page and 100% crops for every former text region. The cleaned master fails when it contains:

- readable remnants, partial glyphs, fake letters, or watermark-like marks;
- blur patches, repeated texture, broken gradients, or mismatched grain;
- bent panel edges, damaged borders, shifted objects, altered faces, or new decoration;
- insufficient contrast or space for the approved type hierarchy.

Compare against the approved concept side by side. Only text pixels and the reconstructed material behind them should differ.

## 4. Rebuild the type system

Translate the concept's typography character into installed fonts rather than copying generated glyph shapes literally. Preserve the approved hierarchy through family, weight, size, line break, alignment, color, and spatial rhythm.

- Use the actual approved copy from the approval record.
- Give every block an explicit `fontFamily` and `style`.
- Use final-output pixel coordinates and explicit line breaks.
- Keep title, supporting copy, date, location, call to action, and footer as separate blocks when their spacing or font role differs.
- Render through the production renderer and inspect the resulting pixels. The HTML canvas is only a positioning aid.

## 5. Produce review evidence

Before Approval 3, show:

- the complete production-rendered poster;
- 100% crops of the title, each information group, and footer;
- the requested and resolved family for every block;
- any part that was upscaled, extended, or repaired.

Do not describe the poster as high-resolution, font-verified, or text-correct without the corresponding file and checks.
