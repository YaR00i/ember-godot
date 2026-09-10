@tool
class_name EmberCombatStatusResource
extends Resource
## Canonical authored presentation contract for one combat status. Runtime
## snapshots keep only status ID and remaining turns; battle rules stay in the
## internal rule modules behind the single resolver facade and look presentation
## up through the shared catalog.

enum Kind { BUFF, DEBUFF }

const KIND_IDS := ["buff", "debuff"]
const KIND_LABELS := ["Усиление", "Ослабление"]

@export_group("Статус")
@export var status_id := ""
@export var display_name := "Новый статус"
@export_multiline var description := ""
@export_enum("Усиление", "Ослабление") var kind: int = Kind.DEBUFF

@export_group("Вид")
@export var glyph := "●"
@export var ui_color := Color.WHITE
@export var icon: Texture2D


func kind_id() -> String:
	return str(KIND_IDS[clampi(kind, 0, KIND_IDS.size() - 1)])


func kind_label() -> String:
	return str(KIND_LABELS[clampi(kind, 0, KIND_LABELS.size() - 1)])


func to_definition() -> Dictionary:
	return {
		"id": status_id.strip_edges(),
		"name": display_name.strip_edges(),
		"description": description.strip_edges(),
		"kind": kind_id(),
		"icon": glyph.strip_edges(),
		"color": ui_color,
		"texture": icon,
		"texturePath": icon.resource_path if icon != null else "",
	}


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if not _valid_id(status_id):
		errors.append("ID статуса: используйте a-z, 0-9, _ или -.")
	if display_name.strip_edges().is_empty():
		errors.append("Укажите понятное название статуса.")
	if description.strip_edges().is_empty():
		errors.append("Опишите состояние для автора боевого контента.")
	if glyph.strip_edges().is_empty() and icon == null:
		errors.append("Добавьте короткий знак или иконку статуса.")
	return errors


func content_signature() -> String:
	return "|".join([
		status_id, display_name, description, kind_id(), glyph,
		ui_color.to_html(true), icon.resource_path if icon != null else "",
	])


func _valid_id(value: String) -> bool:
	var clean := value.strip_edges()
	if clean.is_empty():
		return false
	var expression := RegEx.new()
	return expression.compile("^[a-z0-9][a-z0-9_-]*$") == OK and expression.search(clean) != null
