extends SceneTree
## Probes Malam Poek glyph coverage so we know if it can carry tiles (digits),
## body text (lowercase), and the UI symbols used across screens.

func _init() -> void:
	var path := "res://assets/fonts/MalamPoek.ttf"
	if not ResourceLoader.exists(path):
		print("MISSING: ", path)
		quit(1)
		return
	var ff := load(path) as FontFile
	if ff == null:
		print("LOAD FAILED")
		quit(1)
		return
	var sets := {
		"digits": "0123456789",
		"upper": "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
		"lower": "abcdefghijklmnopqrstuvwxyz",
		"punct": " .,:'!?-",
		"symbols": "‹›‖↺⚙✓✦◷❍⧖❖▣∞◆",
	}
	for key in sets:
		var s: String = sets[key]
		var missing := ""
		for i in s.length():
			var ch := s[i]
			if not ff.has_char(ch.unicode_at(0)):
				missing += ch
		print(key, ": ", "ALL OK" if missing.is_empty() else ("missing -> [" + missing + "]"))
	quit(0)
