class_name BadgePortrait
extends Control
## BadgePortrait — the player's profile picture.
##
## The profile picture IS the rank badge, presented as a circular portrait: a lit
## plate in the player's chosen aura, the tier emblem inside it, and whatever
## frame they have equipped around it. ONE component, used by the Profile tab's
## hero and by the identity sheet's live preview, so the two cannot drift — what
## a player picks in the sheet is literally the widget the page then draws.
##
## Unranked draws the FADED first-tier emblem rather than nothing — the same
## thing Home's capsule shows (TierBadge.make_button), so a new player's picture
## is the bottom of the ladder they are about to climb. It replaced an
## initial-letter disc, which made the one player who had earned nothing the only
## player whose picture wasn't a badge.
##
## There is no drawn laurel here. Every badge in assets/images/badges already
## carries its own wreath, in its OWN metal — the runtime gold one that used to
## be layered on top wrapped a second, always-gold garland over art that had one,
## and over Infinity's violet wings it simply looked broken.
##
## The Play Games photo, when there is one, fills the plate. PGS hands out a URL
## rather than a texture, so the badge is always built FIRST and the photo swapped
## in if and when it lands: a download that is slow, refused or offline leaves a
## portrait that looks finished instead of a hole. Off Android `icon_uri()` is
## empty and this is only ever the badge, which is also why no headless test ever
## touches the network.
##
## Masked to a circle on the CPU at download time rather than by a shader: it is
## one pass over a ~200 px bitmap, once, against a GLES3 shader that would compile
## synchronously on the render thread the first time it binds (CLAUDE.md, RULES
## 9.5) — on the very frame the page is being built.

## The badge is ALIVE, exactly as it is on the Badge page: it floats on a slow
## sine, its aura breathes, and a light glint sweeps the metal every few seconds.
## The badge and its own light only — the Badge page's white progress halo and its
## sparkle cloud are that PAGE's furniture (and 14 dots at 1.3x the box would spill
## across the profile card's text), so they stay there.
##
## All of it is one wrapper deep. This Control is laid out by whatever container
## it sits in — an HBox on the Profile tab, a CenterContainer in the identity
## sheet — and a tween on its own `position` fights that container every frame.
## `_inner` is anchored inside it and is what actually moves (Home's pattern, and
## the Badge page hero's).
const BOB_FRACTION := 0.02   # of `box`; ~5 px on the Badge page's 300 pt badge
const BOB_DUR := 2.0
const BREATHE_LO := 0.6
const BREATHE_HI := 1.0

## Edge of the square the portrait occupies; the plate is the inscribed circle.
var box := 200.0
## The player's chosen aura — the plate's light, fill tint and rim.
var tint: Color = Color.WHITE
## Index into TierBadge.TIERS, or -1 for unranked (which draws the faded first
## tier, not nothing).
var tier_idx := -1
## Index into TierBadge.FRAMES — the equipped decoration.
var frame_idx := 0
## Index into BadgeCosmetics.EFFECTS — what the emblem gives off. Drawn ABOVE
## the frame so an effect is never hidden behind the ornament it was bought to
## be seen with.
var effect_idx := 0
## The Play Games photo URL; empty (and always so off Android) means badge only.
var uri := ""

## Where the photo is inserted when it lands — above the emblem, below the frame.
## Recorded rather than hardcoded: the number of layers under it changes with the
## equipped frame, and an index guessed at write time is the kind of thing that
## silently starts painting the photo over the frame two edits later.
var _photo_at := 0
## The downloaded photo, kept so a rebuild can re-insert it instead of dropping
## the player's picture the moment they touch a swatch in the identity sheet.
var _photo_tex: Texture2D
var _fetched := false
## The animated wrapper every layer rides on. Replaced wholesale by rebuild(),
## which is what retires the previous pass's tweens with it.
var _inner: Control

func _ready() -> void:
	custom_minimum_size = Vector2(box, box)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rebuild()

## Rebuilds every layer from the current properties. Cheap enough to call on each
## tap of an aura swatch — which is exactly what the identity sheet's live
## preview does.
func rebuild() -> void:
	# Only the wrapper is thrown away. An in-flight photo fetch is a direct child
	# of THIS node precisely so it survives a repaint — a player tapping through
	# aura swatches would otherwise cancel their own picture mid-download.
	if is_instance_valid(_inner):
		remove_child(_inner)
		_inner.queue_free()
	custom_minimum_size = Vector2(box, box)
	# Ambient motion, and reduce_motion switches every other ambient layer in the
	# app off (GlassDrift, ThemeTileStrip, the product-tile sweep). Still means
	# still: no float, no breath, no glint.
	var still := bool(SettingsManager.get_value("reduce_motion"))

	var inner := Control.new()
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inner = inner

	# The aura the player CHOSE, actually lit — added first so it reads as light
	# spilling from behind the portrait.
	var halo := TierBadge.accent_glow(box, tint)
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(halo)

	inner.add_child(_plate())

	# The badge, inset so its own laurel wings clear the plate's rim.
	var emblem := TierBadge.make_view(box, maxi(tier_idx, 0), tier_idx < 0)
	emblem.custom_minimum_size = Vector2.ZERO
	emblem.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var inset := box * 0.11
	emblem.offset_left = inset; emblem.offset_top = inset
	emblem.offset_right = -inset; emblem.offset_bottom = -inset
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The same periodic glint the Badge page's hero and Home's capsule wear. It is
	# masked by the badge's own alpha, so only the shield shines — polished metal,
	# not a rectangle of light sweeping the plate.
	if not still:
		emblem.material = TierBadge.shine_material()
	inner.add_child(emblem)

	_photo_at = inner.get_child_count()
	if _photo_tex != null:
		_add_photo(_photo_tex, false)

	# The equipped decoration rides on top of whichever face wins, so the frame
	# the player chose survives the photo landing — and bobs with it.
	TierBadge.add_frame(inner, box, frame_idx, tint)
	BadgeCosmetics.add_effect(inner, box, effect_idx, tint)

	if not still:
		halo.modulate.a = 0.85
		# Connected BEFORE the add: adding to a parent that is already in the tree
		# fires tree_entered immediately, so this covers both the first build (from
		# _ready) and every repaint the identity sheet asks for.
		inner.tree_entered.connect(func() -> void:
			var lift := box * BOB_FRACTION
			var bob := inner.create_tween().set_loops()
			bob.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			bob.tween_property(inner, "position:y", -lift, BOB_DUR)
			bob.tween_property(inner, "position:y", lift, BOB_DUR)
			var breathe := halo.create_tween().set_loops()
			breathe.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			breathe.tween_property(halo, "modulate:a", BREATHE_HI, 1.7)
			breathe.tween_property(halo, "modulate:a", BREATHE_LO, 1.8))
	add_child(inner)

	if not _fetched and uri.begins_with("http"):
		_fetched = true
		_fetch()

## The circular plate the badge sits on — what turns a floating shield into a
## profile PICTURE. Glass in the player's aura with a lit rim, so the portrait
## reads as an object on the card rather than as a sticker over it.
func _plate() -> Panel:
	var plate := Panel.new()
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	# Over the theme's own glass rather than a flat fill: the plate has to sit on
	# both a near-black and a warm light palette without becoming a hole or a slab.
	sb.bg_color = ThemeManager.color("glass").lerp(Color(tint, 0.30), 0.5)
	sb.set_corner_radius_all(int(box * 0.5))
	sb.set_border_width_all(maxi(2, int(box * 0.016)))
	sb.border_color = tint.lerp(Color.WHITE, 0.35)
	sb.anti_aliasing = true
	plate.add_theme_stylebox_override("panel", sb)
	return plate

func _fetch() -> void:
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(_on_photo)
	if req.request(uri) != OK:
		req.queue_free()

func _on_photo(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.is_empty():
		return   # the badge stays; a missing photo is not an error state
	var img := Image.new()
	var err := img.load_png_from_buffer(body)
	if err != OK:
		err = img.load_jpg_from_buffer(body)
	if err != OK:
		err = img.load_webp_from_buffer(body)
	if err != OK or not is_inside_tree():
		return
	var edge := maxi(int(box), 8)
	img.resize(edge, edge, Image.INTERPOLATE_LANCZOS)
	_mask_circle(img)
	_photo_tex = ImageTexture.create_from_image(img)
	_add_photo(_photo_tex, true)

func _add_photo(tex: Texture2D, animate: bool) -> void:
	if not is_instance_valid(_inner):
		return   # a fetch that landed between rebuilds; the next one re-inserts it
	var photo := TextureRect.new()
	photo.texture = tex
	photo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	photo.stretch_mode = TextureRect.STRETCH_SCALE
	photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Inside the rim, over the emblem, under the frame.
	var pad := box * 0.03
	photo.offset_left = pad; photo.offset_top = pad
	photo.offset_right = -pad; photo.offset_bottom = -pad
	_inner.add_child(photo)
	_inner.move_child(photo, mini(_photo_at, _inner.get_child_count() - 1))
	if not animate:
		return
	photo.modulate.a = 0.0
	var tw := photo.create_tween()
	tw.tween_property(photo, "modulate:a", 1.0, DesignSystem.DUR_FAST)

## Multiplies a circular alpha into `img` in place, with a one-pixel soft edge so
## the cut does not crawl.
static func _mask_circle(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var c := Vector2(float(w), float(h)) * 0.5
	var radius := minf(c.x, c.y) - 0.5
	for y in h:
		for x in w:
			var d := (Vector2(float(x) + 0.5, float(y) + 0.5) - c).length()
			var a := clampf(radius - d + 0.5, 0.0, 1.0)
			if a >= 1.0:
				continue
			var px := img.get_pixel(x, y)
			px.a *= a
			img.set_pixel(x, y, px)
