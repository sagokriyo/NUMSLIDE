---
description: Produce an implementation-ready UI/UX design brief from a prompt or reference (runs the ui-designer).
argument-hint: <what to design, e.g. "the series HUD for Classic, first to three">
---

Launch the **ui-designer** subagent (Agent tool) to design:

> **$ARGUMENTS**

Tell it to: read `.claude/context/STATE.md` and the `ThemeData` contract first; read
the matching 2048 screen when one exists; stay consistent with the existing
`AppScreen` + `UI.*` widgets; obey the material law (every surface GlassPanel, every
piece CandyFace, marks are MarkFace tubes, dark ground by default, type never glows,
Malam Poek + Nunito); map every color to a theme role (no hex); design for the phone
frame (root at or under 982 design px, judged at 443x963) with touch targets of at
least 48 dp; write copy short and plain with no em dashes; and write the brief to
`.claude/context/designs/<slug>.md`.

When it returns, show me the brief and ask if I want to proceed to implementation
(`/orchestrate` or hand the brief to **godot-ui-engineer**). Do not write Godot code
in this command.
