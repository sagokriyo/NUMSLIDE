class_name SlideSolver
extends RefCounted
## SlideSolver: the thing that knows the way out.
##
## It answers two questions. `hint` returns the ONE tile the player should tap
## next, which is what the helpline spends a coin on. `solve` returns a whole
## path, which is what the auto-solve and the tests use.
##
## THREE STRATEGIES, CHEAPEST FIRST, and every one of them is capped. A hint
## that thinks for four seconds has already failed, so nothing here is allowed
## to run unbounded and the last strategy always answers:
##
##   1. IDA* on Manhattan + linear conflict. Optimal, and instant on a 3x3 or
##      on any board that is nearly finished. Given a node budget it either
##      returns the optimal path or gives up quickly.
##   2. A* toward the LIVE GROUP: the next few cells a human would place, with
##      everything already finished frozen so the search cannot undo it. This is
##      how a person solves a 4x4 or a 5x5, and it stays cheap at any size
##      because it only ever solves a corner of the problem.
##   3. Greedy: the legal move that most reduces total distance. Never fails,
##      never brilliant, and only ever reached on a board the first two could
##      not crack.
##
## Pure: no nodes, no autoloads. Safe on a worker thread.

## Nodes IDA* may expand before it admits the board is too far off.
const IDA_BUDGET := 40_000
## Nodes the group search may expand. Every node here CLONES a board, which is
## the expensive part in GDScript, so the budget is small and the heuristic is
## made strong enough not to need a big one.
const ASTAR_BUDGET := 20_000
## Board distance above which IDA* is not even attempted.
##
## TWELVE, NOT TWENTY-FOUR, and the difference is a minute and a half. Optimal
## search on a sliding puzzle grows explosively with distance: at twelve a 4x4
## comes back instantly, and at twenty-four the same board is millions of nodes.
## The old ceiling did not stop the solve, it just meant that every time the
## group search brought the board inside twenty-four, IDA* took over and spent
## its whole budget proving an optimal line nobody had asked for. The group
## search is what carries a board from a fresh scramble down to here; IDA* only
## has to close out the end, where being optimal is cheap and actually matters.
const IDA_MAX_DISTANCE := 12
## Steps a full auto-solve may take before it gives up on a board.
const SOLVE_MAX_STEPS := 1500
## Greedy steps in a row that fail to bring the board any closer before the
## solve is abandoned. Greedy is the strategy of last resort, and a greedy move
## that does not reduce the distance is the search saying it cannot see the way
## home; letting it wander to the step cap costs seconds and finds nothing.
const STALL_LIMIT := 24

# --- Public -------------------------------------------------------------------

## The move to play next, or {} when the board is finished or nothing is legal.
static func hint(board: SlideBoard, rules: SlideRules) -> Dictionary:
	if bool(rules.outcome(board)["solved"]):
		return {}
	if rules.rule_id() == "twist":
		var turns := _twist_search(board, rules, 1)
		return turns[0] if not turns.is_empty() else _greedy(board, rules)
	var path := _ida(board, rules, 1)
	if not path.is_empty():
		return path[0]
	path = _toward_group(board, rules, 1)
	if not path.is_empty():
		return path[0]
	return _greedy(board, rules)

## A whole solution, as moves. Empty when the board defeats every strategy.
## Chains the group search when one search cannot see the end, which is how a
## 5x5 gets solved at all.
##
## A FAILED SEARCH IS LATCHED OFF. The group search is the expensive one, and
## when it cannot place a group it will not be able to place it next time round
## either, because nothing structural has changed. Retrying it every step turned
## an unsolvable board into a twenty-thousand-node search repeated a thousand
## times. It is re-armed only when a group actually goes in, which is the one
## event that gives it a new problem to work on. IDA* is not latched: its own
## first check is the board's distance, so retrying it costs one pass over the
## cells and it becomes viable on its own as the board comes together.
static func solve(board: SlideBoard, rules: SlideRules) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var work := board.clone()
	var group_ok := true
	var closest := _distance(work)
	var stalled := 0
	var guard := 0
	while not work.is_solved() and guard < SOLVE_MAX_STEPS:
		guard += 1
		var from_group := false
		var step: Array[Dictionary] = _twist_search(work, rules, 0) \
			if rules.rule_id() == "twist" else _ida(work, rules, 0)
		if step.is_empty() and group_ok:
			step = _toward_group(work, rules, 0)
			if step.is_empty():
				group_ok = false
			else:
				from_group = true
		if step.is_empty():
			var one := _greedy(work, rules)
			if one.is_empty():
				return []
			step = [one]
		for m in step:
			var events := rules.apply(work, m)
			if events.is_empty():
				return []
			out.append(m)
			guard += 1
			# A RULE MAY NOT LEAVE THE BOARD SOLVED. Rush re-deals the instant a
			# board comes out, so `work.is_solved()` is false again by the time
			# the loop tests it and the search would grind on for ever against a
			# fresh scramble it was never asked to solve. The events are the
			# truth about what happened, so the path ends where the rule says
			# the board came home.
			for e_v in events:
				var kind := String((e_v as Dictionary).get("type", ""))
				if kind == "solved" or kind == "cleared":
					return out
		if from_group:
			group_ok = true
		var now := _distance(work)
		if now < closest:
			closest = now
			stalled = 0
		else:
			stalled += 1
			if stalled > STALL_LIMIT:
				return []
	return out if work.is_solved() else []

# --- Strategy 1: IDA* -----------------------------------------------------------

## Iterative deepening A* on the whole board. `want` caps the path returned
## (1 for a hint, 0 for all of it). Empty when the board is out of reach.
static func _ida(board: SlideBoard, rules: SlideRules, want: int) -> Array[Dictionary]:
	# The torus has no hole to walk and its move set displaces a whole line, so
	# the distance heuristic does not bound it and IDA* would search forever.
	if rules.rule_id() == "twist":
		return []
	var start := _distance(board)
	if start == 0 or start > IDA_MAX_DISTANCE:
		return []
	var bound := start
	var budget := IDA_BUDGET
	while budget > 0:
		var path: Array[Dictionary] = []
		var found := _ida_step(board.clone(), rules, 0, bound, path, [budget], -1)
		if found == 0:
			return path.slice(0, want) if want > 0 else path
		if found < 0 or found > IDA_MAX_DISTANCE * 2:
			return []
		bound = found
	return []

## Returns 0 on success (path filled), otherwise the smallest f that exceeded
## the bound, or -1 when the budget ran out.
static func _ida_step(board: SlideBoard, rules: SlideRules, g: int, bound: int,
		path: Array[Dictionary], budget: Array, came_from: int) -> int:
	var h := _distance(board)
	var f := g + h
	if f > bound:
		return f
	if h == 0:
		return 0
	budget[0] -= 1
	if budget[0] <= 0:
		return -1
	var best := -1
	for m in rules.unit_moves(board):
		var cell: int = int(m["cell"])
		# Never slide the tile straight back where it came from.
		if cell == came_from:
			continue
		var next := board.clone()
		if rules.apply(next, m).is_empty():
			continue
		# The cell this tile vacated is where the next move would undo it.
		var vacated := cell
		path.append(m)
		var got := _ida_step(next, rules, g + 1, bound, path, budget, vacated)
		if got == 0:
			return 0
		path.pop_back()
		if got < 0:
			return -1
		if best < 0 or got < best:
			best = got
	return best if best >= 0 else bound + 1

# --- Strategy 2: A* toward the live group ----------------------------------------

## Places the next group a human would place, with everything finished frozen.
static func _toward_group(board: SlideBoard, rules: SlideRules, want: int) -> Array[Dictionary]:
	if rules.rule_id() == "twist":
		return []
	var groups := RulesLock.lock_groups(board.w, board.h)
	var frozen := {}
	var target := PackedInt32Array()
	for g in groups:
		var all_home := true
		for c in g:
			if not board.is_home(c):
				all_home = false
				break
		if all_home:
			for c in g:
				frozen[c] = true
			continue
		target = g
		break
	if target.is_empty():
		return []
	var path := _astar(board, rules, target, frozen)
	if path.is_empty():
		return []
	return path.slice(0, want) if want > 0 else path

## A* whose goal is "every cell of `target` holds its own tile", never moving a
## tile out of `frozen`.
static func _astar(board: SlideBoard, rules: SlideRules, target: PackedInt32Array,
		frozen: Dictionary) -> Array[Dictionary]:
	var start_key := board.hash_key()
	var open := _Heap.new()
	var came := {}          # key -> [parent_key, move]
	var cost := {start_key: 0}
	var states := {start_key: board.clone()}
	open.push(_group_distance(board, target), start_key)
	var expanded := 0

	while not open.is_empty() and expanded < ASTAR_BUDGET:
		var key: int = open.pop()
		var here: SlideBoard = states.get(key, null)
		if here == null:
			continue
		if _group_done(here, target):
			return _rebuild(came, key)
		expanded += 1
		var g_here: int = int(cost[key])
		for m in rules.unit_moves(here):
			var cell: int = int(m["cell"])
			if frozen.has(cell):
				continue
			var next := here.clone()
			if rules.apply(next, m).is_empty():
				continue
			var nkey := next.hash_key()
			var ng := g_here + 1
			if cost.has(nkey) and int(cost[nkey]) <= ng:
				continue
			cost[nkey] = ng
			came[nkey] = [key, m]
			states[nkey] = next
			open.push(ng + _group_distance(next, target), nkey)
	return []

static func _group_done(board: SlideBoard, target: PackedInt32Array) -> bool:
	for c in target:
		if not board.is_home(c):
			return false
	return true

## How far the group's own tiles are from their cells. Drives A* straight at the
## corner of the board that matters and ignores the rest.
##
## THE HOLE IS THE TIE-BREAK. Group distance alone is flat across every move
## that only walks the hole about, which is most of them, and on that plateau A*
## degenerates into breadth-first search and burns its whole budget going
## nowhere. Weighting the group's own distance and adding the hole's walk to the
## nearest tile still to place gives the plateau a slope. It is no longer an
## admissible heuristic and the path it finds is not the shortest one; that is
## the deliberate trade, because this search exists to bring a board home
## quickly for the auto-solve and the hint, and IDA* above is what answers when
## an optimal line is actually wanted.
const GROUP_WEIGHT := 3

static func _group_distance(board: SlideBoard, target: PackedInt32Array) -> int:
	var total := 0
	var nearest := -1
	for c in target:
		var want: int = board.goal[c]
		if want == SlideBoard.BLANK:
			continue
		var here := board.find(want)
		if here < 0 or here == c:
			continue
		total += board.hops_between(here, c)
		if nearest < 0:
			nearest = here
	if total <= 0:
		return 0
	var hole := board.blank()
	var walk: int = board.hops_between(hole, nearest) if hole >= 0 and nearest >= 0 else 0
	return total * GROUP_WEIGHT + walk

static func _rebuild(came: Dictionary, key: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cur: int = key
	while came.has(cur):
		var link: Array = came[cur]
		out.push_front(link[1])
		cur = int(link[0])
	return out

# --- The torus: breadth first over rotations --------------------------------------

## Nodes the torus search may visit. A rotation move set is small (two ways
## round every row and every column) but it BRANCHES wide: a 3x3 offers twelve
## moves, so a level costs twelve times the last one and the whole budget is
## spent somewhere in the fourth. That is the right place to stop. A board three
## rolls from home is found in a moment, and one fifteen rolls out is not going
## to be found at any budget worth waiting for, so the search gives up quickly
## and the greedy fallback answers instead of burning forty seconds first.
const TWIST_BUDGET := 6_000

## The way home on a tray with no hole in it.
##
## NEITHER OF THE OTHER TWO STRATEGIES WORKS HERE, and not for want of tuning.
## IDA* searches on tile distance, and on a torus one rotation moves every tile
## in a line at once, so the distance is not a bound on the moves left and the
## search has nothing to prune with. The group search is worse: it freezes cells
## it has finished, and there is no move on this board that leaves a cell alone.
## What IS true of a torus is that every move is reversible and the move set is
## small, so plain breadth-first search finds the shortest line and finds it
## fast, as long as the board is genuinely near home. Past that it gives up and
## the greedy fallback answers, which is the honest outcome: a torus fifteen
## rolls from home has no short answer to give.
static func _twist_search(board: SlideBoard, rules: SlideRules, want: int) -> Array[Dictionary]:
	if bool(rules.outcome(board)["solved"]):
		return []
	var seen := {board.hash_key(): true}
	# Each entry is [board, path so far].
	var queue: Array = [[board.clone(), [] as Array[Dictionary]]]
	var head := 0
	var visited := 0
	while head < queue.size() and visited < TWIST_BUDGET:
		var node: Array = queue[head]
		head += 1
		visited += 1
		var here: SlideBoard = node[0]
		var path: Array[Dictionary] = node[1]
		for m in rules.legal_moves(here):
			var next := here.clone()
			if rules.apply(next, m).is_empty():
				continue
			var key := next.hash_key()
			if seen.has(key):
				continue
			seen[key] = true
			var grown: Array[Dictionary] = path.duplicate()
			grown.append(m)
			if bool(rules.outcome(next)["solved"]):
				return grown.slice(0, want) if want > 0 else grown
			queue.append([next, grown])
	return []

# --- Strategy 3: greedy ----------------------------------------------------------

## The legal move that leaves the board closest to done. Always answers when
## anything at all is legal.
static func _greedy(board: SlideBoard, rules: SlideRules) -> Dictionary:
	var options := rules.unit_moves(board)
	if options.is_empty():
		options = rules.legal_moves(board)
	var best := {}
	var best_score := 1 << 30
	for m in options:
		var next := board.clone()
		if rules.apply(next, m).is_empty():
			continue
		var score := _distance(next)
		if score < best_score:
			best_score = score
			best = m
	return best

# --- Distance --------------------------------------------------------------------

## Manhattan plus linear conflict: two tiles in their own goal row, both needing
## to pass through each other to get home, cost two extra slides that plain
## Manhattan cannot see. Still admissible, and it roughly halves the search.
static func _distance(board: SlideBoard) -> int:
	return board.manhattan() + 2 * _conflicts(board)

static func _conflicts(board: SlideBoard) -> int:
	var total := 0
	for y in board.h:
		total += _conflicts_in_line(board, y, true)
	for x in board.w:
		total += _conflicts_in_line(board, x, false)
	return total

static func _conflicts_in_line(board: SlideBoard, line: int, is_row: bool) -> int:
	var length: int = board.w if is_row else board.h
	var vals := PackedInt32Array()
	var targets := PackedInt32Array()
	for k in length:
		var i: int = board.index(k, line) if is_row else board.index(line, k)
		var v := board.at(i)
		if v == SlideBoard.BLANK:
			continue
		var home := board.home_of(v)
		if home < 0:
			continue
		var hp := board.xy(home)
		# Only tiles whose home is in THIS line can conflict inside it.
		if is_row and hp.y != line:
			continue
		if not is_row and hp.x != line:
			continue
		vals.append(v)
		targets.append(hp.x if is_row else hp.y)
	var count := 0
	for a in vals.size():
		for b in range(a + 1, vals.size()):
			if targets[a] > targets[b]:
				count += 1
	return count

# --- A tiny binary heap ------------------------------------------------------------

## GDScript has no priority queue and a sorted-insert open list turns A* into an
## O(n^2) crawl on exactly the boards that need it most.
class _Heap extends RefCounted:
	var _pri: PackedInt32Array = PackedInt32Array()
	var _val: PackedInt64Array = PackedInt64Array()

	func is_empty() -> bool:
		return _pri.is_empty()

	func push(priority: int, value: int) -> void:
		_pri.append(priority)
		_val.append(value)
		var i := _pri.size() - 1
		while i > 0:
			@warning_ignore("integer_division")
			var parent := (i - 1) / 2
			if _pri[parent] <= _pri[i]:
				break
			_swap(parent, i)
			i = parent

	func pop() -> int:
		var top := _val[0]
		var last := _pri.size() - 1
		_swap(0, last)
		_pri.resize(last)
		_val.resize(last)
		var i := 0
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var small := i
			if l < _pri.size() and _pri[l] < _pri[small]:
				small = l
			if r < _pri.size() and _pri[r] < _pri[small]:
				small = r
			if small == i:
				break
			_swap(small, i)
			i = small
		return top

	func _swap(a: int, b: int) -> void:
		var p := _pri[a]
		_pri[a] = _pri[b]
		_pri[b] = p
		var v := _val[a]
		_val[a] = _val[b]
		_val[b] = v
