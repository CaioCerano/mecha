class_name TestUtil
extends RefCounted

## Shared helpers for the GUT suites. Gives a BattleState with the real
## mission grid + reactor but no units, so each test places exactly what it
## needs.

static func bare_state() -> BattleState:
	var s := BattleState.new()
	s.units.clear()
	s.occupancy.clear()
	s.telegraphs.clear()
	s.pending_spawns.clear()
	s.events.clear()
	# reset the board to reactor-only; terrain tests add pits / barrels explicitly
	s.objects.clear()
	s.objects[s.reactor.pos] = s.reactor
	s._next_id = 1
	return s

static func add(s: BattleState, kind: Unit.Kind, team: Unit.Team, pos: Vector2i) -> Unit:
	return s._spawn_unit(kind, team, pos)
