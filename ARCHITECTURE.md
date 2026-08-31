# NUMSLIDE Limitless: Architecture

Five ways to slide, numbers made of glass. The map: folders, the singleton
backbone, the move pipeline, the material law, saves, themes, the mode catalog.

---

## 1. How the look is held

Not by each screen. Two layers:

- **`DesignSystem`** (autoload): the invariant tokens. An 8 pt spacing scale, the
  type ramp with the house gains (`TYPE_GAIN` 1.10, `TYPE_FLOOR` 32, `ICON_GAIN`
  1.12), corner radii, motion durations, shadow presets.
- **`ThemeManager`** (autoload): the variable tokens. 61 `ThemeData` palettes, a
  runtime `Theme` applied to every Control, and the tile ramp.

Screens compose from the static **`UI`** factory and the **`AppScreen`** base, so
no screen invents its own spacing, colour or typography. Fonts are not part of a
theme: Malam Poek (display) and Nunito (reading) on every palette, and type never
glows.

The regression suite is where the contracts in this document live. Any change
here ships with its tests updated in the same commit.

---

## 2. Folders

```
res://
├── project.godot                # autoloads (in order), display, renderer, main scene
├── autoload/                    # the singleton backbone (§3), in load order
├── core/                        # pure rules, NO nodes, NO UI (unit-tested)
│   ├── game_modes.gd            #   the 5 modes as data + RULES + RANKED_MODES
│   ├── economy_rules.gd         #   every coin / gem number
│   ├── entitlements.gd          #   free vs shop vs premium
│   ├── bounties.gd  wallet_rules.gd  play_games_ids.gd  store_products.gd
│   └── slide/                   #   THE ENGINE
│       ├── slide_board.gd       #     cells, goal, holes, distance, solvability
│       ├── slide_rules.gd       #     the plug-in contract + the factory
│       ├── rules_<id>.gd        #     one per GameModes.RULES entry
│       ├── solver.gd            #     IDA* / group A* / turn BFS / greedy
│       └── pace.gd              #     the four grades a run is marked against
├── ui/
│   ├── screen.gd                # AppScreen (backdrop, safe area, frame, entrance)
│   ├── components/              # UI factory, GlassPanel, PremiumButton, ModalOverlay,
│   │                            # BottomNav, IconLibrary, ExtrudedWord, CandyFace,
│   │                            # TileFace, HeroBoard, Confetti, GlassDrift, ...
│   ├── fx/                      # ShockWave, BurstShapes
│   └── shaders/                 # glass.gdshader, glass_lite.gdshader
├── scenes/                      # one folder per screen (thin .tscn + script)
│   ├── intro/  splash/  auth/  home/  how_to_play/
│   ├── gameplay/                # gameplay.gd (conductor), board_view, tile_view,
│   │                            # slide_hud, board_fx, reward_fx
│   ├── settings/  statistics/  achievements/  themes/  profile/  badge/
│   └── premium/  shop/  leaderboard/  rewards/
├── data/themes/                 # theme_data.gd, theme_ids.gd, 61 .tres
├── assets/                      # fonts, icons, theme_cards, medals, audio, brand
├── addons/                      # GodotPlayGameServices + android_IAPP
├── regression/headless/         # parse_gate, run_all.ps1, harness, suites, flows
├── tests/                       # core unit suites
└── tools/                       # screen_probe, medal_bake, perf/spike probes
```

---

## 3. The singletons

Seventeen autoloads, in dependency order; each may use those above it.

| Singleton | Responsibility |
|---|---|
| `SaveManager` | One atomic JSON file split into named sections. Debounced, temp-rename, flush on pause. |
| `SettingsManager` | Preferences, typed and range-clamped on read and write. |
| `EntitlementManager` | The runtime truth for premium. Every gate asks it. |
| `BillingService` | Play Billing adapter. An owned lifetime purchase becomes premium. |
| `GodotPlayGameServices` | The PGS addon's own autoload. |
| `DesignSystem` | Invariant tokens, house gains, tween helpers. |
| `ThemeManager` | Palettes, the runtime `Theme`, the tile ramp. |
| `AudioManager` | Music / Ambience / SFX buses. Silent when a file is missing. |
| `Haptics` | Vibration by feeling. No-op on desktop. |
| `GameStats` | Lifetime aggregates per mode. |
| `Achievements` | Data-driven crowns + unlock evaluation. |
| `PlayGames` | Identity, and mirroring achievements and scores. |
| `AccountManager` | The identity facade screens talk to. |
| `AdManager` | Free-tier interstitial cadence. |
| `Wallet` | Coins and gems, purchases, the ledger. |
| `Progression` | **The one funnel every mode reports play through.** The only place coins are earned. |
| `SceneRouter` | All navigation. A 0.16 s crossfade over the old page, never a black frame. |

---

## 4. The move pipeline

```
finger on a tile
  → scenes/gameplay/gameplay.gd     the conductor: owns the session (mode, board,
                                    par, clocks, undo stack) and COMPOSES the move:
                                    a tap is {"cell": i}, a swipe {"dir": d},
                                    Twist a turn {"pivot": p}
  → SlideRules.make(mode).apply()   core/slide: the plug-in validates, mutates the
                                    SlideBoard and returns typed events
  → events                          slid · twisted · locked · blocked · cleared · solved
  → BoardView.apply(events, done)   the tray replays each event as motion; it never
                                    re-reads the board to decide what to draw
  → _after_move                     the HUD, the rule's per-board state, the save
  → Progression.record_series(...)  the one report: grade, score, record, crowns, coins
  → BoardFx.on_swipe / on_merge     the theme world reacts
```

The rules never touch a node. The view never decides a rule. The solver never
sees a node.

**`apply` HAS NO SIDE EFFECTS.** It moves the board and returns events, nothing
more. The solver explores by applying candidate moves to clones, so a rule that
counted a score or re-dealt a tray inside `apply` corrupted every search that
touched it. Rush emits `cleared`; the conductor banks it and calls `deal_next`.

---

## 5. The material law

Every visible thing is the same glass, so the app reads as one object.

- **Surfaces** are `GlassPanel`: a frosted pane that blurs the backdrop.
- **Pieces** are `CandyFace` glass: the tray cells, the tiles, the theme cards.
- **Numbers** are `TileFace`: the numeral cast in the tile's own light, with the
  ink chosen by measured contrast so it reads on all 61 palettes.
- **A tile's hue is its HOME ROW**, spread across the theme's ramp, so a solved
  board reads as clean bands and a stray tile is obvious without reading a digit.
- **Ground** is dark by default (`starforged`).
- **Motion is light.** Entrances under ~0.7 s, `CPUParticles2D` only, all gated by
  reduce-motion.
- **Type never glows.**

---

## 6. Saves

One file, many sections, one write path. Atomic (write `.tmp`, rename) and
debounced, with a forced flush on pause.

```
user://numslide_save.json
├── settings · stats · score_history · achievements · best_scores
├── mode_records · first_clears · economy_daily · bounties
├── current_game     (the resumable board: state, par, elapsed, clock, cleared)
├── profile · academy · entitlements · owned_themes
└── wallet · cosmetics · ledger · ads
```

`SlideBoard.to_dict() / from_dict()` round-trip the whole position (cells, goal,
moves, meta) as JSON.

---

## 7. Themes

- A theme is `data/themes/<id>.tres` filling the `ThemeData` contract, listed in
  `theme_ids.gd` (a manifest, because `DirAccess` is unreliable inside an APK),
  tiered in `core/entitlements.gd`.
- 61 ship. Default `starforged`.
- Every card the pickers show is a baked photograph in `assets/theme_cards/`;
  rendering the worlds live made the picker lag. A suite pins the bakes.
- One mode wears its own world regardless of the player's theme: Blind
  `shadow_fog`.

---

## 8. The mode catalog (`core/game_modes.gd`)

| Mode | Tier | Board | Rule | Notes |
|---|---|---|---|---|
| Classic | launch | 3×3 / 4×4 / 5×5 | `classic` | the pure slide; the only size choice |
| Rush | launch | 4×4 + 60 s | `sprint` | solving re-deals and pays seconds |
| Lockdown | launch | 4×4 | `lock` | a tile that reaches home welds |
| Twist | launch | 3×3, no hole | `twist` | played on the junctions; a turn moves four tiles |
| Blind | w2 | 4×4 | `fog` | numbers hide; home tiles stay lit; world `shadow_fog` |

**ONE RULE, ONE MODE, no exceptions.** `test_game_modes` fails a rule claimed by
two modes: five modes over five rules classes.

**THE BOARD SITS IN THE MIDDLE.** Gameplay splits its slack above and below the
board, so the tray lands on the page's centre line at every screen height.

**EVERY BOARD STATES ITS RULE.** The top bar carries the mode's tagline under its
title, the geometry demoted beneath it. Six modes that all deal numbered tiles
differ by their RULE, and the rule is the one thing the board cannot show.

**NO DIFFICULTY SCREEN.** Tapping a mode deals a board. The only choice offered
anywhere is Classic's tray size, and it is on the board, not in front of it.

HOME LISTS EVERY MODE. Five boards is a list, not a catalogue, and a second
modes screen only hid half of them behind a row most players never tapped.

---

## 9. The solver (`core/slide/solver.gd`)

Answers two questions: `hint` gives the next tile to tap, `solve` gives a whole
path. Four strategies, cheapest first, every one capped, and the last cannot
fail:

1. **IDA\*** on Manhattan + linear conflict. Optimal, instant near home. Only
   attempted inside `IDA_MAX_DISTANCE` (12): optimal search grows explosively,
   and above that the group search is the one that makes progress.
2. **A\* toward the live group** — the next cells a human would place, everything
   finished frozen. How a person solves a 4×4 or 5×5.
3. **Breadth-first over quarter turns** for Twist, which has no hole to walk and
   no distance bound to prune with.
4. **Greedy**: the legal move that most reduces distance. Never brilliant, never
   fails.

A failed group search is latched off until a group actually goes in; retrying it
every step turned an unsolvable board into a long grind.

---

## 10. Regression

`regression/headless/run_all.ps1` runs, each in its own Godot process: the import
gate, the **parse gate**, every suite in `tests/` and `regression/headless/suites/`
(Basic), every flow, the scene smokes and the boot smoke (Full).
`verify_tests.ps1` plants a known bug per test file and proves the right test
goes red.

The gameplay flow solves its boards with **the real solver** rather than a
scripted move list: a scramble is random, so a hardcoded answer would only ever
be right for one seed.

---

## 11. Performance

- `core/` is allocation-light on the hot path; the solver clones boards by the
  thousand. `clone()` shares `goal` and `_home` (never written) and copies only
  what a slide touches.
- Tiles are nodes that hold, and children that draw. Drawing Controls are never
  tweened; a pivot parent is.
- `gl_compatibility` on Android (locked), `CPUParticles2D` only.
- Theme cards are baked; the picker never renders a world live.

Targets: 60 fps on mid-range Android, a page live ~40 ms after a tap, no black
frame.
