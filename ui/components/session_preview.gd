class_name SessionPreview
extends RefCounted
## SessionPreview — the picture of a saved series on Home's Continue card, for
## the boards whose SHAPE is the mode (Ultimate's nine boards, Cube, Orbit).
##
## Every square grid is drawn by Home's own _mini_board from the save's
## "cells"; a mode listed here draws itself instead. Returns null for any mode
## that is a plain grid, which is every launch mode today. Ultimate lands here
## with its board in Phase 2.
##
## Keyed by topology, never by mode id, so a new mode on a known shape needs no
## entry and a new shape cannot be missed: a topology missing from this table
## falls back to the grid drawer and the catalogue test flags it.

const SHAPES := {
	"square": "",        # Home's _mini_board
}

static func build(_mode_id: String, _session: Dictionary) -> Control:
	return null
