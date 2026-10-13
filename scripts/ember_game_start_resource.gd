@tool
class_name EmberGameStartResource
extends Resource
## New-game recipe only. PartyState/Equipment own progression and gear rules;
## ExploreState remains the sole owner of mutable progress and save data.
const Party = preload("res://scripts/ember_party_state.gd")
const Gear = preload("res://scripts/ember_equipment.gd")
const Items = preload("res://scripts/ember_item_catalog.gd")
const DEFAULT_PATH := "res://content/game_start/default.tres"

@export var start_id := "default"
@export var display_name := "Старт игры"
@export var hero_levels: Dictionary = {}
@export var hero_equipment: Dictionary = {}
@export var inventory: Dictionary = {"coin": 20}

static func saved() -> EmberGameStartResource:
	if not ResourceLoader.exists(DEFAULT_PATH): return null
	return ResourceLoader.load(DEFAULT_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as EmberGameStartResource

func validation_errors(items: Dictionary = {}) -> Array[String]:
	var errors: Array[String] = []
	if start_id != "default": errors.append("Старт игры: единственная запись должна иметь ID default.")
	if display_name.strip_edges().is_empty(): errors.append("Укажите название стартового комплекта.")
	var definitions := items
	if items.is_empty():
		definitions = {}
		for id in item_ids():
			var item := Items.definition(id)
			if not item.is_empty(): definitions[id] = item
	for id in hero_levels:
		var value: Variant = hero_levels[id]
		if id not in Party.HERO_IDS: errors.append("Неизвестный герой в уровнях: " + str(id))
		if typeof(value) != TYPE_INT or value < 1 or value > Party.MAX_LEVEL:
			errors.append("%s: уровень должен быть целым числом от 1 до %d." % [id, Party.MAX_LEVEL])
	for id in hero_equipment:
		if id not in Party.HERO_IDS: errors.append("Неизвестный герой в экипировке: " + str(id))
		var value: Variant = hero_equipment[id]
		if not value is Dictionary:
			errors.append("%s: экипировка должна содержать пять слотов." % id)
			continue
		if value.size() != Gear.SLOTS.size() or not Gear.SLOTS.all(func(slot: String) -> bool: return value.has(slot)):
			errors.append("%s: экипировка должна содержать только пять актуальных слотов." % id)
		for slot in value:
			var item_id: Variant = value[slot]
			if slot not in Gear.SLOTS: continue
			if item_id == null: continue
			if typeof(item_id) != TYPE_STRING or not definitions.has(item_id):
				errors.append("%s / %s: неизвестный предмет %s." % [id, slot, item_id])
				continue
			var item: Dictionary = definitions[item_id]
			if slot not in Gear.slots_for_item(item) or not Party.equipment_allowed(item, str(id)):
				errors.append("%s: предмет %s не подходит герою или слоту %s." % [id, item_id, slot])
	for id in inventory:
		var count: Variant = inventory[id]
		if typeof(id) != TYPE_STRING or not definitions.has(id):
			errors.append("Сумка: неизвестный предмет " + str(id))
			continue
		var maximum := maxi(1, int(definitions[id].get("stackMax", 99)))
		if typeof(count) != TYPE_INT or count < 1 or count > maximum:
			errors.append("Сумка / %s: количество должно быть целым числом от 1 до %d." % [id, maximum])
	return errors

func prepare(items: Dictionary) -> Dictionary:
	var errors := validation_errors(items)
	if not errors.is_empty(): return {"ok": false, "error": "\n".join(errors)}
	var party := Party.new_game(items)
	for id in Party.HERO_IDS:
		party[id].level = hero_levels.get(id, 1)
		party[id].equipment = hero_equipment.get(id, Gear.empty()).duplicate(true)
		var stats := Party.derived_stats(id, party[id], items)
		party[id].hp = int(stats.maxHp)
		party[id].mp = int(stats.maxMp)
	return {"ok": true, "party": party, "inventory": inventory.duplicate(true)}

func item_ids() -> Array[String]:
	var result: Array[String] = []
	for id in inventory:
		if typeof(id) == TYPE_STRING and id not in result: result.append(id)
	for hero in hero_equipment:
		var gear: Variant = hero_equipment[hero]
		if not gear is Dictionary: continue
		for slot in gear:
			var id: Variant = gear[slot]
			if typeof(id) == TYPE_STRING and not id.is_empty() and id not in result: result.append(id)
	return result

func behavior_summary() -> String:
	return "Только новая игра: XP = 0, полные HP и MP. Сумка выдаётся дополнительно к надетому. Загрузка сохранений использует их собственные данные."
