extends Node
## Bakes the Themes-card BACKDROPS - NOT part of the game.
##
##   godot --path . res://tools/theme_backdrop_bake.tscn
##   godot --path . res://tools/theme_backdrop_bake.tscn -- sakura_pink ronin
##
## Renders every theme's own BoardFx world once into an offscreen viewport and
## writes the frame to res://assets/theme_cards/<id>.webp, plus a manifest of
## each palette's fingerprint. ThemePreview then simply LOADS that photograph,
## which is the whole point: building these worlds at runtime is what made the
## Themes cards look like they were loading, because a card wore a flat gradient
## until its world had finished building somewhere off screen.
##
## Run this after adding a theme, after editing a .tres, and after any change to
## board_fx.gd that alters how a world is composed - regression/headless/suites/
## test_theme_backdrops.gd fails until you do (it compares the manifest against
## the live .tres files).
##
## Needs a real GPU - never headless (an offscreen viewport renders nothing
## there, and the bake would commit 61 black rectangles).

const OUT_DIR := ThemePreview.BAKE_DIR
const MANIFEST := ThemePreview.BAKE_DIR + "/manifest.gd"
## WebP quality. The art is soft ambience, not line work, so this is generous
## already; the whole set lands around a megabyte.
const QUALITY := 0.90

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("theme_backdrop_bake: needs a real display - an offscreen viewport renders nothing headless")
		get_tree().quit(1)
		return
	# One frame before anything renders: the scene root is still setting up its
	# children during _ready, and a SubViewport added into that window is refused
	# outright - which bakes a flat rectangle rather than a world, quietly.
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var only := _requested_ids()
	var ids: Array = ThemeManager.all_theme_ids()
	# A misspelt id on the command line would otherwise bake nothing and say so
	# only as a count of zero, which reads exactly like a finished run.
	for want in only:
		if not ids.has(String(want)):
			printerr("theme_backdrop_bake: no such theme - %s" % String(want))
			get_tree().quit(1)
			return
	var manifest: Dictionary = _read_manifest()
	var done := 0
	var failed: Array[String] = []
	for id_v in ids:
		var id := String(id_v)
		if not only.is_empty() and not only.has(id):
			continue
		var pal: Dictionary = ThemeManager.palette_for(id)
		var img: Image = await ThemePreview.render_world(get_tree(), pal, ThemePreview.BAKE_SIZE)
		if img == null or img.is_empty():
			failed.append(id)
			printerr("  FAILED %s - the viewport gave back nothing" % id)
			continue
		if _is_flat(img):
			failed.append(id)
			printerr("  FAILED %s - the frame came back FLAT (a world that never rendered)" % id)
			continue
		var path := ThemePreview.bake_path(id)
		var err := img.save_webp(ProjectSettings.globalize_path(path), true, QUALITY)
		if err != OK:
			failed.append(id)
			printerr("  FAILED %s - save_webp err=%d" % [id, err])
			continue
		manifest[id] = fingerprint(id)
		done += 1
		print("  baked %-18s -> %s" % [id, path])
		await get_tree().process_frame
	_write_manifest(manifest)
	print("THEME BACKDROP BAKE: %d baked, %d failed -> %s" % [done, failed.size(), OUT_DIR])
	if not failed.is_empty():
		printerr("failed: %s" % str(failed))
	print("Now run: godot --headless --path . --import   (imports the new .webp files)")
	get_tree().quit(1 if not failed.is_empty() else 0)

## A frame of one single colour is not a world - it is a viewport that never
## rendered. Every theme backdrop carries at least a vertical gradient, so this
## turns the silent failure (committing a flat rectangle that looks like a very
## plain theme) into a loud one.
static func _is_flat(img: Image) -> bool:
	var w := img.get_width()
	var h := img.get_height()
	var first := img.get_pixel(0, 0)
	for y in 4:
		for x in 4:
			var c := img.get_pixel(x * (w - 1) / 3, y * (h - 1) / 3)
			if not c.is_equal_approx(first):
				return false
	return true

## The fingerprint a bake is stamped with: the MD5 of the theme's own .tres.
## Deliberately the WHOLE file rather than the handful of keys BoardFx reads -
## a world can key off almost any palette value, so over-invalidating (one
## needless rebake) is the cheap mistake and under-invalidating (a card wearing
## last month's colours, with nothing to report it) is the expensive one.
static func fingerprint(id: String) -> String:
	var src := "res://data/themes/%s.tres" % id
	if not FileAccess.file_exists(src):
		return ""
	return FileAccess.get_md5(src)

func _requested_ids() -> Array:
	var out: Array = []
	var args := OS.get_cmdline_user_args()
	for a in args:
		out.append(String(a))
	return out

## The header the generated manifest carries. It explains itself where anyone
## who opens it will actually read it, and it is a script (not the .json this
## started as) for the export reason spelled out in _write_manifest.
const DOC_HEAD := [
	"## GENERATED by tools/theme_backdrop_bake.gd - do not edit by hand.",
	"##",
	"## The palette each baked card backdrop in this folder was rendered from:",
	"## the MD5 of data/themes/<id>.tres at bake time. A bake is a PHOTOGRAPH of",
	"## a theme, so an edited palette leaves it showing colours the theme no",
	"## longer has, and nothing about that fails at runtime - the card simply",
	"## looks finished and is out of date. test_theme_backdrops.gd compares",
	"## these stamps against the live .tres files and names what to re-bake.",
	"##",
	"## A script rather than a data file on purpose: the Android preset exports",
	"## \"all_resources\", which carries scripts and imported textures and",
	"## drops loose .json - and a manifest that vanishes on device turns the",
	"## on-device half of that suite into a silent skip.",
	"const FINGERPRINTS := {",
]
## The existing stamps, so a partial bake (-- <id>) keeps everyone else's.
func _read_manifest() -> Dictionary:
	var script := load(MANIFEST) as GDScript
	if script == null:
		return {}
	var out: Dictionary = script.get_script_constant_map().get("FINGERPRINTS", {})
	return out.duplicate()

## Written as a SCRIPT rather than a data file: the Android preset exports
## "all_resources", which carries scripts and imported textures and drops a
## loose .json - and a manifest that vanishes on device turns the on-device
## half of test_theme_backdrops into a silent skip.
func _write_manifest(manifest: Dictionary) -> void:
	var keys: Array = manifest.keys()
	keys.sort()
	var lines := PackedStringArray(DOC_HEAD)
	for k in keys:
		lines.append("\t\"%s\": \"%s\"," % [String(k), String(manifest[k])])
	lines.append("}")
	var f := FileAccess.open(MANIFEST, FileAccess.WRITE)
	if f == null:
		printerr("could not write %s" % MANIFEST)
		return
	f.store_string("\n".join(lines) + "\n")
	f.close()
