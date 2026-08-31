# NUMSLIDE Limitless

Five ways to slide. Numbers made of glass.

A sliding-number puzzle by Sago Kriyo Games, built in **Godot 4.7.1** with
GDScript. Portrait, mobile renderer, neon glass on a dark ground. 61 themes.

## The five boards

One rule each. A sliding puzzle with a clock on it is not a second mode, so the
roster is five boards that share nothing.

| Mode | Board | Rule |
|---|---|---|
| **Classic** | 3×3 / 4×4 / 5×5 | Slide the numbers back into order. |
| **Rush** | 4×4, one clock | Solving does not end the run. It re-deals and buys seconds. |
| **Lockdown** | 4×4 | A tile that reaches home is welded there. Place them in order or never. |
| **Twist** | 3×3, no hole | Tap a junction and the four tiles around it pinwheel. |
| **Blind** | 4×4 | The numbers go out. Only the hole and what is home stays lit. |

Plus **Daily Slide**: one date-seeded scramble, the same on every phone. A
feature over Classic's rules, not a sixth board.

## Par, not an opponent

There is nobody on the other side of a sliding puzzle, so the board sets the
terms. Every scramble is dealt with a **par** taken from its own tile distance,
and the run is graded on how far under it you came home: **Steady · Sharp ·
Expert · Perfect**. That grade is what the game banks, what the streak counts and
what the economy pays for.

## Requirements

- Godot Engine **4.7.1-stable**

## Running it

```sh
<godot> --path .                 # play (main scene: scenes/intro/intro.tscn)
<godot> -e --path .              # open in the editor
```

`<godot>` = `D:\Godot_v4.7.1-stable_win64_console.exe`.

## Checking it

```sh
<godot> --headless --path . --script res://regression/headless/parse_gate.gd
powershell -ExecutionPolicy Bypass -File regression\headless\run_all.ps1
<godot> --path . res://tools/screen_probe.tscn --resolution 443x963 -- home
```

The parse gate is the truth for "does it compile". The suite is the truth for
"does it work". A probe still at 443x963 is the truth for "does it look right".

## Layout

| Path | Purpose |
|---|---|
| `core/slide/` | The engine: board, rules, solver, pace. No nodes. |
| `core/` | Modes, economy, entitlements, bounties, Play ids. |
| `autoload/` | The 17 singletons, in load order. |
| `ui/` | `AppScreen`, the `UI` factory, the shared widgets. |
| `scenes/` | One folder per screen. |
| `data/themes/` | 61 `ThemeData` palettes. |
| `regression/` | Parse gate, suites, flows, the runner. |

The map is [ARCHITECTURE.md](ARCHITECTURE.md); the working rules are
[CLAUDE.md](CLAUDE.md).
