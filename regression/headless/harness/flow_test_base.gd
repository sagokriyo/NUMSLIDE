extends "res://regression/headless/harness/script_test_base.gd"
## Base for full-boot FLOW tests — tests that navigate real screens through
## SceneRouter and play the real game. Adds save-section snapshot/restore
## (flows unavoidably touch stats/achievements/sessions while playing) and a
## board fixture loader for scripted, deterministic gameplay.

## Every section a flow can dirty while playing. Snapshotted before the flow
## runs and written back after, so the player's data survives even when tests
## merge big tiles or finish games.
## "owned_themes" is here because a flow can BUY one (the Shop's shelf is a real
## storefront), and a theme bought by a test is a permanent, invisible change to
## the developer's save — the one section where "it only ran once" still leaves a
## mark. It is also what a test must be able to clear to pin what the shelf shows.
## "bounties" is here because the daily board is now CLAIMED rather than paid
## automatically, so a flow that wants to see a Claim button has to plant a
## finished-but-unclaimed bounty — and leaving that behind would hand the
## developer either free coins or a board that says "collected" for tasks they
## never did.
const GUARDED_SECTIONS := [
	"settings", "entitlements", "stats", "score_history", "achievements",
	"current_game", "best_scores", "ads", "constellation", "profile", "wallet",
	"owned_themes", "bounties",
]

var _section_snapshots: Dictionary = {}
var _had_section: Dictionary = {}

func snapshot_save_state() -> void:
	for name: String in GUARDED_SECTIONS:
		_had_section[name] = SaveManager.has_section(name)
		_section_snapshots[name] = SaveManager.get_section(name, {})

func restore_save_state() -> void:
	for name: String in GUARDED_SECTIONS:
		if bool(_had_section.get(name, false)):
			SaveManager.set_section(name, _section_snapshots[name])
		else:
			SaveManager.clear_section(name)
	SaveManager.flush()

## Loads a deterministic board into a live gameplay controller and rebuilds the
## visual board to match. `values` is id -> tile value; `cells` is "x,y" -> id.
func load_board_fixture(gp: Variant, cells: Dictionary, values: Dictionary, next_id: int) -> void:
	var highest := 0
	for id: Variant in values.keys():
		highest = maxi(highest, int(values[id]))
	var board: Variant = gp._board
	board.load_dict({
		"size": board.size, "score": board.score, "highest": highest,
		"next_id": next_id, "cells": cells, "values": values,
	})
	gp._board_view.rebuild_tiles()

## The classic full-board-no-moves fixture: a value checkerboard.
func checkerboard(size: int) -> Dictionary:
	var cells: Dictionary = {}
	var values: Dictionary = {}
	var id := 0
	for y in size:
		for x in size:
			id += 1
			cells["%d,%d" % [x, y]] = id
			values[id] = 2 if (x + y) % 2 == 0 else 4
	return {"cells": cells, "values": values, "next_id": id}
