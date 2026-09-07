extends SceneTree
## D1 Combat Lab gate: preview and commit share one pure elemental resolver.

const Combat = preload("res://scripts/prototypes/ember_combat_prototype.gd")
const Grid = preload("res://scripts/prototypes/ember_combat_grid.gd")


func _init() -> void:
	var errors: Array[String] = []
	_test_timeline(errors)
	_test_water_cold(errors)
	_test_conduction(errors)
	_test_steam_push(errors)
	_test_guard(errors)
	_test_defend(errors)
	_test_locked_rng_and_mp(errors)
	_test_stat_formula(errors)
	_test_hidden_player_intent(errors)
	_test_deterministic_resistances(errors)
	_test_pair_techniques(errors)
	_test_enemy_command(errors)
	if not errors.is_empty():
		printerr("FAIL combat prototype")
		for error in errors:
			printerr(" - ", error)
		quit(1)
		return
	print("PASS combat prototype")
	print("  visible timeline is deterministic and action delay predicts the next order")
	print("  preview is pure; commit applies the same damage/status/movement result")
	print("  Wet + Cold, Wet + Lightning and Frozen + Fire reactions are explicit")
	print("  pair techniques spend and delay both fixed participants exactly once")
	print("  hidden locked RNG, MP cost, stats and deterministic authored resistances are covered")
	quit(0)


func _test_timeline(errors: Array[String]) -> void:
	var state := Combat.initial_state()
	var current := Combat.current_unit_id(state)
	var before := Combat.timeline(state, 6)
	var after := Combat.timeline(state, 6, "douse")
	if current != "mira" or before.is_empty() or str(before[0].get("unitId", "")) != "mira":
		errors.append("initial timeline does not expose the expected current hero")
	if after.is_empty() or str(after[0].get("unitId", "")) == "mira":
		errors.append("pending action delay did not move the current hero in predicted timeline")


func _test_water_cold(errors: Array[String]) -> void:
	var state := Combat.initial_state()
	var original := state.duplicate(true)
	var wet := Combat.preview(state, "douse", "warden")
	if state != original:
		errors.append("combat preview mutated its input state")
	if not wet.get("ok", false) or int((wet.get("setStatuses", {}) as Dictionary).get("warden", {}).get("wet", 0)) != 2:
		errors.append("water preview did not apply Wet")
	state = Combat.commit(state, wet)
	_force_turn(state, "orik")
	var frozen := Combat.preview(state, "chill", "warden")
	if str(frozen.get("reaction", "")) != "Заморозка":
		errors.append("cold did not recognize prepared Wet")
	state = Combat.commit(state, frozen)
	var warden := Combat.unit_definition(state, "warden")
	if int((warden.get("statuses", {}) as Dictionary).get("frozen", 0)) != 1:
		errors.append("cold commit did not persist Frozen")
	if (warden.get("statuses", {}) as Dictionary).has("wet"):
		errors.append("freezing did not consume explicit Wet")


func _test_conduction(errors: Array[String]) -> void:
	var state := Combat.initial_state()
	_force_turn(state, "sena")
	var preview := Combat.preview(state, "spark", "wisp")
	var damage: Dictionary = preview.get("damage", {})
	if str(preview.get("reaction", "")) != "Проводящая цепь":
		errors.append("lightning did not read the wet zone rule")
	if not damage.has("wisp") or not damage.has("raider") or damage.has("warden"):
		errors.append("conduction did not stay inside the target wet zone")
	var committed := Combat.commit(state, preview)
	var expected_hp := 15 - int(damage.get("raider", 0))
	if int(Combat.unit_definition(committed, "raider").get("hp", 0)) != expected_hp:
		errors.append("conduction preview and commit disagree on chained damage")


func _test_steam_push(errors: Array[String]) -> void:
	var state := Combat.initial_state()
	var units: Dictionary = state.get("units", {})
	var warden: Dictionary = units.get("warden", {})
	warden["statuses"] = {"frozen": 1}
	units["warden"] = warden
	state["units"] = units
	_force_turn(state, "protagonist")
	var preview := Combat.preview(state, "kindle", "warden")
	if str(preview.get("reaction", "")) != "Паровой импульс":
		errors.append("fire did not resolve Frozen as Steam Break")
	if int((preview.get("moves", {}) as Dictionary).get("warden", -1)) != 3:
		errors.append("Steam Break did not preview forced movement")
	var committed := Combat.commit(state, preview)
	var result := Combat.unit_definition(committed, "warden")
	if int(result.get("zone", -1)) != 3 or (result.get("statuses", {}) as Dictionary).has("frozen"):
		errors.append("Steam Break commit lost previewed movement/status removal")


func _test_guard(errors: Array[String]) -> void:
	var state := Combat.initial_state()
	_force_turn(state, "orik")
	var guard := Combat.preview(state, "guard", "sena")
	state = Combat.commit(state, guard)
	_force_turn(state, "wisp")
	var hit := Combat.preview(state, "enemy_strike", "sena")
	if int((hit.get("damage", {}) as Dictionary).get("sena", 0)) != 2:
		errors.append("guard did not halve previewed incoming damage")
	state = Combat.commit(state, hit)
	if (Combat.unit_definition(state, "sena").get("statuses", {}) as Dictionary).has("guard"):
		errors.append("guard was not consumed by the protected hit")


func _test_defend(errors: Array[String]) -> void:
	var state := Combat.initial_state()
	_force_turn(state, "mira")
	var before_preview := state.duplicate(true)
	var defended := Combat.preview(state, "defend", "mira")
	if not bool(defended.get("ok", false)) or not (defended.get("damage", {}) as Dictionary).is_empty():
		errors.append("defend is not a valid non-damaging self command")
	if not str(defended.get("summary", "")).contains("Ход завершается без атаки"):
		errors.append("defend preview does not explain that it ends the turn")
	if state != before_preview:
		errors.append("defend preview mutated its source snapshot")
	state = Combat.commit(state, defended)
	if int((Combat.unit_definition(state, "mira").get("statuses", {}) as Dictionary).get("guard", 0)) != 1:
		errors.append("defend status expired during its own commit")
	_force_turn(state, "wisp")
	var hit := Combat.preview(state, "enemy_strike", "mira")
	if int((hit.get("damage", {}) as Dictionary).get("mira", 0)) != 2:
		errors.append("self defend did not halve the next incoming hit")
	state = Combat.commit(state, hit)
	if (Combat.unit_definition(state, "mira").get("statuses", {}) as Dictionary).has("guard"):
		errors.append("self defend was not consumed by the protected hit")


func _test_enemy_command(errors: Array[String]) -> void:
	var state := Combat.initial_state()
	_force_turn(state, "wisp")
	var command := Combat.enemy_command(state)
	var repeated := Combat.enemy_command(state)
	if not command.get("ok", false) or str(command.get("actorId", "")) != "wisp":
		errors.append("enemy turn produced no deterministic command")
	if command != repeated:
		errors.append("enemy recomputed a different command from the same snapshot")
	if str(command.get("targetId", "")) not in Combat.valid_target_ids(state, "enemy_strike"):
		errors.append("enemy selected a target outside the shared resolver")


func _test_locked_rng_and_mp(errors: Array[String]) -> void:
	var state := Combat.initial_state(1)
	var first := Combat.preview(state, "douse", "warden")
	var repeated := Combat.preview(state, "douse", "warden")
	if (
		int(first.get("hitRoll", 0)) != int(repeated.get("hitRoll", -1))
		or int(first.get("critRoll", 0)) != int(repeated.get("critRoll", -1))
		or first.get("damage", {}) != repeated.get("damage", {})
	):
		errors.append("same command rerolled while its source snapshot was unchanged")
	if int(first.get("mpCost", 0)) != 4 or int(first.get("mpAfter", -1)) != 36:
		errors.append("preview did not expose the authored MP cost and exact remainder")
	var committed := Combat.commit(state, first)
	if int(Combat.unit_definition(committed, "mira").get("mp", -1)) != 36:
		errors.append("commit did not spend the previewed MP exactly once")
	var duplicate_commit := Combat.commit(committed, first)
	if duplicate_commit != committed:
		errors.append("stale preview was applied a second time")
	var units: Dictionary = state.get("units", {})
	var mira: Dictionary = units.get("mira", {})
	mira["mp"] = 3
	units["mira"] = mira
	state["units"] = units
	if not Combat.valid_target_ids(state, "douse").is_empty():
		errors.append("action remained selectable without enough MP")
	var miss := {}
	for seed in range(1, 1000):
		var candidate := Combat.preview(Combat.initial_state(seed), "douse", "warden")
		if bool(candidate.get("ok", false)) and not bool(candidate.get("hit", true)):
			miss = candidate
			break
	if miss.is_empty():
		errors.append("could not exercise a deterministic miss")
	elif (
		not (miss.get("damage", {}) as Dictionary).is_empty()
		or not (miss.get("setStatuses", {}) as Dictionary).is_empty()
	):
		errors.append("miss still applied damage or status")


func _test_stat_formula(errors: Array[String]) -> void:
	var state := Combat.initial_state(1)
	_force_turn(state, "protagonist")
	var normal := Combat.preview(state, "strike", "raider")
	if not bool(normal.get("hit", false)):
		errors.append("stat formula fixture unexpectedly missed")
		return
	var armored := state.duplicate(true)
	var units: Dictionary = armored.get("units", {})
	var raider: Dictionary = units.get("raider", {})
	raider["def"] = int(raider.get("def", 0)) + 20
	units["raider"] = raider
	armored["units"] = units
	var reduced := Combat.preview(armored, "strike", "raider")
	if int((reduced.get("damage", {}) as Dictionary).get("raider", 0)) >= int((normal.get("damage", {}) as Dictionary).get("raider", 0)):
		errors.append("DEF did not reduce physical damage")


func _test_hidden_player_intent(errors: Array[String]) -> void:
	var state := Combat.initial_state(1)
	var resolved := Combat.preview(state, "douse", "wisp")
	var intent := Combat.describe_intent(state, "douse", "wisp")
	if not resolved.has("hitRoll") or not resolved.has("critical"):
		errors.append("resolver no longer locks the hidden hostile result")
	if "Эффект:" not in intent or "Условия:" not in intent or "Wet" not in intent:
		errors.append("player intent does not explain the authored effect and conditions")
	for forbidden in ["Попадание ", "бросок ", "ПРОМАХ", "КРИТ", " HP"]:
		if forbidden in intent:
			errors.append("player intent leaks a locked combat result: %s" % forbidden)


func _test_deterministic_resistances(errors: Array[String]) -> void:
	var state := Combat.initial_state(1)
	_force_turn(state, "orik")
	var units := state.get("units", {}) as Dictionary
	var warden := units.get("warden", {}) as Dictionary
	warden["statuses"] = {"wet": 2}
	warden["statusResistances"] = {"wet": 0, "frozen": 1, "burning": 0}
	units["warden"] = warden
	state["units"] = units
	_lock_hit_seed(state, "chill", "warden")
	var blocked_freeze := Combat.preview(state, "chill", "warden")
	if not bool(blocked_freeze.get("hit", false)):
		errors.append("status resistance fixture unexpectedly missed")
	elif (
		(blocked_freeze.get("setStatuses", {}) as Dictionary).has("warden")
		or not str(blocked_freeze.get("summary", "")).contains("блокирует эффект")
	):
		errors.append("authored Frozen resistance did not deterministically block the status")
	if Combat.preview(state, "chill", "warden") != blocked_freeze:
		errors.append("status resistance changed without a state change")

	state = Combat.initial_state(1)
	_force_turn(state, "mira")
	units = state.get("units", {}) as Dictionary
	var wisp := units.get("wisp", {}) as Dictionary
	wisp["pushResistance"] = 1
	units["wisp"] = wisp
	state["units"] = units
	_lock_hit_seed(state, "gust", "wisp")
	var blocked_push := Combat.preview(state, "gust", "wisp")
	if (
		(blocked_push.get("moves", {}) as Dictionary).has("wisp")
		or not str(blocked_push.get("summary", "")).contains("блокирует отбрасывание")
	):
		errors.append("equal authored push resistance did not deterministically stop force")


func _test_pair_techniques(errors: Array[String]) -> void:
	var state := Grid.initial_state(null, 1)
	_force_turn(state, "sena")
	var setup_units: Dictionary = state.get("units", {})
	var setup_wisp: Dictionary = setup_units.get("wisp", {})
	setup_wisp["statuses"] = {"wet": 2}
	setup_wisp["cell"] = Vector2i(2, 1)
	setup_units["wisp"] = setup_wisp
	var setup_raider: Dictionary = setup_units.get("raider", {})
	setup_raider["statuses"] = {"wet": 2}
	setup_raider["cell"] = Vector2i(2, 2)
	setup_units["raider"] = setup_raider
	state["units"] = setup_units
	_lock_hit_seed(state, "duo_pulse", "wisp")
	var sena_before := Combat.unit_definition(state, "sena")
	var mira_before := Combat.unit_definition(state, "mira")
	var plain_timeline := Combat.timeline(state, 12)
	var pair_timeline := Combat.timeline(state, 12, "duo_pulse")
	var wet_pair := Combat.preview(state, "duo_pulse", "wisp")
	var wet_damage: Dictionary = wet_pair.get("damage", {})
	var wet_context := Combat.duo_partner_context(state, "duo_pulse")
	if (
		not bool(wet_pair.get("ok", false))
		or str(wet_pair.get("partnerId", "")) != "mira"
		or str(wet_pair.get("reaction", "")) != "Грозовая связка"
		or not wet_damage.has("wisp")
		or not wet_damage.has("raider")
		or wet_damage.has("warden")
	):
		errors.append("Mira + Sena pair did not require Wet or stay inside its conducting chain")
	if (
		not bool(wet_context.get("inRange", false))
		or int(wet_context.get("distance", -1)) != 2
		or int(wet_context.get("range", 0)) != 3
	):
		errors.append("pair context did not expose the authored height-aware partner radius")
	if _timeline_index(pair_timeline, "mira") <= _timeline_index(plain_timeline, "mira"):
		errors.append("pair preview did not show the partner's future timeline delay")
	var pair_intent := Combat.describe_intent(state, "duo_pulse", "wisp")
	if "Партнёр: Мира" not in pair_intent or "MP: 6" not in pair_intent:
		errors.append("pair intent does not explain the partner and their MP cost")
	for forbidden in ["Попадание ", "бросок ", "ПРОМАХ", "КРИТ", " HP"]:
		if forbidden in pair_intent:
			errors.append("pair intent leaks a locked combat result: %s" % forbidden)
	var wet_committed := Combat.commit(state, wet_pair)
	var sena_after := Combat.unit_definition(wet_committed, "sena")
	var mira_after := Combat.unit_definition(wet_committed, "mira")
	if (
		int(sena_after.get("mp", -1)) != int(sena_before.get("mp", 0)) - 8
		or int(mira_after.get("mp", -1)) != int(mira_before.get("mp", 0)) - 6
		or float(sena_after.get("nextAt", 0.0)) <= float(sena_before.get("nextAt", 0.0))
		or float(mira_after.get("nextAt", 0.0)) <= float(mira_before.get("nextAt", 0.0))
	):
		errors.append("Mira + Sena pair did not spend/delay both participants")
	if Combat.commit(wet_committed, wet_pair) != wet_committed:
		errors.append("stale pair preview charged its participants twice")

	var blocked := state.duplicate(true)
	var blocked_units: Dictionary = blocked.get("units", {})
	var blocked_mira: Dictionary = blocked_units.get("mira", {})
	blocked_mira["mp"] = 5
	blocked_units["mira"] = blocked_mira
	blocked["units"] = blocked_units
	if (
		not Combat.valid_target_ids(blocked, "duo_pulse").is_empty()
		or "нужно 6 MP" not in Combat.duo_partner_unavailable_reason(blocked, "duo_pulse")
	):
		errors.append("pair remained available without the partner's MP")
	if Combat.commit(blocked, wet_pair) != blocked:
		errors.append("locked pair preview committed after its partner lost the required MP")
	var distant := state.duplicate(true)
	var distant_units: Dictionary = distant.get("units", {})
	var distant_mira: Dictionary = distant_units.get("mira", {})
	distant_mira["cell"] = Vector2i(6, 4)
	distant_units["mira"] = distant_mira
	distant["units"] = distant_units
	var distant_reason := Combat.duo_partner_unavailable_reason(distant, "duo_pulse")
	if (
		not Combat.valid_target_ids(distant, "duo_pulse").is_empty()
		or "вне радиуса" not in distant_reason
		or "9/3" not in distant_reason
	):
		errors.append("pair remained available with its partner outside the authored radius")
	if Combat.commit(distant, wet_pair) != distant:
		errors.append("locked pair preview committed after its partner left the radius")
	var distant_intent := Combat.describe_intent(distant, "duo_pulse", "wisp")
	if "ВНЕ РАДИУСА" not in distant_intent or "дистанция 9/3" not in distant_intent:
		errors.append("pair intent does not explain an out-of-range partner")
	var approach := state.duplicate(true)
	var approach_units: Dictionary = approach.get("units", {})
	var approach_mira: Dictionary = approach_units.get("mira", {})
	approach_mira["cell"] = Vector2i(4, 1)
	approach_units["mira"] = approach_mira
	approach["units"] = approach_units
	var staged_approach := Grid.stage_move(approach, Vector2i(1, 1))
	if (
		staged_approach.is_empty()
		or not Combat.duo_partner_unavailable_reason(
			staged_approach, "duo_pulse"
		).is_empty()
		or "wisp" not in Combat.valid_target_ids(staged_approach, "duo_pulse")
	):
		errors.append("staged movement into the partner radius did not enable the pair")

	state = Grid.initial_state(null, 1)
	_force_turn(state, "protagonist")
	if not Combat.valid_target_ids(state, "steam_breach").is_empty():
		errors.append("steam breach remained available without a Frozen target")
	var units: Dictionary = state.get("units", {})
	var protagonist_setup: Dictionary = units.get("protagonist", {})
	protagonist_setup["cell"] = Vector2i(2, 3)
	units["protagonist"] = protagonist_setup
	var warden: Dictionary = units.get("warden", {})
	warden["statuses"] = {"frozen": 1}
	warden["cell"] = Vector2i(3, 3)
	units["warden"] = warden
	state["units"] = units
	_lock_hit_seed(state, "steam_breach", "warden")
	var protagonist_before := Combat.unit_definition(state, "protagonist")
	var orik_before := Combat.unit_definition(state, "orik")
	var steam_pair := Combat.preview(state, "steam_breach", "warden")
	if (
		not bool(steam_pair.get("ok", false))
		or str(steam_pair.get("partnerId", "")) != "orik"
		or str(steam_pair.get("reaction", "")) != "Паровой пробой"
		or not (steam_pair.get("removeStatuses", {}) as Dictionary).has("warden")
		or not (steam_pair.get("moves", {}) as Dictionary).has("warden")
	):
		errors.append("Orik + protagonist pair did not consume Frozen and force the target")
	var steam_committed := Combat.commit(state, steam_pair)
	var protagonist_after := Combat.unit_definition(steam_committed, "protagonist")
	var orik_after := Combat.unit_definition(steam_committed, "orik")
	if (
		int(protagonist_after.get("mp", -1)) != int(protagonist_before.get("mp", 0)) - 8
		or int(orik_after.get("mp", -1)) != int(orik_before.get("mp", 0)) - 6
		or (Combat.unit_definition(steam_committed, "warden").get("statuses", {}) as Dictionary).has("frozen")
	):
		errors.append("Orik + protagonist pair did not commit both costs and the Frozen reaction")

	var fallen_partner := state.duplicate(true)
	var fallen_units: Dictionary = fallen_partner.get("units", {})
	var fallen_orik: Dictionary = fallen_units.get("orik", {})
	fallen_orik["hp"] = 0
	fallen_units["orik"] = fallen_orik
	fallen_partner["units"] = fallen_units
	if (
		not Combat.valid_target_ids(fallen_partner, "steam_breach").is_empty()
		or "выведен из боя" not in Combat.duo_partner_unavailable_reason(
			fallen_partner, "steam_breach"
		)
	):
		errors.append("pair remained available after its authored partner fell")


func _lock_hit_seed(state: Dictionary, action_id: String, target_id: String) -> void:
	for seed in range(1, 1000):
		state["rngSeed"] = seed
		if bool(Combat.preview(state, action_id, target_id).get("hit", false)):
			return


func _timeline_index(rows: Array[Dictionary], unit_id: String) -> int:
	for index in rows.size():
		if str(rows[index].get("unitId", "")) == unit_id:
			return index
	return rows.size()


func _force_turn(state: Dictionary, active_id: String) -> void:
	var units: Dictionary = state.get("units", {})
	for raw_id in units:
		var unit: Dictionary = units[raw_id]
		unit["nextAt"] = 0.0 if str(raw_id) == active_id else 100.0
		units[raw_id] = unit
	state["units"] = units
