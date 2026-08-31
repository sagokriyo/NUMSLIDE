# JOURNAL: the work log

> How we got here, newest first. The snapshot of where we ARE is
> [STATE.md](./STATE.md).

---

## 2026-08-31 — NUMSLIDE, built on the Tic Tac Toe shell

The whole game, from an empty repo to a green Full tier.

**Ported the shell.** Tic Tac Toe Limitless's Phase 0 was "the 2048 shell
ported"; this is the same move again. 17 autoloads, 61 `ThemeData` palettes with
their baked cards, the fonts, the icon library, the `ui/` widget library, every
screen folder, the addons, the regression harness and the AI org came over
whole. What was deleted was the game: `core/rules`, `core/ai`, the tray, the
mark views, the globe, the persona face.

**Built the engine** (`core/slide/`). `SlideBoard` is cells + a goal + holes,
with the adjacency handed IN so a flat tray, a torus and a cube surface are the
same class. `SlideRules` is the plug-in contract and six plug-ins.
`SlideSolver` answers a hint or a whole path. `Pace` grades the run.

**Par replaced the personas.** A sliding puzzle has no opponent, so the board
sets the terms: par comes off the dealt board's own distance and the run is
graded Steady / Sharp / Expert / Perfect. It drops into the exact slot the
persona ladder occupied, so `Progression`, `GameStats`, `EconomyRules` and the
bounties kept their shape and only changed who is on the other side.

**Painters.** `MarkFace` drew the X and the O as glass tubes; `TileFace` draws
the numeral in the same light. Every caller moved with it, including the ambient
shard field that had been scattering X's and O's across every screen.

**The loading screen solves a puzzle.** It was a laser through a winning line.
It now deals a real scramble with `SlideRules` and slides it home with
`SlideSolver`, one tile a beat, then sweeps the finished board with light.

### Bugs the tests found, and what they were

- **`_place` cleared the lookup the slide had just written.** A slide is two
  writes and the second saw the same value still in the old cell, so every tile
  reported itself as nowhere the moment it moved. Guarded on the entry still
  pointing at that cell.
- **`apply` had side effects.** Rush re-dealt the tray and counted a board
  inside `apply`. The solver explores by applying candidate moves, so IDA* could
  never reach a finished position (the rule destroyed the solution at the exact
  moment it was found) and a single solve banked three boards. The rule now
  emits `cleared`; the conductor banks and re-deals.
- **IDA\* was attempted from 24 moves out.** Optimal search on a sliding puzzle
  grows explosively; a 4×4 solve took 77 seconds, nearly all of it inside an
  optimal line nobody asked for. Capped at 12, where the group search hands it a
  board it can close instantly: 0.67 s.
- **The hop-distance cache collided.** A flat 3×3 and a torus 3×3 keyed the same,
  so Wrap searched on the flat board's distances. Keyed on the adjacency itself,
  and cached on the board, because rebuilding it per lookup was worse than the
  collision.
- **A tile's drawing child never got sized.** `size = x` only notifies on a
  CHANGE, and the tray handed the same number twice. The whole board came up as
  an empty tray of sockets. Children are anchored now.
- **A theme change wiped the board.** `AppScreen` rebuilds its content on a new
  palette, and Gameplay IS the state. It overrides the handler and restyles in
  place.
- **`clone()` shared arrays the slide writes to.** Sharing `goal` and `_home` is
  free; sharing `cells` and `_at` corrupted every parent board.

### Second pass: the Cube and the hero

- **The Cube rendered as a heap of loose tiles.** Two bugs. It was scaled off a
  fraction of the short side tuned for a resting pose, so it ran off all four
  edges; the scale is now MEASURED by sweeping orientations and projecting the
  eight corners, so it fits at every rotation. And the stickers were stamped as
  axis-aligned squares at their projected centres, which ignores the solid
  entirely: they are now mapped through the face's own screen frame, so the
  glass and the numeral lie ON the face. The resting pitch went 24 to 31 so the
  top face is read rather than glimpsed edge-on.
- **The hero could not be scrambled.** It was a 1 x 4 strip, and on a single row
  tiles can be translated but never REORDERED, so it celebrated the moment it
  was dealt, in a loop. It is a 3 x 2 tray now, running the real rules, and a
  tap slides the whole run. `test_slide_rules` pins that a one-row tray can
  never reorder its tiles.
- **The tray size was thrown away on every boot.** JSON has one number type, so
  an int setting came back as a float and the sanitiser refused it as malformed
  and handed back the default, silently. `flow_settings_live` now round-trips
  every setting through JSON and back.

### Third pass: the roster cut

- **Cube removed.** Six faces of eight tiles was a solid the player spun more
  than solved, and its renderer was the only thing in the app that needed a
  projection. Gone with it: `cube_solid.gd`, `rules_cube.gd`, `cube_view.gd`,
  and `SlideBoard`'s third dimension (`faces`, `face_of`, `face_size`) which had
  no other caller. `GameView` went too: with one board left, a base class with
  one subclass is an abstraction over nothing, so `BoardView` carries the
  contract itself.
- **Mode Select removed; Home lists all five.** A second screen holding three of
  six boards meant half the game sat behind a row most players never tapped.
- **The hero's long-press bomb removed.** A hold on the wordmark charged a
  screen-wide confetti detonation that slowed time to 0.45 and flung the whole
  background field outward. Fine over a wordmark. The hero is a BOARD now, and a
  player sliding tiles holds a beat too long constantly, so the bomb kept firing
  over the thing they were trying to play.
- **Icons stopped being tinted.** `PanelRail` washed its tab glyphs monochrome
  through `UI.icon_material`, which turned a set of lit gold, silver and glass
  objects into six identical grey shapes; Settings and Profile both wear that
  rail. The active tab is lifted by alpha, scale, its bloom and its marker
  instead. The settings gear was the last PNG still washed to `text_dim`.

### Fourth pass: the gear, the splash, the crowns

- **The gear is 2048's, washed to `text_dim`.** The PNG itself is violet; the
  tint is what makes it the quiet grey gear the siblings show. A gear is chrome,
  not one of the coloured tokens beside it, so it is the one icon that keeps a
  wash while the rest of the set keeps its own colours.
- **The hero's long press is back.** Removing it last pass was the wrong call:
  the two gestures never collided, because LineBoard refuses to slide on a press
  that outlived `long_press_s` and that is the very threshold the charge starts
  at. Restored without the branches that targeted the old ExtrudedWord (cower,
  pet, amaze), which were dead the moment the hero became a board.
  `flow_home.gd` pins all four outcomes: a tap slides and charges nothing, a
  hold charges and slides nothing, a release detonates, a drag stands down.
- **The medals were still the sibling's art.** They had been re-pointed by
  filename, not re-baked, so "First Board" was three pink X marks with a strike
  through them and "Against the Clock" was Blitz's three-second clock. Re-baked
  all thirteen from the app's own painters: 1 2 3 for the first board, the
  mode's own number for each crown. The Achievements screen also still grouped
  them as "series wins"; it says boards now.

### Fifth pass: the bar, the door, and Wrap

- **The HUD was two numerals and a word.** "PERFECT" sat in the right-hand slot
  at title size, running near twice the width of the "0" opposite it, so the bar
  read as one heavy end and one light one. Three numbers across the top now
  (moves, tiles home, par) and the grade on a strip of its own, where it also
  carries how many moves are left before it drops. The ring's readout was
  laying out against the ring's full box and running under its own stroke; it is
  inset and set at body size.
- **Pause became BACK.** A pause glyph promises a paused clock and only Rush has
  one; on every other board the button's real job is "let me out". The sheet it
  opens is unchanged.
- **Wrap became TWIST.** The torus was a real puzzle and an unreadable one:
  nothing on screen said where a rolled row would land, and with no corner to
  anchor to the goal had to be accepted at any whole-board shift, so a finished
  board did not look finished. Twist is the same class of puzzle with all of it
  visible: tap a junction, the four tiles around it pinwheel. The handles are
  drawn ON TOP of the tiles, because a twist tray is full and a handle under the
  glass is a handle nobody can see. `rotate_line` went with the torus, its only
  caller.

### Verified

Full tier, 19 of 19 green: parse gate, 13 unit suites (1,900+ checks), the
academy catalogue, the progression funnel, the gameplay flow (which solves its
boards with the real solver rather than a scripted move list), settings live,
the account facade and the boot smoke. Probe stills at 443x963 on Home,
Gameplay, Splash, Themes, Mode Select, How to Play and Settings.
