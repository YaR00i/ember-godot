extends RefCounted
## Pure hit, critical and damage math. It has no timeline, targeting, UI or
## commit ownership and is only called by EmberCombatPrototype.

const StatusRules := preload("res://scripts/prototypes/ember_combat_status_rules.gd")


static func hit_chance(actor: Dictionary, target: Dictionary, action: Dictionary) -> int:
	return clampi(
		int(actor.get("acc", 90))
		+ int(action.get("accuracyModifier", 0))
		- int(target.get("eva", 0)),
		60,
		99,
	)


static func critical_chance(actor: Dictionary, action: Dictionary) -> int:
	if int(action.get("power", 0)) <= 0:
		return 0
	return clampi(int(actor.get("crit", 5)), 0, 35)


static func locked_roll(
	state: Dictionary,
	actor: Dictionary,
	action: Dictionary,
	target: Dictionary,
	secondary_cell: Vector2i,
	channel: String,
) -> int:
	var actor_cell: Variant = actor.get("cell", actor.get("zone", 0))
	var target_cell: Variant = target.get("cell", target.get("zone", 0))
	var key := "%d|%d|%s|%s|%s|%s|%s|%d:%d|%s" % [
		int(state.get("rngSeed", 1)),
		int(state.get("turn", 1)),
		str(actor.get("id", "")),
		str(action.get("id", "")),
		str(target.get("id", "")),
		str(actor_cell),
		str(target_cell),
		secondary_cell.x,
		secondary_cell.y,
		channel,
	]
	return posmod(key.hash(), 100) + 1


static func scaled_action_damage(
	actor: Dictionary,
	target: Dictionary,
	action: Dictionary,
	raw_power: int,
	critical: bool,
) -> int:
	var scaling := str(action.get("scaling", "strength"))
	var offense := int(actor.get("mag", 1)) if scaling == "magic" else int(actor.get("str", 1))
	var element_id := str(action.get("element", "physical"))
	var defense_key := "def" if element_id == "physical" else "res"
	var mitigation := floori(float(target.get(defense_key, 0)) * 0.35)
	var amount := maxi(1, raw_power + floori(float(offense) * 0.5) - mitigation)
	var resistance_percent := int(
		(target.get("resistances", {}) as Dictionary).get(element_id, 0)
	)
	amount = maxi(0, roundi(float(amount) * float(100 - resistance_percent) / 100.0))
	if StatusRules.has(target, "overheated") and amount > 0:
		amount = ceili(float(amount) * 1.25)
	if critical and amount > 0:
		amount = ceili(float(amount) * 1.5)
	return amount


static func set_damage(resolved: Dictionary, unit_id: String, amount: int) -> void:
	var damage: Dictionary = resolved.get("damage", {})
	damage[unit_id] = maxi(0, amount)
	resolved["damage"] = damage


static func add_damage(resolved: Dictionary, unit_id: String, amount: int) -> void:
	var damage: Dictionary = resolved.get("damage", {})
	damage[unit_id] = maxi(0, int(damage.get(unit_id, 0)) + amount)
	resolved["damage"] = damage


static func add_fixed_damage(resolved: Dictionary, unit_id: String, amount: int) -> void:
	add_damage(resolved, unit_id, amount)
	var fixed: Dictionary = resolved.get("fixedDamage", {})
	fixed[unit_id] = maxi(0, int(fixed.get(unit_id, 0)) + amount)
	resolved["fixedDamage"] = fixed
