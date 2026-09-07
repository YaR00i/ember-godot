@tool
class_name EmberCombatUnitResource
extends Resource
## Canonical authored combatant definition. Runtime snapshots copy these values
## and own mutable HP/status/cell state; the Resource itself is never mutated by battle.

enum Team { HERO, ENEMY }
enum CreatureType { HUMAN, ANIMAL, CONSTRUCT, UNDEAD, SPIRIT, OTHER }

const CREATURE_TYPE_IDS := ["human", "animal", "construct", "undead", "spirit", "other"]
const CREATURE_TYPE_LABELS := ["Человек", "Животное", "Конструкт", "Нечисть", "Дух", "Иное"]
const SIZE_LABELS := ["", "Малый", "Средний", "Крупный"]

const ActionCatalog := preload("res://scripts/prototypes/ember_combat_action_catalog.gd")
const AiProfileCatalog := preload("res://scripts/prototypes/ember_combat_ai_profile_catalog.gd")

@export_group("Боец")
@export var unit_id := ""
@export var display_name := "Новый боец"
@export_enum("Герой", "Враг") var team: int = Team.HERO
@export_multiline var description := ""
@export_range(1, 99, 1) var combat_level := 1
@export_enum("Человек", "Животное", "Конструкт", "Нечисть", "Дух", "Иное") var creature_type: int = CreatureType.HUMAN

@export_group("Основные характеристики")
@export_range(1, 999, 1) var max_hp := 10
@export_range(0, 999, 1) var max_mp := 0
@export_range(1, 99, 1) var strength := 6
@export_range(1, 99, 1) var magic := 6
@export_range(0, 99, 1) var defense := 3
@export_range(0, 99, 1) var resistance := 3
@export_range(1, 99, 1) var speed := 10
@export_range(1, 99, 1) var accuracy := 92
@export_range(0, 99, 1) var luck := 6

@export_group("Производные и перемещение")
@export_range(0, 12, 1) var move_range := 3
@export_range(0, 8, 1) var jump_height := 1
## 1 = light, 2 = medium, 3 = heavy/boss. Stage 1 only needs a stable
## lift/throw boundary; the full production stat model belongs to stage 3.
@export_range(1, 3, 1) var weight_class := 1
@export_range(0, 3, 1) var push_resistance := 0
@export var action_ids := PackedStringArray(["strike", "defend"])
@export var ai_profile_id := ""
@export var loot_table: EmberCombatLootTableResource
@export var combat_tags := PackedStringArray()

@export_group("Сопротивления, %")
@export_range(-100, 100, 1) var fire_resistance := 0
@export_range(-100, 100, 1) var water_resistance := 0
@export_range(-100, 100, 1) var cold_resistance := 0
@export_range(-100, 100, 1) var lightning_resistance := 0
@export_range(-100, 100, 1) var air_resistance := 0
@export_range(-100, 100, 1) var earth_resistance := 0

@export_group("Устойчивость к эффектам, сокращение ходов")
@export_range(0, 2, 1) var wet_resistance := 0
@export_range(0, 2, 1) var frozen_resistance := 0
@export_range(0, 2, 1) var burning_resistance := 0

@export_group("Вид")
@export var battle_color := Color("65cfe1")
@export var portrait: Texture2D

@export_group("Лабораторная расстановка")
@export_range(0, 99, 1) var prototype_roster_order := 0
@export_range(0, 8, 1) var prototype_zone := 0
@export_range(0.0, 999.0, 0.5) var prototype_next_at := 0.0


func team_id() -> String:
	return "enemy" if team == Team.ENEMY else "hero"


func creature_type_id() -> String:
	return str(CREATURE_TYPE_IDS[clampi(creature_type, 0, CREATURE_TYPE_IDS.size() - 1)])


func creature_type_label() -> String:
	return str(CREATURE_TYPE_LABELS[clampi(creature_type, 0, CREATURE_TYPE_LABELS.size() - 1)])


func size_label() -> String:
	return str(SIZE_LABELS[clampi(weight_class, 1, SIZE_LABELS.size() - 1)])


func to_definition() -> Dictionary:
	var derived_evasion := maxi(0, floori(float(speed) * 0.5 + float(luck) * 0.25))
	var derived_crit := clampi(5 + floori(float(luck) * 0.5), 0, 35)
	return {
		"id": unit_id.strip_edges(),
		"name": display_name.strip_edges(),
		"team": team_id(),
		"level": combat_level,
		"description": description.strip_edges(),
		"creatureType": creature_type_id(),
		"creatureTypeLabel": creature_type_label(),
		"hp": max_hp,
		"maxHp": max_hp,
		"mp": max_mp,
		"maxMp": max_mp,
		"str": strength,
		"mag": magic,
		"def": defense,
		"res": resistance,
		"speed": speed,
		"acc": accuracy,
		"luck": luck,
		"eva": derived_evasion,
		"crit": derived_crit,
		"resistances": {
			"fire": fire_resistance,
			"water": water_resistance,
			"cold": cold_resistance,
			"lightning": lightning_resistance,
			"air": air_resistance,
			"earth": earth_resistance,
		},
		"moveRange": move_range,
		"jumpHeight": jump_height,
		"weightClass": weight_class,
		"sizeLabel": size_label(),
		"pushResistance": push_resistance,
		"statusResistances": {
			"wet": wet_resistance,
			"frozen": frozen_resistance,
			"burning": burning_resistance,
		},
		"zone": prototype_zone,
		"nextAt": prototype_next_at,
		"statuses": {},
		"actions": Array(action_ids),
		"aiProfileId": ai_profile_id.strip_edges(),
		"lootTableId": loot_table.table_id if loot_table != null else "",
		"combatTags": Array(combat_tags),
		"battleColor": battle_color,
		"portraitPath": portrait.resource_path if portrait != null else "",
	}


func validation_errors(known_action_ids: PackedStringArray = PackedStringArray()) -> Array[String]:
	var errors: Array[String] = []
	if not _valid_id(unit_id):
		errors.append("ID бойца: используйте a-z, 0-9, _ или -.")
	if display_name.strip_edges().is_empty():
		errors.append("Укажите понятное имя бойца.")
	if max_hp <= 0:
		errors.append("Максимальное HP должно быть больше нуля.")
	if combat_level <= 0:
		errors.append("Уровень бойца должен быть больше нуля.")
	if max_mp < 0:
		errors.append("Максимальное MP не может быть отрицательным.")
	if strength <= 0 or magic <= 0:
		errors.append("Сила и Магия должны быть больше нуля.")
	if defense < 0 or resistance < 0:
		errors.append("Защита и Сопротивление не могут быть отрицательными.")
	if speed <= 0:
		errors.append("Скорость должна быть больше нуля.")
	if accuracy <= 0:
		errors.append("Точность должна быть больше нуля.")
	if luck < 0:
		errors.append("Удача не может быть отрицательной.")
	if jump_height < 0:
		errors.append("Jump не может быть отрицательным.")
	if weight_class < 1:
		errors.append("Класс веса должен быть не меньше 1.")
	if action_ids.is_empty():
		errors.append("Добавьте хотя бы одно действие.")
	var seen_actions := {}
	for raw_action_id in action_ids:
		var action_id := str(raw_action_id).strip_edges()
		if not _valid_id(action_id):
			errors.append("Некорректный ID действия: %s." % action_id)
		elif seen_actions.has(action_id):
			errors.append("Действие %s добавлено дважды." % action_id)
		elif not known_action_ids.is_empty() and action_id not in known_action_ids:
			errors.append("Действие %s отсутствует в текущем боевом каталоге." % action_id)
		seen_actions[action_id] = true
	var clean_profile := ai_profile_id.strip_edges()
	if team == Team.ENEMY and clean_profile.is_empty():
		errors.append("Для врага выберите профиль AI.")
	elif not clean_profile.is_empty():
		var profile := AiProfileCatalog.resource(clean_profile)
		if profile == null:
			errors.append("Профиль AI %s отсутствует в каталоге." % clean_profile)
		else:
			for profile_error in profile.validation_errors():
				errors.append("Профиль AI: %s" % profile_error)
	if team == Team.ENEMY and loot_table == null:
		errors.append("Для врага выберите таблицу лута.")
	elif loot_table != null:
		for loot_error in loot_table.validation_errors():
			errors.append("Лут: %s" % loot_error)
	var seen_tags := {}
	for raw_tag in combat_tags:
		var tag := str(raw_tag).strip_edges()
		if not _valid_id(tag):
			errors.append("Некорректный combat tag: %s." % tag)
		elif seen_tags.has(tag):
			errors.append("Combat tag %s добавлен дважды." % tag)
		seen_tags[tag] = true
	return errors


func content_signature() -> String:
	return "|".join([
		unit_id, display_name, team_id(), description, str(combat_level),
		creature_type_id(), str(max_hp), str(max_mp),
		str(strength), str(magic), str(defense), str(resistance),
		str(speed), str(accuracy), str(luck), str(move_range),
		str(jump_height), str(weight_class), str(push_resistance),
		str(fire_resistance), str(water_resistance), str(cold_resistance),
		str(lightning_resistance), str(air_resistance), str(earth_resistance),
		str(wet_resistance), str(frozen_resistance),
		str(burning_resistance),
		",".join(action_ids), _action_signature(), ai_profile_id, _ai_profile_signature(),
		loot_table.content_signature() if loot_table != null else "", ",".join(combat_tags),
		battle_color.to_html(true), portrait.resource_path if portrait != null else "",
		str(prototype_roster_order), str(prototype_zone), str(prototype_next_at),
	])


func _action_signature() -> String:
	var signatures := PackedStringArray()
	for raw_id in action_ids:
		var action := ActionCatalog.resource(str(raw_id))
		signatures.append(action.content_signature() if action != null else "missing:%s" % raw_id)
	return "||".join(signatures)


func _ai_profile_signature() -> String:
	if ai_profile_id.strip_edges().is_empty():
		return ""
	var profile := AiProfileCatalog.resource(ai_profile_id)
	return profile.content_signature() if profile != null else "missing:%s" % ai_profile_id


func _valid_id(value: String) -> bool:
	var clean := value.strip_edges()
	if clean.is_empty():
		return false
	var expression := RegEx.new()
	return expression.compile("^[a-z0-9][a-z0-9_-]*$") == OK and expression.search(clean) != null
