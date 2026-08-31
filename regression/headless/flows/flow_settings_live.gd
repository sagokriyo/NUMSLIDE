extends "res://regression/headless/harness/flow_test_base.gd"
## Settings flow: drives the real widgets on the rebuilt Settings screen (hero +
## rail) and pins that every switch, slider and segment writes its key, that the
## masters dim and lock their dependants, and that reset restores DEFAULTS.

## EVERY SETTING SURVIVES THE DISK. JSON has one number type, so an INT setting
## comes back off the save as a float; the sanitiser used to refuse it as
## malformed and hand back the default, which threw the player's tray size away
## on every boot without ever saying so.
func _test_settings_survive_a_round_trip() -> void:
	print("test_settings_survive_a_round_trip:")
	for key in SettingsManager.DEFAULTS.keys():
		var id := String(key)
		if id.begins_with("_"):
			continue
		var original: Variant = SettingsManager.get_value(id)
		# What the save gives back: a JSON round trip, exactly as SaveManager does.
		var packed: Variant = JSON.parse_string(JSON.stringify({"v": original}))["v"]
		var clean: Variant = SettingsManager._sanitize(id, packed)
		check("'%s' survives the save file" % id, typeof(clean) != TYPE_NIL)
		if typeof(clean) == TYPE_NIL:
			continue
		check_eq("'%s' comes back as itself" % id, clean, original)
		check_eq("'%s' keeps its type" % id, typeof(clean), typeof(original))

func _buttons(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Button:
			out.append(c)
		_buttons(c, out)

func _find_button(n: Node, label: String) -> Button:
	var all: Array = []
	_buttons(n, all)
	for b: Button in all:
		if b.text == label:
			return b
	return null

func _labels(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Label:
			out.append((c as Label).text)
		_labels(c, out)

func _sliders(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is HSlider:
			out.append(c)
		_sliders(c, out)

## The ambience chips, in tree order: settings.gd stamps each with the id it
## stands for ("" is Off).
func _chips(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Control and c.has_meta("ambience_id"):
			out.append(c)
		_chips(c, out)

func _chip_for(chips: Array, id: String) -> Control:
	for c: Control in chips:
		if String(c.get_meta("ambience_id")) == id:
			return c
	return null

## A tap through the REAL path (UI.make_scroll_tappable's gui_input handler):
## a left press and release that never moves, so the slop check passes and
## _fire_tap runs the chip's callback.
func _tap(c: Control) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = Vector2(2, 2)
	c.gui_input.emit(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = Vector2(2, 2)
	c.gui_input.emit(up)

func run_tests() -> void:
	snapshot_save_state()
	_test_settings_survive_a_round_trip()
	var screen: Node = (load("res://scenes/settings/settings.tscn") as PackedScene).instantiate()
	root.add_child(screen)
	await process_frame
	await process_frame

	var rail: Variant = screen.get("_rail")
	check("rail built", rail != null)
	check_eq("four tabs", rail.tab_labels(), ["Visual", "Audio", "Feel", "Access"])
	check("hero Change pill exists", _find_button(screen, "Change") != null)

	# --- Visual ---
	screen.probe_show_page("visual")
	await process_frame
	var btns: Array = []
	_buttons(rail.current_panel(), btns)
	check_eq("visual: two switches", btns.size(), 2)
	var rnd_before: bool = SettingsManager.get_value("random_theme_each_game")
	(btns[0] as Button).pressed.emit()
	check_eq("random theme flips", SettingsManager.get_value("random_theme_each_game"), not rnd_before)
	var tilt_before: bool = SettingsManager.get_value("tilt_parallax")
	(btns[1] as Button).pressed.emit()
	check_eq("tilt parallax flips", SettingsManager.get_value("tilt_parallax"), not tilt_before)

	# --- Audio ---
	# Pinned before the panel builds: the ambience slider's lock state is read
	# off ambience_id at build time, and the developer's save may hold a loop.
	SettingsManager.set_value("ambience_id", "")
	screen.probe_show_page("audio")
	await process_frame
	btns = []
	_buttons(rail.current_panel(), btns)
	var sliders: Array = []
	_sliders(rail.current_panel(), sliders)
	check_eq("audio: one switch", btns.size(), 1)
	check_eq("audio: sfx + ambience sliders", sliders.size(), 2)
	var sl: HSlider = sliders[0]
	SettingsManager.set_value("sound_enabled", true)
	(btns[0] as Button).pressed.emit()
	check_eq("sound effects off", SettingsManager.get_value("sound_enabled"), false)
	check_eq("volume locks when sound is off", sl.editable, false)
	(btns[0] as Button).pressed.emit()
	check_eq("sound effects on", SettingsManager.get_value("sound_enabled"), true)
	check_eq("volume unlocks", sl.editable, true)
	sl.value = 0.3
	check_near("volume writes sfx_volume", float(SettingsManager.get_value("sfx_volume")), 0.3)

	# Ambience: Off plus every loop AudioManager ships, as chips; a chip tap
	# writes ambience_id (and AudioManager follows), the slider writes
	# ambience_volume and locks while Off.
	var chips: Array = []
	_chips(rail.current_panel(), chips)
	var ids: Array = []
	for c: Control in chips:
		ids.append(String(c.get_meta("ambience_id")))
	var want_ids: Array = [""]
	want_ids.append_array(AudioManager.AMBIENCE_IDS)
	check_eq("ambience: Off + every loop, in catalogue order", ids, want_ids)
	var amb: HSlider = sliders[1]
	check_eq("ambience slider locks while Off", amb.editable, false)
	_tap(_chip_for(chips, "rain"))
	check_eq("chip tap writes ambience_id", SettingsManager.get_value("ambience_id"), "rain")
	check_eq("AudioManager follows the chip", AudioManager.current_ambience(), "rain")
	check_eq("ambience slider unlocks with a loop", amb.editable, true)
	amb.value = 0.4
	check_near("ambience slider writes ambience_volume",
		float(SettingsManager.get_value("ambience_volume")), 0.4)
	_tap(_chip_for(chips, ""))
	check_eq("Off chip writes an empty ambience_id", SettingsManager.get_value("ambience_id"), "")
	check_eq("ambience slider locks again", amb.editable, false)

	# --- Feel ---
	screen.probe_show_page("feel")
	await process_frame
	btns = []
	_buttons(rail.current_panel(), btns)
	check_eq("feel: switch + two segmented triples", btns.size(), 7)
	_find_button(rail.current_panel(), "Strong").pressed.emit()
	check_eq("haptic strength strong", SettingsManager.get_value("haptic_strength"), "strong")
	_find_button(rail.current_panel(), "Fast").pressed.emit()
	check_eq("animation speed fast", SettingsManager.get_value("tile_speed"), "fast")
	SettingsManager.set_value("haptics_enabled", true)
	(btns[0] as Button).pressed.emit()
	check_eq("vibration off", SettingsManager.get_value("haptics_enabled"), false)
	check_eq("strength locks when vibration is off", _find_button(rail.current_panel(), "Light").disabled, true)

	# --- Access ---
	screen.probe_show_page("access")
	await process_frame
	btns = []
	_buttons(rail.current_panel(), btns)
	var rm_before: bool = SettingsManager.get_value("reduce_motion")
	(btns[0] as Button).pressed.emit()
	check_eq("reduce motion flips", SettingsManager.get_value("reduce_motion"), not rm_before)
	var reset_btn := _find_button(rail.current_panel(), "Reset settings")
	check("reset button exists", reset_btn != null)
	reset_btn.pressed.emit()
	await process_frame
	var confirm := _find_button(screen, "Reset")
	check("reset confirm modal opened", confirm != null)
	confirm.pressed.emit()
	await process_frame
	await process_frame
	check_eq("reset: sfx_volume", float(SettingsManager.get_value("sfx_volume")), 0.8)
	check_eq("reset: haptic_strength", SettingsManager.get_value("haptic_strength"), "medium")
	check_eq("reset: tile_speed", SettingsManager.get_value("tile_speed"), "normal")
	check_eq("reset: haptics_enabled", SettingsManager.get_value("haptics_enabled"), true)
	check_eq("reset: reduce_motion", SettingsManager.get_value("reduce_motion"), false)
	check_eq("reset: ambience_id", SettingsManager.get_value("ambience_id"), "")
	check_near("reset: ambience_volume", float(SettingsManager.get_value("ambience_volume")), 0.7)
	var rail2: Variant = screen.get("_rail")
	check("rebuilt after reset", rail2 != null and rail2 != rail)
	check_eq("open tab kept across rebuild", rail2.active(), 3)

	# --- No 2048 vocabulary anywhere on the page ---
	var texts: Array = []
	for tab in ["visual", "audio", "feel", "access"]:
		screen.probe_show_page(tab)
		await process_frame
		_labels(screen, texts)
	var leak := false
	for t: String in texts:
		var low := t.to_lower()
		if low.contains("tile") or low.contains("merge") or low.contains("swipe") or low.contains("2048"):
			leak = true
			printerr("  leaked copy: %s" % t)
	check("no tile/merge/swipe/2048 copy", not leak)

	screen.queue_free()
	await process_frame
	restore_save_state()
