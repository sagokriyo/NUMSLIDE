# Regression Test Strategy — 2048 Infinity

The goal: **every piece of shipped functionality keeps working while development
continues.** Two suites share that job:

| Suite | Where it runs | What it proves | Status |
|-------|---------------|----------------|--------|
| **S1 — Headless** (`regression/headless/`) | This machine / any CI box, headless Godot 4.7.1 | Rules, persistence, services, UI flows, animations *behave* correctly | **Live** — `run_all.ps1` |
| **S2 — Device matrix** (`regression/android/`) | Android Virtual Devices via the installed Android Studio SDK | The same game *runs, renders and performs* on the full spread of phone/tablet configurations | Planned — see `android/README.md` |

The same regression philosophy drives both: S1 asserts *logic and behaviour*
(fast, deterministic, every commit); S2 asserts *device reality* (rendering,
performance, input, lifecycle — slower, pre-release / nightly). Every test
S2 drives on a device is a behaviour S1 already pinned down headlessly, so a
device failure isolates to "device/platform problem", never "logic problem".

---

## S1 — the headless suite (live)

### Layers

1. **Compile gates** — two of them, and only the second one actually gates.
   - **Import gate** — `--headless --import` imports every resource and scene
     and warms `.godot`. It is **not** a parse gate, and this document claimed
     for a long time that it was. Measured twice on 4.6.3: against a planted
     hard parse error in an ordinary `.gd` it returns **exit 0 with zero
     stderr** (`regression/perf/SPEC.md` §2, defect D1) — reproduced again here
     on `ui/components/progress_ring.gd`, where `import_gate.log` contained
     zero `SCRIPT ERROR` lines. It trips on a broken **autoload** only
     incidentally, because the editor's own autoload pass prints a
     `SCRIPT ERROR` the runner happens to count: 15 of ~190 scripts, by luck,
     not by design. `ResourceLoader.load()` null-checking is exactly as blind —
     it returns a non-null, *invalid* `GDScript`.
   - **Parse gate** — `regression/headless/parse_gate.gd`, the real one.
     ~2.4 s, ~190 files: every `.gd` under `autoload/`, `core/`, `scenes/`,
     `ui/`, `data/`, `addons/`, `tests/`, `tools/` and `regression/` is
     compiled individually and the run fails on the first `reload() != OK`
     (it keeps sweeping so the report lists the root cause *and* every file
     that cascaded off it). **Any parse error anywhere fails the run before a
     single test executes** — which is what this line always promised.
     Verdict line: `PARSE_GATE: PASS|FAIL|ORACLE_BROKEN|COVERAGE_GAP|UNREADABLE …`.

   Three things about the parse gate are load-bearing and easy to undo by
   accident:

   - **Detached twins, not `load()`.** `Script.reload()` returns
     `ERR_ALREADY_IN_USE` (22) *before it looks at the source* when the script
     has a live instance — and a `--script` run has all 15 autoloads
     instantiated, so the cached script of `SaveManager` answers 22 whether it
     is perfect or wrecked. The gate therefore reads each file with
     `FileAccess`, pours it into a fresh `GDScript.new()` nothing has ever
     instantiated, and reloads *that*.
     `parse_gate.gd -- --explain-autoload-trap` prints the live-vs-twin columns
     for all 15 and is the fastest way to re-convince yourself.
   - **`tests/`, `tools/` and `regression/` are in scope on purpose.** A parse
     error in a suite does not lose one test — `headless_boot.gd` **hangs** on
     it (D1's second half: `load()` hands back the broken script, `.new()`
     raises *"Nonexistent function new in base GDScript"*, and the SceneTree
     spins with the autoloads live, measured at 100% of a core for 3+ minutes).
     Failing in 2.4 s beats burning CI's wall clock. `--shipping-only` narrows
     to the six shipping directories if you specifically want the device
     question.
   - **It re-proves its own oracle every run** (a known-bad snippet must report
     `ERR_PARSE_ERROR`, a known-good one `OK`) and fails `COVERAGE_GAP` if a
     configured directory has vanished or gone empty, or if an autoload named
     in `project.godot` was not swept. A gate that silently stops gating is the
     defect it was built to fix; it is not allowed to become one.
2. **Pure-rules suites** (`tests/test_*.gd` + `regression/headless/suites/`)
   — `GameBoard` (merge mechanics, ids, four directions, big boards, the JSON
   save round-trip, seeded spawn determinism + distribution), `TowerGrid`,
   `GameModes` catalog, `Entitlements` switchboard, billing payload parsing,
   store/PGS catalogs, theme data contracts.
3. **Service suites** (`regression/headless/suites/`) — the autoload backbone
   against its real implementations: `SaveManager` (copy-isolation, atomic
   write, debounced flush, v1→v2 migration, wipe latch), `SettingsManager`
   (schema, change signal, persistence write-through, sensitivity migration),
   `GameStats` (rollups, capped history, signals), `EntitlementManager`
   (free/premium gates, grant/revoke, reward-theme gating), `SceneRouter`
   route table (every route loads and instantiates).
4. **Flow tests** (`regression/headless/flows/`) — boot the entire real game
   (all 15 autoloads) and drive it like a player:
   - `flow_ui_navigation` — intro → splash → home auto-boot, every screen
     out-and-back, transition-guard semantics, payload delivery, live theme
     switching, all four playable mode scenes surviving real frames.
   - `flow_gameplay` — real keyboard input through the input pipeline: merges,
     model↔view sync per tile, undo + the free-tier undo budget upsell,
     pause/resume + hardware-back, session persistence shape, game over
     (stats rollup, session cleared, modal, dimmed board), victory (modal,
     continue-past-win), daily-mode determinism, the premium mode gate.
   - `flow_animations` — the animation regression tier (below).
5. **Scene smokes** (`tests/*.tscn`) — Tower scripted turns, BoardFx and
   Confetti across every theme, How-to-Play pages, account facade defaults.
6. **Boot smoke** — the shipped main scene runs headlessly for ~2400 frames;
   any `SCRIPT ERROR` in the log fails it.

### Continuous integration

The suite is **tiered**, and `run_all.ps1 -Tier Basic|Full` selects which half runs:

| Tier | Contents | Wall clock | Runs on |
|------|----------|-----------|---------|
| **Basic** | both compile gates + every `--script` unit/service suite (`tests\`, `regression\headless\suites\`) — deterministic, no booted game | **~45 s** (27 tests + 2 gates) | every pull request |
| **Full** | *everything*: Basic + the full-boot flows + scene smokes + boot smoke | ~3 min (43 tests + 2 gates) | merge to `main`, nightly, manual |

**Two counts, both right, do not "fix" either.** `run_all.ps1 -List` says **43
tests** — the gates are not tests and are not discovered; they run ahead of the
plan and abort it. The closing banner says **`ALL 45 TESTS PASSED`** because it
counts every result row, gates included (it said 44 when there was one gate).
Anything that consumes this runner must read its **exit code** — the number of
failed rows — never a count parsed out of the banner.

Full is a superset, so `main` is always covered by the strictest gate; a PR gets a
fast, high-signal answer. **The tier is inferred from the test's DIRECTORY, never a
hand-kept list** — a new suite is Basic and a new flow is Full automatically. That is
deliberate: this repo has twice been bitten by a hardcoded inventory silently
drifting (`verify_tests.ps1`'s mutation catalog, `device_test_runner.gd`'s
`SUITE_SCRIPTS`).

The three scripts run in **GitHub Actions** (`.github/workflows/`):

- **`regression.yml`** runs `run_all.ps1` on every push to `main` and every
  pull request (and on demand). It gates changes: the job fails with the number
  of failed tests, and the per-run `.results/` logs upload as an artifact.
- **`verify-tests.yml`** runs `verify_tests.ps1` when test code changes
  (`tests/**`, `regression/**`) or on demand — so a new test can't merge without
  being proven able to fail.

Both use a **Windows runner** so CI executes the exact PowerShell runner
developers use locally (the save-backup path and Godot invocation are Windows
paths). Godot is downloaded and cached by the `setup-godot` composite action;
bump `GODOT_VERSION` in the workflows to move engine versions. A Linux runner is
possible but would require porting `run_all.ps1`'s `%APPDATA%` save-dir logic to
`~/.local/share/godot`.

### Animation strategy

Animations can't be "watched" headlessly, but they can be **measured**. All
motion here is `Tween`-driven (no `AnimationPlayer`), timings come from
`DesignSystem` constants, and the `reduce_motion` setting removes exactly two
things — confetti celebrations and the drifting glass-shard fields — while
every other animation plays identically ON and OFF. That gives three testable
contracts:

| Tier | What is asserted | Where |
|------|------------------|-------|
| **T1 — Motion truth** (headless, live) | For each animation: it *starts* (property leaves its initial value), it *travels* (≥3 distinct intermediate samples, no teleport), and it *settles exactly* on the model's final state (position == `cell_to_pos`, scale == 1, alpha == 1, curtain == 0). Sampled per frame over sim-time windows, so it's frame-rate independent. | `flow_animations.gd` — tile slide (incl. overshoot settle), merge pop + halo flash/decay + number morph + `merged_at` signal + consumed-view free, spawn grow/fade, tension rim escalation (2/1/0 empties) and clear, route curtain rise/clear + slide reveal glide |
| **T2 — Behaviour under animation** (headless, live) | Input locks while tiles move; a swipe mid-animation is buffered and replayed; the 512+ slow-mo beat dips `Engine.time_scale` to 0.5 and restores 1.0; `reduce_motion` leaves ALL of that identical while removing only confetti + drift shards (`flow_accessibility.gd` owns that contract). | `flow_animations.gd`, `flow_gameplay.gd`, `flow_accessibility.gd` |
| **T3 — Visual + perceptual** (device, planned) | Screenshots at fixed sim timestamps vs golden images (per-device tolerance); screen recordings of merge bursts; frame-time percentiles during animation-heavy play (no jank on low-end profiles). | S2 device suite |

Why this split: T1/T2 catch 90% of animation regressions (a tween that never
fires, wrong target, desynced view, broken lock) deterministically and in
seconds. Only "does it *look* right" needs pixels, and that's exactly what the
device tier is for.

### Mechanics & guarantees

- **One process per test.** A crash, hang (wall-clock timeout + in-test
  watchdog) or state leak never contaminates the next test.
- **The player's save is sacred.** `run_all.ps1` backs up
  `%APPDATA%\Godot\app_userdata\2048 Infinity\infinity_save.json` before the
  run and restores it afterwards — *always*, even on abort. Tests additionally
  snapshot/restore the sections they touch so they stay hand-runnable.
- **Pass criteria**: exit code 0 **and** zero `SCRIPT ERROR` lines. Assertion
  counts are parsed into the report. Runner exit code = number of failures.
- **Artifacts**: `regression/headless/.results/<timestamp>/` keeps one log per
  test + `summary.md` + `summary.json` (gitignored).
- **Never ships**: `regression/*` is in the Android export preset's
  `exclude_filter` (alongside `tests/*`, `tools/*`).

### Changing behaviour? Update its tests in the same change

**A change is not done until the suite is green again.** The code and every test
that asserts the old behaviour move together, in the same commit — a red suite
handed to the next person is a bug report with no author.

When a failure appears, it is a question you owe an answer to: *is the test
stale, or did I break the app?* Decide it with evidence — read the assertion,
check what the code now does, print the actual values if it is not obvious.
"The test must be out of date" is a conclusion, never an assumption.

What routinely needs updating alongside a behaviour change:

- The suites and flows that assert the old behaviour.
- **Hardcoded counts and user-facing copy that track a catalogue** — theme
  counts, the route-table size, the paywall's "All N themes" claim. These never
  fail loudly at runtime; the test is the only thing standing between a stale
  number and the store listing.
- The matching anchor in `verify_tests.ps1` when you move or rename code a
  mutation targets. A missing anchor is a loud `SETUP ERROR`; a mutation still
  pointing at the *wrong* line is a silent hole.

Two rules that keep a green suite honest:

1. **Rewrite obsolete assertions to pin the NEW contract — never delete one and
   never loosen one to get green.** Then plant a mutation and watch the rewritten
   form fail (see below), or you have only proved it can pass.
2. **Pin the state a test depends on; never inherit it from the machine.**
   Settings, save sections and timing must be set by the test and restored in
   teardown. An assertion that reads the developer's own save, or races the
   frame clock against a ~0.1s animation, passes on one box and fails on
   another — a false negative that costs more trust than the check was worth.

### Writing a new test (conventions)

- New **suite**: `regression/headless/suites/test_<thing>.gd` extending
  `res://regression/headless/harness/script_test_base.gd`; override
  `run_tests()` (may `await`), use `check/check_eq/check_near`. The runner
  discovers it automatically.
- New **flow**: `regression/headless/flows/flow_<thing>.gd` extending
  `flow_test_base.gd` (adds save-state snapshot/restore + board fixtures +
  `goto_and_settle`/`press_key`).
- New **gate** (something that must pass *before* the plan, not a test):
  `regression/headless/<name>_gate.gd`, a bare `extends SceneTree` run directly
  under `--script` — **not** in `tests/`, `suites/` or `flows/`, and **not**
  named `test_*` / `flow_*`, or the runner's directory globs will discover it as
  a test and run it after the very thing it is supposed to gate. Wire it by hand
  into `run_all.ps1`'s gate block, print a `NAME: PASS|FAIL …` verdict line like
  `parse_gate.gd` and the `regression/perf/` G-gates do, and exit non-zero.
- **Two hard-won rules for `--script` tests** (they run *before* autoloads
  register their global identifiers):
  1. Never reference `SaveManager`/`SceneRouter`/etc. as raw identifiers in a
     new harness — the base class exposes same-named `Variant` members that
     resolve at runtime; suites just use them normally.
  2. Never statically reference a `class_name` whose script itself uses
     autoload identifiers (e.g. `BoardView`, `TileView`, any screen) — that
     poisons the compile chain for the whole process. `load()` it inside
     `run_tests()` instead. Pure `core/` classes (`GameBoard`, `GameModes`,
     `Entitlements`, `TowerGrid`) are safe to name statically.
- Anything autoload-derived is `Variant` — remember `var x := <Variant>` is a
  hard parse error in this Godot; type the variable explicitly.

### Validating the validators (mutation verification)

A test is only trustworthy once you've watched it **fail for the right
reason** — a suite that stays green on broken code is worse than no suite.
`verify_tests.ps1` automates that check:

```powershell
powershell -ExecutionPolicy Bypass -File regression\headless\verify_tests.ps1
```

The catalog covers **every test file in the suite** (all 22 test files + the
boot smoke — one planted bug each). For each entry it plants a realistic bug
in product code, runs the test(s) that must catch it, asserts they went
**red**, restores the file byte-for-byte from memory (never git — uncommitted
work is safe), and finishes with a green pass over every involved test on clean
code. Exit code 0 means *every test file was proven able to fail on its target
bug*.

"Red" is the same signal `run_all.ps1` uses: a non-zero exit, a `SCRIPT ERROR`
in the output, or a timeout. That last two matter for the scene smokes, which
`quit(0)` but log a `SCRIPT ERROR` (or fail to load) when their exercised path
breaks — so a smoke is proven by planting a crash in the class it drives
(BoardFx motif, confetti recipe, a How-to-Play page, the Tower performer, the
intro boot chain). The assertion suites are proven by a wrong result (bad merge
value, wrong daily seed, a premium mode/theme leaking free, a drifted store/PGS
id, an inverted purchase check, miscounted stats, a broken route, a leaked
payload). Scene smokes run under `--fixed-fps` so their real-time waits collapse
to fast frames.

Run it whenever the suite itself changes materially, and **when you add a new
test file, add a mutation that proves it bites** (the catalog is the coverage
ledger — a file with no mutation is a test nobody has watched fail). If a
mutation reports `MISSED (stayed green!)`, the test is asserting less than it
claims — fix the test, not the catalog.

---

## S2 — the Android device matrix (planned)

Full plan, device matrix and tooling notes live in
[`android/README.md`](android/README.md). Summary:

- **AVD fleet** created via the installed Android SDK's `avdmanager`
  (Android Studio on this machine): small/low-RAM phone, current mid-range,
  flagship tall-screen, small tablet, large tablet — across API 26 / 30 / 34 —
  ~7 configurations chosen to maximise spread of resolution, DPI, aspect
  ratio, RAM and Android version.
- **Identical test set on every device** (the "same tests everywhere" rule):
  an on-device harness build of the game whose main scene runs the *same*
  `regression/headless/flows/*.gd` scripts (they live inside the project, so
  the exported harness build carries them), writing a JSON verdict to the
  app's files dir; `adb` pulls and aggregates it.
- **Device-only layers on top**: golden-frame screenshots (T3 animation
  tier), `adb shell input swipe` real-gesture sanity, app lifecycle
  (background/foreground → save flush; hardware back), install/launch/uninstall,
  logcat error scan, frame-time percentiles on the low-end profile.
- **Orchestration**: `run_matrix.ps1` boots each AVD in turn (headless
  emulator, `-no-window`), installs the harness APK, runs the set, collects
  results into one matrix report.

---

## Bugs already caught by this suite (fixed)

1. **Premium-gate reroute was silently dropped** — `gameplay.on_ready()` sent
   blocked players to the paywall while the router was still mid-transition;
   `SceneRouter.goto()` drops calls when busy, stranding free players on an
   empty gameplay screen (continue/restore paths). Fixed: wait for the router
   to settle before rerouting (`scenes/gameplay/gameplay.gd`).
2. **The navigation slide-reveal never played** — `goto()` resumed from a
   tween callback, so one `process_frame` after `change_scene_to_file` still
   left `current_scene` null and `_slide_reveal` no-opped on every navigation
   since the feature was written. Fixed: wait until the new scene is live
   (`autoload/scene_router.gd`, forward + back paths).

Both were found by asserting *intended* behaviour, not current behaviour —
keep doing that.
