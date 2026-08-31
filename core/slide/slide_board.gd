class_name SlideBoard
extends RefCounted
## SlideBoard: a grid of numbered tiles and the holes they slide into.
##
## Pure data with no rules in it. Rule plug-ins mutate it through `slide`,
## `rotate_block` and `swap`; the view animates by VALUE, never by re-scanning
## cells, because a tile keeps its number for the whole run and that number is
## the only stable identity a slide puzzle has.
##
## A cell holds a tile's value, or BLANK for a hole. `goal[i]` is the value that
## belongs at cell `i`, so "solved" is one array compare and every rule answers
## it the same way. Row-major: the cell at (x, y) is `y * w + x`, y = 0 the top.
##
## ADJACENCY IS HANDED IN, not computed here. A flat tray's neighbours are the
## four orthogonal cells; the torus wraps. The rule builds the table once and
## every clone shares it by reference, so a solver expanding a million nodes
## never rebuilds it.

## The hole. Tiles are 1 and up.
const BLANK := 0

## Largest board the Zobrist table covers (the biggest tray is 5 x 5).
const MAX_CELLS := 32
## One key per (cell, value) pair. Values run to MAX_CELLS, blanks included.
const ZOBRIST_SIZE := MAX_CELLS * (MAX_CELLS + 1)

## Zobrist keys, filled once when the class loads so every thread reads one
## immutable table.
static var _zobrist: PackedInt64Array = PackedInt64Array()

var w: int = 4
var h: int = 4
## Row-major tile values; BLANK for a hole.
var cells: PackedInt32Array = PackedInt32Array()
## The value that belongs at each cell. Solved is `cells == goal`.
var goal: PackedInt32Array = PackedInt32Array()
## Slides made so far. The score on every mode that counts moves.
var moves: int = 0
## Rule-owned extras that travel with the board: Lockdown keeps "locked" (an
## Array of cells that may never move again). Cloned deep, saved and loaded
## with the board, and part of hash_key().
var meta: Dictionary = {}

## Neighbours per cell, shared by reference between clones. Built by the rule
## through `set_adjacency`; an empty table falls back to the flat grid.
var _adj: Array[PackedInt32Array] = []
## Where each value currently sits, so `find` is O(1) on the solver's hot path.
var _at: PackedInt32Array = PackedInt32Array()
## Where each value belongs, from `goal`. Built with the goal.
var _home: PackedInt32Array = PackedInt32Array()
## This board shape's key into the shared hop-distance cache. See _make_shape_key.
var _shape_id: String = "1:1"

static func _static_init() -> void:
	_zobrist = _make_zobrist()

static func _make_zobrist() -> PackedInt64Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x51DE0B0A
	var out := PackedInt64Array()
	out.resize(ZOBRIST_SIZE)
	for i in ZOBRIST_SIZE:
		var hi: int = int(rng.randi())
		var lo: int = int(rng.randi())
		out[i] = (hi << 32) ^ lo
	return out

## One Zobrist key by slot. Slots wrap so a stray index never reads out of range.
static func zkey(slot: int) -> int:
	if _zobrist.is_empty():
		_zobrist = _make_zobrist()
	return _zobrist[posmod(slot, ZOBRIST_SIZE)]

func _init(p_w: int = 4, p_h: int = 4) -> void:
	w = maxi(1, p_w)
	h = maxi(1, p_h)
	var n := w * h
	cells = PackedInt32Array()
	cells.resize(n)
	goal = PackedInt32Array()
	goal.resize(n)
	# With no adjacency yet the key is just the shape, which is exactly right:
	# `neighbours` falls back to the flat grid until a rule hands one in.
	_shape_id = _make_shape_key()
	solve()

# --- Geometry -------------------------------------------------------------------

func size() -> int:
	return cells.size()

func index(x: int, y: int) -> int:
	return y * w + x

func xy(i: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(i % w, i / w)

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h

# --- Reads ----------------------------------------------------------------------

func at(i: int) -> int:
	if i < 0 or i >= cells.size():
		return BLANK
	return cells[i]

func is_blank(i: int) -> bool:
	return i >= 0 and i < cells.size() and cells[i] == BLANK

## Where `value` currently sits, or -1 when it is not on the board.
func find(value: int) -> int:
	if value <= 0 or value >= _at.size():
		return -1
	return _at[value]

## Where `value` belongs, or -1 when nothing claims it.
func home_of(value: int) -> int:
	if value <= 0 or value >= _home.size():
		return -1
	return _home[value]

## True when the tile at `i` is already where it belongs. A blank counts.
func is_home(i: int) -> bool:
	return i >= 0 and i < cells.size() and cells[i] == goal[i]

## Every hole on the board, in cell order.
func blanks() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in cells.size():
		if cells[i] == BLANK:
			out.append(i)
	return out

## The first hole, or -1. The flat modes keep exactly one.
func blank() -> int:
	for i in cells.size():
		if cells[i] == BLANK:
			return i
	return -1

func is_solved() -> bool:
	return cells == goal

## How many tiles are already home. Drives the progress ring.
func placed() -> int:
	var n := 0
	for i in cells.size():
		if cells[i] != BLANK and cells[i] == goal[i]:
			n += 1
	return n

## Tiles that are not blanks. The denominator of the progress ring.
func tile_count() -> int:
	var n := 0
	for i in goal.size():
		if goal[i] != BLANK:
			n += 1
	return n

# --- Adjacency ------------------------------------------------------------------

## Hands the board its neighbour table. The rule owns the topology; clones
## share the table by reference, so a search never rebuilds it.
func set_adjacency(table: Array[PackedInt32Array]) -> void:
	_adj = table
	_shape_id = _make_shape_key()

## The cells a tile at `i` could slide into if they were empty.
func neighbours(i: int) -> PackedInt32Array:
	if i < 0 or i >= cells.size():
		return PackedInt32Array()
	if not _adj.is_empty():
		return _adj[i]
	return _flat_neighbours(i)

## The four orthogonal cells of a flat grid, clipped at the edges.
func _flat_neighbours(i: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var p := xy(i)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var q: Vector2i = p + d
		if in_bounds(q.x, q.y):
			out.append(index(q.x, q.y))
	return out

## The flat four-neighbour table, for the rules that use a plain tray.
func build_flat_adjacency() -> Array[PackedInt32Array]:
	var table: Array[PackedInt32Array] = []
	for i in cells.size():
		table.append(_flat_neighbours(i))
	return table

## The wrapping four-neighbour table: the left edge touches the right, the top
## the bottom.
func build_torus_adjacency() -> Array[PackedInt32Array]:
	var table: Array[PackedInt32Array] = []
	for i in cells.size():
		var out := PackedInt32Array()
		var p := xy(i)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			out.append(index(posmod(p.x + d.x, w), posmod(p.y + d.y, h)))
		table.append(out)
	return table

# --- Writes ---------------------------------------------------------------------

## Resets to the solved arrangement: 1 .. n-1 across the board, the last cell
## left blank. Rules with another goal call `set_goal` after.
func solve() -> void:
	var n := cells.size()
	for i in n:
		if i == n - 1:
			goal[i] = BLANK
		else:
			goal[i] = i + 1
	cells = goal.duplicate()
	moves = 0
	_reindex()

## Replaces the goal and resets the board to it.
func set_goal(g: PackedInt32Array) -> void:
	goal = g.duplicate()
	cells = goal.duplicate()
	moves = 0
	_reindex()

## Rebuilds the value lookups after any write that is not a slide.
func _reindex() -> void:
	var top := 0
	for i in cells.size():
		top = maxi(top, cells[i])
	for i in goal.size():
		top = maxi(top, goal[i])
	_at = PackedInt32Array()
	_at.resize(top + 1)
	_home = PackedInt32Array()
	_home.resize(top + 1)
	for i in _at.size():
		_at[i] = -1
		_home[i] = -1
	for i in cells.size():
		if cells[i] != BLANK:
			_at[cells[i]] = i
	for i in goal.size():
		if goal[i] != BLANK:
			_home[goal[i]] = i

## Moves the tile at `from` into the blank at `to`. False when `from` holds no
## tile, `to` is not a hole, or the two are not neighbours. Does NOT count the
## move; the rule decides what one move is.
func slide(from: int, to: int) -> bool:
	if from < 0 or to < 0 or from >= cells.size() or to >= cells.size():
		return false
	if cells[from] == BLANK or cells[to] != BLANK:
		return false
	if not neighbours(from).has(to):
		return false
	_place(to, cells[from])
	_place(from, BLANK)
	return true

## Swaps two cells outright, neighbours or not. The scrambler and the torus
## rotation use it; ordinary play never does.
func swap(a: int, b: int) -> void:
	if a < 0 or b < 0 or a >= cells.size() or b >= cells.size() or a == b:
		return
	var va := cells[a]
	var vb := cells[b]
	_place(a, vb)
	_place(b, va)

## Writes a value and keeps the value lookup in step.
##
## The guard on the old value matters more than it looks. A slide is two writes
## (the tile into the hole, then the hole into the cell it left), and the second
## one sees the SAME value still sitting in `cells[from]`. Clearing its lookup
## unconditionally there would erase the entry the first write had just made,
## and every tile would report itself as nowhere the moment it moved. So the
## entry is only cleared when it still points at this cell.
func _place(i: int, value: int) -> void:
	var old := cells[i]
	if old != BLANK and old < _at.size() and _at[old] == i:
		_at[old] = -1
	cells[i] = value
	if value != BLANK and value < _at.size():
		_at[value] = i

## Junctions on this tray: the interior corners where four cells meet. A twist
## board is played on these rather than on the cells.
func pivot_count() -> int:
	return maxi(0, (w - 1) * (h - 1))

## The four cells around junction `pivot`, clockwise from the top left.
func pivot_cells(pivot: int) -> PackedInt32Array:
	var pw := w - 1
	if pw <= 0 or pivot < 0 or pivot >= pivot_count():
		return PackedInt32Array()
	@warning_ignore("integer_division")
	var pr := pivot / pw
	var pc := pivot % pw
	return PackedInt32Array([
		index(pc, pr), index(pc + 1, pr), index(pc + 1, pr + 1), index(pc, pr + 1)])

## Turns the four cells around `pivot` a quarter turn. Returns the (from, to)
## pairs so the view can animate the pinwheel; empty when the pivot is not one.
func rotate_block(pivot: int, cw: bool = true) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var ring := pivot_cells(pivot)
	if ring.size() < 4:
		return out
	var was := PackedInt32Array()
	for c in ring:
		was.append(cells[c])
	for k in 4:
		# Clockwise, the cell at k moves to k + 1 round the ring.
		var dst: int = ring[posmod(k + (1 if cw else -1), 4)]
		_place(dst, was[k])
		out.append(Vector2i(ring[k], dst))
	return out

# --- Distance -------------------------------------------------------------------

## Sum over every tile of its shortest path to home, in slides. The admissible
## heuristic the solver searches on, and the "how far off am I" readout.
## Uses the adjacency table, so it is correct on the cube and the torus too.
func manhattan() -> int:
	var total := 0
	for i in cells.size():
		var v := cells[i]
		if v == BLANK:
			continue
		var home := home_of(v)
		if home < 0 or home == i:
			continue
		total += hops_between(i, home)
	return total

## Cached breadth-first hop counts between cells, shared between clones. Built
## lazily per board shape; a flat grid could do this with arithmetic, but the
## cube cannot and one path keeps the heuristic honest on both.
static var _hops: Dictionary = {}

func hops_between(a: int, b: int) -> int:
	if a < 0 or b < 0 or a >= cells.size() or b >= cells.size():
		return 0
	var table: Array = _hops.get(_shape_id, [])
	if table.is_empty():
		table = _build_hops()
		_hops[_shape_id] = table
	var row: PackedInt32Array = table[a]
	return row[b]

## The cache key for this board's SHAPE, built ONCE when the adjacency lands and
## carried on the board after that.
##
## It has to include the adjacency itself and not just its size: a flat 3x3 and a
## torus 3x3 are both nine cells with nine neighbour lists, so a key built from
## the dimensions alone collided and the torus read the flat board's hop table.
## Every distance on Wrap came back wrong and the solver searched on a heuristic
## that did not describe the board it was solving.
##
## And it is CACHED because `hops_between` sits on the solver's hot path: a
## million-node search asks for a distance millions of times, and rebuilding a
## two-hundred-character key out of the neighbour table on each one costs more
## than the entire search.
func _make_shape_key() -> String:
	var k := "%d:%d" % [w, h]
	for row in _adj:
		k += "|"
		for nb in row:
			k += str(nb) + ","
	return k

func _build_hops() -> Array:
	var n := cells.size()
	var out: Array = []
	for src in n:
		var dist := PackedInt32Array()
		dist.resize(n)
		for i in n:
			dist[i] = -1
		dist[src] = 0
		var queue := PackedInt32Array([src])
		var head := 0
		while head < queue.size():
			var cur := queue[head]
			head += 1
			for nb in neighbours(cur):
				if dist[nb] < 0:
					dist[nb] = dist[cur] + 1
					queue.append(nb)
		for i in n:
			if dist[i] < 0:
				dist[i] = n
		out.append(dist)
	return out

# --- Solvability ----------------------------------------------------------------

## True when this flat arrangement can be slid to its goal. Half of all
## permutations of an N-puzzle cannot, so a scrambler that shuffles blindly
## deals an unsolvable board every other time. Counts inversions against the
## GOAL order and pairs them with the blank's row, the standard test.
## Meaningless off a single-blank grid; those rules never ask.
func is_solvable() -> bool:
	var order := PackedInt32Array()
	for i in goal.size():
		if goal[i] != BLANK:
			order.append(goal[i])
	var rank := {}
	for k in order.size():
		rank[order[k]] = k
	var seq := PackedInt32Array()
	var blank_row := 0
	for i in cells.size():
		if cells[i] == BLANK:
			blank_row = xy(i).y
			continue
		seq.append(int(rank.get(cells[i], 0)))
	var inversions := 0
	for i in seq.size():
		for j in range(i + 1, seq.size()):
			if seq[i] > seq[j]:
				inversions += 1
	if w % 2 == 1:
		return inversions % 2 == 0
	# Even width: the blank's row counted from the BOTTOM flips the parity.
	var from_bottom := h - 1 - blank_row
	return (inversions + from_bottom) % 2 == 0

# --- Copies and keys ------------------------------------------------------------

## A copy that shares what a search never writes to.
##
## `goal` and `_home` are shared rather than copied: a search never writes to
## either, so a clone per expanded node was paying for two array copies it could
## not use. `cells` and `_at` ARE written by every slide, so they are copied.
func clone() -> SlideBoard:
	var b := SlideBoard.new(w, h)
	b.cells = cells.duplicate()
	b.goal = goal
	b.moves = moves
	b._at = _at.duplicate()
	b._home = _home
	b._adj = _adj
	b._shape_id = _shape_id
	if not meta.is_empty():
		b.meta = meta.duplicate(true)
	return b

func to_dict() -> Dictionary:
	return {
		"w": w, "h": h,
		"cells": Array(cells), "goal": Array(goal),
		"moves": moves, "meta": meta.duplicate(true),
	}

static func from_dict(d: Dictionary) -> SlideBoard:
	var pw: int = int(d.get("w", 4))
	var ph: int = int(d.get("h", 4))
	var b := SlideBoard.new(pw, ph)
	var raw_goal: Array = d.get("goal", [])
	if not raw_goal.is_empty():
		var g := PackedInt32Array()
		g.resize(b.goal.size())
		for i in mini(raw_goal.size(), g.size()):
			g[i] = int(raw_goal[i])
		b.goal = g
	var raw_cells: Array = d.get("cells", [])
	for i in mini(raw_cells.size(), b.cells.size()):
		b.cells[i] = int(raw_cells[i])
	b.moves = int(d.get("moves", 0))
	var raw_meta: Dictionary = d.get("meta", {})
	b.meta = _normalise(raw_meta)
	b._reindex()
	return b

## A deep copy of a meta value with what JSON did to it undone: numeric string
## keys become ints again and whole-number floats become ints, at every depth,
## so a loaded table still answers cell lookups.
static func _normalise(v: Variant) -> Variant:
	if v is Dictionary:
		var out := {}
		var d: Dictionary = v
		for key in d:
			var k: Variant = key
			if k is String and (k as String).is_valid_int():
				k = int(k)
			out[k] = _normalise(d[key])
		return out
	if v is Array:
		var arr: Array = []
		var list: Array = v
		for item in list:
			arr.append(_normalise(item))
		return arr
	if v is float and is_equal_approx(v, floor(v)):
		return int(v)
	return v

## Zobrist hash over the arrangement. Equal boards hash equal, so the value is
## stable across clones and dictionary round trips.
func hash_key() -> int:
	var n := cells.size()
	var k: int = 0
	if n <= MAX_CELLS:
		for i in n:
			k ^= zkey(i * (MAX_CELLS + 1) + mini(cells[i], MAX_CELLS))
	else:
		for i in n:
			k = k * 1000003 + cells[i]
	return k

## Debug text: one row per line, the blank as a dot.
func _to_string() -> String:
	var out := ""
	for y in h:
		var row := ""
		for x in w:
			var v := cells[index(x, y)]
			row += "  ." if v == BLANK else "%3d" % v
		out += row + "\n"
	return out.strip_edges()
