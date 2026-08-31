extends Node
## SceneRouter — the UI manager. Owns all screen navigation and transitions.
##
## Screens never call get_tree().change_scene_* directly. Instead they call
## SceneRouter.goto(Route.HOME) and a single, consistent crossfade plays. This
## centralises transition feel, lets us pass a typed payload between screens
## (e.g. which game mode to start), and keeps a lightweight history for "back".
##
## Overlays (pause / victory / game over) are NOT routes — they are instanced
## on top of the live gameplay scene by the gameplay controller. Routing is for
## full-screen destinations only.

# Canonical scene paths. One place to rename or relocate a screen.
const Route := {
	"INTRO": "res://scenes/intro/intro.tscn",
	"SPLASH": "res://scenes/splash/splash.tscn",
	"SIGN_IN": "res://scenes/auth/auth.tscn",
	"HOME": "res://scenes/home/home.tscn",
	"GAMEPLAY": "res://scenes/gameplay/gameplay.tscn",
	# The Daily Puzzle calendar: today's puzzle and every past day, replayable.
	"SETTINGS": "res://scenes/settings/settings.tscn",
	"STATISTICS": "res://scenes/statistics/statistics.tscn",
	"ACHIEVEMENTS": "res://scenes/achievements/achievements.tscn",
	"THEMES": "res://scenes/themes/themes.tscn",
	# The bottom-nav Profile TAB: identity, account, membership, support.
	"PROFILE": "res://scenes/profile/profile.tscn",
	# The progression page behind Home's floating tier capsule: the badge itself,
	# the rank ladder, the trophy case and per-mode mastery. Deliberately NOT the
	# same screen as PROFILE — tapping a rank badge must open the rank.
	"BADGE": "res://scenes/badge/badge.tscn",
	"HOW_TO_PLAY": "res://scenes/how_to_play/how_to_play.tscn",
	"PREMIUM": "res://scenes/premium/premium.tscn",
	# Soft currency (coins / gems). Distinct from PREMIUM, which is the Play
	# Billing paywall for the one lifetime unlock.
	"SHOP": "res://scenes/shop/shop.tscn",
	# The player's own record book — best score per mode, ranked — and the door
	# to the same boards on Play Games. Sits where the energy meter used to, as
	# the purse strip's third pill.
	"LEADERBOARD": "res://scenes/leaderboard/leaderboard.tscn",
	# A finished run's receipt, itemised, with the purse rolling up as it reads.
	# Reached ONLY from a game-over modal's exit actions (never from a tab or a
	# menu) and always with `replace`, so it never enters the back stack — see
	# scenes/rewards/rewards.gd.
	"REWARDS": "res://scenes/rewards/rewards.tscn",
}

var _fade_layer: CanvasLayer
var _fade_rect: ColorRect
var _toast_layer: CanvasLayer
var _active_toast: Control
var _history: Array[String] = []
var _payload: Dictionary = {}
var _transitioning := false
var _last_tier: int = -1   # highest mastery tier the player has reached
var _confirm_modal: ModalOverlay   # the "Quit?" confirmation, when showing

func _ready() -> void:
	# Full-screen fade overlay sits above everything (high layer index).
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 128
	add_child(_fade_layer)
	_fade_rect = ColorRect.new()
	# Base colour is opaque; we reveal/hide the curtain via modulate.a so the
	# fill colour can track the theme without disturbing the animation.
	_fade_rect.color = ThemeManager.color("bg0")
	_fade_rect.modulate.a = 0.0
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade_rect)
	ThemeManager.theme_changed.connect(func(p):
		_fade_rect.color = Color(p["bg0"], 1.0))
	# High-refresh Android: with swappy_mode=pipeline_forced_on (project.godot)
	# the frame pacer honours Engine.max_fps instead of auto-downgrading the app
	# to a "sustainable" 60/40/30 fps — and pinning max_fps to the panel's real
	# refresh rate is also the explicit vote Android 15+ needs before it grants
	# a game more than 60 Hz.
	if OS.get_name() == "Android":
		_target_display_hz()

	# Global achievement-unlock / tier-up toast layer (just below the curtain).
	_toast_layer = CanvasLayer.new()
	_toast_layer.layer = 120
	add_child(_toast_layer)
	Achievements.unlocked.connect(_on_achievement_unlocked)

	# Watch progression so a freshly-earned mastery tier is celebrated.
	_last_tier = TierBadge.current_index(GameStats.best_mastery_ratio()["ratio"])
	GameStats.stats_changed.connect(_on_stats_changed)

	# The whole interface runs at a fixed 110% scale — the one size every screen
	# is designed around (no user setting; the old Text Size slider is gone).
	_apply_ui_scale()

	# Own the Android hardware back button instead of letting Godot quit the app
	# on the first press. We route it through _notification below so back navigates
	# within the app and only offers to quit at the root (Home). See _on_back().
	get_tree().quit_on_go_back = false

	# Godot auto-enables processing on any node whose script declares _process().
	# The warm poller costs nothing at rest, so it stays OFF until warm() turns it on.
	set_process(false)

## Scales the entire UI (every screen, modal and toast) via the window's
## content_scale_factor, which multiplies on top of the canvas_items stretch so
## text stays crisp. Locked at 110%.
const UI_SCALE := 1.1

func _apply_ui_scale() -> void:
	var w := get_window()
	if w:
		w.content_scale_factor = UI_SCALE

# --- Resource warm-up ---------------------------------------------------------
## Pre-load a route's scene graph on a worker thread so the navigation that wants
## it finds a cache hit instead of paying for the parse.
##
## This does NOT change navigation. `SceneTree.change_scene_to_file()` resolves
## through `ResourceLoader::load()` with CACHE_MODE_REUSE, so goto() / back() /
## _fade_to_path() are untouched by construction — they simply find the resource
## already in the cache. Nothing here can alter the crossfade, the payload, the
## back stack or the transition guard.
##
## The first caller was the studio intro (scenes/intro/intro.gd), which has
## ~1.75 s of idle runway while its logo fades; Home's scene graph costs ~400 ms to
## parse and used to be paid entirely behind the opaque splash→Home curtain.
## goto() and _fade_to_path() now also warm their own destination first thing,
## and the splash warms Sign In across its hold, so a navigation's parse
## overlaps its fade instead of landing inside the curtain hold.
##
## Every failure mode degrades to today's behaviour, never worse:
##   * a request that never lands is dropped by the watchdog and the cold load runs;
##   * a tap-to-skip that navigates mid-warm makes the main thread JOIN the worker
##     task (measured) — it blocks only for the remainder, never double-parses.
const _WARM_TIMEOUT_MS := 15000

var _warming: Dictionary = {}   # path -> Time.get_ticks_msec() when requested
var _warmed: Dictionary = {}    # path -> PackedScene, held until the scene goes live

func warm(route: String) -> void:
	if route.is_empty() or _warming.has(route) or _warmed.has(route):
		return
	if ResourceLoader.has_cached(route):
		return
	if ResourceLoader.load_threaded_request(route, "PackedScene", false,
			ResourceLoader.CACHE_MODE_REUSE) != OK:
		return
	_warming[route] = Time.get_ticks_msec()
	set_process(true)

## Polls in-flight warms and releases a warmed scene once its instance is live.
## Deliberately uses Time.get_ticks_msec() rather than a SceneTreeTimer: the
## animation-hash gate censuses `create_timer(` / `set_delay(` across res://autoload
## and a timer here would move a hash that must not move.
func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	for path: String in _warming.keys():
		var st := ResourceLoader.load_threaded_get_status(path)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			var res := ResourceLoader.load_threaded_get(path)
			_warming.erase(path)
			if res != null:
				_warmed[path] = res
		elif st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if now - int(_warming[path]) > _WARM_TIMEOUT_MS:
				_warming.erase(path)
		else:
			# FAILED / INVALID_RESOURCE — stay silent; the cold path still works.
			_warming.erase(path)
	# Once the scene is live it owns its own graph; drop our reference so the warm
	# never becomes a permanent hold.
	var cur := get_tree().current_scene
	if cur != null and _warmed.has(cur.scene_file_path):
		_warmed.erase(cur.scene_file_path)
	set_process(not (_warming.is_empty() and _warmed.is_empty()))

# --- Back stack ---------------------------------------------------------------
## The back stack is a convenience, not a journal. A player never walks back more
## than a handful of screens, but a session that keeps navigating FORWARD (Home ->
## Settings -> Home -> Settings ...) used to grow `_history` for as long as the app
## stayed open. 32 is far deeper than anything the UI can actually build — the
## deepest real chain, Home -> Settings -> Themes -> Premium, is four — so no real
## session ever notices the trim; past it the OLDEST entry is dropped, because the
## far end of the stack is the part the player can no longer plausibly walk to.
const HISTORY_MAX := 32

## The boot chain plays once, forward only. Every screen in it has a real
## `scene_file_path`, so without this rule the hand-offs (intro -> splash ->
## sign in -> home) stranded them ALL on the back stack and nothing ever popped
## them: a deep enough back() chain resurfaced the SPLASH on top of a live
## session, and back()'s empty-history branch could never be reached in normal
## play. SIGN_IN belongs here for the same reason and one of its own — the choice
## is made once per boot, so walking back into it from Home would ask the player
## to sign in again over a game they are already playing. Held as Route KEYS so a
## relocated scene cannot silently fall out of the set.
const TRANSIENT_ROUTE_KEYS: Array[String] = ["INTRO", "SPLASH", "SIGN_IN"]

## True when the screen we are leaving is worth recording as a back destination.
## Every rule about what back() may land on lives here, in one place:
##   * a scene with no file path is not a screen (the headless host starts on none);
##   * the boot chain is one-way — see TRANSIENT_ROUTE_KEYS;
##   * re-opening the screen we are already on, or repeating the entry already on
##     top of the stack, would spend a back press to land the player exactly where
##     they started — the live screen and the top of the stack are the same thing.
func _is_back_target(path: String, destination: String) -> bool:
	if path.is_empty() or path == destination:
		return false
	for key: String in TRANSIENT_ROUTE_KEYS:
		if String(Route[key]) == path:
			return false
	return _history.is_empty() or _history[_history.size() - 1] != path

## Navigate to a route with a crossfade. `payload` is readable by the next
## scene via SceneRouter.take_payload(). Whether the outgoing screen becomes a
## back destination at all is decided by _is_back_target().
##
## `replace` swaps the current screen OUT of the back stack instead of stacking
## on top of it: the outgoing screen is not pushed onto `_history`, so back()
## from the destination returns to whatever the player came from before it.
## Use it only when the outgoing screen bounces the player onward the instant it
## opens — a screen like that must never become a back target. The premium gate
## (scenes/gameplay/gameplay.gd) is the case: stacking a screen that immediately
## reroutes traps back() in a loop between the two (the "paywall back-trap" —
## back pops the blocked board, it blocks again, reroutes to the paywall and
## re-pushes itself, so the player can never reach Home). Ordinary forward
## navigation leaves this false and pushes as before.
## A navigation asked for while a hop is in flight (a screen rerouting from its
## own on_ready, a tap during the crossfade) runs the moment the hop lands
## instead of vanishing. Last request wins.
var _pending: Callable = Callable()

func _flush_pending() -> void:
	if not _pending.is_valid():
		return
	var queued := _pending
	_pending = Callable()
	queued.call()

func goto(route: String, payload: Dictionary = {}, replace: bool = false) -> void:
	if _transitioning:
		_pending = goto.bind(route, payload, replace)
		return
	# First act of an ACCEPTED navigation — the destination's parse starts on the
	# loader thread now, so it overlaps the fade instead of the curtain hold. A
	# goto dropped by the guard above must not warm: it would pin a PackedScene
	# for a route the player may never visit. warm() documents why this cannot
	# alter the transition.
	warm(route)
	_transitioning = true
	_payload = payload
	var current := get_tree().current_scene
	if not replace and current and _is_back_target(current.scene_file_path, route):
		_history.push_back(current.scene_file_path)
		# Bounded (see HISTORY_MAX): the oldest entry falls off the far end, so a
		# marathon session cannot grow the array without limit.
		while _history.size() > HISTORY_MAX:
			_history.pop_front()
	await _crossfade_to(route, 48.0)   # forward navigation glides in from the right
	_transitioning = false
	_flush_pending()

## Returns to the previous full-screen route (or Home if history is empty).
##
## Awaits the navigation it starts, so a caller that awaits back() knows when the
## player has actually landed. Every shipped caller fires and forgets (the header
## chevron, Themes' / How-to-play's Done, the hardware back button) and is
## unaffected: an un-awaited coroutine still runs to completion on its own.
func back() -> void:
	# Guard BEFORE popping: _fade_to_path also checks _transitioning and would
	# silently no-op mid-transition, which would discard the popped entry and make
	# a rapid double-back skip a screen. goto() guards the same way.
	if _transitioning:
		return
	if _history.is_empty():
		# Nothing to return to: go Home and REPLACE, never push. Pushing here would
		# refill the stack we just found empty with the screen the player pressed
		# back on, so the next back() would hand them the screen they just left
		# instead of taking this branch again — the "empty" stack was empty for
		# exactly one frame.
		await goto(Route["HOME"], {}, true)
		return
	var prev: String = _history.pop_back()
	await _fade_to_path(prev)

func _fade_to_path(path: String) -> void:
	if _transitioning:
		return
	warm(path)   # accepted navigation only — parse overlaps the fade, see goto()
	_transitioning = true
	await _crossfade_to(path, -48.0)   # going back glides in from the left
	_transitioning = false
	_flush_pending()

## THE HOP. No curtain, ever: the destination is loaded and BUILT while the page
## being left is still on view, then crossfades in over it, and only once it
## fully owns the screen is the old page freed. The old page is frozen for that
## beat so nothing in it can still react. The swap is manual (instantiate, add
## under the root, point current_scene at it) rather than change_scene_to_file,
## which removes the old page BEFORE the new one exists and leaves a frame of
## clear colour between them. The user's rule: a black gap of any length reads
## as the page "taking a while".
##
## `from_x` is the arriving page's glide (see _slide_reveal); it rides on top
## of the fade so travel still has a direction.
const CROSSFADE := 0.16

func _crossfade_to(path: String, from_x: float) -> void:
	# Input is blocked by the curtain rect (kept transparent) for the swap only.
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	get_tree().paused = false
	# One frame: a caller can be inside its own _ready while the root is still
	# busy adding it, and add_child would be refused.
	await get_tree().process_frame
	var packed := ResourceLoader.load(path, "PackedScene") as PackedScene
	if packed == null:
		push_error("SceneRouter: could not load %s" % path)
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return
	var old := get_tree().current_scene
	var next := packed.instantiate()
	if old != null:
		old.process_mode = Node.PROCESS_MODE_DISABLED
		if old.has_method("freeze"):
			old.call("freeze")   # AppScreen: stop its render targets too
	get_tree().root.add_child(next)   # _ready → build_content: the one synchronous cost
	get_tree().current_scene = next
	_warmed.erase(path)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var reduce: bool = bool(SettingsManager.get_value("reduce_motion"))
	if old != null and next is CanvasItem and not reduce:
		var arriving := next as CanvasItem
		arriving.modulate.a = 0.0
		_slide_reveal(from_x)
		# Real time: a hop inside a slow-motion beat must not stretch the fade.
		var tw := create_tween().set_ignore_time_scale(true)
		tw.tween_property(arriving, "modulate:a", 1.0, CROSSFADE)
		await tw.finished
	if is_instance_valid(old):
		old.queue_free()

## A subtle directional glide on the freshly-arrived screen while the curtain
## lifts: forward navigation enters from the right, back() from the left, so
## moving between screens reads as travel rather than a static crossfade.
## Composes with each screen's own entrance (stagger_in etc.); skipped for
## non-Control roots.
func _slide_reveal(from_x: float) -> void:
	var cur := get_tree().current_scene
	if not (cur is Control):
		return
	var c := cur as Control
	c.position.x = from_x
	# A breath of depth with the glide: the screen arrives a hair "closer" and
	# settles to rest, so navigation reads as moving through space, not sliding
	# flat cards. Scale-only (canvas transform), so it never touches layout.
	c.pivot_offset = c.get_viewport_rect().size * 0.5
	c.scale = Vector2(1.012, 1.012)
	var tw := c.create_tween().set_parallel(true)
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(c, "position:x", 0.0, DesignSystem.DUR_PAGE)
	tw.tween_property(c, "scale", Vector2.ONE, DesignSystem.DUR_PAGE)

## True while a route transition (fade → scene change → reveal) is in flight.
## goto() silently drops requests during a transition, so any screen that
## latches a "done" flag before navigating (splash/intro) MUST check this
## first — latching while busy would strand the screen with no retry.
func is_busy() -> bool:
	return _transitioning

# --- Hardware back button (Android) -------------------------------------------
## The OS back request is delivered to every node in the tree; we handle it here
## (autoloads receive it too) so a single place decides what "back" means per
## screen. quit_on_go_back is off, so nothing quits unless we say so.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back()
	# Re-check the panel rate on every return to the foreground: the OS can move
	# the app between 60/90/120 Hz display modes while it is backgrounded.
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and OS.get_name() == "Android":
		_target_display_hz()

## Ask to run at the display's full refresh rate; 0 (uncapped, vsync-paced) when
## the rate can't be read. Never a cap below what the panel can actually show.
func _target_display_hz() -> void:
	var hz := DisplayServer.screen_get_refresh_rate()
	Engine.max_fps = int(round(hz)) if hz > 0.0 else 0

func _on_back() -> void:
	# Never act mid-transition — the destination isn't settled yet.
	if _transitioning:
		return
	# A quit confirmation we own takes priority: back dismisses it (a "no").
	if is_instance_valid(_confirm_modal):
		_dismiss_quit_confirm()
		return
	var cur := get_tree().current_scene
	# Let the current screen intercept first (e.g. Gameplay opens/closes its pause
	# menu) — if it handled the press, we're done.
	if cur and cur.has_method("on_back_request") and bool(cur.call("on_back_request")):
		return
	# Default: at the root (Home) offer to quit; anywhere else, step back a screen.
	if cur and cur.scene_file_path == Route["HOME"]:
		request_quit()
	else:
		back()

## Ask the player to confirm before leaving the app. Reused by the hardware back
## button on Home and by Home's own Exit button, so both share one dialog.
func request_quit() -> void:
	if is_instance_valid(_confirm_modal):
		return
	var host := get_tree().current_scene
	if host == null:
		get_tree().quit()
		return
	_confirm_modal = ModalOverlay.new()
	_confirm_modal.compact = true
	_confirm_modal.set_header("Quit", "Leave the game?", "Your progress is saved.")
	_confirm_modal.add_action("Quit", PremiumButton.Variant.DANGER, func():
		get_tree().quit())
	_confirm_modal.add_action("Stay", PremiumButton.Variant.GLASS, _dismiss_quit_confirm)
	_confirm_modal.open(host)

func _dismiss_quit_confirm() -> void:
	if is_instance_valid(_confirm_modal):
		_confirm_modal.close()
	_confirm_modal = null

## The receiving scene calls this in _ready() to consume navigation params.
func take_payload() -> Dictionary:
	var p := _payload
	_payload = {}
	return p

# --- Toasts (achievements + tier-ups) -----------------------------------------
func _on_achievement_unlocked(id: String, def: Dictionary) -> void:
	# The toast wears the badge's own medallion art (falling back to the glyph
	# icon in its payout theme's accent) — badge, toast and reward theme share
	# one identity instead of a generic trophy.
	var icon: Control
	var medal := UI.icon_tex("res://assets/images/medals/%s.png" % id)
	if medal:
		var rect := TextureRect.new()
		rect.texture = medal
		rect.custom_minimum_size = Vector2(72, 72)
		rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon = rect
	else:
		icon = PremiumIcon.make(String(def.get("icon", "trophy")),
			ThemeManager.badge_accent(id), 72, String(def.get("icon_label", "")))
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_show_toast("ACHIEVEMENT UNLOCKED", String(def.get("title", "Achievement")), icon)
	# EVERY badge pays gems, so a second toast always follows once the first has
	# had its moment. Badges used to pay out one fixed theme each; they now pay
	# the currency that buys ANY theme, so this is where the player learns the
	# badge was worth something. Progression does the actual crediting — this
	# only reports it, and reads the same constant so the two cannot drift.
	await get_tree().create_timer(3.4).timeout
	if not is_inside_tree():
		return
	_show_toast("GEMS EARNED", "+%d Gems" % EconomyRules.GEMS_PER_BADGE, _gem_icon())

## The gem token at toast size — the payout icon for a freshly-earned badge.
func _gem_icon() -> Control:
	var rect := TextureRect.new()
	rect.texture = IconLibrary.texture("currency_gems", 64, false)
	rect.custom_minimum_size = Vector2(64, 64)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return rect

## A small rounded swatch in a theme's own accent — the toast icon for a
## freshly-bought shop theme.
func _theme_swatch(theme_id: String) -> Control:
	var pal := ThemeManager.palette_for(theme_id)
	var accent: Color = pal.get("accent", ThemeManager.color("accent"))
	var swatch := Panel.new()
	swatch.custom_minimum_size = Vector2(64, 64)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = accent
	sb.set_corner_radius_all(18)
	sb.set_border_width_all(2)
	sb.border_color = accent.lightened(0.35)
	swatch.add_theme_stylebox_override("panel", sb)
	return swatch

## Celebrate when the player's highest tile crosses into a new mastery tier.
func _on_stats_changed() -> void:
	var t := TierBadge.current_index(GameStats.best_mastery_ratio()["ratio"])
	if t > _last_tier:
		_last_tier = t
		_show_rank_up(t)

## A mastery tier-up is the game's biggest single milestone, so it gets a
## CEREMONY, not a toast: the screen dims, the new badge zooms in on a burst of
## theme tile shards under a "RANK UP" banner, then gently auto-dismisses (tap
## anywhere to skip). Stamps the tier as celebrated (profile.seen_tier) FIRST,
## so Home's capsule flare never replays a rank the ceremony already owned —
## and a mid-ceremony quit can't re-celebrate on the next boot.
## Plays the rank-up ceremony again, on demand.
##
## The ceremony is the biggest single moment the game has and it fires exactly
## once, unannounced, on whatever screen the player happened to be looking at —
## so the one place it is guaranteed to be missed is the moment it matters. The
## Badge page trophy case hands it back: tap an earned shield, replay its
## ceremony. Refuses an UNEARNED tier, because the ceremony says "rank up" and a
## rank you have not reached must not be able to say it.
func replay_rank_up(t: int) -> bool:
	if t < 0 or t >= TierBadge.count():
		return false
	if t > TierBadge.current_index(GameStats.best_mastery_ratio()["ratio"]):
		return false
	_show_rank_up(t)
	return true

func _show_rank_up(t: int) -> void:
	if is_instance_valid(_active_toast):
		_active_toast.queue_free()
	var prof: Dictionary = SaveManager.get_section("profile", {"name": "Player", "avatar": -1})
	prof["seen_tier"] = maxi(t, int(prof.get("seen_tier", -1)))
	SaveManager.set_section("profile", prof)

	var accent: Color = TierBadge.tier(t)["accent"]
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_toast_layer.add_child(overlay)
	_active_toast = overlay

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var col := UI.vbox(int(DesignSystem.SPACE_MD))
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	const BADGE := 320.0
	var badge := TierBadge.make_glowing(BADGE, t, false)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.pivot_offset = Vector2(BADGE, BADGE) * 0.5
	col.add_child(badge)
	var eyebrow := UI.label("RANK UP", 32, "gold")
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(eyebrow)
	var title := UI.label("%s Tier" % String(TierBadge.tier(t)["name"]), 64, "text")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if ThemeManager.display_font:
		title.add_theme_font_override("font", ThemeManager.display_font)
	col.add_child(title)

	AudioManager.play_sfx("achievement")
	Haptics.success()

	var closing := {"done": false}
	var close := func():
		if bool(closing["done"]) or not is_instance_valid(overlay):
			return
		closing["done"] = true
		var tw := overlay.create_tween()
		tw.tween_property(overlay, "modulate:a", 0.0, DesignSystem.DUR_FAST)
		tw.tween_callback(overlay.queue_free)
	dim.gui_input.connect(func(e: InputEvent):
		var pressed: bool = (e is InputEventMouseButton and (e as InputEventMouseButton).pressed) \
			or (e is InputEventScreenTouch and (e as InputEventScreenTouch).pressed)
		if pressed:
			close.call())

	dim.modulate.a = 0.0
	var din := dim.create_tween()
	din.tween_property(dim, "modulate:a", 1.0, DesignSystem.DUR_BASE)
	badge.scale = Vector2(0.2, 0.2)
	var bt := badge.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	bt.tween_property(badge, "scale", Vector2.ONE, 0.5).set_delay(0.1)
	bt.tween_callback(func():
		if is_instance_valid(badge):
			TierBadge.sparkle_burst(badge, BADGE, accent, 16)
			Haptics.heavy())
	for lbl in [eyebrow, title]:
		var l := lbl as Control
		l.modulate.a = 0.0
		var lt := l.create_tween()
		lt.tween_property(l, "modulate:a", 1.0, DesignSystem.DUR_BASE).set_delay(0.45)

	await get_tree().create_timer(4.2).timeout
	close.call()

func _show_toast(eyebrow_text: String, title_text: String, icon_node: Control) -> void:
	if is_instance_valid(_active_toast):
		_active_toast.queue_free()

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_TOP_WIDE)
	center.offset_top = 60
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_layer.add_child(center)
	_active_toast = center

	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", UI.glass_box(3, DesignSystem.RADIUS_PILL))
	center.add_child(card)

	var row := UI.hbox(DesignSystem.SPACE_MD)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	row.add_child(icon_node)

	var col := UI.vbox(2)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var eyebrow := UI.label(eyebrow_text, 24, "accent")
	eyebrow.autowrap_mode = TextServer.AUTOWRAP_OFF
	col.add_child(eyebrow)
	var title := UI.label(title_text, 38, "text")
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	if ThemeManager.display_font:
		title.add_theme_font_override("font", ThemeManager.display_font)
	col.add_child(title)
	row.add_child(col)

	AudioManager.play_sfx("achievement")
	Haptics.success()

	card.modulate.a = 0.0
	card.position.y = -30
	var tin := card.create_tween().set_parallel(true)
	tin.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tin.tween_property(card, "modulate:a", 1.0, DesignSystem.DUR_BASE)
	tin.tween_property(card, "position:y", 0.0, DesignSystem.DUR_SLOW)
	await get_tree().create_timer(2.6).timeout
	if not is_instance_valid(center):
		return
	var tout := card.create_tween().set_parallel(true)
	tout.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tout.tween_property(card, "modulate:a", 0.0, DesignSystem.DUR_FAST)
	tout.tween_property(card, "position:y", -30.0, DesignSystem.DUR_FAST)
	await tout.finished
	if is_instance_valid(center):
		center.queue_free()

func _fade(target_alpha: float) -> void:
	var dur := DesignSystem.DUR_PAGE
	var tw := create_tween()
	tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_fade_rect, "modulate:a", target_alpha, dur)
	# Block input while the curtain is up.
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP if target_alpha > 0.5 \
		else Control.MOUSE_FILTER_IGNORE
	await tw.finished
