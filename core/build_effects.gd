class_name BuildEffects
extends RefCounted

static func proc(state: BattleState, unit: Unit, type: String, id: String) -> void:
	state.tel.bump(type + ":" + id)
	state.events.append({"t": "build_proc", "id": unit.id, "pos": unit.pos, "text": SquadLoadout.label(id)})

static func update_damage(state: BattleState, unit: Unit, old: Unit.DamageState) -> void:
	if not unit.is_player():
		return
	if old != unit.damage_state():
		state.tel.bump("condition:" + unit.damage_label())
		state.events.append({"t": "build_proc", "id": unit.id, "pos": unit.pos, "text": unit.damage_label()})
	if unit.damage_state() != Unit.DamageState.NORMAL and not unit.impairment_triggered:
		unit.impairment_triggered = true
		for slot: int in [1, 0]:
			if unit.systems[slot] != "":
				unit.impaired_slot = slot
				proc(state, unit, "impairment", unit.systems[slot])
				break

static func repair(state: BattleState, unit: Unit) -> void:
	unit.engineer_used = true
	if unit.impaired_slot >= 0:
		unit.impaired_slot = -1
	else:
		var old := unit.damage_state()
		if old == Unit.DamageState.CRITICAL:
			unit.hp = unit.max_hp / 4 + 1
		elif old == Unit.DamageState.DAMAGED:
			unit.hp = unit.max_hp / 2 + 1
		update_damage(state, unit, old)
	proc(state, unit, "pilot", "engineer")

static func after_action(state: BattleState, unit: Unit, action: String, old_positions: Dictionary, ace_ready: bool, actuators: bool) -> void:
	if action == unit.secondary():
		state.tel.bump("secondary:" + action)
	if action in ["thrust", "shield_bash", "impact_spear", "repulsor_plate", "throw", "grapple"]:
		if ace_ready:
			unit.ace_used = true
			proc(state, unit, "pilot", "ace")
		if actuators:
			proc(state, unit, "system", "reinforced_actuators")
	if action in ["grapple", "throw", "tow_cable", "emergency_winch"] and unit.pilot_id == "rescuer" and not unit.rescuer_used:
		for id: int in old_positions:
			var ally: Unit = state.units[id]
			if ally.id != unit.id and ally.is_player() and ally.is_alive() and ally.pos != old_positions[id]:
				unit.ap = mini(unit.max_ap, unit.ap + 1)
				unit.rescuer_used = true
				proc(state, unit, "pilot", "rescuer")
				break
