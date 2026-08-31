---
description: Persist the current state of the app and recent changes into shared memory so the next session or agent has full context.
argument-hint: (optional) short note on what was just done
---

Capture the current state into shared memory so no future agent starts cold.

1. Gather reality: `git --no-pager log --oneline -8`, `git status --porcelain`, and
   recall what changed this session.
2. Update `.claude/context/STATE.md`:
   - Bump **Last updated** to today's date and what updated it.
   - Refresh **§2 Current focus / in-flight** to reflect reality now, including
     which phase step landed.
   - Add or clear items in **§6 Known issues**. Remove fixed items, add new ones.
   - Append to **§7 Decisions log** only when a real decision was made this session.
3. Append an entry to `.claude/context/JOURNAL.md` using the template at the top of
   that file (date, request, agents, changes, verified, follow-ups). Fold in
   `$ARGUMENTS` if provided.
4. If a plan step landed, update the memory note
   `C:\Users\SAI GOPAL\.claude\projects\e--TIC-TAC-TOE\memory\tictactoe-plan.md` so
   it says which step is next.
5. Keep STATE.md a *snapshot* (concise, current) and JOURNAL.md the *history*
   (append-only). Confirm what you wrote in 2 or 3 lines.

Do not commit unless I ask. When you do commit, no `Co-Authored-By` trailer.
