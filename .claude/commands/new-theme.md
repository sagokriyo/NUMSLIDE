---
description: Design and add a new ThemeData .tres theme end to end, then verify it renders.
argument-hint: <theme vibe / name, e.g. "deep sea neon, calm, colorblind-safe">
---

Create a new theme: **$ARGUMENTS**

1. Launch **ui-designer** (Agent tool) to produce the theme concept: a full set of
   `ThemeData` field values (surfaces, text, accent, the tile ramp the marks draw
   from, effects, background world, ambience) that reads well on glass and keeps the
   X and O far apart in hue. Have it sanity-check text-on-surface contrast and say
   whether the theme is dark or light.
2. Launch **godot-ui-engineer** (Agent tool) to implement it as
   `data/themes/<slug>.tres` in the exact format of an existing theme (for example
   `data/themes/starforged.tres`), then walk the checklist in the root `CLAUDE.md`
   under "New theme": add the id to `data/themes/theme_ids.gd`; place it in
   `core/entitlements.gd` (`FREE_THEMES`, `SHOP_THEMES` with a gem price, or premium
   by default) and keep `category` in agreement; run the ramp separation check if the
   probe exists here; bake the card with
   `& "D:\Godot_v4.7.1-stable_win64_console.exe" --path . res://tools/theme_backdrop_bake.tscn -- <slug>`
   (needs a real window, never headless), then `--headless --path . --import`, and
   commit the `.webp` + `.import` under `assets/theme_cards/`; update any hardcoded
   theme count the tests pin.
3. Launch **qa-automation** (Agent tool) to run the theme suites
   (`run_all.ps1 -Filter *theme*`) and shoot Home and Gameplay in the new theme with
   `/probe`.
4. Append a short JOURNAL entry noting the new theme.

Report with the PNG paths and the final `.tres` location.
