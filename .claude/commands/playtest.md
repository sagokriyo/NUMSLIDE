---
description: Launch Godot and verify the game (or a specific screen) actually works: parse gate, boot, probe stills (runs qa-automation).
argument-hint: (optional) scene path, screen key or feature to verify, e.g. "home" or "res://scenes/gameplay/gameplay.tscn"
---

Launch the **qa-automation** subagent (Agent tool) to verify the game.

Target: **${ARGUMENTS:-the main scene and the most recently changed area}**

Tell it to:
1. Read `.claude/context/STATE.md` (Build & tooling) for the Godot paths and commands.
2. Run the parse gate first and quote any failure line.
3. Boot the target scene headless with `--quit-after 40` and quote any
   `SCRIPT ERROR` / `Parse Error`.
4. Shoot the target screen with `tools/screen_probe.tscn` at `--resolution 443x963`
   in a dark and a light theme, read the PNGs back from
   `%APPDATA%\Godot\app_userdata\Tic Tac Toe Limitless\screen_probe\`, and confirm
   they look right (nothing clipped, root within the frame, glass everywhere, type
   not glowing).
5. If a design brief or acceptance criteria exist for the recent change, verify each
   and report **PASS / FAIL per criterion** with evidence (log lines + PNG paths).
6. On failure, identify the responsible agent and the exact error. Do not fix it here.

If this is likely something I'm waiting on, have it send a PushNotification when
that tool is available.
