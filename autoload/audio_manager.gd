extends Node
## AudioManager — a single SFX layer for overlap-free one-shots.
##
## Creates a dedicated SFX bus at runtime (so the project ships without a
## hand-edited bus layout) and drives a small pool of SFX players.
##
## All assets are resolved lazily by *id* from conventional paths; authored
## files additionally start loading on the resource loader's worker at boot
## (see _request_sfx_streams). If a file is missing the call is a quiet no-op —
## the game never crashes for want of a wav, which keeps the project runnable
## before audio is authored. Drop real files into res://assets/audio/sfx/ and
## they light up automatically.

const SFX_VOICES := 6
const SFX_BUS := "SFX"
const AMBIENCE_BUS := "Ambience"

## The ambience loops (assets/audio/music), by id. "" is silence, the default:
## the app never auto-plays a loop the player did not pick.
const MUSIC_DIR := "res://assets/audio/music/"
const MUSIC_NAMES := {
	"lofi": "lofi", "piano": "piano", "cafe": "cafe", "rain": "rain",
	"whitenoise": "white noise", "fireplace": "fireplace", "forest": "forest",
	"temple": "temple",
}
const AMBIENCE_IDS: Array[String] = ["lofi", "piano", "cafe", "rain", "whitenoise",
	"fireplace", "forest", "temple"]
const FADE_TIME := 0.8         # cross-fade when the loop changes
const LOOP_FADE_TIME := 1.5    # cross-fade at the loop point (hides the MP3 gap)

# Mapped to the real clips imported from the sibling project (assets/audio/).
const SFX_PATHS := {
	"tile_move": "res://assets/audio/sfx/menu button.mp3",
	"tile_merge": "res://assets/audio/sfx/block_merge.mp3",
	"button_tap": "res://assets/audio/sfx/button.mp3",
	# Baked here rather than inherited from 2048 with the rest of the palette —
	# a line landing wants its own voice. See tools/win_sting.py, which is the
	# only thing that may edit win.wav; the old clip is still in the folder if
	# this one has to go back.
	"victory": "res://assets/audio/sfx/win.wav",
	"achievement": "res://assets/audio/sfx/default bckground chime.mp3",
	"game_over": "res://assets/audio/sfx/game over.mp3",
	"invalid": "res://assets/audio/sfx/wrong block.mp3",
	"opening": "res://assets/audio/sfx/opening scene.mp3",
	# Playful "juice" hooks — silent no-ops until the clips are authored.
	"combo": "res://assets/audio/sfx/combo.mp3",
	"streak": "res://assets/audio/sfx/streak.mp3",
	"drop_land": "res://assets/audio/sfx/drop_land.mp3",
	"whoosh": "res://assets/audio/sfx/whoosh.mp3",
	# Antimatter: the inward "shut" of a pair cancelling. Wants the opposite shape
	# to tile_merge — a collapse rather than an impact.
	"annihilate": "res://assets/audio/sfx/annihilate.mp3",
	# The crystal wordmark's voice (see ExtrudedWord): a tiny glass chime as the
	# light sweep rings each digit / on poke bursts, and the cast's achoo.
	"crystal_ting": "res://assets/audio/sfx/crystal_ting.mp3",
	"sneeze": "res://assets/audio/sfx/sneeze.mp3",
}

var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _stream_cache: Dictionary = {}
var _missing_warned: Dictionary = {}
var _sfx_requested: Dictionary = {}   # path -> true while a threaded preload is in flight

# Two ambience players, cross-faded: between loops, and at each loop point.
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _active_music: AudioStreamPlayer
var _current_ambience := ""
var _loop_timer: Timer

func _ready() -> void:
	_ensure_bus(SFX_BUS)
	_ensure_bus(AMBIENCE_BUS)

	for i in SFX_VOICES:
		_sfx_pool.append(_make_player(SFX_BUS))
	_music_a = _make_player(AMBIENCE_BUS)
	_music_b = _make_player(AMBIENCE_BUS)
	_active_music = _music_a
	_loop_timer = Timer.new()
	_loop_timer.one_shot = true
	_loop_timer.timeout.connect(_on_loop_timer)
	add_child(_loop_timer)

	_apply_all_volumes()
	SettingsManager.setting_changed.connect(_on_setting_changed)
	_warm_procedural_streams()
	_request_sfx_streams()
	# The player's chosen loop starts with the app, under the intro.
	play_theme_ambience.call_deferred()

	# The bomb's synthesized boom is ~100 ms of pure per-sample math. Baked
	# lazily it landed on the DETONATION frame itself — the first bomb's hitch —
	# so it bakes once on a worker thread at boot instead (pure computation on
	# locals; nothing it touches is shared until the result is read back).
	_boom_task = WorkerThreadPool.add_task(_bake_boom_async, false, "bake boom sfx")

func _ensure_bus(name: String) -> void:
	if AudioServer.get_bus_index(name) != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, name)
	AudioServer.set_bus_send(idx, "Master")

func _make_player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p

# --- Public API ---------------------------------------------------------------
func play_sfx(id: String, pitch_jitter: float = 0.0) -> void:
	var stream := _get_stream(SFX_PATHS.get(id, ""))
	if stream == null:
		return
	var p := _sfx_pool[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_pool.size()
	p.stream = stream
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()

## Play a one-shot at an explicit pitch (used for musical SFX). Same lazy-load
## and silent no-op rules as play_sfx.
func play_sfx_pitched(id: String, pitch: float) -> void:
	var stream := _get_stream(SFX_PATHS.get(id, ""))
	if stream == null:
		return
	var p := _sfx_pool[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_pool.size()
	p.stream = stream
	p.pitch_scale = clampf(pitch, 0.25, 4.0)
	p.play()

# --- Procedural chime (Sky Merge's chain melody) --------------------------------
## Each cascade step in Sky Merge plays the NEXT note up a pentatonic scale, so a
## long chain literally plays a melody — always harmonious, never dissonant. The
## bell tone is synthesized once (no asset needed) and pitch-scaled per note.
const _PENTA := [0, 2, 4, 7, 9]   # major pentatonic, in semitones
var _chime_stream: AudioStreamWAV

func play_chime(step: int) -> void:
	if _chime_stream == null:
		_claim_warm()
	if _chime_stream == null:
		_chime_stream = _bake_chime()
	var s := maxi(step, 0)
	var semi: int = _PENTA[s % 5] + 12 * (s / 5)
	var p := _sfx_pool[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_pool.size()
	p.stream = _chime_stream
	p.pitch_scale = clampf(pow(2.0, float(semi) / 12.0), 0.25, 4.0)
	p.play()

## A soft struck-bell: a fundamental plus two inharmonic overtones on fast decays,
## with a 2 ms attack so it "dings" rather than clicks. Gentle by design — long
## chains layer many of these, and they must shimmer, not shriek.
func _bake_chime() -> AudioStreamWAV:
	var rate := 44100
	var dur := 0.9
	var n := int(float(rate) * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var f0 := 660.0
	for i in n:
		var t := float(i) / float(rate)
		var atk := clampf(t / 0.002, 0.0, 1.0)
		var fade := clampf((dur - t) / 0.15, 0.0, 1.0)
		var s := sin(TAU * f0 * t) * exp(-t * 5.5) \
			+ 0.42 * sin(TAU * f0 * 2.76 * t) * exp(-t * 9.0) \
			+ 0.18 * sin(TAU * f0 * 5.40 * t) * exp(-t * 14.0)
		var v: float = tanh(s * atk * 0.85) * fade
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav

# --- Procedural blast ---------------------------------------------------------
## A synthesized party-popper "POP" for the wordmark detonation — no audio file
## needed. Three NOISE-based layers so it cracks like a real confetti pop and
## never rings like a tone:
##   • CRACK — a sharp broadband noise snap, the bang, gone in ~12 ms
##   • POP   — a fast downward pitch-drop (~720→95 Hz) that gives the rounded
##             "pop" shape and a bit of low thump; over in ~60 ms
##   • SPRAY — bright high-passed noise on a two-part envelope: a punchy "psshhh"
##             burst, then a soft slow-decaying bed that keeps rustling as the
##             confetti flutters down, fading to silence over ~3 s (matched to the
##             on-screen confetti fall)
## Deliberately NO sustained high sines (those read as a metallic ring). Baked
## ONCE into an AudioStreamWAV and cached; `strength` (0..1) modulates pitch, so a
## full charge pops fatter and a light tap snaps tighter.
var _boom_stream: AudioStreamWAV
var _boom_task := -1   # WorkerThreadPool id of the boot-time bake (-1 = collected)

func _bake_boom_async() -> void:
	_boom_baked = _bake_boom()

## Written only by the worker task; read on the main thread strictly AFTER
## wait_for_task_completion (which is the synchronisation point).
var _boom_baked: AudioStreamWAV

func play_boom(strength: float = 1.0) -> void:
	if _boom_stream == null:
		_claim_warm()
	if _boom_stream == null:
		if _boom_task >= 0:
			# Long since finished in any realistic session — this returns
			# immediately; at worst the very first bomb waits out the tail of
			# the boot-time bake instead of paying the whole ~100 ms itself.
			WorkerThreadPool.wait_for_task_completion(_boom_task)
			_boom_task = -1
			_boom_stream = _boom_baked
		if _boom_stream == null:   # belt and braces: task missing or failed
			_boom_stream = _bake_boom()
	var p := _sfx_pool[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_pool.size()
	p.stream = _boom_stream
	p.pitch_scale = lerpf(1.12, 0.9, clampf(strength, 0.0, 1.0))
	p.play()

## NOTE ON THE NOISE SOURCE: this bake draws 132,300 uniform samples and is
## therefore NON-DETERMINISTIC by design — two launches have always produced two
## different waveforms. It uses its OWN RandomNumberGenerator (same PCG32, same
## uniform distribution, auto-seeded) rather than the global `randf()` for two
## reasons: the global generator is not thread-safe and this bake now also runs
## on a WorkerThreadPool task, and drawing 132,300 numbers out of the global
## stream perturbed every later consumer of it. Every deterministic term —
## envelopes, the pitch drop, the filter, the soft-clip and the fade — is
## untouched, so the sound's shape, level and spectrum are exactly as authored;
## only which particular noise realization you get differs, as it always did.
func _bake_boom() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	var rate := 44100
	var dur := 3.0
	var n := int(float(rate) * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var nlp := 0.0                 # 1-pole low-pass state (splits noise into lo/hi)
	var pphase := 0.0             # phase for the pitch-dropping pop
	for i in n:
		var t := float(i) / float(rate)
		var atk := clampf(t / 0.001, 0.0, 1.0)           # ~1 ms attack — a snap
		# A long smooth ramp to zero over the last 0.6 s so the drifting tail
		# fades right out with the confetti — no click where the sample ends.
		var fade := clampf((dur - t) / 0.6, 0.0, 1.0)
		# Split white noise into a bright (high-pass) stream for the paper spray.
		var white := rng.randf() * 2.0 - 1.0
		nlp = lerpf(nlp, white, 0.5)
		var hp := white - nlp                            # bright hiss = flying paper
		# CRACK: the bang — full-band noise snapping away almost instantly.
		var crack := white * exp(-t * 80.0)
		# POP: a fast downward pitch-drop = the rounded "pop" (and a little thump).
		var pf := lerpf(720.0, 95.0, clampf(t / 0.035, 0.0, 1.0))
		pphase += TAU * pf / float(rate)
		var pop := sin(pphase) * exp(-t * 36.0)
		# SPRAY: a punchy "psshhh" burst (fast decay) layered over a soft bed that
		# decays slowly, so it keeps rustling for seconds as the paper settles.
		var spray := hp * (0.7 * exp(-t * 6.0) + 0.32 * exp(-t * 1.25))
		# Mix, soft-clip hot for punch, then apply the long tail fade.
		var s: float = tanh((crack * 0.85 + pop * 1.0 + spray * 0.75) * atk * 2.3) * fade
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav

# --- Off-thread warm-up of the two baked streams -------------------------------
## Both procedural streams are built by per-sample GDScript loops — 39,690
## iterations for the chime, 132,300 for the boom — and they used to run on the
## frame the sound was first WANTED. Measured on a 24-core desktop: 14.4 ms and
## 52.2 ms, i.e. one and three-plus dropped frames, several times that on a
## phone. The stall therefore landed exactly on the moment the sound exists to
## sell: Home's wordmark party-popper, and Sky Merge's first cascade.
##
## They are now baked once on a WorkerThreadPool task submitted at boot, while
## the intro/splash are on screen and nothing else wants the main thread. The
## inline bake is deliberately KEPT: a call that arrives before the task has
## landed bakes it inline exactly as before, so the worst case is today's
## behaviour and never a blocking wait or a swallowed sound.
var _bake_task := -1
var _warm_chime: AudioStreamWAV
var _warm_boom: AudioStreamWAV

func _warm_procedural_streams() -> void:
	if _bake_task != -1:
		return
	# Pure PackedByteArray math on the task: no scene tree, no Object state, no
	# global RNG (see the note on _bake_boom) — nothing that needs the main thread.
	_bake_task = WorkerThreadPool.add_task(_bake_warm, false, "audio: bake chime + boom")

func _bake_warm() -> void:
	_warm_chime = _bake_chime()
	_warm_boom = _bake_boom()

## Adopts the warmed streams IF the task has already finished. Never blocks:
## is_task_completed() is a non-blocking poll and wait_for_task_completion() is
## called only once that has returned true — there it is the join that publishes
## the worker's writes to this thread, and releases the task id.
func _claim_warm() -> void:
	if _bake_task == -1:
		return
	if not WorkerThreadPool.is_task_completed(_bake_task):
		return
	WorkerThreadPool.wait_for_task_completion(_bake_task)
	_bake_task = -1
	if _chime_stream == null:
		_chime_stream = _warm_chime
	if _boom_stream == null:
		_boom_stream = _warm_boom
	_warm_chime = null
	_warm_boom = null

func _exit_tree() -> void:
	# Never leave a submitted task unjoined — the pool is torn down at shutdown and
	# an outstanding id would be waited on there, after this node is gone.
	if _bake_task == -1:
		return
	WorkerThreadPool.wait_for_task_completion(_bake_task)
	_bake_task = -1
	_warm_chime = null
	_warm_boom = null

# --- Volume plumbing ----------------------------------------------------------
func _on_setting_changed(key: String, _value: Variant) -> void:
	# The SFX bus level is the volume slider gated by the master mute toggle, so
	# either setting re-applies the same effective level.
	if key == "sfx_volume" or key == "sound_enabled" or key == "ambience_volume":
		_apply_all_volumes()
	if key == "ambience_id":
		play_theme_ambience()

func _apply_all_volumes() -> void:
	_set_bus_linear(_effective_sfx_volume(), SFX_BUS)
	_set_bus_linear(_ambience_volume(), AMBIENCE_BUS)

func _ambience_volume() -> float:
	return clampf(float(SettingsManager.get_value("ambience_volume")), 0.0, 1.0)

# --- Ambience -------------------------------------------------------------------
## Cross-fades to the loop `id` ("" = silence). The same id again is a no-op.
func play_ambience(id: String) -> void:
	if id == _current_ambience:
		return
	_current_ambience = id
	_loop_timer.stop()
	var incoming: AudioStreamPlayer = _music_b if _active_music == _music_a else _music_a
	if _active_music != null and _active_music.playing:
		_fade(_active_music, _active_music.volume_db, -40.0, true, FADE_TIME)
	if id.is_empty():
		_active_music = incoming
		return
	var file_name := String(MUSIC_NAMES.get(id, id))
	var stream := _get_stream(MUSIC_DIR + file_name + ".mp3")
	if stream == null:
		_active_music = incoming
		return
	incoming.stream = stream
	incoming.volume_db = -40.0
	incoming.play()
	_fade(incoming, -40.0, 0.0, false, FADE_TIME)
	_active_music = incoming
	_schedule_loop()

## Plays only what the player picked in Settings. Silence is the default.
func play_theme_ambience() -> void:
	play_ambience(String(SettingsManager.get_value("ambience_id")))

func current_ambience() -> String:
	return _current_ambience

## Fires LOOP_FADE_TIME before the track ends so the loop cross-fades into
## itself instead of exposing the MP3 gap.
func _schedule_loop() -> void:
	if _active_music == null or _active_music.stream == null:
		return
	var length: float = _active_music.stream.get_length()
	if length <= 0.0:
		return
	var pos: float = _active_music.get_playback_position()
	_loop_timer.wait_time = maxf(0.1, length - pos - LOOP_FADE_TIME)
	_loop_timer.start()

func _on_loop_timer() -> void:
	if _active_music == null or not _active_music.playing or _active_music.stream == null:
		return
	var incoming: AudioStreamPlayer = _music_b if _active_music == _music_a else _music_a
	incoming.stream = _active_music.stream
	incoming.volume_db = -40.0
	incoming.play()
	_fade(incoming, -40.0, 0.0, false, LOOP_FADE_TIME)
	_fade(_active_music, _active_music.volume_db, -40.0, true, LOOP_FADE_TIME)
	_active_music = incoming
	_schedule_loop()

func _fade(player: AudioStreamPlayer, from_db: float, to_db: float,
		stop_after: bool, duration: float = FADE_TIME) -> void:
	player.volume_db = from_db
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(player, "volume_db", to_db, duration)
	if stop_after:
		tw.finished.connect(func():
			if is_instance_valid(player):
				player.stop())

## The volume actually sent to the SFX bus: the slider value while sound is on,
## or a hard zero (muted bus) when the master toggle is off.
func _effective_sfx_volume() -> float:
	return SettingsManager.sfx_volume() if SettingsManager.sound_enabled() else 0.0

func _set_bus_linear(linear: float, bus: String) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx == -1:
		return
	# Mute cleanly at zero rather than -inf math edge cases.
	if linear <= 0.001:
		AudioServer.set_bus_mute(idx, true)
	else:
		AudioServer.set_bus_mute(idx, false)
		AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0, 1.0)))

# --- Lazy stream loading ------------------------------------------------------
## Every AUTHORED SFX starts loading on the resource loader's worker at boot, so
## the session's first merge/button claims a finished stream instead of paying a
## synchronous mp3 decode on the main thread. Unauthored paths are never
## requested — they stay the quiet no-op _get_stream has always made of them.
func _request_sfx_streams() -> void:
	for id: String in SFX_PATHS:
		var path: String = SFX_PATHS[id]
		if ResourceLoader.exists(path) and ResourceLoader.load_threaded_request(
				path, "AudioStream", false, ResourceLoader.CACHE_MODE_REUSE) == OK:
			_sfx_requested[path] = true

func _get_stream(path: String) -> AudioStream:
	if path.is_empty():
		return null
	if _stream_cache.has(path):
		return _stream_cache[path]
	if not ResourceLoader.exists(path):
		if not _missing_warned.has(path):
			_missing_warned[path] = true
			print("[AudioManager] (info) audio not yet authored: %s" % path)
		_stream_cache[path] = null
		return null
	if _sfx_requested.has(path):
		var st := ResourceLoader.load_threaded_get_status(path)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			_sfx_requested.erase(path)
			var claimed := ResourceLoader.load_threaded_get(path) as AudioStream
			_stream_cache[path] = claimed
			return claimed
		if st != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_sfx_requested.erase(path)
		# IN_PROGRESS falls through: load() below JOINS the in-flight request and
		# blocks only for the remainder — never worse than the old cold load.
	var res := load(path)
	var stream := res as AudioStream
	_stream_cache[path] = stream
	return stream
