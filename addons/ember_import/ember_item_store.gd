@tool
class_name EmberItemStore
extends RefCounted
## Validation/writer boundary for the shared Godot-native item catalog.

const Catalog = preload("res://scripts/ember_item_catalog.gd")
const KINDS := ["material", "consumable", "weapon_jrpg", "armor", "shoes", "accessory", "key"]
const LEGACY_KINDS := ["weapon_arena"]
const SLOTS := ["none", "weapon", "armor", "shoes", "accessory"]
const LEGACY_SLOTS := ["head", "body"]
const RARITIES := ["common", "uncommon", "rare", "epic"]
const USE_TARGETS := ["explore", "arena", "both"]


static func document(item_id: String) -> Dictionary:
	return Catalog.definition(item_id)


static func owner(item_id: String) -> String:
	return Catalog.owner(item_id)


static func source_path(item_id: String) -> String:
	return Catalog.native_path(item_id) if owner(item_id) == "native" else ""


static func ids() -> Array[String]:
	return Catalog.ids()


static func icon_ids() -> Array[String]:
	return Catalog.icon_ids()


static func exists(item_id: String) -> bool:
	return not owner(item_id).is_empty()


static func suggested_id(source: String) -> String:
	var clean := source.strip_edges().to_lower()
	var expression := RegEx.new()
	expression.compile("[^a-z0-9_-]+")
	clean = expression.sub(clean, "_", true).strip_edges().trim_prefix("_").trim_suffix("_")
	return "%s_item" % (clean if not clean.is_empty() else "new")


static func normalized_document(raw: Dictionary) -> Dictionary:
	var result := raw.duplicate(true)
	result["id"] = str(raw.get("id", "")).strip_edges()
	result["name"] = str(raw.get("name", "")).strip_edges()
	result["nameRu"] = str(raw.get("nameRu", "")).strip_edges()
	result["kind"] = str(raw.get("kind", "material")).strip_edges()
	result["slot"] = str(raw.get("slot", "none")).strip_edges()
	if result.kind == "armor" and result.slot == "body": result.slot = "armor"
	result["rarity"] = str(raw.get("rarity", "common")).strip_edges()
	result["useIn"] = str(raw.get("useIn", "explore")).strip_edges()
	result["stackMax"] = maxi(1, roundi(float(raw.get("stackMax", 1))))
	result["iconId"] = str(raw.get("iconId", "")).strip_edges()
	for key in ["atk", "def", "hpRestore", "mpRestore", "reviveHp", "sellPrice"]:
		result[key] = maxi(0, roundi(float(raw.get(key, 0))))
	result["combatRange"] = clampi(roundi(float(raw.get("combatRange", 1))), 0, 99)
	result["unsellable"] = bool(raw.get("unsellable", false))
	result["notesRu"] = str(raw.get("notesRu", "")).strip_edges()
	var tags: Array[String] = []
	var raw_tags: Variant = raw.get("tags", [])
	if typeof(raw_tags) == TYPE_ARRAY or typeof(raw_tags) == TYPE_PACKED_STRING_ARRAY:
		for raw_tag in raw_tags:
			var tag := str(raw_tag).strip_edges()
			if not tag.is_empty() and tag not in tags:
				tags.append(tag)
	result["tags"] = tags
	for key in ["hpBonus", "mpBonus", "combatDelay"]:
		if raw.has(key): result[key] = int(raw[key])
	if raw.has("allowedHeroIds") and typeof(raw.allowedHeroIds) in [TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY]:
		var allowed: Array[String] = []
		for raw_id in raw.allowedHeroIds:
			var hero_id := str(raw_id).strip_edges()
			if not hero_id.is_empty() and hero_id not in allowed: allowed.append(hero_id)
		result["allowedHeroIds"] = allowed
	return result


static func validation_errors(raw: Dictionary) -> Array[String]:
	var value := normalized_document(raw)
	var errors: Array[String] = []
	if not _valid_id(str(value.get("id", ""))):
		errors.append("ID: только a-z, 0-9, _ и -, первый символ — буква или цифра.")
	if str(value.get("nameRu", "")).is_empty():
		errors.append("Укажите русское название предмета.")
	if str(value.get("kind", "")) not in KINDS + LEGACY_KINDS:
		errors.append("Выберите поддерживаемый тип предмета.")
	if str(value.get("slot", "")) not in SLOTS + LEGACY_SLOTS:
		errors.append("Выберите поддерживаемый слот.")
	if str(value.get("kind", "")) == "armor" and str(value.get("slot", "")) not in ["armor", "head"]:
		errors.append("Броне нужен слот брони. Старый головной убор хранится в сумке до изменения типа.")
	if raw.has("allowedHeroIds") and typeof(raw.allowedHeroIds) not in [TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY]:
		errors.append("Список героев должен содержать ID; пустой список разрешает экипировку всем.")
	if raw.has("combatDelay") and int(value.get("combatDelay", 100)) < 1:
		errors.append("Задержка применения в бою должна быть не меньше 1.")
	if str(value.get("rarity", "")) not in RARITIES:
		errors.append("Выберите редкость.")
	if str(value.get("useIn", "")) not in USE_TARGETS:
		errors.append("Выберите режим использования.")
	if (
		str(value.get("kind", "")) == "consumable"
		and str(value.get("useIn", "")) in ["arena", "both"]
		and int(value.get("hpRestore", 0)) <= 0
		and int(value.get("mpRestore", 0)) <= 0
		and int(value.get("reviveHp", 0)) <= 0
	):
		errors.append("Боевому расходнику нужен эффект HP, MP или воскрешения.")
	var icon_id := str(value.get("iconId", ""))
	if not icon_id.is_empty() and icon_id not in icon_ids():
		errors.append("Выберите существующую пиксельную иконку.")
	return errors


static func write_document(raw: Dictionary) -> int:
	var value := normalized_document(raw)
	var errors := validation_errors(value)
	if not errors.is_empty():
		push_error("Ember item: %s" % " ".join(errors))
		return ERR_INVALID_DATA
	return Catalog.write_native(value)


static func snapshot(item_id: String) -> Dictionary:
	return Catalog.snapshot(item_id)


static func restore_snapshot(snapshot_value: Dictionary) -> int:
	return Catalog.restore(snapshot_value)


static func _valid_id(value: String) -> bool:
	if value.is_empty():
		return false
	var expression := RegEx.new()
	return expression.compile("^[a-z0-9][a-z0-9_-]*$") == OK and expression.search(value) != null
