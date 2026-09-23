extends SceneTree

const Combat = preload("res://scripts/prototypes/ember_combat_prototype.gd")
const Grid = preload("res://scripts/prototypes/ember_combat_grid.gd")


func _init() -> void:
	var errors: Array[String] = []
	var state := Grid.initial_state()
	for id in state.units:
		state.units[id].nextAt = 0.0 if id == "mira" else 100.0
		if id not in ["mira", "orik", "wisp"]:
			state.units[id].hp = 0
	state.units.mira.cell = Vector2i(0, 2)
	state.units.orik.cell = Vector2i(2, 3)
	state.units.orik.hp = 5
	state.units.wisp.cell = Vector2i(4, 2)
	state.units.mira.moveRange = 3
	state.units.mira.actions = ["strike", "spark", "guard", "mira_mend", "lift_throw", "earth_wall", "wind_spread", "defend", "forge_leap"]
	var before := hash(state)
	for action_id in ["strike", "spark", "guard", "mira_mend", "lift_throw", "earth_wall", "wind_spread", "defend", "forge_leap"]:
		var cell := Vector2i(4, 2)
		if action_id in ["guard", "mira_mend"]:
			cell = Vector2i(2, 3)
		elif action_id in ["earth_wall", "forge_leap"]:
			cell = Vector2i(1, 2)
		var plan := Grid.action_plan(state, action_id, cell)
		for key in ["originCell", "movementPath", "destination", "applicationCell", "occupantId", "cellContent", "footprint", "reason", "commitRule"]:
			if not plan.has(key):
				errors.append("%s lacks %s" % [action_id, key])
		if not plan.ok:
			errors.append("%s unexpectedly unavailable: %s" % [action_id, plan.reason])
			continue
		if plan.movementPath[-1] != plan.destination:
			errors.append("%s path and stop disagree" % action_id)
		var after := Combat.commit(state, plan.resolved)
		if after.turn != state.turn + 1 or hash(Combat.commit(after, plan.resolved)) != hash(after):
			errors.append("%s commit was not exactly once" % action_id)
	if hash(state) != before:
		errors.append("planning or commit mutated original snapshot")
	var context := Grid.action_plan_context(state, "strike")
	var a := Grid.action_plan(state, "strike", Vector2i(4, 2), Combat.INVALID_CELL, Combat.INVALID_CELL, "hold", context)
	var b := Grid.action_plan(state, "strike", Vector2i(2, 3), Combat.INVALID_CELL, Combat.INVALID_CELL, "hold", context)
	if not a.ok or b.ok or b.reason.is_empty() or not b.resolved.is_empty():
		errors.append("compatible to incompatible hover retained executable preview")
	state.units.mira.moveRange = 1
	var partial := Grid.action_plan(state, "strike", Vector2i(4, 2), Combat.INVALID_CELL, Combat.INVALID_CELL, "hold", context)
	if not partial.fallbackDefend or partial.destination != Vector2i(1, 2) or partial.commitRule != "stop_defend":
		errors.append("state mutation did not invalidate cached movement / fallback")
	var manual := Grid.action_plan_context(state, "strike", Vector2i(0, 2), true)
	var anchored := Grid.action_plan(state, "strike", Vector2i(4, 2), Vector2i(0, 2), Combat.INVALID_CELL, "hold", manual)
	if anchored.destination != Vector2i(0, 2) or not anchored.fallbackDefend:
		errors.append("M at the origin did not lock the selected stop")
	var remote := Grid.action_plan(state, "earth_wall", Vector2i(6, 4))
	if remote.ok or remote.fallbackDefend:
		errors.append("earth wall escaped MOVE plus authored range")
	var movement := Grid.action_plan(state, "__move", Vector2i(1, 2))
	if not movement.ok or movement.commitRule != "stage_move" or movement.movementPath.size() != 2:
		errors.append("manual movement lacks a cell plan")
	state.units.orik.hp = 0
	state = Combat.with_inventory(state, {"revive": 1}, {"revive": {"id": "revive", "nameRu": "Возвращение", "kind": "consumable", "useIn": "arena", "reviveHp": 1, "combatRange": 2}})
	var revival := Grid.action_plan(state, "item:revive", Vector2i(2, 3))
	if not revival.ok or revival.occupantId != "orik" or not revival.willExecute:
		errors.append("cell lookup lost the fallen ally for revival")
	state.units.mira.moveRange = 3
	var lower := Grid.action_plan(state, "lift_throw", Vector2i(4, 2), Combat.INVALID_CELL, Combat.INVALID_CELL, "lower")
	if not lower.ok or not lower.resolved.get("setHold", {}).is_empty():
		errors.append("lower created a persistent hold")
	var big := Grid.initial_state(Grid.STRESS_16X12_FIELD)
	for id in big.units:
		big.units[id].nextAt = 0.0 if id == "orik" else 100.0
	var cached := Grid.action_plan_context(big, "ice_wall")
	var targets := Grid.approach_target_cells(big, "ice_wall")
	var started := Time.get_ticks_usec()
	for index in 80:
		Grid.action_plan(big, "ice_wall", targets[index % targets.size()], Combat.INVALID_CELL, Combat.INVALID_CELL, "hold", cached)
	var elapsed := float(Time.get_ticks_usec() - started) / 80000.0
	if elapsed >= 20.0:
		errors.append("cached hover exceeds 20 ms: %.2f" % elapsed)
	print("16x12 cached cell ActionPlan: %.2f ms" % elapsed)
	if not errors.is_empty():
		for error in errors:
			printerr("FAIL action plan: ", error)
		quit(1)
	else:
		print("PASS combat ActionPlan: all categories, fallback, anchored M, revive, stale context, pure once-only commit")
		quit(0)
