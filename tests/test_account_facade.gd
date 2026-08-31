extends Node
## Smoke test for the AccountManager identity facade (off-device contract).
##
## Runs as a SCENE so the real autoloads load (AccountManager over PlayGames).
## Off-device (editor / desktop / headless) the PGS plugin is absent, so every
## facade query must report the dormant defaults and nothing may crash. Run:
##   <godot> --headless --path . res://tests/test_account_facade.tscn --quit-after 60

var _failures := 0
var _checks := 0

func _ready() -> void:
	_run()

func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame   # let autoloads finish _ready

	# Ground truth for the environment is the PLATFORM, never the facade itself:
	# branching on is_configured() would let a bug (or planted mutation) that
	# forces it true off-device dodge the dormant-default assertions below.
	# Android test builds always bundle the PGS plugin, so Android == on-device.
	if OS.get_name() == "Android":
		# On a real device the PGS plugin is present: the facade must report a
		# COHERENT live state (configured; signed-in players have a name;
		# signed-out ones report empty strings) and never crash.
		print("test_account_facade (on-device, PGS present):")
		_check("is_configured() is true with the PGS plugin",
			AccountManager.is_configured())
		if AccountManager.is_signed_in():
			_check("signed-in player has a display name",
				not AccountManager.display_name().is_empty())
		else:
			_check("display_name() is empty while signed out",
				AccountManager.display_name().is_empty())
			_check("icon_uri() is empty while signed out",
				AccountManager.icon_uri().is_empty())
	else:
		print("test_account_facade (off-device defaults):")
		_check("is_configured() is false without the PGS plugin",
			not AccountManager.is_configured())
		_check("is_signed_in() is false without the PGS plugin",
			not AccountManager.is_signed_in())
		_check("display_name() is empty while signed out",
			AccountManager.display_name().is_empty())
		_check("icon_uri() is empty while signed out",
			AccountManager.icon_uri().is_empty())
	_check("signal auth_changed exists", AccountManager.has_signal("auth_changed"))
	_check("signal profile_changed exists", AccountManager.has_signal("profile_changed"))
	_check("signal sign_in_failed exists", AccountManager.has_signal("sign_in_failed"))

	print("\n%d checks, %d failures" % [_checks, _failures])
	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		printerr("TESTS FAILED")
	_finish_smoke(0 if _failures == 0 else 1)

func _check(label: String, condition: bool) -> void:
	_checks += 1
	if condition:
		print("  ok  - %s" % label)
	else:
		_failures += 1
		printerr("  FAIL - %s" % label)

## Ends the smoke. Standalone (headless scene run) this quits the process with
## the code; embedded by the device suite runner (which sets the
## "suite_reporter" meta) it reports instead so the app keeps running.
func _finish_smoke(code: int) -> void:
	if has_meta("suite_reporter"):
		(get_meta("suite_reporter") as Callable).call(code)
	else:
		get_tree().quit(code)
