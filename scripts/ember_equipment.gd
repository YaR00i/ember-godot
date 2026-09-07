class_name EmberEquipment
extends RefCounted
## Pure inventory/equipment projection and mutations mirroring JOI
## emberEquipment.ts. EmberExploreState remains the only mutable owner.

const SLOTS: Array[String] = [
	"weapon",
	"arena_weapon",
	"head",
	"body",
	"accessory",
]
const SLOT_LABELS := {
	"weapon": "Оружие",
	"arena_weapon": "Арена",
	"head": "Голова",
	"body": "Тело",
	"accessory": "Аксессуар",
}
const UNARMED_ATK := 4
const UNARMED_DEF := 0


static func empty() -> Dictionary:
	return {
		"weapon": null,
		"arena_weapon": null,
		"head": null,
		"body": null,
		"accessory": null,
	}


static func normalize(raw: Variant) -> Dictionary:
	var result := empty()
	if typeof(raw) != TYPE_DICTIONARY:
		return result
	for slot in SLOTS:
		var value: Variant = raw.get(slot, null)
		var item_id := str(value).strip_edges() if value != null else ""
		result[slot] = item_id if not item_id.is_empty() else null
	return result


static func slot_for_item(item: Dictionary) -> String:
	match str(item.get("kind", "")):
		"weapon_jrpg":
			return "weapon"
		"weapon_arena":
			return "arena_weapon"
		"armor":
			var slot := str(item.get("slot", ""))
			return slot if slot == "head" or slot == "body" else ""
		"accessory":
			return "accessory"
	return ""


static func inventory_views(inventory: Dictionary, items: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for raw_id in inventory:
		var item_id := str(raw_id).strip_edges()
		var count := int(inventory[raw_id])
		if item_id.is_empty() or count <= 0:
			continue
		var item: Dictionary = items.get(item_id, {})
		var kind := str(item.get("kind", "material"))
		rows.append({
			"itemId": item_id,
			"nameRu": str(item.get("nameRu", item.get("name", item_id))),
			"count": count,
			"kind": kind,
			"slot": str(item.get("slot", "none")),
			"atk": int(item.get("atk", 0)),
			"def": int(item.get("def", 0)),
			"hpRestore": int(item.get("hpRestore", 0)),
			"mpRestore": int(item.get("mpRestore", 0)),
			"reviveHp": int(item.get("reviveHp", 0)),
			"arenaOnly": kind == "weapon_arena",
			"canEquip": not slot_for_item(item).is_empty(),
			"canUse": (
				str(item.get("useIn", "explore")) in ["explore", "both"]
				and (
					int(item.get("hpRestore", 0)) > 0
					or int(item.get("mpRestore", 0)) > 0
					or int(item.get("reviveHp", 0)) > 0
				)
			),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("nameRu", "")).naturalnocasecmp_to(str(b.get("nameRu", ""))) < 0
	)
	return rows


static func combat_stats(equipment: Dictionary, items: Dictionary) -> Dictionary:
	var eq := normalize(equipment)
	var explore_atk := UNARMED_ATK
	var arena_atk := UNARMED_ATK
	var defense := UNARMED_DEF
	explore_atk += _stat(items, eq.get("weapon"), "atk")
	explore_atk += _stat(items, eq.get("accessory"), "atk")
	arena_atk += _stat(items, eq.get("arena_weapon"), "atk")
	defense += _stat(items, eq.get("head"), "def")
	defense += _stat(items, eq.get("body"), "def")
	defense += _stat(items, eq.get("accessory"), "def")
	return {"atk": explore_atk, "def": defense, "arenaAtk": arena_atk}


static func equip(
	inventory: Dictionary,
	equipment: Dictionary,
	item_id: String,
	items: Dictionary,
) -> Dictionary:
	var inv := EmberEconomy.compact_counts(inventory)
	var eq := normalize(equipment)
	var item: Dictionary = items.get(item_id, {})
	if item.is_empty():
		return _failure("missing_item", inv, eq)
	var slot := slot_for_item(item)
	if slot.is_empty():
		return _failure("cannot_equip", inv, eq)
	if int(inv.get(item_id, 0)) < 1:
		return _failure("not_in_bag", inv, eq)
	_set_count(inv, item_id, int(inv.get(item_id, 0)) - 1)
	var previous: Variant = eq.get(slot, null)
	if previous != null and not str(previous).is_empty():
		inv = EmberEconomy.grant_items(inv, [str(previous)], items)
	eq[slot] = item_id
	return {"ok": true, "reason": "", "inventory": inv, "equipment": eq}


static func unequip(
	inventory: Dictionary,
	equipment: Dictionary,
	slot: String,
	items: Dictionary,
) -> Dictionary:
	var inv := EmberEconomy.compact_counts(inventory)
	var eq := normalize(equipment)
	if slot not in SLOTS:
		return _failure("empty_slot", inv, eq)
	var item_id: Variant = eq.get(slot, null)
	if item_id == null or str(item_id).is_empty():
		return _failure("empty_slot", inv, eq)
	inv = EmberEconomy.grant_items(inv, [str(item_id)], items)
	eq[slot] = null
	return {"ok": true, "reason": "", "inventory": inv, "equipment": eq}


static func use_item(
	inventory: Dictionary,
	equipment: Dictionary,
	item_id: String,
	items: Dictionary,
) -> Dictionary:
	var inv := EmberEconomy.compact_counts(inventory)
	var eq := normalize(equipment)
	var item: Dictionary = items.get(item_id, {})
	if item.is_empty():
		return _failure("missing_item", inv, eq)
	var heal := int(item.get("hpRestore", 0))
	var mana := int(item.get("mpRestore", 0))
	var revive_hp := int(item.get("reviveHp", 0))
	if (
		str(item.get("useIn", "explore")) not in ["explore", "both"]
		or (heal <= 0 and mana <= 0 and revive_hp <= 0)
	):
		return _failure("cannot_use", inv, eq)
	if int(inv.get(item_id, 0)) < 1:
		return _failure("not_in_bag", inv, eq)
	_set_count(inv, item_id, int(inv.get(item_id, 0)) - 1)
	return {
		"ok": true,
		"reason": "",
		"inventory": inv,
		"equipment": eq,
		"heal": heal,
		"mana": mana,
		"reviveHp": revive_hp,
	}


static func failure_ru(reason: String) -> String:
	match reason:
		"missing_item":
			return "Нет такого предмета"
		"not_in_bag":
			return "Нет в сумке"
		"empty_slot":
			return "Слот пуст"
		"cannot_use":
			return "Нельзя использовать"
		"wrong_hero":
			return "Этот герой не может надеть предмет"
		"missing_hero":
			return "Герой не найден"
		"target_alive":
			return "Предмет предназначен для павшего героя"
		_:
			return "Нельзя надеть"


static func _stat(items: Dictionary, raw_id: Variant, key: String) -> int:
	if raw_id == null:
		return 0
	var item: Dictionary = items.get(str(raw_id), {})
	return int(item.get(key, 0))


static func _set_count(counts: Dictionary, item_id: String, value: int) -> void:
	if value > 0:
		counts[item_id] = value
	else:
		counts.erase(item_id)


static func _failure(reason: String, inventory: Dictionary, equipment: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"inventory": inventory,
		"equipment": equipment,
	}
