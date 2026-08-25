---
name: a4-notice-poster
description: Create or redesign print-ready A4 posters and notices for events, promotions, culture, education, services, safety, and other subjects. Use when final artwork needs an image-generated complete concept, preserved composition, exact local-font typesetting, high-resolution output, and verified copy.
---

# A4 Poster

Create a visually complete poster first, then reconstruct that approved poster at print resolution with deterministic text. Preserve the generated design, and replace only the generated characters that are actually wrong.

Use three approval gates: requirements and copy, complete visual concept, and final typesetting canvas. Return only to the earliest gate affected by a later change.

## 1. Requirements and copy

Identify whether the user starts from a topic, supplied copy, an existing poster, or brand assets. Read [references/intake-and-approvals.md](references/intake-and-approvals.md) for the relevant questions, reference-image treatments, and approval record.

Ask only about information that changes the copy, design, production method, or output. Separate verbatim text from editable text. Do not make artwork until the user approves the concise requirements and copy record.

When the user has not fixed a visual direction, offer only two or three relevant choices from [references/preset-styles.md](references/preset-styles.md). These are poster design languages, not industry templates.

## 2. Generate the complete poster

After Approval 1, use image generation to create the **entire poster as one integrated design**: imagery, intended text, panels, shapes, ornaments, texture, hierarchy, and typography.

- Ask for a finished portrait poster, not a background template, empty layout, wireframe, or isolated illustration.
- Include the approved wording and hierarchy in the prompt. Generated words remain non-authoritative until audited in step 3.
- Let image generation solve the relationship between type, imagery, decoration, rhythm, and negative space.
- Iterate on the complete image until the user approves its actual composition, imagery, color, information zones, title scale, intended line breaks, and typography character.

Do not begin from a blank text-free background and invent the design around system text afterward.

## 3. Audit the generated text

Current image models often render display type correctly, including Chinese. Removing and re-typesetting text that is already correct destroys designed lettering and risks damaging the artwork for no gain. Audit before cleaning.

Crop every text region at 1:1 with [scripts/crop_text_regions.ps1](scripts/crop_text_regions.ps1) and read the actual pixels. `-Grid` tiles the whole poster so no small line is missed; `-Regions` targets known areas. Never classify from the downscaled full page. Then mark each block:

- **Keep** — every character is correct and cleanly formed, and the block is display type whose specific lettering carries the design: title, subtitle, large numerals, logotype, or a deliberately styled word. Kept blocks are not inpainted and get no text layer. Their concept pixels are the final artwork.
- **Replace** — any wrong, missing, invented, doubled, or mirrored character; broken, melted, blurred, smeared, or clipped strokes; or a block small enough that an installed font is more legible than generated lettering. Body, detail, legal, contact, and footer text default to Replace.

Anything uncertain is Replace. Show the crops with the Keep or Replace decision and get user confirmation before cleaning, because a kept character can no longer be corrected once the master is edited, and a wrong kept character becomes a printed error.

Record each Keep block and its exact wording in the approval record. Verification still has to check that wording against the approved copy, and it is no longer in a config.

## 4. Preserve, clean, and typeset

After Approval 2 and the text audit, read [references/production-reconstruction.md](references/production-reconstruction.md). The required order is:

1. Create a high-resolution working master from the approved concept at the final aspect ratio.
2. Remove the **Replace** regions **in place** from that same master by image editing or inpainting. Name the Keep regions as protected in every edit request.
3. Reject residual letters, pseudo-text, smears, repeated texture, damaged edges, shifted artwork, changed composition, or any alteration inside a Keep region.
4. Add every Replace character as a deterministic text layer.

Do not regenerate a loosely similar text-free poster. If cleaning cannot preserve the approved design, return to the visual concept or obtain approval for a redesigned section.

For typography, read [references/layout-config.md](references/layout-config.md), build the review canvas with [scripts/build_poster_canvas.ps1](scripts/build_poster_canvas.ps1), then render the authoritative review PNG with [scripts/render_a4_poster.ps1](scripts/render_a4_poster.ps1).

Every final text block must explicitly declare its requested `fontFamily`, `style`, `role`, line breaks, line height, final-resolution coordinates, and bounds. Set the approved `viewingDistanceMeters` in the config. The renderer must stop when a family does not resolve, a style is unavailable, required glyphs are missing, Chinese line-break rules fail, text is too small for its viewing distance, or text or its rectangle exceeds declared bounds. Report requested and resolved family names; localized names may differ without being substitutions.

Run the canvas with `-Serve`. It opens a loopback web page in the reviewer's browser and blocks until they press `儲存並回傳 agent`, which writes the reviewed config back to disk and prints the changed fields, so the layout returns to you without anyone copying JSON by hand. `不存離開` and the `-TimeoutMinutes` timeout both write nothing.

The browser canvas is a positioning aid. The production-rendered PNG and its 100% text crops are the evidence for Approval 3.

## 5. Final output and verification

After Approval 3, render the final PNG and run [scripts/verify_poster.ps1](scripts/verify_poster.ps1). Default output is A4 portrait `2480 x 3508` at `300 DPI`, plus a lightweight preview when useful.

Use verifier `-ReportPath` for a machine-readable record when the result will be regression-tested or used in CI. A failed run writes the report before throwing.

Verify automated facts and visual facts separately:

- file, dimensions, DPI, requested-to-resolved fonts, supported styles, and glyph coverage;
- exact approved copy, full-page readability, text-region crops, clipping, collisions, sampled contrast, background-noise warnings, residual AI text, and damage from text removal.

Automated checks cover only rendered text blocks. Re-crop every Keep region on the final file and read it again, because the verifier cannot see wording that lives in the background image.

Do not promise PDF, CMYK, bleed, or print-shop compliance unless those outputs are explicitly produced and verified.

## Layout invariants

- Work in final-output pixels from the first production layout and scale source measurements mathematically.
- Kept generated text stays in the background image. Give it no text block and no rectangle, and do not let a Replace block overlap it.
- Use explicit line breaks; do not depend on automatic wrapping.
- Measure visible panel interiors after text removal instead of reusing estimated concept coordinates. Use the review canvas's measure mode rather than reading coordinates off the image by eye.
- Keep glyphs inside real visual boundaries with breathing room, including irregular waves, crops, and decorations.
- Use the viewing-distance table in `references/layout-config.md`; do not replace it with one universal minimum.
- If the same defect survives three corrections, stop nudging coordinates and remeasure or redesign that section.

## Scripts on Windows

Every script is Windows PowerShell and depends on `System.Drawing` and installed fonts. Scripts that contain Chinese literals are stored UTF-8 **with BOM**; Windows PowerShell 5.1 otherwise reads them as ANSI and `layout_checks.ps1` fails to parse, which silently disables the Chinese line-break rules. Keep the BOM when editing these files.
