---
name: a4-notice-poster
description: Create or redesign print-ready A4 posters and notices for events, promotions, culture, education, services, safety, and other subjects. Use when final artwork needs an image-generated complete concept, preserved composition, exact local-font typesetting, high-resolution output, and verified copy.
---

# A4 Poster

Create a visually complete poster first, then reconstruct that approved poster at print resolution with deterministic text. Preserve the generated design while replacing every generated character with exact system-rendered copy.

Use three approval gates: requirements and copy, complete visual concept, and final typesetting canvas. Return only to the earliest gate affected by a later change.

## 1. Requirements and copy

Identify whether the user starts from a topic, supplied copy, an existing poster, or brand assets. Read [references/intake-and-approvals.md](references/intake-and-approvals.md) for the relevant questions, reference-image treatments, and approval record.

Ask only about information that changes the copy, design, production method, or output. Separate verbatim text from editable text. Do not make artwork until the user approves the concise requirements and copy record.

When the user has not fixed a visual direction, offer only two or three relevant choices from [references/preset-styles.md](references/preset-styles.md). These are poster design languages, not industry templates.

## 2. Generate the complete poster

After Approval 1, use image generation to create the **entire poster as one integrated design**: imagery, intended text, panels, shapes, ornaments, texture, hierarchy, and typography.

- Ask for a finished portrait poster, not a background template, empty layout, wireframe, or isolated illustration.
- Include the approved wording and hierarchy in the prompt. Generated words remain non-authoritative concept content.
- Let image generation solve the relationship between type, imagery, decoration, rhythm, and negative space.
- Iterate on the complete image until the user approves its actual composition, imagery, color, information zones, title scale, intended line breaks, and typography character.

Do not begin from a blank text-free background and invent the design around system text afterward.

## 3. Preserve, clean, and typeset

After Approval 2, read [references/production-reconstruction.md](references/production-reconstruction.md). The required order is:

1. Create a high-resolution working master from the approved concept at the final aspect ratio.
2. Remove all generated text **in place** from that same master by image editing or inpainting.
3. Reject residual letters, pseudo-text, smears, repeated texture, damaged edges, shifted artwork, or changed composition.
4. Add every formal character as a deterministic text layer.

Do not regenerate a loosely similar text-free poster. If cleaning cannot preserve the approved design, return to the visual concept or obtain approval for a redesigned section.

For typography, read [references/layout-config.md](references/layout-config.md), build the review canvas with [scripts/build_poster_canvas.ps1](scripts/build_poster_canvas.ps1), then render the authoritative review PNG with [scripts/render_a4_poster.ps1](scripts/render_a4_poster.ps1).

Every final text block must explicitly declare its requested `fontFamily`, `style`, `role`, line breaks, line height, final-resolution coordinates, and bounds. Set the approved `viewingDistanceMeters` in the config. The renderer must stop when a family does not resolve, a style is unavailable, required glyphs are missing, Chinese line-break rules fail, text is too small for its viewing distance, or text or its rectangle exceeds declared bounds. Report requested and resolved family names; localized names may differ without being substitutions.

The browser canvas is a positioning aid. The production-rendered PNG and its 100% text crops are the evidence for Approval 3.

## 4. Final output and verification

After Approval 3, render the final PNG and run [scripts/verify_poster.ps1](scripts/verify_poster.ps1). Default output is A4 portrait `2480 x 3508` at `300 DPI`, plus a lightweight preview when useful.

Use verifier `-ReportPath` for a machine-readable record when the result will be regression-tested or used in CI. A failed run writes the report before throwing.

Verify automated facts and visual facts separately:

- file, dimensions, DPI, requested-to-resolved fonts, supported styles, and glyph coverage;
- exact approved copy, full-page readability, text-region crops, clipping, collisions, sampled contrast, background-noise warnings, residual AI text, and damage from text removal.

Do not promise PDF, CMYK, bleed, or print-shop compliance unless those outputs are explicitly produced and verified.

## Layout invariants

- Work in final-output pixels from the first production layout and scale source measurements mathematically.
- Use explicit line breaks; do not depend on automatic wrapping.
- Measure visible panel interiors after text removal instead of reusing estimated concept coordinates.
- Keep glyphs inside real visual boundaries with breathing room, including irregular waves, crops, and decorations.
- Use the viewing-distance table in `references/layout-config.md`; do not replace it with one universal minimum.
- If the same defect survives three corrections, stop nudging coordinates and remeasure or redesign that section.
