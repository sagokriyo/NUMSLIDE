class_name RulesClassic
extends SlideRules
## Classic: the pure sliding puzzle. Tap a tile in the hole's row or column and
## the whole run between them shifts one step. Order 1 to n and you are done.
##
## The base class already plays it. This subclass exists so the rule has a name
## of its own and Classic is never "whatever SlideRules happens to do", which is
## how a base class quietly becomes a mode.

func rule_id() -> String:
	return "classic"
