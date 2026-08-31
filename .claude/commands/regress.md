---
description: Run the headless regression suite and explain every failure as stale-test or broken-app.
argument-hint: (optional) -Tier Basic | -Filter <glob> | -List
---

Run the regression suite from the project root:

```powershell
powershell -ExecutionPolicy Bypass -File regression\headless\run_all.ps1 ${ARGUMENTS}
```

With no arguments this is the Full tier: import gate, parse gate, every unit and
service suite (`tests/`, `regression/headless/suites/`), every full-boot flow
(`regression/headless/flows/`), every scene smoke (`tests/*.tscn`), and a boot smoke
of intro → splash → home. Each test runs in its own Godot process. The user save is
backed up and restored. `-Tier Basic` is the fast gate (import + parse + suites).
Exit code = number of failed tests. Logs land in `regression/headless/.results/<stamp>/`.

Report:
1. The verdict lines verbatim: the `PARSE_GATE: ...` line and the runner's final
   summary (passed / failed / timed out counts).
2. For each failure: the test name, the first `SCRIPT ERROR` or assertion line from
   its `.out.log` / `.err.log`, and the product file it points at.
3. For each failure, decide with evidence which it is:
   - **Stale test**: the behavior changed on purpose this session and the assertion
     pins the old contract. The fix is to rewrite the assertion to pin the new
     contract (never delete it, never loosen it), then re-run.
   - **Broken app**: the assertion still describes what we want and the code no
     longer does it. Name the responsible agent (game-logic-engineer /
     godot-ui-engineer) and the exact line.
   - A `PARSE_GATE: FAIL` is always broken app; the report names the root file and
     every file that cascaded off it. Fix the root first.
   - `ORACLE_BROKEN` or `COVERAGE_GAP` from the parse gate means the gate itself needs
     attention before anything else is trusted.
4. If a suite was added this session, remind me it needs a mutation in
   `regression/headless/verify_tests.ps1`, and offer to run
   `powershell -ExecutionPolicy Bypass -File regression\headless\verify_tests.ps1 -Filter <name>`.

Do not edit product code inside this command. Report, then hand fixes to the right
agent or ask me.
