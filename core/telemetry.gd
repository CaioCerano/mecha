class_name Telemetry
extends RefCounted

## Development-only per-mission counters. NOT a player-facing stats screen and
## NOT analytics infrastructure -- just plain ints so we can tell whether the
## mechanics are actually being used. battle.gd prints summary_text() when the
## mission ends.

var c: Dictionary = {}                 # flat "name" -> int
var mech_actions: Dictionary = {}      # Unit.Kind -> int
var mech_ability: Dictionary = {}      # Unit.Kind -> { action_id -> int }
var mech_dmg_dealt: Dictionary = {}    # Unit.Kind -> int
var mech_dmg_taken: Dictionary = {}    # Unit.Kind -> int
var result: String = "?"
var turns_completed: int = 0
var enemies_alive_at_end: int = 0

func bump(k: String, n: int = 1) -> void:
	c[k] = c.get(k, 0) + n

func _mbump(d: Dictionary, kind: int, n: int) -> void:
	d[kind] = d.get(kind, 0) + n

func note_action(kind: int, action_id: String) -> void:
	_mbump(mech_actions, kind, 1)
	var per: Dictionary = mech_ability.get(kind, {})
	per[action_id] = per.get(action_id, 0) + 1
	mech_ability[kind] = per

## `cause` : "melee" | "pierce" | "collision" | "explosion" | "pit" | "charge" | "aoe"
func note_damage(state: BattleState, target_id: int, amount: int, cause: String, by_id: int) -> void:
	if amount <= 0:
		return
	var tgt: Unit = state.units.get(target_id)
	var src: Unit = state.units.get(by_id)
	if src != null and src.is_player() and tgt != null and not tgt.is_player():
		_mbump(mech_dmg_dealt, src.kind, amount)
		match cause:
			"collision": bump("collision_damage", amount)
			"explosion", "pit": bump("environmental_damage", amount)
			_: bump("direct_damage", amount)
	if tgt != null and tgt.is_player():
		_mbump(mech_dmg_taken, tgt.kind, amount)

func note_death(state: BattleState, unit: Unit, cause: String, by_id: int) -> void:
	if unit.is_player():
		return
	bump("enemies_killed")
	# by cause -- so we can see how many kills came from positioning the board
	# (pit / blast / slam) versus straight damage.
	match cause:
		"pit": bump("pit_deaths")
		"explosion": bump("blast_kills")
		"collision": bump("collision_kills")
	var src: Unit = state.units.get(by_id)
	if src != null and src.kind == Unit.Kind.GRAPPLER:
		bump("grappler_kills")

func finalize(state: BattleState, won: bool) -> void:
	result = "WIN" if won else "DEFEAT"
	turns_completed = state.turn_number
	enemies_alive_at_end = state.living_enemies().size()

# ----------------------------------------------------------------- summary

func summary_text(state: BattleState) -> String:
	var names := {
		Unit.Kind.LANCER: "Lancer", Unit.Kind.BULWARK: "Bulwark", Unit.Kind.GRAPPLER: "Grappler",
	}
	var lines: Array[String] = []
	lines.append("")
	lines.append("================  MISSION SUMMARY  ================")
	lines.append("Result: %s   Turns: %d   Reactor: %d/%d   Enemies left: %d" % [
		result, turns_completed, maxi(state.reactor.hp, 0), state.reactor.max_hp, enemies_alive_at_end])
	var kills: int = c.get("enemies_killed", 0)
	var pit: int = c.get("pit_deaths", 0)
	var blast: int = c.get("blast_kills", 0)
	var slam: int = c.get("collision_kills", 0)
	lines.append("Enemies killed: %d   (direct %d · pit %d · blast %d · slam %d)" % [
		kills, maxi(kills - pit - blast - slam, 0), pit, blast, slam])
	for kind: int in [Unit.Kind.LANCER, Unit.Kind.BULWARK, Unit.Kind.GRAPPLER]:
		lines.append("")
		lines.append("%s" % names[kind])
		lines.append("  Actions: %d   Damage dealt: %d   Damage taken: %d" % [
			mech_actions.get(kind, 0), mech_dmg_dealt.get(kind, 0), mech_dmg_taken.get(kind, 0)])
		var per: Dictionary = mech_ability.get(kind, {})
		if not per.is_empty():
			var parts: Array[String] = []
			for a: String in per:
				parts.append("%s x%d" % [a, per[a]])
			lines.append("  Uses: " + ", ".join(parts))
	lines.append("")
	lines.append("Manipulation")
	lines.append("  Enemies displaced: %d   Allies repositioned: %d" % [
		c.get("enemies_displaced", 0), c.get("allies_repositioned", 0)])
	lines.append("  Intents interrupted: %d   redirected: %d" % [
		c.get("intents_interrupted", 0), c.get("intents_redirected", 0)])
	lines.append("  Pit kills: %d   Charges blocked: %d   Shields deployed: %d" % [
		c.get("pit_deaths", 0), c.get("charges_blocked", 0),
		mech_ability.get(Unit.Kind.BULWARK, {}).get("deploy_shield", 0)])
	lines.append("")
	lines.append("Damage breakdown (player-dealt)")
	lines.append("  Direct: %d   Collision: %d   Environmental: %d" % [
		c.get("direct_damage", 0), c.get("collision_damage", 0), c.get("environmental_damage", 0)])
	lines.append("Environment")
	lines.append("  Barrels triggered: %d   Explosions: %d   Reactor damage taken: %d" % [
		c.get("barrels_triggered", 0), c.get("explosions", 0), c.get("reactor_damage_taken", 0)])
	lines.append("=================================================")
	return "\n".join(lines)
