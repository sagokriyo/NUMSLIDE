extends Node
## SaveManager — generic, atomic, sectioned JSON persistence.
##
## Every other system (settings, stats, achievements, in-progress games) owns
## a named "section" of one save file. This keeps persistence in one place,
## one format, one write path — instead of a dozen scattered files.
##
## Writes are atomic (write to .tmp, then rename) so a crash mid-save can never
## corrupt the player's progress. Saves are also debounced: callers ask to
## persist freely and the actual disk write coalesces over a quiet window, then
## lands from a worker thread (the OS pause/quit flush stays synchronous).
##
## The store is also self-repairing: a section whose stored value is not an
## object (a hand-edited or torn save) is replaced with the caller's default the
## first time it is read, so corruption cannot ride along in every later write.

const SAVE_PATH := "user://numslide_save.json"
const TMP_PATH := "user://numslide_save.tmp"
const SAVE_VERSION := 2
const FLUSH_DEBOUNCE := 0.8   # seconds of quiet before the coalesced disk write

var _data: Dictionary = {}
var _dirty := false
## Hash of `_data` as of the last write that actually reached disk. The OS
## lifecycle hook compares against it instead of trusting `_dirty` alone, so a
## change that skipped mark_dirty() can't be dropped — and a write that FAILED
## is retried on the next pause/close (the hash stays stale until one lands).
var _flushed_hash := 0
var _flush_timer: Timer
## WorkerThreadPool id of the in-flight debounced write (-1 = none). Exactly one
## writer can be airborne at a time: every dispatch AND every synchronous flush
## joins the previous task first (RULES 4.5 — every task id is waited), which is
## also what keeps the tmp→rename pair atomic — two interleaved writers could
## rename a torn tmp over a good save.
var _write_task_id := -1
## Worker → main handoff for the in-flight write: the task stores the content
## hash of what actually reached disk under "hash" (absent when the write
## failed). Only ever read on the main thread AFTER wait_for_task_completion —
## the wait is the synchronization point, so no lock is needed.
var _write_result: Dictionary = {}
## Latched by wipe(): the player asked for their data deleted, so persistence is
## dead until the process restarts. quit() only lands at the end of the frame,
## and screen rebuilds can write sections back on read (e.g. Profile re-stamps
## "joined") — this flag makes the wipe unresurrectable instead of assuming
## nothing writes during quit teardown.
var _wiped := false

func _ready() -> void:
	_load()
	# What we just read IS what the file holds, so the lifecycle hook starts in
	# sync (an absent or unreadable file is equivalent to the empty save booted
	# in its place — there is no player data to lose by not rewriting it).
	_flushed_hash = _data.hash()
	_flush_timer = Timer.new()
	_flush_timer.one_shot = true
	_flush_timer.wait_time = FLUSH_DEBOUNCE
	_flush_timer.timeout.connect(func():
		if _dirty:
			_flush_async())
	add_child(_flush_timer)

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_data = {"version": SAVE_VERSION}
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		push_warning("SaveManager: could not open save file; starting fresh.")
		_data = {"version": SAVE_VERSION}
		return
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveManager: save file unreadable; starting fresh.")
		_data = {"version": SAVE_VERSION}
		return
	_data = parsed
	_migrate()

func _migrate() -> void:
	var v: int = int(_data.get("version", 1))
	if v < 2:
		_migrate_current_game_to_keyed()
	if v < SAVE_VERSION:
		_data["version"] = SAVE_VERSION
		flush()

## v1 saved a single flat in-progress game under "current_game". v2 keys that
## section by mode id instead, so every mode can hold its own resumable
## session without one overwriting another.
func _migrate_current_game_to_keyed() -> void:
	if not _data.has("current_game") or typeof(_data["current_game"]) != TYPE_DICTIONARY:
		return
	var old: Dictionary = _data["current_game"]
	if not old.has("mode"):
		return   # already keyed (or empty) — nothing to migrate
	var mode_id := String(old["mode"])
	_data["current_game"] = {mode_id: old}

## Returns a *copy* of a section so callers can't mutate internal state by
## reference. Persist changes back with set_section().
##
## A stored value that is not an object is REPAIRED here, not merely masked:
## returning the default alone left the junk sitting in `_data`, where the next
## flush() faithfully re-serialized it — corruption that outlived every session.
## Overwriting it with the caller's default lets one read heal the file for good.
## This can never mask a real error: it only fires for a value get_section
## already refuses to hand back, and never for a section that is simply ABSENT
## (a missing section still returns the default and writes nothing).
func get_section(name: String, default: Dictionary = {}) -> Dictionary:
	var live: Variant = _live_section(name, default)
	if live != null:
		return (live as Dictionary).duplicate(true)
	return default.duplicate(true)

## The section's LIVE dictionary inside `_data`, or null when there is none to
## hand back (absent, or unusable while the store is wiped). NEVER returned to a
## caller outside this file — the copy-isolation contract is that no other system
## can hold a reference into `_data`, and it is unit-tested both ways
## (test_save_manager.gd:41-46, test_save_manager_edges.gd:74-111).
##
## Guards the cast: the save file is plaintext on device, so a hand-edited or
## corrupted section that isn't an object must not crash on `as Dictionary`.
## Present but not an object -> heal it in place with `repair_with`, then schedule
## the repaired file; returning the default alone left the junk sitting in `_data`,
## where the next flush() faithfully re-serialized it — corruption that outlived
## every session. "version" is the loader's own scalar field rather than a section,
## so a stray read of it must never stomp the save's version stamp. A section that
## is simply ABSENT is never conjured into existence here.
func _live_section(section: String, repair_with: Dictionary = {}) -> Variant:
	if not _data.has(section):
		return null
	if typeof(_data[section]) == TYPE_DICTIONARY:
		return _data[section]
	if section == "version" or _wiped:
		return null
	var repaired: Dictionary = repair_with.duplicate(true)
	_data[section] = repaired
	mark_dirty()
	return repaired

## As _live_section(), but for the write path: a missing (or unusable) section is
## created empty rather than refused. Callers must already have rejected `_wiped`.
func _writable_section(section: String) -> Dictionary:
	var live: Variant = _live_section(section)
	if live != null:
		return live
	var fresh: Dictionary = {}
	_data[section] = fresh
	return fresh

func set_section(name: String, value: Dictionary) -> void:
	if _wiped:
		return
	_data[name] = value.duplicate(true)
	mark_dirty()

## Merge a handful of TOP-LEVEL fields into a section, in place.
##
## The read-modify-write shape callers reach for by reflex —
## `get_section()` / mutate / `set_section()` — deep-copies the WHOLE section
## twice per write. Gameplay's per-move `_persist_game()` pays that on
## "current_game", measured at 34.2 us a move on the live save (17.2 out +
## 17.1 in) to change two keys. This copies only the values actually being
## written, so the cost stops scaling with everything else the section holds.
##
## Same isolation contract as set_section(): Dictionary and Array values are
## deep-copied IN, so a later mutation of the caller's object cannot reach the
## store. Fields not named are left exactly as they are — this is a merge, not a
## replace; use set_section() when you mean to overwrite the whole section.
func set_section_fields(section: String, fields: Dictionary) -> void:
	if _wiped or fields.is_empty():
		return
	var sec: Dictionary = _writable_section(section)
	for key in fields:
		var v: Variant = fields[key]
		match typeof(v):
			TYPE_DICTIONARY: sec[key] = (v as Dictionary).duplicate(true)
			TYPE_ARRAY: sec[key] = (v as Array).duplicate(true)
			_: sec[key] = v
	mark_dirty()

## Read-only membership test that copies NOTHING — the cheap form of
## `get_section(s).has(k)` for the callers that only ever asked the question.
## Safe by construction where a cache behind get_section() would not be: it hands
## back a bool, so there is no object for a caller to alias or mutate.
func section_has_key(section: String, key: String) -> bool:
	var live: Variant = _live_section(section)
	return live != null and (live as Dictionary).has(key)

func has_section(name: String) -> bool:
	return _data.has(name)

func clear_section(name: String) -> void:
	if _data.erase(name):
		mark_dirty()

## Sugar for a section that is itself a dict keyed by id (e.g. mode id) — the
## shape "best_scores" and GameStats' per-mode totals already use. Same
## copy-out/duplicate-in safety as get_section()/set_section().
##
## These four work against the LIVE section (via _live_section) rather than
## round-tripping a copy of it: the caller only ever sees a copy of the one ENTRY
## it asked about, so the isolation contract is unchanged, but the cost no longer
## scales with the size of everything else the section holds. Reading one of
## thirteen best_scores used to deep-copy all thirteen and then the one.
func get_keyed(section: String, key: String, default: Dictionary = {}) -> Dictionary:
	var live: Variant = _live_section(section)
	if live != null:
		var sec: Dictionary = live
		if sec.has(key) and typeof(sec[key]) == TYPE_DICTIONARY:
			return (sec[key] as Dictionary).duplicate(true)
	return default.duplicate(true)

func set_keyed(section: String, key: String, value: Dictionary) -> void:
	if _wiped:
		return
	_writable_section(section)[key] = value.duplicate(true)
	mark_dirty()

## True only for a real keyed ENTRY — the value has to be the Dictionary that
## get_keyed() would hand back, so the two helpers can never disagree. A section
## may legitimately carry non-dict bookkeeping alongside its entries (Gameplay
## keeps a "_last" mode-id String beside the sessions in "current_game"); that is
## section state, read with get_section(), not a keyed entry.
func has_keyed(section: String, key: String) -> bool:
	var live: Variant = _live_section(section)
	if live == null:
		return false
	var sec: Dictionary = live
	return sec.has(key) and typeof(sec[key]) == TYPE_DICTIONARY

func clear_keyed(section: String, key: String) -> void:
	if _wiped:
		return
	var live: Variant = _live_section(section)
	if live == null:
		return
	if (live as Dictionary).erase(key):
		mark_dirty()

## Schedules a debounced save. Cheap to call repeatedly.
## Gameplay marks dirty on every move and merge; the old "next frame" coalescing
## still serialized + wrote the whole JSON to flash once per move, which read as
## micro-stutter on phones. Writes now coalesce over a short quiet window — the
## OS pause/close hooks below still flush instantly, so nothing is ever lost on
## backgrounding; a hard crash loses at most the last second of stats.
func mark_dirty() -> void:
	if _wiped:
		return
	_dirty = true
	if _flush_timer != null and _flush_timer.is_stopped():
		_flush_timer.start()

## Forces an immediate atomic write, entirely on the calling thread. This is the
## LIFECYCLE path (app pause / quit, wipe, boot migration): the OS may kill the
## process the moment the pause hook returns, so this write must have LANDED by
## then — it stays fully synchronous. Only the debounced timer path below is
## allowed to defer its IO to a worker.
func flush() -> void:
	_join_pending_write()   # never overlap the worker's tmp→rename pair
	_dirty = false
	var text := JSON.stringify(_data, "\t")
	if _write_to_disk(text):
		# The file now holds exactly this snapshot.
		_flushed_hash = _data.hash()
	# On failure _flushed_hash stays stale, so the next pause/close hook retries
	# this write instead of assuming it landed.

## The debounced TIMER flush. Stringify + tmp write + rename + full-Dictionary
## hash all ran on the main thread every quiet window (~0.8 s cadence during
## play) — a periodic spike the stall metric sees. This path snapshots the store
## with one deep copy (cheaper on the main thread than the stringify was, and it
## moves the serialize AND the hash to the worker too) and pushes all disk work
## to WorkerThreadPool. The lifecycle path above never comes through here.
func _flush_async() -> void:
	_join_pending_write()   # one writer at a time; the previous id is waited
	_dirty = false
	var snap: Dictionary = _data.duplicate(true)
	var result: Dictionary = {}
	_write_result = result
	var done := _on_write_done
	_write_task_id = WorkerThreadPool.add_task(func() -> void:
		var text := JSON.stringify(snap, "\t")
		if _write_to_disk(text):
			# Dictionary.hash() is a content hash, so the snapshot's hash IS
			# _data.hash() as of the moment the copy was taken.
			result["hash"] = snap.hash()
		# Fold the outcome in promptly ON THE MAIN THREAD (call_deferred is
		# thread-safe; a worker must never touch node state directly — RULES
		# 4.5). Waiting for the next flush instead would leave _flushed_hash
		# stale, and the GO_BACK hook's hash compare would rewrite an unchanged
		# save on every back press until then.
		done.call_deferred(),
		false, "SaveManager debounced flush")

## Deferred back onto the main thread by the worker once its write landed. The
## join is unconditional: call_deferred is posted as the task body's LAST
## statement, so by the time this runs the work is done and the wait is bounded
## by the closure's return — effectively instant. (Gating on
## is_task_completed() had a race: a preempted worker could post the deferred
## call before the pool marked the task complete, the gate skipped the fold,
## and _flushed_hash stayed stale until the next writer — the adversarial
## review's fold-skip finding.)
func _on_write_done() -> void:
	_join_pending_write()

## Wait out the in-flight debounced write, if any, and fold its result in.
## Every dispatched task id passes through here exactly once (RULES 4.5: every
## WorkerThreadPool id waited), and every writer — sync or async — calls this
## before touching the save paths, so two writers can never overlap and the
## tmp→rename atomicity holds.
func _join_pending_write() -> void:
	if _write_task_id < 0:
		return
	var id := _write_task_id
	_write_task_id = -1
	WorkerThreadPool.wait_for_task_completion(id)
	if _write_result.has("hash"):
		_flushed_hash = int(_write_result["hash"])
	_write_result = {}

## The one disk pipeline every writer shares: write the whole text to the tmp
## path, then atomically rename it over the live save (with the direct-write
## fallback for platforms that refuse the rename). Static and self-contained on
## purpose — it runs on the MAIN thread for the lifecycle flush and on a
## WorkerThreadPool thread for the debounced one, so it may touch nothing
## beyond its own locals (fresh FileAccess/DirAccess instances are safe
## per-thread; shared node state is not). Returns whether the text reached disk.
static func _write_to_disk(text: String) -> bool:
	var f := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if f == null:
		push_error("SaveManager: failed to open temp save for writing.")
		return false
	f.store_string(text)
	f.close()
	# Atomic replace.
	var err := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(TMP_PATH),
		ProjectSettings.globalize_path(SAVE_PATH)
	)
	if err != OK:
		# Fallback: some platforms disallow cross-handle rename; write directly.
		var direct := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if direct == null:
			# Nothing reached disk.
			return false
		direct.store_string(text)
		direct.close()
	return true

## Erase everything, permanently. Persistence stays dead afterwards (see
## _wiped) — the deletion flow quits the app right after calling this.
func wipe() -> void:
	_wiped = true
	_dirty = false
	_data = {"version": SAVE_VERSION}
	flush()
	# Belt-and-braces: flush() can fail (e.g. the tmp file won't open), which
	# would leave the OLD save intact while the UI claims deletion. Removing the
	# files outright covers that; if removal fails instead, the flushed-clean
	# file is the fallback. A missing save and a fresh one are equivalent.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))

func _notification(what: int) -> void:
	# Persist whenever the OS backgrounds or closes the app. Nothing else this
	# node hears is our business, so filter first and do no work for the rest
	# (APPLICATION_RESUMED deliberately has no handler: nothing re-reads).
	if what != NOTIFICATION_APPLICATION_PAUSED \
			and what != NOTIFICATION_WM_CLOSE_REQUEST \
			and what != NOTIFICATION_WM_GO_BACK_REQUEST \
			and what != NOTIFICATION_PREDELETE:
		return
	if _wiped:
		return   # the player asked for deletion — never resurrect the file here
	# An instance that never booted (_load always leaves at least a "version")
	# has nothing to say about the file — writing its empty store would erase a
	# perfectly good save.
	if _data.is_empty():
		return
	# `_dirty` is a promise callers have to remember to make, not a fact, and the
	# one writer that forgets (a direct `_data` mutation) was being dropped by the
	# very hook meant to persist it. Reconcile against the snapshot that actually
	# reached disk before trusting the flag.
	#
	# Deliberately NOT an unconditional flush: GO_BACK fires on every hardware
	# back press, so an unchanged save must stay a no-op instead of rewriting the
	# whole file on each navigation. Dictionary.hash() is an in-memory compare
	# with no allocation, and it is short-circuited away entirely while the save
	# is already dirty — the cost is a hash on the rare clean background, and the
	# guarantee is that no change can be silently lost.
	# Fold the airborne debounced write's hash in BEFORE the compare: during
	# its flight window _flushed_hash still holds the PREVIOUS write's hash, so
	# an unchanged save would fail the compare and pay a spurious synchronous
	# full-file rewrite on every back press until the fold landed (the
	# adversarial review's compare-before-join finding).
	_join_pending_write()
	if _dirty or _data.hash() != _flushed_hash:
		flush()
