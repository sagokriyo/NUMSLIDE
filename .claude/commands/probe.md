---
description: Shoot a screen at phone scale in one or more themes and read the stills back.
argument-hint: <screen> [theme ...] [--free] [--page=<x>]  e.g. "home starforged carrara"
---

Shoot the screen from the project root (needs a window, never `--headless`):

```powershell
& "D:\Godot_v4.7.1-stable_win64_console.exe" --path . res://tools/screen_probe.tscn --resolution 443x963 -- $ARGUMENTS
```

- `<screen>` is a route key the probe knows (home, mode_select, gameplay, settings,
  statistics, achievements, themes, profile, badge, premium, shop, leaderboard,
  rewards, how_to_play, ...). Check `tools/screen_probe.gd` for the current list.
- With no themes the probe shoots a dark and a light theme, the two ends of the
  catalog where layout breaks show. Name themes to shoot specific ones.
- `--free` photographs a non-premium player with a small purse so locked states show.
- `--page=<x>` calls the screen's `probe_show_page(x)` to open a tab, sheet or state.
- `PROBE_WAIT=<seconds>` in the environment holds the shot for a timed entrance.
- `WIDTH_PROBE=981` lists every control whose minimum width exceeds the phone frame.
- 443x963 is the phone's true UI space (~982 design px at UI scale 1.1). Do not
  judge size in a bigger window.

The PNGs land in:

```
%APPDATA%\Godot\app_userdata\Tic Tac Toe Limitless\screen_probe\
```

Then Read each PNG back and report what you see: does the page fit the frame, is
every surface glass, do the marks read as neon tubes, is the type on the floor size
and not glowing, does anything clip or overflow. Quote the probe's "wrote N frames"
line and any `SCRIPT ERROR`. If the probe reports an unknown screen key, list the
keys it accepts.
