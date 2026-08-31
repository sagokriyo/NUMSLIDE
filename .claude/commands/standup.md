---
description: Standup-style status report from shared memory and git. Read-only, no changes.
argument-hint: (none)
---

Give me a crisp standup report. Read-only. Change nothing.

Pull from `.claude/context/STATE.md`, the last few `.claude/context/JOURNAL.md`
entries, `git --no-pager log --oneline -10`, and `git status --porcelain`.

Report in this shape:
- **Phase:** which plan phase we are in and the step in flight.
- **Now:** the current focus (1 or 2 lines).
- **Recently done:** the last 3 to 5 meaningful changes (journal + git).
- **Uncommitted:** working-tree changes, if any.
- **Risks / known issues:** top items from STATE §6, by severity.
- **Suggested next:** the 1 to 3 highest-leverage things to do next, and which agent
  or command handles each (e.g. "`/regress` → qa-automation", "Vanish rule plug-in →
  game-logic-engineer").
