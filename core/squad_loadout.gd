class_name SquadLoadout
extends RefCounted

## Session-only selections. IDs are independent of menu labels.
const FRAMES: Array[int] = [Unit.Kind.LANCER, Unit.Kind.BULWARK, Unit.Kind.GRAPPLER]
const SECONDARIES := {
	Unit.Kind.LANCER: ["throw_spear", "impact_spear", "thermal_lance"],
	Unit.Kind.BULWARK: ["deploy_shield", "brace", "repulsor_plate"],
	Unit.Kind.GRAPPLER: ["throw", "anchor_shot", "tow_cable"],
}
const SYSTEMS: Array[String] = ["", "vector_thrusters", "stabilizers", "reinforced_actuators", "shock_absorbers", "emergency_winch", "targeting_suite"]
const PILOTS: Array[String] = ["", "ace", "brawler", "rescuer", "engineer"]
const DESCRIPTIONS := {
	"": "None",
	"thrust": "Melee lunge; damage 2, push 1. Steps in behind the hit.",
	"shield_bash": "Melee; damage 1, push 2. Cheap, reliable displacement.",
	"grapple": "Reel toward an adjacent-line target: enemy, ally, wall or reactor.",
	"throw_spear": "Range 4 / damage 3. Leaves a spear; retrieve free to restore Thrust.",
	"impact_spear": "Cardinal range 3 / damage 1 / push 2 / collision 2. Reusable.",
	"thermal_lance": "Cardinal range 2 / damage 3. Breaks barrels. No push; reusable.",
	"deploy_shield": "Place adjacent blocking shield; retrieve free. Stowing reduces damage by 1.",
	"brace": "1 AP, self. Immune to enemy forced movement until next player phase.",
	"repulsor_plate": "Adjacent enemy / no direct damage / push 3 / collision 2.",
	"throw": "Grab adjacent unit; choose cardinal placement or slam up to 3 cells.",
	"anchor_shot": "Empty cardinal tile, range 3. One anchor per owner, until replaced or mission ends. Walkable; stops forced moves; Grapple anchor.",
	"tow_cable": "Ally in cardinal range 3; choose safe pull of 1-2 cells. No damage.",
	"vector_thrusters": "First normal move each turn has +1 range (consumed even on a short move).",
	"stabilizers": "Incoming forced movement -1 (minimum zero). Willing ally reposition is exempt.",
	"reinforced_actuators": "Thrust, Bash, Impact and Repulsor push +1; Throw/Grapple maximum +1. Precise choices stay precise.",
	"shock_absorbers": "Received collision damage -1, minimum zero, after stowed shield protection.",
	"emergency_winch": "Once per mission, free: choose adjacent ally then a safe adjacent destination.",
	"targeting_suite": "Emphasize known enemy intents intersecting this mech's movement or action reach when selected.",
	"ace": "Move 3 cells this turn: next powered displacement action gains +1 push/max distance. Once per turn.",
	"brawler": "First damaging collision caused each turn: +1 collision damage to the collision's recipients.",
	"rescuer": "First intentional ally reposition each turn refunds 1 AP (capped at 2).",
	"engineer": "Once per mission, free: repair impaired system; otherwise heal to the next damage-state threshold.",
}
var mechs: Dictionary = {}

func _init() -> void:
	for kind: int in FRAMES:
		mechs[kind] = {"secondary_id": SECONDARIES[kind][0], "systems": ["", ""], "pilot_id": ""}

func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	var pilots: Array = []
	if mechs.size() != 3:
		errors.append("Configure exactly the three frames.")
	for kind: int in FRAMES:
		var m: Dictionary = mechs.get(kind, {})
		if m.get("secondary_id", "") not in SECONDARIES[kind]:
			errors.append("Invalid secondary for frame %d." % kind)
		var systems: Array = m.get("systems", [])
		if systems.size() != 2:
			errors.append("Exactly two System slots required.")
		for system: String in systems:
			if system not in SYSTEMS or (system != "" and systems.count(system) > 1):
				errors.append("Invalid or duplicate System.")
		var pilot: String = m.get("pilot_id", "")
		if pilot not in PILOTS or (pilot != "" and pilot in pilots):
			errors.append("Invalid or duplicate Pilot.")
		pilots.append(pilot)
	return errors

func copy() -> SquadLoadout:
	var result := SquadLoadout.new()
	result.mechs = mechs.duplicate(true)
	return result

static func label(id: String) -> String:
	return "None" if id == "" else id.replace("_", " ").capitalize()

static func category(kind: int) -> String:
	return "LIGHT" if kind == Unit.Kind.LANCER else ("HEAVY" if kind == Unit.Kind.BULWARK else "MEDIUM")

static func primary(kind: int) -> String:
	return "thrust" if kind == Unit.Kind.LANCER else ("shield_bash" if kind == Unit.Kind.BULWARK else "grapple")
