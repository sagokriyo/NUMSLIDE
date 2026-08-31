# CLAUDE.md

This file guides Claude Code (claude.ai/code) when working in this repository. The
repo is maintained by a small **AI organization** (specialist subagents, an
orchestrator, slash commands) backed by a shared persistent memory in `.claude/`.

> Open the project folder itself in Claude Code so `.claude/` and this file load.
> Everything is scoped to this repo, the Godot binaries, Godot's user-data dir, adb,
> and the two sibling repos as read-only reference.

## Read order for every task

1. **@.claude/context/STATE.md**: the living snapshot (what the app is, the phase and
   focus, known issues, build facts, the decisions the user will not re-ask). Always
   read first.
2. **@.claude/context/JOURNAL.md**: the work log (how we got here).
3. **@ARCHITECTURE.md**: the map (folders, singletons, move pipeline, material law,
   saves, mode catalog, roadmap).

> Run `/prime` at the start of a session to load all of the above plus recent git history.

## The org chart

| Agent | Role | Hands off to |
|-------|------|--------------|
| **ui-designer** | Turns a prompt or reference into an implementation-ready design brief under the neon-glass material law. Specs, not code. | godot-ui-engineer |
| **godot-ui-engineer** | Builds screens, widgets, themes (`.tres`), fonts, icons, animation and the gameplay views in Godot 4.7.1 GDScript. | code-reviewer |
| **game-logic-engineer** | Owns `core/slide` (board, rule plug-ins, solver, pace). Pure, unit-tested, no nodes. | code-reviewer |
| **code-reviewer** | SOLID, conventions, project law, duplication, dead code, loopholes, tests moved with the code. Runs after any code change. | (back to the author) |
| **qa-automation** | Parse gate, regression suite, headless boots, probe stills at 443x963, APK export. Proves it, never assumes it. | (reports back) |

The **Orchestrator** is the `/orchestrate` command run in the main thread (subagents
cannot spawn subagents). Pipeline: plan → design → build → review → verify → checkpoint.

## Custom commands (`.claude/commands/`)

| Command | Does |
|---------|------|
| `/prime [area]` | Load STATE, JOURNAL, git log, key files for an area. |
| `/orchestrate <feature>` | The full pipeline for one feature. |
| `/design <prompt>` | ui-designer → a design brief. |
| `/new-theme <vibe>` | Design + add a `ThemeData` `.tres`, walk the theme checklist, shoot it. |
| `/playtest [scene]` | qa-automation: parse gate, boot, probe stills. |
| `/probe <screen> [themes]` | Shoot one screen at 443x963 and read the PNGs back. |
| `/regress [-Tier Basic]` | Run the regression suite; explain failures as stale-test or broken-app. |
| `/build-apk [debug\|release]` | Export the Android APK. |
| `/solid-check [area]` | code-reviewer on the current diff. |
| `/checkpoint [note]` | Persist state + a journal entry. Run before ending a session. |
| `/standup` | Read-only status report. |

## Project

**NUMSLIDE Limitless**, by Sago Kriyo Games. Five ways to slide, numbers made of
glass. Built in **Godot 4.7.1** with **GDScript**. Portrait, mobile renderer, full
neon-glass look on a dark ground. Android only via Google Play. **Play Games
Services is the whole backend** (identity, achievements, leaderboards; premium is
one lifetime Play Billing unlock). **No Supabase.** **Offline, and SOLO:** there
is no opponent. The board is dealt with a PAR and the run is graded against it
(`core/slide/pace.gd`). Tic Tac Toe Limitless is the shell and the design source
of truth. The map lives in [ARCHITECTURE.md](ARCHITECTURE.md).

## Engine & tooling

- **Engine:** Godot 4.7.1 stable, the only engine on this machine. Editor binary
  `D:\Godot_v4.7.1-stable_win64.exe`; use `D:\Godot_v4.7.1-stable_win64_console.exe`
  for headless and probe runs so output reaches the terminal. CI runs the same version.
- **Language:** GDScript only. No C# / .NET.
- **Renderer / display:** `mobile` method, D3D12 on Windows, **`gl_compatibility` on
  Android (locked)**, portrait 1080x2340, `canvas_items` stretch, UI scale 1.1
  (`SceneRouter.UI_SCALE`), so the phone's design space is ~982 px wide. Probe at
  `--resolution 443x963`.
- **Android tooling (not on PATH):** adb
  `C:\Users\SAI GOPAL\AppData\Local\Android\Sdk\platform-tools\adb.exe`; Java from
  Android Studio's JBR; Python 3.14 + Pillow + numpy for `tools/*.py`; git 2.55; no `gh`.
- **Package id** `com.sagokriyo.numslide`. GitHub org `sagokriyogames`.

## Commands

`<godot>` = `D:\Godot_v4.7.1-stable_win64_console.exe` (quote it). Run from the
project root. Every `.ps1` in `regression/` defaults `-Godot` to this path.

- **Open in editor:** `& <godot> -e --path .`
- **Run the game:** `& <godot> --path .` (main scene `res://scenes/intro/intro.tscn`)
- **Run a scene:** `& <godot> --path . res://scenes/home/home.tscn`
- **Refresh imports and `class_name`s:** `& <godot> --headless --path . --import`.
  This is NOT a parse gate: it returns 0 against a broken script.
- **Parse gate (the real "does it compile"):**
  `& <godot> --headless --path . --script res://regression/headless/parse_gate.gd`
  → one `PARSE_GATE: PASS|FAIL|...` line, ~3 s.
- **Regression suite:** `powershell -ExecutionPolicy Bypass -File regression\headless\run_all.ps1`
  (`-Tier Basic` for the fast gate; `-Filter`, `-List`, `-SkipImport`). Import gate,
  parse gate, every suite in `tests/` and `regression/headless/suites/`, every flow
  in `regression/headless/flows/`, scene smokes, boot smoke; one Godot process per
  test; the user save backed up and restored; exit code = failed tests. Strategy in
  [regression/STRATEGY.md](regression/STRATEGY.md). The tier comes from the test's
  directory. `--script` tests compile before autoloads register, so suites extend
  the harness bases in `regression/headless/harness/` and `load()` screens at
  runtime. **When you add a suite, add a mutation to
  `regression/headless/verify_tests.ps1`**; a test nobody has watched fail proves
  nothing.
- **One test:** `& <godot> --headless --path . --script res://regression/headless/harness/headless_boot.gd -- --test=res://tests/test_economy_rules.gd`
- **Smoke-test a screen headlessly:** `& <godot> --headless --path . res://scenes/<x>/<x>.tscn --quit-after 40`, then read stderr.
- **Probe a screen (needs a window):**
  `& <godot> --path . res://tools/screen_probe.tscn --resolution 443x963 -- <screen> <theme ...>`
  → PNGs in `%APPDATA%\Godot\app_userdata\NUMSLIDE Limitless\screen_probe\`.
  `--free` shoots a non-premium player, `--page=<x>` opens a screen's
  `probe_show_page`, env `WIDTH_PROBE=981` lists anything wider than the frame.
- **Export:** `& <godot> --headless --path . --export-debug "Android" "build\numslide.apk"`
  once `export_presets.cfg` exists (Phase 5). `--export-release` needs the release
  keystore, which is never read or committed.

## Architecture in one paragraph

Seventeen **autoload singletons** form the backbone, sixteen in `autoload/` plus
the Play Games addon's own, in load order: `SaveManager` (atomic sectioned JSON),
`SettingsManager`, `EntitlementManager` (the runtime truth for premium),
`BillingService`, `GodotPlayGameServices`, `DesignSystem` (spacing / type / motion
tokens and the house gains), `ThemeManager` (61 `ThemeData` palettes, a runtime
`Theme`, the tile ramp), `AudioManager`, `Haptics`, `GameStats`, `Achievements`,
`PlayGames`, `AccountManager`, `AdManager`, `Wallet`, `Progression` (**the one
funnel every mode reports play through** and the only place coins are earned), and
`SceneRouter` (all navigation; a 0.16 s crossfade, no black frame). Order matters:
each may reference those above it. Pure logic lives in `core/` with zero node
dependencies: `GameModes` (5 modes as data), `EconomyRules`, `WalletRules`,
`Entitlements`, `Bounties`, `PlayGamesIds`, `StoreProducts`, `BillingPayloads`,
and **`core/slide/`** — `SlideBoard` (cells, goal, holes, distance, solvability),
`SlideRules` + one plug-in per mode, `SlideSolver` (IDA* / group A* / torus BFS /
greedy) and `Pace` (the four grades). Screens live in `scenes/<name>/` as a thin
`.tscn` + a script extending `AppScreen`; the board visuals in `scenes/gameplay/`.
The shared widget library is `ui/` (`AppScreen`, the `UI` factory, `GlassPanel`,
`PremiumButton`, `ModalOverlay`, `BottomNav`, `IconLibrary`, `ExtrudedWord`,
`CandyFace`, `TileFace`, `HeroBoard`, `Confetti`, `GlassDrift`, `ShockWave`).
Themes are `data/themes/*.tres` with baked cards in `assets/theme_cards/`.

## Conventions & gotchas (read these, they will bite you)

- **The renderer is LOCKED to `gl_compatibility` on Android. Never change it.** Not
  back to Vulkan, not "temporarily" for a comparison. Measured on an Adreno 650
  (iQOO): Vulkan carried a p95 of 24 to 29 ms on Home while GL held p50 = p95 =
  16.67 ms. Perceived lag lives in the variance. Accepted costs: no 2D MSAA on
  device, and cold-launch shader warm-up matters (`PipelineWarmup`).
- **Every change ships with its tests updated. The work is not done until the suite
  is green.** When a test fails, decide with evidence whether the test is stale or
  the app broke. A stale assertion is rewritten to pin the new contract, never
  deleted or loosened. Hardcoded counts and copy that track a catalog (theme count,
  route-table size, "All N themes") only fail in tests. Tests pin the state they
  depend on (settings, save sections, timing) instead of reading the developer's
  save or racing the frame clock.
- **Code-first UI.** A screen is a thin `.tscn` (one `Control` root + script). The
  script overrides `AppScreen.build_content(root: VBoxContainer)` and composes `UI.*`
  widgets. Do not hand-author node trees. Theme changes rebuild content
  automatically; Gameplay overrides this so a live board is not torn down.
- **`var x := <Variant>` is a hard parse error.** Any right-hand side typed `Variant`
  (a `Dictionary` index, an untyped `Array` element, `event.pressed` on a base
  `InputEvent`) needs an explicit type: `var h: int = d["hour"]`.
- **Autoload references show false LSP errors** until the editor reloads
  `project.godot`. They are not real. Verify with the parse gate, not the live linter.
- **Validate by running.** The parse gate is the truth for parse errors; `--import`
  refreshes imports and is blind to a broken `.gd`; headless boots and the suite
  catch runtime errors; a probe still catches layout.
- **A composite tappable needs `UI.pass_through(root)` before
  `UI.make_scroll_tappable(root, ...)`.** `Control` defaults to `MOUSE_FILTER_STOP`,
  so a child panel takes the tap and the widget renders perfectly and does nothing.
  Never layer a momentum tween over `ScrollContainer`; STOP controls inside a scroll
  must PASS.
- **`apply` on a rule MUST have no side effects.** It moves the board and
  returns events, nothing else. The solver explores by applying candidate moves
  to clones, so a rule that counted a score or re-dealt the tray inside `apply`
  corrupted every search that touched it (Rush did both; one solve banked three
  boards and IDA* could never reach a finished position). The rule emits
  `cleared`; the conductor banks it and calls `deal_next`.
- **A Control's `size = x` only notifies when the value CHANGES.** A child sized
  by hand from a `_notification(NOTIFICATION_RESIZED)` handler stays at zero when
  the parent is handed the same number twice, and draws nothing. Anchor children
  to the parent instead (`set_anchors_preset(PRESET_FULL_RECT)`).
- **`SlideBoard.clone()` may share `goal` and `_home` but NEVER `cells` or
  `_at`.** A packed-array member assignment shares the buffer; the two the slide
  writes to have to be duplicated or every clone corrupts its parent.
- **Gameplay overrides `_on_theme_changed`.** `AppScreen` rebuilds its content on
  a palette change, and this screen IS the state: `build_content` makes an empty
  tray and only `on_ready` deals a board into it, so the inherited behaviour
  swapped a live run for an empty grid.
- **A scramble is a WALK, never a shuffle.** Half of all arrangements of an
  N-puzzle are unreachable. Walking out of the solved position can only reach
  what it can walk back from, and it is correct on the torus too,
  where the parity test means nothing.
- **`draw_colored_polygon` re-triangulates on every draw.** Triangulate once
  (`Geometry2D.triangulate_polygon`), cache the index buffer, replay with
  `RenderingServer.canvas_item_add_triangle_array` (`ExtrudedWord._stamp_mesh` is the
  pattern). Measure with `tools/spike_probe.tscn` before guessing.
- **`CPUParticles2D`, never `GPUParticles2D`.** GPU particles render nothing on many
  Android drivers. Keep counts at or under ~130 per emitter.
- **Shader `smoothstep` edges must ascend.** A reversed smoothstep renders black on
  D3D12. Use `1.0 - smoothstep(a, b, x)`.
- **Never tween rotation / scale / pivot on a Control that draws.** It queues a redraw
  every frame. Tween a bare pivot parent and draw on a child.
- **No black-frame transitions.** `SceneRouter` builds the new page while the old one
  stays on view, then crossfades 0.16 s. Never `change_scene_to_file`, never a fade
  through black, not even 0.12 s. A page's own entrance stays under ~0.7 s.
- **Screen-reading FX sample the latest `BackBufferCopy`.** `ShockWave` is a moment
  cost (~0.6 s), never per-frame or per-tap. Negative `z_index` hides under
  `AppScreen`'s backdrop; layer with tree order.
- **A hold that outlives its node:** use a tween interval on the node, not
  `get_tree().create_timer`, or `_ready` resumes into a freed instance.
- **Probes and tests are scenes** (or extend the harness bases). A bare
  `extends SceneTree --script` compiles before autoloads exist. Headless cannot
  render particles or shaders; screenshot from a real window.
- **Judge visuals at 443x963.** That window is the phone's true UI space. A larger
  desktop window under-judges size, and a window taller than the monitor gets
  clamped and widened.
- **Copy voice.** One short plain sentence per string, contractions welcome. No em
  dashes (period, comma or colon instead), no aphorisms, no adjective triads, no
  restating what the UI already shows. Mode taglines about 45 characters, the
  challenge line under 70. A self-explanatory toggle gets no subtitle.
- **Comments: short and on point.** Say why, once. A doc comment that restates
  the code, or repeats a rationale already given above it, is noise.
- **Commits carry no `Co-Authored-By` trailer.** Never rewrite pushed history.
- **Missing audio is fine.** `AudioManager` no-ops when a file is absent.
- **Line endings: LF**, UTF-8 (`.gitattributes` / `.editorconfig`).
- **`.godot/`** is generated and gitignored. Commit `.import` / `.uid` sidecars next
  to their resource. `*.keystore` / `*.jks` are gitignored and never read.
- **The Bash tool mangles apostrophes and backslashes in big inline heredocs.** Write
  patch scripts to a file and run by path.
- **An open editor rewrites `project.godot` and `export_presets.cfg` from memory** on
  save. Check those files after any editor session.

## Where things go (extending the game)

- **New screen:** `scenes/<name>/<name>.gd` extending `AppScreen`, a thin
  `<name>.tscn`, and a `Route` entry in `autoload/scene_router.gd`. It gets no bottom
  bar unless it overrides `nav_tab()`; the bar is for the five `BottomNav.TABS`.
- **New game mode:** a config dict in `core/game_modes.gd` `_CONFIGS` whose `rule`
  is in `RULES`, plus a plug-in in `core/slide/` emitting the engine's typed
  events (no engine edits). **The rule must be the mode's own**: `test_game_modes`
  fails a rule shared by two modes, with NO exceptions. A sliding puzzle with a
  clock bolted on is not a second mode; Rush earns its place because solving does
  not END a run there, it re-deals one. The config also carries `challenge` (what
  the board asks of you, under 70 chars) and `lesson` (the one line the Academy
  teaches first), plus a crown in `Achievements.DEFS` with a `PlayGamesIds`
  slot, a `MODE_WIN_GEMS` entry, an `icon_path`, a Home colour story, a listing
  on exactly one of Home's featured trio or Mode Select, and a lesson in the
  Academy's `LESSONS`. Play is reported only through `Progression`. The suites
  fail on a mode missing any catalog.
- **New theme:** a `.tres` in `data/themes/` filling the `ThemeData` contract; its id
  in `data/themes/theme_ids.gd`; its tier in `core/entitlements.gd` (`FREE_THEMES`,
  `SHOP_THEMES` with a gem price, or premium by default; `category` must agree); a
  ramp whose rungs stay apart across the row bands; the card baked with
  `& <godot> --path . res://tools/theme_backdrop_bake.tscn -- <id>` (real window),
  then `--import`, and the `.webp` + `.import` committed under `assets/theme_cards/`;
  any hardcoded theme count updated. Type stays Malam Poek + Nunito; nothing about a
  theme may change a font or make type glow.
- **Economy change (a rate, a price, a payout):** edit `core/economy_rules.gd` and
  nothing else. `Wallet` holds balances, `Progression` decides when. Never call
  `Wallet.add()` from a screen; spending happens at the point of use and **must check
  `spend()`'s return**. The economy is tier-neutral and soft currency is never sold
  for money.
- **Solver work:** `core/slide/solver.gd`. Every strategy is CAPPED and the last
  one cannot fail: a hint that thinks for four seconds has already failed the
  player. `tests/test_solver.gd` pins that it answers on every mode at every size
  the game deals, and that it never moves the board it was asked about.
- **A new grade or a change to par:** `core/slide/pace.gd` and nothing else.
  `EconomyRules.PACE_BONUS` must price every rung; the progression suite fails
  when the two drift.
- **New achievement:** `Achievements.DEFS`, the matching `report_*` through
  `Progression`, and a `PlayGamesIds.ACHIEVEMENTS` slot; the progression suite fails
  when the catalogs drift.
- **New daily bounty:** a dict in `core/bounties.gd` `DEFS` with an existing `KIND_*`;
  a new kind also needs one `_advance_bounties()` call in `Progression`.
- **New design token or color:** `DesignSystem` for spacing / type / motion;
  `ThemeManager` palettes for color. Never hardcode colors or magic spacing.
