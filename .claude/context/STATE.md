# PROJECT STATE: living snapshot

> **Shared memory for every AI agent.** Read it FIRST so you don't start cold.
> Keep it accurate: update via `/checkpoint`. History is in
> [JOURNAL.md](./JOURNAL.md); the map is [ARCHITECTURE.md](../../ARCHITECTURE.md);
> the rules of the road are [CLAUDE.md](../../CLAUDE.md).

**Last updated:** 2026-08-31 · **Updated by:** the session that rebuilt the
auto-solve (threaded, on-board in every mode, assisted runs pay nothing).

---

## 1. What this is

**NUMSLIDE Limitless**, by Sago Kriyo Games. Six ways to slide, numbers made of
glass. **Godot 4.7.1 + GDScript**, portrait 1080x2340, `canvas_items` stretch,
mobile renderer (D3D12 on Windows, **gl_compatibility on Android, locked**), UI
scale 1.1. Ships to Google Play, Android only.

- **Backend: Play Games Services only.** Identity, achievements, leaderboards.
  Premium is one lifetime Play Billing unlock. **No Supabase.**
- **Offline, and SOLO.** There is no opponent.
- **THE OPPONENT IS THE PAR.** Every scramble is dealt with a par from its own
  tile distance; the run is graded **Steady · Sharp · Expert · Perfect**
  (`core/slide/pace.gd`). That grade is what Progression banks, what the streak
  counts and what the economy pays for. It occupies the exact slot the sibling
  project's persona ladder did, so none of the shell's plumbing changed.
- **NO DIFFICULTY SCREEN.** Tapping a mode deals a board. The only choice
  anywhere is Classic's tray size, and it sits on the board, not in front of it.

## 2. The five modes

One rule each. `test_game_modes` fails a rule claimed by two modes.

| Mode | Board | Rule | Tier |
|---|---|---|---|
| Classic | 3×3 / 4×4 / 5×5 | `classic` | launch, free |
| Rush | 4×4 + 60 s | `sprint` | launch, free |
| Lockdown | 4×4 | `lock` | launch, free |
| Twist | 3×3, no hole | `twist` | launch, free |
| Blind | 4×4 | `fog` | w2, premium |

**HOME LISTS EVERY MODE.** There is no second modes screen: five boards is a
list, not a catalogue, and a row the player had to go looking for was a row most
of them never saw. **Daily Slide** is a date-seeded feature over Classic's
rules, not a sixth board.

## 3. Where things stand

- **Shell ported in full** from Tic Tac Toe Limitless: 17 autoloads, 61 themes +
  baked cards, fonts, icons, the `ui/` widget library, every screen, the
  regression harness, the AI org.
- **Engine built:** `core/slide/` — `SlideBoard`, `SlideRules` + six plug-ins,
  `SlideSolver`, `Pace`, `CubeSolid`.
- **Gameplay built:** conductor, `BoardView` + `TileView`, `CubeView`,
  `SlideHud`. Undo, hints, auto-solve, pause, save/resume, Rush's clock.
- **Auto-solve rebuilt (2026-08-31):** a Solve pill on the controls row in
  EVERY mode (it was hidden in the pause sheet and skipped the timed modes).
  The search runs on a worker `Thread` with a 15 s leash, so the app never
  freezes and the hard 5×5s that died at the old main-thread deadline solve.
  On Rush the line ends at `cleared`, the conductor banks and re-deals, and
  the run continues assisted. The clock stops while the solver thinks/plays.
- **Painters swapped:** `MarkFace` (the X and O) is gone; `TileFace` paints the
  numeral. Every caller moved: the tray, the Continue glimpse, the Splash, the
  drifting shard field, the theme cards, the Shop strip, the medal tool.
- **Loading screen solves a puzzle.** The splash deals a real scramble and slides
  it home with the real solver, then lights the finished board.
- **Regression: ALL 20 GREEN** (Full tier), 2,000+ checks.

## 4. Known gaps

- `export_presets.cfg` and the Android keystore are not set up: no APK yet.
- Play Console ids are empty (`core/play_games_ids.gd`), so PGS stays dormant.

## 5. Decisions not to re-litigate

- Five modes, one rule each. A clock on Classic is not a sixth mode.
- Home lists them all. No second modes screen.
- Par and grades, not personas. There is nobody on the other side of the board.
- A tile's hue is its HOME ROW, spread across the theme's ramp. Bands are how a wrong tile is spotted without reading a digit.
- A scramble is a WALK out of the solved position, never a shuffle.
- `apply` on a rule has no side effects. The solver searches on it.
- One move = one player action. A tap that shifts three tiles counts once.
- An ASSISTED run pays NOTHING: no score, no coins, no best, no bounty
  progress, no solve badge. It is still a game played (stats, history). The
  mark persists in the session save and, on Rush, taints the whole run.
