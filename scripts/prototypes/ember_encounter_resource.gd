@tool
class_name EmberEncounterResource
extends Resource
## Authored battle entry point. It references the existing Battlefield Resource
## and current prototype roster instead of owning another combat/runtime schema.

const Combat := preload("res://scripts/prototypes/ember_combat_prototype.gd")
const UnitCatalog := preload("res://scripts/prototypes/ember_combat_unit_catalog.gd")
const EmberPartyState := preload("res://scripts/ember_party_state.gd")

enum VictoryRule { ALL_ENEMIES_DEFEATED }
enum DefeatRule { ALL_HEROES_DEFEATED }

@export_group("Встреча")
@export var encounter_id := ""
@export var display_name := "Новая встреча"
@export_multiline var description := ""
@export_multiline var intro_text := ""

@export_group("Поле")
@export var battlefield: EmberBattlefieldResource
@export var arena_scene: PackedScene

@export_group("Участники прототипа")
@export var party_unit_ids: PackedStringArray = PackedStringArray(["mira", "orik", "sena", "protagonist"])
@export var enemy_unit_ids: PackedStringArray = PackedStringArray(["wisp", "raider", "warden"])

@export_group("После боя")
@export var victory_rule := VictoryRule.ALL_ENEMIES_DEFEATED
@export var defeat_rule := DefeatRule.ALL_HEROES_DEFEATED
@export var victory_flag_id := ""
@export var defeat_flag_id := ""
@export var victory_action_script_id := ""
@export var defeat_action_script_id := ""
@export_range(0, 999999, 1) var victory_xp := 0
@export var repeatable := true


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if not _valid_id(encounter_id):
		errors.append("ID встречи: используйте a-z, 0-9, _ или -.")
	if display_name.strip_edges().is_empty():
		errors.append("Укажите понятное название встречи.")
	if battlefield == null:
		errors.append("Выберите Battlefield Resource.")
	else:
		for field_error in battlefield.validation_errors():
			errors.append("Поле: %s" % field_error)
		if party_unit_ids.size() > battlefield.party_deployment_cells.size():
			errors.append("Для героев нужно %d точек расстановки, на поле есть %d." % [
			party_unit_ids.size(), battlefield.party_deployment_cells.size(),
		])
		if enemy_unit_ids.size() > battlefield.enemy_deployment_cells.size():
			errors.append("Для врагов нужно %d точек расстановки, на поле есть %d." % [
			enemy_unit_ids.size(), battlefield.enemy_deployment_cells.size(),
		])
	if arena_scene == null:
		errors.append("Выберите сцену арены для редактирования в 3D.")
	_validate_roster("Герои", party_unit_ids, "hero", errors)
	_validate_roster("Враги", enemy_unit_ids, "enemy", errors)
	for unit_id in party_unit_ids:
		if unit_id in enemy_unit_ids:
			errors.append("Боец %s назначен обеим сторонам." % unit_id)
	_validate_action("После победы", victory_action_script_id, errors)
	_validate_action("После поражения", defeat_action_script_id, errors)
	if victory_xp <= 0:
		errors.append("После победы: укажите положительный XP для всей активной партии.")
	return errors


func active_party_errors(active_ids: Array[String]) -> Array[String]:
	var errors: Array[String] = []
	if not EmberPartyState.valid_active_hero_ids(active_ids):
		errors.append("Активная группа должна содержать от 1 до 4 разных героев каталога.")
		return errors
	for hero_id in active_ids:
		if hero_id not in party_unit_ids:
			errors.append("Встреча не поддерживает активного героя: %s." % hero_id)
	if battlefield == null or active_ids.size() > battlefield.party_deployment_cells.size():
		errors.append("На поле недостаточно клеток для активной группы (%d)." % active_ids.size())
	return errors


func initial_state(party_snapshot: Dictionary = {}, rng_seed: int = 0, active_ids: Array[String] = []) -> Dictionary:
	if battlefield == null:
		return {}
	if not active_ids.is_empty() and not active_party_errors(active_ids).is_empty():
		return {}
	var roster := PackedStringArray()
	for hero_id in party_unit_ids:
		if active_ids.is_empty() or hero_id in active_ids:
			roster.append(hero_id)
	var active_seed := rng_seed
	if active_seed == 0:
		active_seed = int(Time.get_ticks_usec()) ^ encounter_id.hash()
	var state := Combat.initial_state(active_seed)
	var source_units: Dictionary = state.get("units", {})
	var units := {}
	for index in roster.size():
		var unit_id := str(roster[index])
		if not source_units.has(unit_id) or index >= battlefield.party_deployment_cells.size():
			continue
		var unit: Dictionary = (source_units[unit_id] as Dictionary).duplicate(true)
		unit["cell"] = battlefield.party_deployment_cells[index]
		units[unit_id] = unit
	for index in enemy_unit_ids.size():
		var unit_id := str(enemy_unit_ids[index])
		if not source_units.has(unit_id) or index >= battlefield.enemy_deployment_cells.size():
			continue
		var unit: Dictionary = (source_units[unit_id] as Dictionary).duplicate(true)
		unit["cell"] = battlefield.enemy_deployment_cells[index]
		units[unit_id] = unit
	state["encounterId"] = encounter_id
	state["encounterName"] = display_name
	state["units"] = units
	state["grid"] = battlefield.to_grid_dictionary()
	state["log"] = [intro_text if not intro_text.strip_edges().is_empty() else display_name]
	if not party_snapshot.is_empty():
		state = EmberPartyState.apply_to_combat_state(
			state,
			party_snapshot,
			EmberInteractionContent.item_definitions(),
		)
	return state


func action_for_outcome(outcome: String) -> String:
	return victory_action_script_id if outcome == "victory" else defeat_action_script_id


func flag_for_outcome(outcome: String) -> String:
	return victory_flag_id if outcome == "victory" else defeat_flag_id


func can_start(progress: EmberExploreState) -> bool:
	return (
		repeatable
		or progress == null
		or victory_flag_id.strip_edges().is_empty()
		or not bool(progress.flags.get(victory_flag_id, false))
	)


func content_signature() -> String:
	return "|".join([
		encounter_id, display_name,
		battlefield.content_signature() if battlefield != null else "missing_field",
		",".join(party_unit_ids), ",".join(enemy_unit_ids),
		_roster_signature(),
		victory_flag_id, defeat_flag_id,
		victory_action_script_id, defeat_action_script_id,
		str(victory_xp),
		str(victory_rule), str(defeat_rule), str(repeatable),
	])


func _validate_roster(
	title: String,
	ids: PackedStringArray,
	expected_team: String,
	errors: Array[String],
) -> void:
	if ids.is_empty():
		errors.append("%s: добавьте хотя бы одного участника." % title)
		return
	var seen := {}
	for raw_id in ids:
		var unit_id := str(raw_id).strip_edges()
		if seen.has(unit_id):
			errors.append("%s: %s указан дважды." % [title, unit_id])
			continue
		seen[unit_id] = true
		var unit := UnitCatalog.resource(unit_id)
		if unit == null:
			errors.append("%s: боец %s отсутствует в каталоге Resources." % [title, unit_id])
		elif unit.team_id() != expected_team:
			errors.append("%s: боец %s относится к другой стороне." % [title, unit_id])
		else:
			for unit_error in unit.validation_errors(Combat.action_ids()):
				errors.append("%s · %s: %s" % [title, unit_id, unit_error])


func _validate_action(title: String, action_id: String, errors: Array[String]) -> void:
	var clean := action_id.strip_edges()
	if not clean.is_empty() and clean not in EmberInteractionContent.action_script_ids():
		errors.append("%s: цепочка %s не найдена." % [title, clean])


func _roster_signature() -> String:
	var signatures := PackedStringArray()
	for raw_id in party_unit_ids + enemy_unit_ids:
		var unit := UnitCatalog.resource(str(raw_id))
		signatures.append(unit.content_signature() if unit != null else "missing:%s" % raw_id)
	return "||".join(signatures)


func _valid_id(value: String) -> bool:
	var clean := value.strip_edges()
	if clean.is_empty():
		return false
	var expression := RegEx.new()
	return expression.compile("^[a-z0-9][a-z0-9_-]*$") == OK and expression.search(clean) != null
