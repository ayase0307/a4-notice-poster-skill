# Intake and approvals

Ask only questions whose answers change the copy, composition, production method, or final output. Combine related questions and preserve answers in a concise approval summary.

## Topic only

Confirm:

- What must the audience understand or do?
- Who will read it, where will it appear, and from roughly what distance?
- Which facts, dates, organization names, contacts, or legal statements are mandatory?
- What tone should it have: formal, friendly, urgent, celebratory, or another direction?
- May the copy be drafted and edited, and who approves it?
- Are there brand assets, colors, prohibited imagery, accessibility needs, or printing constraints?

Draft the poster copy and hierarchy first. Mark unresolved facts clearly. Obtain Approval 1 before image generation.

## Topic and supplied copy

Confirm:

- Which passages are verbatim and which may be shortened or rewritten?
- Are spelling, punctuation, dates, phone numbers, email addresses, URLs, and organization names current?
- Which message is primary, secondary, supporting, legal, and footer content?
- What visual tone, placement, audience, and output size apply?
- Are logos, images, colors, fonts, or references required?

Do not silently correct formal wording. Propose changes separately and record what the user approves.

## Existing poster redesign

Inspect the actual file at useful resolution. Confirm:

- Which text and visual elements must remain?
- Which information has changed?
- Should the brand identity and visual language be preserved, modernized, or replaced?
- What specifically is failing: readability, hierarchy, spacing, density, outdated styling, wrong dimensions, or inaccurate content?
- Is the old layout a reference or a constraint?
- Are source assets available, or must the design be reconstructed from the flattened poster?

Do not assume every element in the old poster is approved or current.

## Reference images

Inspect every supplied reference at useful resolution. First separate what can be observed from what the user intends. Then confirm one of these treatments:

| Treatment | Preserve | Change | Appropriate when |
|---|---|---|---|
| Continue the style | Visual language, palette logic, composition, typography feel, decorative vocabulary | Copy, exact assets, dimensions, and required operational details | The user wants a recognizable continuation |
| Adapt selected traits | Only the explicitly named traits | All unselected traits may be redesigned | The reference contains useful elements but is not the target design |
| Redesign | Content, constraints, or quality bar only | Overall visual system and composition | The old style is unsuitable or the user wants a fresh direction |

Ask: `這張參考圖要沿用整體設計風格、只保留指定特徵，還是重新設計？`

If the answer is “selected traits,” record separate `preserve` and `replace` lists. For multiple references, identify each file and assign its role: `style`, `layout`, `palette`, `illustration`, `content`, or `quality bar`.

Do not reproduce third-party logos, watermarks, branded characters, or near-identical protected artwork without authorization. Use them only as constraints or abstract design traits when reuse rights are unclear.

## Approval record

Before the integrated concept draft, show a compact record containing:

```text
Purpose and audience:
Placement and viewing distance:
Output format:
Exact required copy:
Editable copy:
Information hierarchy:
Visual direction:
Reference image treatment:
Preset style or custom direction:
Required assets and constraints:
Intentionally unresolved items:
```

Ask for confirmation of this record. Later changes update the record rather than replacing it silently.

Copy the approved viewing distance into the production config as `viewingDistanceMeters`. Classify every final text block with a `role` so the renderer can apply the title or body minimum from `references/layout-config.md`.

## Three approval gates

1. **Requirements and copy:** approves the brief and formal content used to make the concept.
2. **Visual direction:** approves the actual integrated concept image and permits reconstruction.
3. **Typesetting canvas:** approves the actual background, exact text, fonts, spacing, and composition and permits final export.

If the user changes an earlier approved decision, return only to the earliest affected gate. A phone-number correction returns to typesetting; a new visual direction returns to the visual gate.
