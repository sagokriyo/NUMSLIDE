---
description: Review the current changes for SOLID, conventions, duplication, dead code, and loopholes (runs code-reviewer).
argument-hint: (optional) path or area to focus the review
---

Launch the **code-reviewer** subagent (Agent tool) to review the current work.

Focus: **${ARGUMENTS:-the current uncommitted diff}**

Tell it to:
1. Read `.claude/context/STATE.md` for conventions and focus, and the root
   `CLAUDE.md` for the gotchas and the "Where things go" rules.
2. Review the actual diff (`git diff` / `git diff --staged`) plus enough surrounding
   code to judge correctly. Not the whole repo.
3. Check SOLID as applied to Godot / GDScript, this repo's conventions (naming, tabs,
   typed GDScript, code-first UI, signal-driven, no hardcoded theme colors, sizes
   through `DesignSystem.type()`), project law (`core/` stays pure, earning only in
   `Progression`, numbers only in `core/economy_rules.gd`, CPUParticles2D only, no
   fade-to-black, no `Co-Authored-By`), duplication / dead code, correctness
   loopholes (unhandled `await`, coroutine races, holds outliving nodes, unfreed
   signals, swallowed errors), and that tests moved with the behavior.
4. Return findings grouped Blocking / Should-fix / Nice-to-have, each with
   `file:line`, why it matters, and a concrete fix. Fix trivial and safe items
   directly; flag the rest. End with a verdict: ship / fix-then-ship / needs-rework.
