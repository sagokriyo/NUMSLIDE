---
description: Export the Android APK with Godot and report when it is ready (runs qa-automation).
argument-hint: debug | release  (default debug)
---

Launch the **qa-automation** subagent (Agent tool) to build the Android APK.

Build type: **${ARGUMENTS:-debug}**

Tell it to:
1. Read `.claude/context/STATE.md` (Build & tooling). Preset name is `Android`, output
   `build\tictactoe.apk`, arm64-v8a, package `com.sagokriyo.tictactoe`. Run from the
   project root with `--path .`.
2. Check that `export_presets.cfg` exists. If it does not (Phase 5 has not landed),
   STOP and tell me the preset must be created in the editor first (Project → Export,
   Android, arm64-v8a, the four `launcher_icons/*` slots pointing at `assets/icon/*`,
   `exclude_filter` covering `brand/*,tools/*`). Do not invent one.
3. Run the parse gate and the Basic tier of the suite so we never package broken code.
4. Run the export headless:
   - debug: `& "D:\Godot_v4.7.1-stable_win64_console.exe" --headless --path . --export-debug "Android" "build\tictactoe.apk"`
   - release: `--export-release "Android" "build\tictactoe.apk"` (requires a
     configured release keystore; if it is missing, STOP and say exactly what to set
     up; never produce an unsigned build silently; never read a `.keystore` file).
5. Confirm the APK exists and report its path and size. If export templates are
   missing, report Godot's exact message and the fix (Editor → Manage Export
   Templates). If the debug keystore's SHA-1 is not registered as a Play Games
   Android OAuth client, PGS sign-in fails on device; say so.
6. If `PushNotification` is available (ToolSearch `select:PushNotification`), notify
   me that the APK is ready (with path) or that the build failed (with the reason).
