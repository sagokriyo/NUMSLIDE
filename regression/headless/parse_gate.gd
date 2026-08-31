extends SceneTree
## PARSE GATE — every .gd in the project must actually compile.
##
## Replaces the assurance `--headless --path . --import` only PRETENDED to give.
## (`regression/perf/SPEC.md` §2 defect D1, reproduced twice: `--import` returns
## **exit 0 with zero stderr** against a planted hard parse error, and
## `ResourceLoader.load()` null-checking is exactly as blind — it returns a
## non-null, invalid `GDScript`.)
##
## The oracle that does work, measured on 4.6.3:
##
##   | accessor                       | broken script      | valid script |
##   |--------------------------------|--------------------|--------------|
##   | `script.reload()`              | 43 (ERR_PARSE_ERROR) | 0 (OK)     |
##   | `script.can_instantiate()`     | false              | true         |
##   | `script.get_instance_base_type()` | ""              | e.g. "Node"  |
##
## `reload()` is the gate; the other two are recorded as corroborating detail.
##
## THE AUTOLOAD TRAP. `reload()` on a script that has a LIVE INSTANCE returns
## **22 (ERR_ALREADY_IN_USE)** before it ever looks at the source — and a
## `--script` run has all 15 autoloads instantiated, so probing the live
## autoload script (or anything `load()`/`ResourceLoader` hands back, which is
## the same cached `GDScript` object per path no matter the cache mode) reports
## 22 for a perfect file and 22 for a broken one alike. Gating on `!= OK` there
## would fail all 15 autoloads on a clean tree; gating on `== 43` would pass a
## broken autoload silently — the exact failure mode this gate exists to kill.
##
## So every file is probed as a DETACHED TWIN: source read with `FileAccess`,
## poured into a fresh `GDScript.new()` that nothing has ever instantiated, then
## `reload()`. A twin has no instances, so it answers about the SOURCE, never
## about the process's state, and autoloads take the identical code path as
## everything else. `set_path_cache()` gives the twin the real res:// path
## (without claiming the ResourceCache entry) so Godot's own error output names
## the real file and relative resolution behaves.
##
## SELF-TEST. The gate re-proves its own oracle on every run before it trusts
## it: a known-bad snippet must report ERR_PARSE_ERROR and a known-good one must
## report OK. If a future engine changes that behaviour this gate says
## ORACLE_BROKEN and exits 2 instead of quietly becoming another green no-op.
## (Engine error printing is muted for the self-test so a clean run's stderr
## stays clean — `run_all.ps1` fails any test that prints "SCRIPT ERROR".)
##
## COVERAGE. Every directory it is told to scan must exist and must contain at
## least one .gd, and every autoload declared in `project.godot` must have been
## swept. A rename that silently empties the sweep fails the gate rather than
## turning it green.
##
## THE SAVE. This gate never opens `user://`. It cannot: it compiles source, it
## does not run any of it. Measured anyway, because `regression/perf/SPEC.md`
## §12 hole 11 is what happens when nobody checks — the real 5,799-byte player
## save (11 sections, `best_scores {classic 9736, merge_drop 30412, tower
## 1000}`, `theme vaporwave`) came out of a full sweep **byte-identical**, sha
## 0C62FD93…, and four consecutive sweeps of a smaller save were a fixed point
## too. (`--script` does boot all 15 autoloads, so the *engine* holds the save
## open for the ~2.4 s the sweep lasts; it is `run_all.ps1`'s backup/restore
## that covers that, exactly as it does for every other entry.)
##
## Run:
##   godot --headless --path . --script res://regression/headless/parse_gate.gd
##   ... --script res://regression/headless/parse_gate.gd -- --shipping-only
##   ... --script res://regression/headless/parse_gate.gd -- --list
##
## Exit 0 = PASS, 1 = a file does not compile, 2 = the gate itself is broken
## (oracle, coverage, or unreadable file). Machine-greppable verdict on stdout:
##   PARSE_GATE: PASS|FAIL|ORACLE_BROKEN|COVERAGE_GAP|UNREADABLE ...
##
## NOT named `test_*.gd` / `flow_*.gd` and NOT placed in `tests/`,
## `regression/headless/suites/` or `regression/headless/flows/` — deliberately,
## so `run_all.ps1`'s directory globs do not discover it as a test. It is a
## GATE: it runs before the plan, and it aborts the plan.

const VERDICT := "PARSE_GATE"

## The shipping tree — everything that can end up in a player's APK.
const SHIPPING_DIRS: Array[String] = [
	"res://autoload",
	"res://core",
	"res://scenes",
	"res://ui",
	"res://data",
	"res://addons",
]

## Test/tooling code. IN SCOPE BY DEFAULT, on purpose:
##
##  * A parse error in a `tests/` or `suites/` file does not merely lose one
##    test — `headless_boot.gd` HANGS on it (SPEC §2 D1, second half: `load()`
##    returns the broken script, `.new()` raises "Nonexistent function new in
##    base GDScript", and the SceneTree spins forever with the autoloads live,
##    measured at 100% of a core for 3+ minutes). CI then burns its wall-clock
##    budget instead of reporting a one-line failure.
##  * A parse error in a `flows/` or `regression/perf/` file breaks the very
##    instrument a campaign is reading its numbers off.
##  * `tools/` holds the release gate and the export/upload path; a broken one
##    is found at ship time otherwise.
##
## `--shipping-only` narrows to SHIPPING_DIRS for the rare case where you want
## to ask "would this compile on a device?" and nothing else.
const TEST_DIRS: Array[String] = [
	"res://tests",
	"res://tools",
	"res://regression",
]

## Pruned during recursion, with the reason. `res://android` is not one of the
## scan roots today, so this entry is a guard rather than an active filter: it
## documents the four .gd files that live down there and keeps them out if
## anyone ever adds `res://android` to TEST_DIRS. Anything listed here that no
## longer exists fails the gate, so the list cannot silently rot (the failure
## mode this repo has already been bitten by three times: verify_tests.ps1's
## mutation catalog, device_test_runner.gd's SUITE_SCRIPTS, SPEC §4.1's
## hardcoded floor).
const EXCLUDED_DIRS: Dictionary = {
	# Gradle's instrumented-build staging copy of Godot's OWN Java-integration
	# test assets (main.gd, test/base_test.gd, two more). Not our code, not
	# exported by us, regenerated by the build.
	"res://android/build": "gradle build artifact, not project source",
}

## Files whose compilation legitimately cannot be judged from a plain `--script`
## process. Empty today, and measured so: every one of the 190+ scripts compiles
## in this process, including `addons/GodotPlayGameServices/export_plugin.gd`
## (`EditorExportPlugin`) — the editor binary registers its editor classes even
## under `--headless --script`. Every entry must still exist on disk or the gate
## fails, so this list cannot silently rot.
const EXCLUDED_FILES: Dictionary = {}

## How many failing files get Godot's own parse output echoed to stderr. One
## broken base class can fail dozens; the stdout list is always complete.
const ECHO_LIMIT := 10

var _checked := 0
var _autoload_checked := 0
var _swept: Dictionary = {}

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()

	var shipping_only := false
	var list_only := false
	var verbose := false
	var explain_trap := false
	for arg: String in OS.get_cmdline_user_args():
		match arg:
			"--shipping-only": shipping_only = true
			"--list": list_only = true
			"--verbose": verbose = true
			"--explain-autoload-trap": explain_trap = true
			_:
				_verdict("ORACLE_BROKEN", "unknown argument %s" % arg)
				quit(2)
				return

	if explain_trap:
		_explain_autoload_trap()
		quit(0)
		return

	# --- 0. Prove the oracle still works before trusting a single verdict -----
	var oracle := _self_test()
	if oracle != "":
		_verdict("ORACLE_BROKEN", oracle)
		quit(2)
		return

	# --- 1. Enumerate ---------------------------------------------------------
	var dirs: Array[String] = SHIPPING_DIRS.duplicate()
	if not shipping_only:
		dirs.append_array(TEST_DIRS)

	var files := PackedStringArray()
	for dir_path: String in dirs:
		if not DirAccess.dir_exists_absolute(dir_path):
			_verdict("COVERAGE_GAP", "configured directory is missing: %s" % dir_path)
			quit(2)
			return
		var before := files.size()
		_collect(dir_path, files)
		if files.size() == before:
			_verdict("COVERAGE_GAP", "configured directory holds no .gd: %s" % dir_path)
			quit(2)
			return
	files.sort()

	for path: String in EXCLUDED_FILES.keys():
		if not FileAccess.file_exists(path):
			_verdict("COVERAGE_GAP", "EXCLUDED_FILES names a file that no longer exists: %s" % path)
			quit(2)
			return
	# An absent EXCLUDED_DIRS entry is NOT a coverage gap: nothing is being
	# skipped, so the sweep is a superset of what the entry would have allowed.
	# This differs deliberately from EXCLUDED_FILES above, and from the missing
	# SCAN-dir check, where absence DOES mean something went unchecked.
	#
	# It is not hypothetical. `.gitignore:3` ignores `/android/` wholesale, so
	# `res://android/build` is a gradle artifact that exists only on a machine
	# that has run an Android build. On a fresh CI clone -- or in a `git archive`
	# staging tree -- it is absent, and the strict form failed the gate with
	# COVERAGE_GAP, aborting the whole suite before a single test ran. It passed
	# locally for exactly the reason it must not be trusted to: this machine had
	# built the APK.
	for path: String in EXCLUDED_DIRS.keys():
		if not DirAccess.dir_exists_absolute(path):
			print("PARSE_GATE: note: excluded dir absent (nothing skipped): %s" % path)

	var autoloads := _autoload_scripts()
	for path: String in files:
		_swept[path] = true

	if list_only:
		for path: String in files:
			var tag := ""
			if autoloads.has(path):
				tag = "  [autoload %s]" % autoloads[path]
			print("%s%s" % [path, tag])
		_verdict("LIST", "%d scripts (%d autoloads), %d dirs" % [files.size(), autoloads.size(), dirs.size()])
		quit(0)
		return

	# Every autoload declared in project.godot must be inside the sweep. If one
	# is not, this gate is not gating the most load-bearing scripts in the game.
	var uncovered := PackedStringArray()
	for path: String in autoloads.keys():
		if not _swept.has(path):
			uncovered.append("%s (%s)" % [path, autoloads[path]])
	if uncovered.size() > 0:
		_verdict("COVERAGE_GAP", "%d autoload script(s) not in the sweep: %s" % [
			uncovered.size(), ", ".join(uncovered)])
		quit(2)
		return

	# --- 2. Compile every one of them ----------------------------------------
	# Engine error output is muted for the sweep so the run's stderr stays clean
	# (run_all.ps1 fails any entry that prints "SCRIPT ERROR"); it is turned back
	# on to re-emit Godot's own parse message for the files that actually failed.
	#
	# The sweep does NOT stop at the first bad file, and that is deliberate. One
	# broken `class_name` cascades: planting a syntax error in
	# `core/entitlement_policy.gd` makes `autoload/entitlement_manager.gd` fail
	# too ("Could not resolve class EntitlementPolicy, because of a parser
	# error"), and the autoload sorts FIRST. A fail-fast gate would therefore
	# name a victim and hide the cause. Sweeping all 190-odd files costs ~2.4 s
	# and puts the cause and every victim in one report.
	var prev_errors := Engine.print_error_messages
	Engine.print_error_messages = false

	var failures: Array[Dictionary] = []
	for path: String in files:
		if EXCLUDED_FILES.has(path):
			continue
		var res := _probe(path)
		_checked += 1
		if autoloads.has(path):
			_autoload_checked += 1
		if verbose:
			print("  %-6s %s" % [str(res.get("err", -1)), path])
		if not bool(res.get("ok", false)):
			res["autoload"] = autoloads.get(path, "")
			failures.append(res)

	Engine.print_error_messages = prev_errors

	var elapsed := (Time.get_ticks_msec() - t0) / 1000.0

	# --- 3. Verdict -----------------------------------------------------------
	if failures.is_empty():
		_verdict("PASS", "%d scripts compiled (%d autoloads, detached twin), 0 failures, %.2fs" % [
			_checked, _autoload_checked, elapsed])
		quit(0)
		return

	var first: Dictionary = failures[0]
	var first_path: String = String(first.get("path", "?"))
	var first_err: int = int(first.get("err", -1))
	var unreadable := 0
	for f: Dictionary in failures:
		if String(f.get("why", "")) == "unreadable":
			unreadable += 1

	# stdout: the one-line machine-greppable verdict, then one block per failure.
	var state := "FAIL"
	var accessor := "reload()"
	if unreadable == failures.size():
		state = "UNREADABLE"
		accessor = "FileAccess"
	_verdict(state, "%s %s=%d (%s) -- %d of %d scripts do not compile, %.2fs" % [
		first_path, accessor, first_err, _err_name(first_err), failures.size(), _checked, elapsed])
	print("")
	for f: Dictionary in failures:
		var path: String = String(f.get("path", "?"))
		var err: int = int(f.get("err", -1))
		print("  %s" % path)
		if String(f.get("autoload", "")) != "":
			print("    autoload        : %s  (probed as a DETACHED TWIN, so 22/ERR_ALREADY_IN_USE is not what you are seeing)" % f["autoload"])
		if String(f.get("why", "")) == "unreadable":
			print("    FileAccess      : open error %d (%s)" % [err, error_string(err)])
			continue
		print("    reload()        : %d  (%s / %s)" % [err, _err_name(err), error_string(err)])
		print("    can_instantiate : %s" % str(f.get("can_instantiate", "?")))
		print("    base type       : \"%s\"" % str(f.get("base_type", "")))
	print("")
	if failures.size() > 1:
		print("  NOTE: a parse error CASCADES -- every file that names the broken script's")
		print("  class_name fails with \"Could not resolve class X, because of a parser error\".")
		print("  Fix the file whose message is a real syntax error first; the rest follow.")
	print("  Godot's own parse output is on stderr, under the banners.")
	print("")

	# stderr: the same banners, each followed by Godot's own message re-emitted
	# right beneath it (reload() re-parses from source every call, so it
	# reprints). printerr() and the engine's error output share the stream, so
	# the ordering here is real, not a guess about interleaving.
	Engine.print_error_messages = true
	var echoed := 0
	printerr("")
	for f: Dictionary in failures:
		if String(f.get("why", "")) == "unreadable":
			printerr("======== %s: UNREADABLE - %s ========" % [VERDICT, String(f.get("path", "?"))])
			continue
		if echoed >= ECHO_LIMIT:
			printerr("======== %s: %d more failing file(s) not echoed (ECHO_LIMIT=%d); see the stdout list ========" % [
				VERDICT, failures.size() - echoed, ECHO_LIMIT])
			break
		var path: String = String(f.get("path", "?"))
		var err: int = int(f.get("err", -1))
		printerr("======== %s: FAIL - %s does not compile ========" % [VERDICT, path])
		printerr("reload() returned %d (%s / %s). Godot's own parse errors follow:" % [
			err, _err_name(err), error_string(err)])
		var echo := _make_twin(path)
		if echo != null:
			echo.reload()
		printerr("======== end of %s parse output for %s ========" % [VERDICT, path])
		echoed += 1
	printerr("")

	if state == "UNREADABLE":
		quit(2)
		return
	quit(1)

# --- The oracle -------------------------------------------------------------------

## Build a detached twin of `path`: a GDScript nothing has ever instantiated,
## carrying the file's source and the file's res:// path. Returns null if the
## file cannot be read.
func _make_twin(path: String) -> GDScript:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var src := f.get_as_text()
	f.close()
	var twin := GDScript.new()
	# set_path_cache() stamps the path WITHOUT claiming the ResourceCache slot
	# (set_path()/take_over_path() would hijack the real script's cache entry and
	# poison every later load in this process).
	if twin.has_method("set_path_cache"):
		twin.set_path_cache(path)
	twin.source_code = src
	return twin

func _probe(path: String) -> Dictionary:
	var twin := _make_twin(path)
	if twin == null:
		var open_err := FileAccess.get_open_error()
		if open_err == OK:
			open_err = ERR_FILE_CANT_OPEN
		return {"ok": false, "path": path, "err": int(open_err), "why": "unreadable"}
	var err := twin.reload()
	return {
		"ok": err == OK,
		"path": path,
		"err": int(err),
		"why": "reload",
		"can_instantiate": twin.can_instantiate(),
		"base_type": twin.get_instance_base_type(),
	}

## `--explain-autoload-trap`: a demonstration, not a gate. Side by side, for
## every autoload, what the LIVE cached script says versus what the detached
## twin says — on a tree that is known to be clean. The live column reads 22
## (ERR_ALREADY_IN_USE) for every one of them because the autoload node IS an
## instance, and `reload()` bails on that before it ever looks at the source.
## Anyone tempted to "simplify" this gate to `load(path).reload()` should run
## this first.
func _explain_autoload_trap() -> void:
	var autoloads := _autoload_scripts()
	var paths := PackedStringArray()
	for p: String in autoloads.keys():
		paths.append(p)
	paths.sort()
	print("%s: EXPLAIN live cached script vs detached twin, %d autoloads" % [VERDICT, paths.size()])
	print("")
	print("  %-20s %-20s  %s" % ["live (cached)", "twin (detached)", "autoload script"])
	var prev := Engine.print_error_messages
	Engine.print_error_messages = false
	for p: String in paths:
		var live: Variant = load(p)
		var live_err := -1
		if live is GDScript:
			live_err = (live as GDScript).reload()
		var twin := _make_twin(p)
		var twin_err := -1
		if twin != null:
			twin_err = twin.reload()
		print("  %-20s %-20s  %s (%s)" % [_err_name(live_err), _err_name(twin_err), p, autoloads[p]])
	Engine.print_error_messages = prev
	print("")
	print("  live = ResourceLoader's cached GDScript, which the running autoload instantiates.")
	print("  twin = GDScript.new() + source_code + reload(): no instances, so it answers")
	print("         about the SOURCE. That is the only column that tracks the file.")

const GOOD_SNIPPET := "extends RefCounted\nvar n := 1\nfunc f() -> int:\n\treturn n\n"
const BAD_SNIPPET := "extends RefCounted\nfunc f() -> int:\n\tvar x := = 1 ((\n\treturn x\n"

## Returns "" when the oracle behaves as documented, else the reason it does not.
func _self_test() -> String:
	var prev := Engine.print_error_messages
	Engine.print_error_messages = false

	var good := GDScript.new()
	good.source_code = GOOD_SNIPPET
	var good_err := good.reload()

	var bad := GDScript.new()
	bad.source_code = BAD_SNIPPET
	var bad_err := bad.reload()
	var bad_can := bad.can_instantiate()

	Engine.print_error_messages = prev

	if good_err != OK:
		return "a known-GOOD snippet reported reload()=%d (%s); the oracle is unusable" % [good_err, _err_name(good_err)]
	if bad_err == OK:
		return "a known-BAD snippet reported reload()=OK; the oracle no longer detects parse errors"
	if bad_err != ERR_PARSE_ERROR:
		return "a known-BAD snippet reported reload()=%d (%s), expected 43 (ERR_PARSE_ERROR)" % [bad_err, _err_name(bad_err)]
	if bad_can:
		return "a known-BAD snippet reported can_instantiate()=true; the engine's validity flag is not tracking parse state"
	return ""

# --- Enumeration ------------------------------------------------------------------

func _collect(dir_path: String, out: PackedStringArray) -> void:
	for excluded: String in EXCLUDED_DIRS.keys():
		if dir_path == excluded or dir_path.begins_with(excluded + "/"):
			return
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var entry := d.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = d.get_next()
			continue
		var full := dir_path.path_join(entry)
		if d.current_is_dir():
			_collect(full, out)
		elif entry.ends_with(".gd"):
			out.append(full)
		entry = d.get_next()
	d.list_dir_end()

## { "res://autoload/save_manager.gd": "SaveManager", ... } straight out of
## project.godot, uid:// entries resolved (GodotPlayGameServices is one).
func _autoload_scripts() -> Dictionary:
	var out: Dictionary = {}
	for prop: Dictionary in ProjectSettings.get_property_list():
		var key: String = String(prop.get("name", ""))
		if not key.begins_with("autoload/"):
			continue
		var raw: String = String(ProjectSettings.get_setting(key, ""))
		if raw.is_empty():
			continue
		if raw.begins_with("*"):
			raw = raw.substr(1)
		if raw.begins_with("uid://"):
			var uid := ResourceUID.text_to_id(raw)
			if ResourceUID.has_id(uid):
				raw = ResourceUID.get_id_path(uid)
		if raw.ends_with(".gd"):
			out[raw] = key.trim_prefix("autoload/")
	return out

# --- Reporting --------------------------------------------------------------------

## `error_string()` gives the prose ("Parse error."); this gives the identifier a
## reader can grep the engine for.
const ERR_NAMES: Dictionary = {
	0: "OK", 1: "FAILED", 6: "ERR_OUT_OF_MEMORY", 7: "ERR_FILE_NOT_FOUND",
	12: "ERR_FILE_CANT_OPEN", 14: "ERR_FILE_CANT_READ", 16: "ERR_FILE_CORRUPT",
	17: "ERR_FILE_MISSING_DEPENDENCIES", 19: "ERR_CANT_OPEN",
	22: "ERR_ALREADY_IN_USE", 30: "ERR_INVALID_DATA", 36: "ERR_COMPILATION_FAILED",
	39: "ERR_SCRIPT_FAILED", 40: "ERR_CYCLIC_LINK", 41: "ERR_INVALID_DECLARATION",
	42: "ERR_DUPLICATE_SYMBOL", 43: "ERR_PARSE_ERROR", 44: "ERR_BUSY",
}

func _err_name(code: int) -> String:
	if ERR_NAMES.has(code):
		return String(ERR_NAMES[code])
	return "error %d" % code

func _verdict(state: String, detail: String) -> void:
	print("%s: %s %s" % [VERDICT, state, detail])
