# The Tic Tac Toe Limitless AI Organization

A small "company" of AI agents that builds and maintains this Godot game, with a
shared persistent memory so no agent starts cold. Everything is scoped to **this
repo** plus the Godot binaries, Godot's user-data dir, adb, and the two sibling
repos (2048, Sudoku) as read-only reference. There is no backend to reach.

> **Setup:** open the project folder itself in Claude Code so this `.claude/` tree and
> the root `CLAUDE.md` load automatically.

## Map of this folder

```
.claude/
├── README.md              ← you are here
├── settings.json          ← permissions (routine = auto, destructive = ask, keystores = deny)
├── agents/                ← the 5 specialists (Claude picks them by description, or name them)
│   ├── ui-designer.md
│   ├── godot-ui-engineer.md
│   ├── game-logic-engineer.md
│   ├── code-reviewer.md
│   └── qa-automation.md
├── commands/              ← /slash commands you type
│   ├── orchestrate.md  prime.md  checkpoint.md  standup.md
│   ├── design.md  new-theme.md
│   ├── playtest.md  probe.md  regress.md  build-apk.md
│   └── solid-check.md
└── context/               ← the shared MEMORY (read first, kept up to date)
    ├── STATE.md           ← living snapshot: what the app is + what is going on now
    ├── JOURNAL.md         ← append-only history of work
    └── designs/           ← design briefs from ui-designer (created on first use)
```

Probe screenshots stay out of the repo. They land in
`%APPDATA%\Godot\app_userdata\Tic Tac Toe Limitless\screen_probe\` and agents read
them from there.

## The team

| Agent | Owns |
|-------|------|
| **ui-designer** | Design briefs (layout, color roles, type, motion, copy) under the neon-glass material law. |
| **godot-ui-engineer** | Screens, widgets, themes, fonts, icons, animation, the gameplay views. |
| **game-logic-engineer** | `core/rules` (board engine + rule plug-ins) and `core/ai` (minimax, MCTS, personas, puzzles). Pure, unit-tested. |
| **code-reviewer** | SOLID, conventions, project law, duplication, dead code, loopholes, tests moved with the code. |
| **qa-automation** | Parse gate, regression suite, probe stills at 443x963, headless boots, APK export. |

The **orchestrator** is the `/orchestrate` command (the main thread conducts;
subagents cannot call subagents).

## Commands cheat-sheet

| Type this | To... |
|-----------|-------|
| `/prime [area]` | Warm up a fresh session (memory + git). Run this first. |
| `/orchestrate <feature>` | Deliver a whole feature: plan → design → build → review → verify → checkpoint. |
| `/design <prompt>` | Get a design brief only. |
| `/new-theme <vibe>` | Design + add a theme `.tres`, walk the theme checklist, shoot it. |
| `/playtest [scene]` | Parse gate, boot, probe stills for a change. |
| `/probe <screen> [themes]` | Shoot one screen at phone scale and read the PNGs back. |
| `/regress [-Tier Basic]` | Run the regression suite; explain each failure as stale-test or broken-app. |
| `/build-apk [debug\|release]` | Export the Android APK. |
| `/solid-check [area]` | Review the current diff for quality. |
| `/checkpoint [note]` | Save current state to memory for the next session. |
| `/standup` | Read-only status report. |

You can also just describe a task. Claude routes it to the right specialist from the
agent descriptions.

## How memory works

1. `context/STATE.md` is the single source of truth for "what is this app and what
   is going on right now." Every agent reads it first. Its §7 holds the decisions
   the user does not want re-asked.
2. `context/JOURNAL.md` is the history, appended after each unit of work.
3. The root `CLAUDE.md` tells every session to read both plus `ARCHITECTURE.md`.
4. `/checkpoint` (and `/orchestrate`'s last step) keep them current. **Run
   `/checkpoint` before ending a working session.**
5. The user's cross-session notes live outside the repo in
   `C:\Users\SAI GOPAL\.claude\projects\e--TIC-TAC-TOE\memory\`. STATE.md must agree
   with them.

## Permissions (`settings.json`)

- **Auto (no prompt):** file reads and edits, routine git (status, diff, add, commit,
  branch, stash, fetch, pull), adb, keytool / jarsigner / java, python, both Godot
  binaries, the regression runners.
- **Asks first:** `git push`, `git reset --hard`, `git clean`, `git rebase`,
  `git branch -D`, any `rm` / `Remove-Item`.
- **Denied:** `rm -rf`, `Remove-Item -Recurse -Force`, reading any `.keystore` or
  `.jks`.

Edit `settings.json` or run `/permissions` to adjust. Per-machine overrides go in
`settings.local.json` (gitignored).
