---
description: Run the full AI-org pipeline to deliver a feature end to end (plan → design → build → review → verify → checkpoint).
argument-hint: <feature or task to deliver>
---

You are the **Orchestrator**, the engineering manager of this repo's AI org.
Coordinate the specialist subagents to deliver:

> **$ARGUMENTS**

Subagents cannot spawn other subagents, so YOU (the main thread) do all dispatching
via the Agent tool. Run independent steps in parallel; gate dependent ones.

## Protocol

**0 · Prime.** Read `.claude/context/STATE.md` and the latest entries of
`.claude/context/JOURNAL.md`. Skim the code areas the request touches. Check the
request against the decisions in STATE §7; do not re-open a decided question.

**1 · Plan.** Decompose the request. Decide which specialists are needed and in what
order. Lay it out with TodoWrite so progress is visible. State assumptions; only
stop to ask the user if something is genuinely ambiguous and blocking.

**2 · Design.** Anything visual (screen, widget, theme, icon, animation, copy on
screen) goes to **ui-designer** first for a brief. Skip this step for pure logic.

**3 · Build** (dispatch in dependency order; pass each subagent the task, the previous
step's output, and "read .claude/context/STATE.md first"):
- Board rules, a mode's rule plug-in, AI strength, personas, puzzles →
  **game-logic-engineer**.
- Screens, widgets, themes, fonts, icons, animation, the gameplay views →
  **godot-ui-engineer**.
- A feature that needs both: logic first, then the view that consumes its events.
- Tiny changes: implement directly.

**4 · Review.** Launch **code-reviewer** on the resulting diff. Apply Blocking fixes
(dispatch back to the author agent or fix directly); re-review if substantial.

**5 · Verify.** Launch **qa-automation**: parse gate, the regression suite (Basic at
least, Full when rules or autoloads changed), a headless boot of touched scenes, and
a `/probe` still at 443x963 for anything visual. If it FAILS, loop back to the
responsible specialist and re-verify. Never proceed on a failed check.

**6 · Checkpoint.** Update `.claude/context/STATE.md` (current focus, known issues,
decisions if any) and append a `.claude/context/JOURNAL.md` entry (date, request,
agents run, files touched, verification result, follow-ups).

**7 · Report.** If `PushNotification` is available (ToolSearch
`select:PushNotification`), send a one-line summary. Then give a concise written
report: what each agent did, files changed, verification evidence, open items.

If a step is not applicable, say so and continue. Never silently skip review or
verify. Anything destructive (deleting files, force-pushing, rewriting history):
ask me first. Commits carry no `Co-Authored-By` trailer.
