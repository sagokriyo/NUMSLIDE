extends Node
## Shared base for every regression test suite (suites, flows AND the core
## tests/ scripts). A suite is a NODE, so the same test file runs in two hosts:
##
##   headless (CI):  godot --headless --path . --script res://regression/headless/harness/headless_boot.gd -- --test=res://<dir>/<file>.gd
##                   (the bootstrap adds the suite to the tree; on finish the
##                   suite quits the process with exit 0 (pass) / 1 (fail) / 2 (watchdog))
##
##   on-device:      regression/android/harness/device_test_runner.gd embeds the
##                   suite in the running app (quit_on_finish = false), awaits
##                   `suite_finished`, and aggregates the counts — so the SAME
##                   assertions gate real hardware.
##
## Autoload NODES exist in both hosts by the time tests run (the base resolves
## them one frame in). Subclasses override run_tests() (it may await) and use
## the check_* helpers; the base prints a summary and reports/quits.
##
## NOTE: headless tests run one-per-process (the runner isolates them), so state
## leaks between test FILES are impossible there. On-device all suites share the
## app process — each test must restore what it touched (they do: belt and
## braces, and it keeps a single test runnable by hand without the runner).

## Emitted exactly once with the suite's exit code (0 pass / 1 fail / 2 watchdog).
signal suite_finished(exit_code: int)

## Sim-time watchdog. The PowerShell runner adds a wall-clock kill on top.
const WATCHDOG_SEC := 240.0

## Headless: quit the whole process with the exit code (CI contract).
## The device runner sets this false and consumes `suite_finished` instead.
var quit_on_finish := true

# Autoload singletons, resolved at runtime. Suites reference these same-named
# members so test code reads exactly like game code, without compile-order
# coupling to the autoload list.
var SaveManager: Variant
var SettingsManager: Variant
var EntitlementManager: Variant
var ThemeManager: Variant
var AudioManager: Variant
var GameStats: Variant
var Achievements: Variant
var Progression: Variant
var Wallet: Variant
var SceneRouter: Variant

# --- SceneTree API shims ----------------------------------------------------------
# The suites were written against SceneTree (`root`, `await process_frame`,
# `create_timer`, `current_scene`); these keep that code byte-identical now that
# a suite is a Node hosted inside a live tree.
var root: Node = null
var process_frame: Signal
var current_scene: Node:
	get:
		return get_tree().current_scene if is_inside_tree() else null

var _checks: int = 0
var _failures: int = 0
var _finished := false
var _test_name := "test"

func _ready() -> void:
	var script_ref: Script = get_script()
	_test_name = script_ref.resource_path.get_file()
	root = get_tree().root
	process_frame = get_tree().process_frame
	_boot()

func _boot() -> void:
	# One frame so the autoload tree has fully settled before tests touch it.
	await process_frame
	for autoload_name: String in ["SaveManager", "SettingsManager", "EntitlementManager",
			"ThemeManager", "AudioManager", "GameStats", "Achievements", "Progression",
			"Wallet", "SceneRouter"]:
		set(autoload_name, root.get_node(NodePath(autoload_name)))
	_arm_watchdog()
	print("=== %s ===" % _test_name)
	await run_tests()
	finish()

## Override me. May await freely; call the check_* helpers as you go.
func run_tests() -> void:
	check("run_tests() overridden", false)

func create_timer(sec: float) -> SceneTreeTimer:
	return get_tree().create_timer(sec)

## Mirrors SceneTree.quit() for the headless host; reports without killing the
## app when embedded. The single exit path for finish() and the watchdog.
func quit(exit_code: int = 0) -> void:
	suite_finished.emit(exit_code)
	if quit_on_finish:
		get_tree().quit(exit_code)

func _arm_watchdog() -> void:
	# Bound method (not a lambda): the connection auto-cleans if the suite node
	# is freed by an embedding runner before the timer fires.
	create_timer(WATCHDOG_SEC).timeout.connect(_on_watchdog)

func _on_watchdog() -> void:
	if not _finished:
		printerr("WATCHDOG - %s exceeded %.0fs (sim time); aborting." % [_test_name, WATCHDOG_SEC])
		_finished = true
		quit(2)

# --- Assertions -----------------------------------------------------------------
func check(label: String, condition: bool) -> void:
	_checks += 1
	if condition:
		print("  ok  - %s" % label)
	else:
		_failures += 1
		printerr("  FAIL - %s" % label)

func check_eq(label: String, got: Variant, want: Variant) -> void:
	_checks += 1
	if got == want:
		print("  ok  - %s" % label)
	else:
		_failures += 1
		printerr("  FAIL - %s (got %s, want %s)" % [label, str(got), str(want)])

func check_near(label: String, got: float, want: float, eps: float = 0.001) -> void:
	_checks += 1
	if absf(got - want) <= eps:
		print("  ok  - %s" % label)
	else:
		_failures += 1
		printerr("  FAIL - %s (got %f, want %f +/- %f)" % [label, got, want, eps])

# --- Flow helpers (scene navigation / frame stepping) ----------------------------
## Steps frames until `predicate` returns true. Returns false on frame budget
## exhaustion (and lets the caller decide whether that is a failure).
func await_until(predicate: Callable, max_frames: int = 600) -> bool:
	for i in max_frames:
		if bool(predicate.call()):
			return true
		await process_frame
	return bool(predicate.call())

## Steps a fixed number of frames (lets tweens/timers/physics advance).
func settle(frames: int = 5) -> void:
	for i in frames:
		await process_frame

## Navigates via SceneRouter and waits for the destination to be the live scene.
## Returns the destination scene's root node, or null on timeout.
func goto_and_settle(route_path: String, payload: Dictionary = {}, max_frames: int = 900) -> Node:
	# The router DROPS goto() requests while a transition is in flight, and the
	# full-motion crossfade (2 x DUR_PAGE) runs regardless of reduce_motion — so
	# a back-to-back navigation must wait out the previous one first.
	await await_until(func() -> bool: return not SceneRouter.is_busy(), max_frames)
	SceneRouter.goto(route_path, payload)
	var ok := await await_until(func() -> bool:
		return (not SceneRouter.is_busy()) and current_scene != null \
			and current_scene.scene_file_path == route_path, max_frames)
	if not ok:
		return null
	await settle(2)
	return current_scene

## The scene_file_path of the current scene ("" when none).
func current_path() -> String:
	return current_scene.scene_file_path if current_scene != null else ""

## Sends a key press+release through the real input pipeline (reaches _input).
func press_key(keycode: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = keycode
	down.physical_keycode = keycode
	down.pressed = true
	root.push_input(down)
	var up := InputEventKey.new()
	up.keycode = keycode
	up.physical_keycode = keycode
	up.pressed = false
	root.push_input(up)

# --- Summary --------------------------------------------------------------------
func finish() -> void:
	if _finished:
		return
	_finished = true
	print("\n%s: %d checks, %d failures" % [_test_name, _checks, _failures])
	if _failures == 0:
		print("ALL TESTS PASSED")
		quit(0)
	else:
		printerr("TESTS FAILED")
		quit(1)
