class_name RulesLock
extends SlideRules
## Lockdown: a tile that reaches home is welded there and never moves again.
##
## THE REASON THE ORDER MATTERS. A naive "lock the moment a tile is home" rule
## deals dead boards: a tile drifts across its own home cell on the way to
## somewhere else, welds itself into the middle of the tray, and the puzzle is
## over with nothing the player did wrong. So a tile locks only when it is home
## AND every tile ahead of it in the LOCK ORDER is already locked. The order is
## the one a human actually solves a sliding puzzle in, which is why following
## it can always be completed:
##
##   * the top rows, left to right, down to the last two rows
##   * BUT the final two cells of each row lock together, because you cannot
##     place a row's last tile without disturbing the one before it, so they go
##     in as a pair
##   * then the last two rows in COLUMN pairs, left to right, for the same
##     reason turned ninety degrees
##   * then the final 2x2, all four at once
##
## The board shows which group is live, so the mode teaches the method while it
## punishes you for ignoring it.

## Cells already welded down, as an Array in board.meta.
const META_LOCKED := "locked"

## The lock order, as groups. Cached per board shape; every board of a size
## shares one table.
static var _orders: Dictionary = {}

func rule_id() -> String:
	return "lock"

## The groups, in the order they may be locked, for a w x h tray.
static func lock_groups(w: int, h: int) -> Array[PackedInt32Array]:
	var key := "%dx%d" % [w, h]
	if _orders.has(key):
		return _orders[key]
	var groups: Array[PackedInt32Array] = []
	# Every row above the last two: singles, then the row's last pair together.
	for y in maxi(0, h - 2):
		for x in maxi(0, w - 2):
			groups.append(PackedInt32Array([y * w + x]))
		if w >= 2:
			groups.append(PackedInt32Array([y * w + (w - 2), y * w + (w - 1)]))
	# The last two rows, in column pairs, up to the final 2 x 2.
	if h >= 2:
		var top := (h - 2) * w
		var bot := (h - 1) * w
		for x in maxi(0, w - 2):
			groups.append(PackedInt32Array([top + x, bot + x]))
		if w >= 2:
			groups.append(PackedInt32Array([
				top + (w - 2), top + (w - 1), bot + (w - 2), bot + (w - 1),
			]))
	_orders[key] = groups
	return groups

func _groups(board: SlideBoard) -> Array[PackedInt32Array]:
	return lock_groups(board.w, board.h)

## The cells welded down right now.
static func locked_cells(board: SlideBoard) -> PackedInt32Array:
	var out := PackedInt32Array()
	var raw: Array = board.meta.get(META_LOCKED, [])
	for v in raw:
		out.append(int(v))
	return out

## The group the player is working on: the first one not yet locked. Empty when
## the board is finished. The tray rims these cells so the method is visible.
func live_group(board: SlideBoard) -> PackedInt32Array:
	var locked := locked_cells(board)
	for g in _groups(board):
		var all_in := true
		for c in g:
			if not locked.has(c):
				all_in = false
				break
		if not all_in:
			return g
	return PackedInt32Array()

func _can_move(board: SlideBoard, cell: int) -> bool:
	return not locked_cells(board).has(cell)

## Welds every group whose cells are all home, front of the order first, and
## stops at the first that is not. Runs after each slide.
func _after_slide(board: SlideBoard, _pairs: Array[Vector2i], events: Array[Dictionary]) -> void:
	var locked := locked_cells(board)
	var added := PackedInt32Array()
	for g in _groups(board):
		var already := true
		for c in g:
			if not locked.has(c):
				already = false
				break
		if already:
			continue
		var all_home := true
		for c in g:
			if not board.is_home(c):
				all_home = false
				break
		if not all_home:
			break
		for c in g:
			locked.append(c)
			added.append(c)
	if added.is_empty():
		return
	board.meta[META_LOCKED] = Array(locked)
	events.append({"type": "locked", "cells": added})

func sync(board: SlideBoard) -> void:
	# Rebuild the welds from the position alone, so an undo or a load can never
	# leave a cell locked that the board no longer has home.
	var locked := PackedInt32Array()
	for g in _groups(board):
		var all_home := true
		for c in g:
			if not board.is_home(c):
				all_home = false
				break
		if not all_home:
			break
		for c in g:
			locked.append(c)
	board.meta[META_LOCKED] = Array(locked)

## Lockdown opens on a board that is fully shuffled but has nothing welded, so
## the scramble runs on a clean meta and the welds are derived after.
func scramble(board: SlideBoard, rng: RandomNumberGenerator, steps: int) -> void:
	board.meta.erase(META_LOCKED)
	super(board, rng, steps)
