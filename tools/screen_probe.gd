extends Node
## screen_probe — boots ONE screen scene, lets it settle, and writes a PNG per
## theme. The visual check for a screen: run it, look at the frames.
##
##   & <godot> --path . res://tools/screen_probe.tscn --resolution 443x963 -- <route> [theme ...] [--free] [--motion] [--page=<id>] [--mode=<id>]
##
## `--mode=<id>` shoots GAMEPLAY on one board. It grants premium first, because
## a locked mode routes itself to the paywall and photographs that instead.
##
## `route` is a SceneRouter.Route key, any case ("home", "HOME"). With no themes
## it shoots the boot default and a light world, which is where layout breaks
## show. Frames land in user://screen_probe (printed at the end).
##
## Run at 443x963: that window fits the monitor and gives the true ~982-px UI
## space. A 540x1170 window is clamped by the monitor and widens the canvas.

const OUT := "user://screen_probe"
const DEFAULT_THEMES := ["starforged", "carrara"]
const SETTLE_FRAMES := 30

var _screen: Node = null
var _key := "HOME"
var _themes: Array = []
var _i := 0
var _page := ""
var _mode := ""
var _motion := false

func _ready() -> void:
	var argv := OS.get_cmdline_user_args()
	if argv.size() > 0:
		_key = String(argv[0]).to_upper()
	_themes = argv.slice(1) if argv.size() > 1 else DEFAULT_THEMES.duplicate()
	for a in _themes.duplicate():
		if String(a).begins_with("--page="):
			_page = String(a).substr(7)
			_themes.erase(a)
		elif String(a).begins_with("--mode="):
			_mode = String(a).substr(7)
			_themes.erase(a)
	if _themes.has("--motion"):
		_themes.erase("--motion")
		_motion = true
	# `--free` photographs the app as a NON-premium player, so every locked state
	# on Themes and the Shop is visible to the probe.
	if _themes.has("--free"):
		_themes.erase("--free")
		EntitlementManager.revoke_premium("probe")
	if _themes.is_empty():
		_themes = DEFAULT_THEMES.duplicate()
	DirAccess.make_dir_recursive_absolute(OUT)
	var path: String = SceneRouter.Route.get(_key, "")
	if path.is_empty():
		push_error("screen_probe: unknown route '%s' (keys: %s)" % [_key, ", ".join(SceneRouter.Route.keys())])
		get_tree().quit(1)
		return
	if not _mode.is_empty():
		# The board reads its mode off the router's payload, exactly as it does
		# when the player taps a mode card.
		EntitlementManager.grant_premium("probe")
		SceneRouter._payload = {"mode": _mode, "continue": false}
	_screen = (load(path) as PackedScene).instantiate()
	add_child(_screen)
	await get_tree().process_frame
	_shoot()

func _shoot() -> void:
	if _i >= _themes.size():
		print("screen_probe: wrote %d frames to %s"
			% [_themes.size(), ProjectSettings.globalize_path(OUT)])
		get_tree().quit()
		return
	var id := String(_themes[_i])
	# set_theme refuses locked themes; the probe wants the picture regardless.
	ThemeManager._apply(id)
	if not _page.is_empty() and _screen != null and _screen.has_method("probe_show_page"):
		_screen.call("probe_show_page", _page)
	for _f in SETTLE_FRAMES:
		await get_tree().process_frame
	# WIDTH_PROBE=<px> lists every control whose MINIMUM width exceeds <px>.
	var wide := OS.get_environment("WIDTH_PROBE")
	if wide != "" and _screen != null:
		_dump_wide(_screen, float(wide))
	# PROBE_WAIT=<seconds> holds the shot for a screen whose entrance is timed.
	var hold := OS.get_environment("PROBE_WAIT")
	if hold != "":
		await get_tree().create_timer(float(hold)).timeout
	# A page id may carry a colon ("mode:arena"); Windows refuses it in a name.
	var tag := _page if not _page.is_empty() else _mode
	var stem := "%s/%s%s_%02d_%s" % [OUT, _key.to_lower(),
		("_" + tag.replace(":", "-")) if not tag.is_empty() else "", _i, id]
	get_viewport().get_texture().get_image().save_png(stem + ".png")
	if _motion:
		for _f in 70:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(stem + "_b.png")
	print("screen_probe: %s / %s" % [_key, id])
	_i += 1
	_shoot()

func _dump_wide(root: Node, px: float) -> void:
	print("width_probe: controls with minimum width > %.0f (design px)" % px)
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is Control:
			var m := (n as Control).get_combined_minimum_size().x
			if m > px:
				var label := ""
				if n is Label:
					label = "  \"%s\"" % (n as Label).text.left(40)
				print("  %6.0f  %s (%s)%s" % [m, root.get_path_to(n), n.get_class(), label])
