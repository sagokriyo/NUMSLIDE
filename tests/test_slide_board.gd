extends "res://regression/headless/harness/script_test_base.gd"
## SlideBoard: the grid, the holes, the goal, the distances and the round trip.
## Pure data, no rules in it, so everything here is arithmetic that either holds
## or does not.

func run_tests() -> void:
	_test_shape_and_goal()
	_test_slide_and_swap()
	_test_adjacency_tables()
	_test_rotate_block()
	_test_distance()
	_test_solvability()
	_test_round_trip()

func _test_shape_and_goal() -> void:
	print("test_shape_and_goal:")
	var b := SlideBoard.new(4, 4)
	check_eq("sixteen cells", b.size(), 16)
	check_eq("fifteen tiles", b.tile_count(), 15)
	check("a fresh board is solved", b.is_solved())
	check_eq("every tile is home", b.placed(), 15)
	check_eq("tile 1 opens top left", b.at(0), 1)
	check_eq("tile 15 sits before the hole", b.at(14), 15)
	check_eq("the hole is the last cell", b.at(15), SlideBoard.BLANK)
	check_eq("and blank() finds it", b.blank(), 15)
	check_eq("there is exactly one hole", b.blanks().size(), 1)
	check_eq("a value knows where it is", b.find(7), 6)
	check_eq("and where it belongs", b.home_of(7), 6)
	check_eq("an absent value is nowhere", b.find(99), -1)
	check_eq("index round trips", b.index(2, 3), 14)
	check_eq("xy round trips", b.xy(14), Vector2i(2, 3))
	# A non-square tray: the rows count, not the columns.
	var wide := SlideBoard.new(5, 3)
	check_eq("a 5 wide 3 tall tray has fifteen cells", wide.size(), 15)
	check_eq("and fourteen tiles", wide.tile_count(), 14)
	check_eq("its hole is still the last cell", wide.blank(), 14)

func _test_slide_and_swap() -> void:
	print("test_slide_and_swap:")
	var b := SlideBoard.new(3, 3)
	b.set_adjacency(b.build_flat_adjacency())
	check("tile 8 slides into the hole beside it", b.slide(7, 8))
	check_eq("it landed there", b.at(8), 8)
	check_eq("and left a hole behind", b.at(7), SlideBoard.BLANK)
	check_eq("the value lookup followed it", b.find(8), 8)
	check("the board is no longer solved", not b.is_solved())
	check_eq("seven tiles are still home", b.placed(), 7)
	check("a slide into a taken cell is refused", not b.slide(6, 8))
	check("a slide from a hole is refused", not b.slide(7, 0))
	# Non-neighbours never slide, whatever the geometry says they can see.
	check("a slide across the board is refused", not b.slide(0, 7))
	b.swap(0, 8)
	check_eq("swap moves a tile", b.at(0), 8)
	check_eq("and brings the other back", b.at(8), 1)
	check_eq("the lookups followed both", b.find(8), 0)

func _test_adjacency_tables() -> void:
	print("test_adjacency_tables:")
	var flat := SlideBoard.new(3, 3)
	flat.set_adjacency(flat.build_flat_adjacency())
	check_eq("a corner has two neighbours", flat.neighbours(0).size(), 2)
	check_eq("an edge has three", flat.neighbours(1).size(), 3)
	check_eq("the middle has four", flat.neighbours(4).size(), 4)
	check("the corner does not wrap to the far side", not flat.neighbours(0).has(2))

	var torus := SlideBoard.new(3, 3)
	torus.set_adjacency(torus.build_torus_adjacency())
	check_eq("every cell of a torus has four", torus.neighbours(0).size(), 4)
	check("the left edge touches the right", torus.neighbours(0).has(2))
	check("the top touches the bottom", torus.neighbours(0).has(6))

func _test_rotate_block() -> void:
	print("test_rotate_block:")
	var b := SlideBoard.new(3, 3)
	var g := PackedInt32Array([1, 2, 3, 4, 5, 6, 7, 8, 9])
	b.set_goal(g)
	b.set_adjacency(b.build_flat_adjacency())
	check_eq("a 3x3 has four junctions", b.pivot_count(), 4)
	check_eq("junction 0 rings the top left, clockwise", b.pivot_cells(0),
		PackedInt32Array([0, 1, 4, 3]))
	var pairs := b.rotate_block(0, true)
	check_eq("a turn moves four tiles", pairs.size(), 4)
	check_eq("the top left went right", b.at(1), 1)
	check_eq("the top right went down", b.at(4), 2)
	check_eq("the bottom right went left", b.at(3), 5)
	check_eq("the bottom left went up", b.at(0), 4)
	check("the tiles outside the ring never moved", b.at(2) == 3 and b.at(8) == 9)
	b.rotate_block(0, false)
	check("turning it back restores the board", b.cells == g)
	# Four quarter turns is a whole one, which is why one direction is enough.
	for _i in 4:
		b.rotate_block(3, true)
	check("four turns of a junction come back round", b.cells == g)
	check("a junction off the tray turns nothing", b.rotate_block(99, true).is_empty())

func _test_distance() -> void:
	print("test_distance:")
	var b := SlideBoard.new(3, 3)
	b.set_adjacency(b.build_flat_adjacency())
	check_eq("a solved board is nought away", b.manhattan(), 0)
	b.slide(7, 8)
	check_eq("one slide is one away", b.manhattan(), 1)
	b.slide(4, 7)
	check_eq("two slides is two away", b.manhattan(), 2)
	# The hole is not a tile and does not count toward the distance.
	var far := SlideBoard.new(3, 3)
	far.set_adjacency(far.build_flat_adjacency())
	far.swap(0, 2)
	check_eq("a swapped pair two apart costs four", far.manhattan(), 4)

func _test_solvability() -> void:
	print("test_solvability:")
	# Every position a WALK reaches is solvable, which is the whole reason the
	# scrambler walks. The parity test exists to prove the other half: a board
	# assembled by hand can be unreachable, and half of them are.
	var b := SlideBoard.new(4, 4)
	b.set_adjacency(b.build_flat_adjacency())
	check("a solved board is solvable", b.is_solvable())
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for _i in 200:
		var blank := b.blank()
		var nbs := b.neighbours(blank)
		b.slide(nbs[rng.randi_range(0, nbs.size() - 1)], blank)
	check("a walked board is still solvable", b.is_solvable())
	# The classic unsolvable 15-puzzle: 14 and 15 transposed.
	var bad := SlideBoard.new(4, 4)
	bad.set_adjacency(bad.build_flat_adjacency())
	bad.swap(13, 14)
	check("swapping two tiles breaks the parity", not bad.is_solvable())
	bad.swap(13, 14)
	check("and putting them back mends it", bad.is_solvable())
	# Odd width: the blank's row does not enter into it.
	var odd := SlideBoard.new(3, 3)
	odd.set_adjacency(odd.build_flat_adjacency())
	odd.swap(0, 1)
	check("an odd tray reads parity without the blank row", not odd.is_solvable())

func _test_round_trip() -> void:
	print("test_round_trip:")
	var b := SlideBoard.new(4, 4)
	b.set_adjacency(b.build_flat_adjacency())
	b.slide(14, 15)
	b.slide(10, 14)
	b.moves = 7
	b.meta["locked"] = [0, 1, 2]
	var back := SlideBoard.from_dict(b.to_dict())
	check("cells survive the round trip", back.cells == b.cells)
	check("the goal survives it", back.goal == b.goal)
	check_eq("the move count survives it", back.moves, 7)
	check_eq("meta survives it, keys and all", back.meta["locked"], [0, 1, 2] as Array)
	check_eq("and the value lookup was rebuilt", back.find(11), b.find(11))
	check_eq("equal boards hash equal", back.hash_key(), b.hash_key())
	var moved := b.clone()
	moved.set_adjacency(moved.build_flat_adjacency())
	moved.slide(9, 10)
	check("a different board hashes differently", moved.hash_key() != b.hash_key())
	var twin := b.clone()
	check("a clone is a separate board", twin.cells == b.cells)
	twin.swap(0, 1)
	check("and writing to it leaves the original alone", twin.cells != b.cells)
