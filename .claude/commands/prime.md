---
description: Warm up a fresh session. Load shared memory, recent history, and key files so you and the agents do not start cold.
argument-hint: (optional) area to focus on, e.g. "rules", "ai", "themes", "gameplay"
---

Load context for this session. Do it efficiently, then give me a 6 to 10 line briefing.

1. Read `.claude/context/STATE.md` (the living snapshot) and the latest ~3 entries of
   `.claude/context/JOURNAL.md`.
2. Read the recent git history: `git --no-pager log --oneline -10` and
   `git status --porcelain`.
3. If `$ARGUMENTS` names a focus area, also skim the most relevant files for it:
   rules → `core/game_modes.gd` + `core/rules/`; ai → `core/ai/`; themes →
   `data/themes/theme_data.gd` + `autoload/theme_manager.gd` + `core/entitlements.gd`;
   gameplay → `scenes/gameplay/`; economy → `core/economy_rules.gd` +
   `autoload/progression.gd`. Otherwise skim the root `CLAUDE.md` headings only.

Then summarize: **what the app is, which phase we are in, the current focus,
uncommitted changes, top known issues, and what you'd suggest doing next.** Do not
change any files. This is read-only priming.
