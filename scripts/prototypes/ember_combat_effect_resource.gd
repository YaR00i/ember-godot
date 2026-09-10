@tool
class_name EmberCombatEffectResource
extends Resource
## One reusable, authored effect step. Actions may compose several steps, while
## the combat resolver remains the only owner of their runtime semantics.

const StatusCatalog := preload("res://scripts/prototypes/ember_combat_status_catalog.gd")

enum Operation {
	APPLY_STATUS,
	REMOVE_STATUS,
	PUSH,
	CELL_PATCH,
	SPREAD,
	RESTORE_HP,
	MOVE_ACTOR,
	ACTIVATE_FOCUS,
}
enum BlockMode { KEEP, OPEN, BLOCK }

const OPERATION_IDS := [
	"apply_status", "remove_status", "push", "cell_patch", "spread",
	"restore_hp", "move_actor", "activate_focus",
]
const OPERATION_LABELS := [
	"Наложить статус", "Снять статусы", "Толчок", "Изменить клетку", "Распространить стихию",
	"Восстановить HP", "Переместить применяющего", "Активировать узел",
]
const BLOCK_MODE_IDS := ["keep", "open", "block"]
const BLOCK_MODE_LABELS := ["Не менять", "Убрать преграду", "Поставить преграду"]

@export_group("Эффект")
@export var effect_id := ""
@export var display_name := "Новый эффект"
@export_multiline var description := ""
@export_enum(
	"Наложить статус", "Снять статусы", "Толчок", "Изменить клетку",
	"Распространить стихию", "Восстановить HP", "Переместить применяющего",
	"Активировать узел",
) var operation: int = Operation.APPLY_STATUS

@export_group("Статус")
@export var status_id := ""
@export_range(0, 12, 1) var status_duration := 0
@export var remove_status_ids := PackedStringArray()

@export_group("Толчок")
@export_range(0, 8, 1) var force := 0

@export_group("Клетка и террейн")
## The same canonical elevation used by movement, LOS and AI is changed. The
## authored Battlefield Resource is never mutated; the patch lives in battle state.
@export_range(-8, 8, 1) var elevation_delta := 0
@export_enum("Не менять", "Убрать преграду", "Поставить преграду") var block_mode: int = BlockMode.KEEP
@export var add_cell_tags := PackedStringArray()
@export var remove_cell_tags := PackedStringArray()

@export_group("Распространение")
@export_range(0, 8, 1) var spread_radius := 0
@export var spread_status_ids := PackedStringArray()
@export var spread_cell_tags := PackedStringArray()
## Used when a terrain tag is the source and there is no unit duration to copy.
@export_range(1, 12, 1) var spread_status_duration := 2
@export var spread_to_units := true
@export var spread_to_cells := true

@export_group("Лечение")
@export_range(0, 999, 1) var restore_hp_amount := 0

@export_group("Особое перемещение")
## Maximum absolute height difference of the destination. Range and line of
## sight still belong to the action, while occupancy belongs to the battlefield.
@export_range(0, 16, 1) var move_max_height_delta := 0

@export_group("Вид")
@export var ui_color := Color("d8dee9")
@export var icon: Texture2D


func operation_id() -> String:
	return str(OPERATION_IDS[clampi(operation, 0, OPERATION_IDS.size() - 1)])


func operation_label() -> String:
	return str(OPERATION_LABELS[clampi(operation, 0, OPERATION_LABELS.size() - 1)])


func block_mode_id() -> String:
	return str(BLOCK_MODE_IDS[clampi(block_mode, 0, BLOCK_MODE_IDS.size() - 1)])


func block_mode_label() -> String:
	return str(BLOCK_MODE_LABELS[clampi(block_mode, 0, BLOCK_MODE_LABELS.size() - 1)])


func to_definition() -> Dictionary:
	return {
		"id": effect_id.strip_edges(),
		"name": display_name.strip_edges(),
		"description": description.strip_edges(),
		"operation": operation_id(),
		"statusId": status_id.strip_edges(),
		"statusDuration": status_duration,
		"removeStatusIds": Array(remove_status_ids),
		"force": force,
		"elevationDelta": elevation_delta,
		"blockMode": block_mode_id(),
		"addCellTags": Array(add_cell_tags),
		"removeCellTags": Array(remove_cell_tags),
		"spreadRadius": spread_radius,
		"spreadStatusIds": Array(spread_status_ids),
		"spreadCellTags": Array(spread_cell_tags),
		"spreadStatusDuration": spread_status_duration,
		"spreadToUnits": spread_to_units,
		"spreadToCells": spread_to_cells,
		"restoreHpAmount": restore_hp_amount,
		"moveMaxHeightDelta": move_max_height_delta,
		"uiColor": ui_color,
		"icon": icon,
		"iconPath": icon.resource_path if icon != null else "",
	}


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if not _valid_id(effect_id):
		errors.append("ID эффекта: используйте a-z, 0-9, _ или -.")
	if display_name.strip_edges().is_empty():
		errors.append("Укажите понятное название эффекта.")
	if description.strip_edges().is_empty():
		errors.append("Опишите результат эффекта для библиотеки.")
	match operation:
		Operation.APPLY_STATUS:
			if not _valid_id(status_id):
				errors.append("Для наложения укажите стабильный ID статуса.")
			elif StatusCatalog.resource(status_id) == null:
				errors.append("Статус %s отсутствует в боевом каталоге." % status_id)
			if status_duration <= 0:
				errors.append("Длительность статуса должна быть больше нуля.")
		Operation.REMOVE_STATUS:
			_validate_status_list(remove_status_ids, "Снимаемый статус", errors)
			if remove_status_ids.is_empty():
				errors.append("Добавьте хотя бы один снимаемый статус.")
		Operation.PUSH:
			if force <= 0:
				errors.append("Сила толчка должна быть больше нуля.")
		Operation.CELL_PATCH:
			_validate_id_list(add_cell_tags, "Добавляемый тег клетки", errors)
			_validate_id_list(remove_cell_tags, "Удаляемый тег клетки", errors)
			if (
				elevation_delta == 0
				and block_mode == BlockMode.KEEP
				and add_cell_tags.is_empty()
				and remove_cell_tags.is_empty()
			):
				errors.append("Изменение клетки пока ничего не меняет.")
		Operation.SPREAD:
			_validate_status_list(spread_status_ids, "Распространяемый статус", errors)
			_validate_id_list(spread_cell_tags, "Распространяемый тег клетки", errors)
			if spread_radius <= 0:
				errors.append("Радиус распространения должен быть больше нуля.")
			if spread_status_ids.is_empty() and spread_cell_tags.is_empty():
				errors.append("Укажите хотя бы один статус или тег для распространения.")
			if not spread_to_units and not spread_to_cells:
				errors.append("Распространение должно затрагивать бойцов, клетки или оба варианта.")
		Operation.RESTORE_HP:
			if restore_hp_amount <= 0:
				errors.append("Лечение должно восстанавливать больше нуля HP.")
		Operation.MOVE_ACTOR:
			if move_max_height_delta <= 0:
				errors.append("Особому перемещению нужен допустимый перепад высоты больше нуля.")
		Operation.ACTIVATE_FOCUS:
			pass
	return errors


func content_signature() -> String:
	return "|".join([
		effect_id, display_name, description, operation_id(), status_id,
		str(status_duration), ",".join(remove_status_ids), str(force),
		str(elevation_delta), block_mode_id(), ",".join(add_cell_tags),
		",".join(remove_cell_tags), str(spread_radius),
		",".join(spread_status_ids), ",".join(spread_cell_tags),
		str(spread_status_duration), str(spread_to_units), str(spread_to_cells),
		str(restore_hp_amount), str(move_max_height_delta),
		ui_color.to_html(true), icon.resource_path if icon != null else "",
	])


func _validate_id_list(values: PackedStringArray, label: String, errors: Array[String]) -> void:
	var seen := {}
	for raw_value in values:
		var value := str(raw_value).strip_edges()
		if not _valid_id(value):
			errors.append("%s: используйте a-z, 0-9, _ или -." % label)
		elif seen.has(value):
			errors.append("%s %s добавлен дважды." % [label, value])
		seen[value] = true


func _validate_status_list(values: PackedStringArray, label: String, errors: Array[String]) -> void:
	_validate_id_list(values, label, errors)
	for raw_value in values:
		var value := str(raw_value).strip_edges()
		if _valid_id(value) and StatusCatalog.resource(value) == null:
			errors.append("%s %s отсутствует в боевом каталоге." % [label, value])


func _valid_id(value: String) -> bool:
	var clean := value.strip_edges()
	if clean.is_empty():
		return false
	var expression := RegEx.new()
	return expression.compile("^[a-z0-9][a-z0-9_-]*$") == OK and expression.search(clean) != null
