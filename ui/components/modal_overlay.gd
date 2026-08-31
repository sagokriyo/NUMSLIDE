class_name ModalOverlay
extends Control
## ModalOverlay — a calm, glassy modal used for Pause, Victory and Game Over.
##
## Dims the scene behind a soft scrim, floats a glass card with a title, an
## optional message, optional stat rows, and a stack of actions. One component,
## configured per use — so every modal in the game shares the same feel and
## entrance motion. Build it fluently, then open(parent).

var _scrim: ColorRect
var _card: PanelContainer
var _col: VBoxContainer
var _actions: VBoxContainer

## When true the card is narrower and uses tighter spacing — for quick
## congratulation/confirmation toasts that don't need a full modal layout.
var compact: bool = false

## When true the pane frosts far more heavily and the scrim goes deeper — for a
## modal the player READS AND TYPES INTO (the identity sheet) rather than one that
## states a sentence and offers two buttons. At the default frost the page behind
## shows clean through the glass, which is fine behind "A composed finish." and
## unusable behind a text field.
var solid: bool = false

func _init() -> void:
	# Build the whole structure here (not in _ready) because callers configure the
	# modal — set_header(), add_action() — immediately after .new(), i.e. BEFORE it
	# enters the tree. If we built in _ready(), those containers would still be null.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # swallow input behind the modal

	var p := ThemeManager.palette()
	_scrim = ColorRect.new()
	_scrim.color = Color(p["bg0"], 0.0)
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_scrim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# The same lit-glass surface as Home's mode tiles and the gameplay cards, so the
	# Victory / Game Over cards read as one family with the rest of the app. It frosts
	# the screen's backdrop snapshot (not the scrim), which is what makes the pane read
	# as lit glass over the dimmed scene rather than a flat slab.
	_card = UI.glass_card(3)
	# Width set in open() once `compact` is known; default keeps legacy behaviour.
	_card.custom_minimum_size = Vector2(860, 0)
	center.add_child(_card)

	_col = UI.vbox(DesignSystem.SPACE_XL)
	_card.add_child(_col)

	_actions = UI.vbox(DesignSystem.SPACE_MD)
	# Header/stats get added before actions; actions are appended in open().

func set_header(eyebrow_text: String, title_text: String = "", subtitle_text: String = "") -> ModalOverlay:
	if not eyebrow_text.is_empty():
		var ey := UI.label(eyebrow_text.to_upper(), 24 if compact else 28, "text_faint")
		ey.autowrap_mode = TextServer.AUTOWRAP_OFF
		_col.add_child(ey)
	# TYPE_DISPLAY (132) is far too large for sentence titles like "No moves
	# left." — TYPE_TITLE keeps the modal heading strong but tidy.
	var t := UI.label(title_text, DesignSystem.TYPE_TITLE, "text")
	# Wrap (don't run off the card) so long titles never force the modal wider
	# than the screen and push the stat values out of view.
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.size_flags_horizontal = Control.SIZE_FILL
	_col.add_child(t)
	if not subtitle_text.is_empty():
		var sub_size := DesignSystem.TYPE_CAPTION if compact else DesignSystem.TYPE_BODY
		var sub := UI.label(subtitle_text, sub_size, "text_dim")
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_col.add_child(sub)
	return self

## Adds an arbitrary content block (e.g. a badge image) in document order —
## after whatever was added so far, before the actions.
func add_content(node: Control) -> ModalOverlay:
	_col.add_child(node)
	return self

## Adds a labelled value row. Great for end-of-game stats.
func add_stat_row(name_text: String, value_text: String) -> ModalOverlay:
	var row := UI.hbox(DesignSystem.SPACE_MD)
	var name_size := DesignSystem.TYPE_BODY if compact else DesignSystem.TYPE_HEADLINE
	var val_size := DesignSystem.TYPE_HEADLINE if compact else DesignSystem.TYPE_TITLE
	var n := UI.label(name_text, name_size, "text_dim")
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.autowrap_mode = TextServer.AUTOWRAP_OFF
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var v := UI.label(value_text, val_size, "text", HORIZONTAL_ALIGNMENT_RIGHT)
	v.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(n)
	row.add_child(v)
	_col.add_child(row)
	return self

## `enabled` false keeps the action ON the card but greyed out, for an offer the
## player should see and cannot take right now (a retry the purse will not
## cover): the label says why. An offer that simply vanishes reads as a feature
## the game does not have.
func add_action(label: String, variant: PremiumButton.Variant, on_press: Callable,
		enabled: bool = true) -> ModalOverlay:
	var b := PremiumButton.make(label, variant)
	b.full_width = true
	b.disabled = not enabled
	b.add_theme_font_size_override("font_size",
		DesignSystem.TYPE_BODY if compact else DesignSystem.TYPE_HEADLINE)
	b.pressed.connect(func():
		on_press.call())
	_actions.add_child(b)
	return self

## Adds the actions block and animates the modal in over `parent`.
func open(parent: Node) -> void:
	if compact:
		# Compact toast: narrower card, tighter internal spacing, lighter scrim.
		_card.custom_minimum_size = Vector2(660, 0)
		_col.add_theme_constant_override("separation", int(DesignSystem.SPACE_SM))
		_actions.add_theme_constant_override("separation", int(DesignSystem.SPACE_SM))
	if solid:
		# Set before the card enters the tree: GlassPanel builds its material in
		# _enter_tree and never rereads the field.
		(_card as GlassPanel).opacity_override = 0.93
		# A form is also a stack of groups, not one paragraph — SPACE_XL between
		# every child leaves an eyebrow orphaned from the field it labels.
		_col.add_theme_constant_override("separation", int(DesignSystem.SPACE_LG))
	_col.add_child(UI.spacer(DesignSystem.SPACE_XS, false))
	_col.add_child(_actions)
	parent.add_child(self)
	_animate_in()

func _animate_in() -> void:
	var p := ThemeManager.palette()
	var scrim_a: float = 0.62 if not compact else 0.38
	if solid:
		scrim_a = 0.78
	_card.pivot_offset = _card.size / 2.0
	_card.scale = Vector2.ONE * 0.94
	_card.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_scrim, "color", Color(p["bg0"], scrim_a), DesignSystem.DUR_BASE)
	tw.tween_property(_card, "modulate:a", 1.0, DesignSystem.DUR_BASE)
	var spring := create_tween()
	spring.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	spring.tween_property(_card, "scale", Vector2.ONE, DesignSystem.DUR_SLOW)

func close() -> void:
	var tw := create_tween().set_parallel(true)
	tw.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_scrim, "color:a", 0.0, DesignSystem.DUR_FAST)
	tw.tween_property(_card, "modulate:a", 0.0, DesignSystem.DUR_FAST)
	tw.tween_property(_card, "scale", Vector2.ONE * 0.96, DesignSystem.DUR_FAST)
	await tw.finished
	queue_free()
