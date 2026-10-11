@tool
class_name EmberCombatStatusResource
extends Resource
## Canonical status definition. Instances keep ID/remaining turns only;
## supported behavior is executed by the existing StatusRules/resolver.

enum Kind { BUFF, DEBUFF }
enum Reapply { REFRESH, KEEP_LONGEST, EXTEND, IGNORE }
const REAPPLY_IDS := ["refresh", "keep_longest", "extend", "ignore"]
const REAPPLY_LABELS := ["Обновить длительность", "Оставить большую", "Добавить ходы", "Не менять активный статус"]

const KIND_IDS := ["buff", "debuff"]
const KIND_LABELS := ["Усиление", "Ослабление"]

@export_group("Статус")
@export var status_id := ""
@export var display_name := "Новый статус"
@export_multiline var description := ""
@export_enum("Усиление", "Ослабление") var kind: int = Kind.DEBUFF

@export_group("Длительность и повтор")
@export_range(1, 12, 1) var default_duration := 2
@export_enum("Обновить длительность", "Оставить большую", "Добавить ходы", "Не менять активный статус") var reapply: int = Reapply.REFRESH
@export_range(1, 99, 1) var max_duration := 12

@export_group("Действие в бою")
@export_range(-999, 999, 1) var power_bonus := 0
@export_range(0, 400, 1) var outgoing_damage_percent := 100
@export_range(0, 400, 1) var incoming_damage_percent := 100
@export var remove_on_damage := false

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
		"defaultDuration": default_duration,
		"reapply": REAPPLY_IDS[clampi(reapply, 0, REAPPLY_IDS.size() - 1)],
		"maxDuration": max_duration,
		"powerBonus": power_bonus,
		"outgoingDamagePercent": outgoing_damage_percent,
		"incomingDamagePercent": incoming_damage_percent,
		"removeOnDamage": remove_on_damage,
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
	if kind not in [Kind.BUFF, Kind.DEBUFF]: errors.append("Выберите усиление или ослабление.")
	if default_duration < 1 or default_duration > 12: errors.append("Длительность по умолчанию: от 1 до 12 ходов бойца.")
	if reapply < 0 or reapply >= REAPPLY_IDS.size(): errors.append("Выберите поддерживаемое правило повторного наложения.")
	if max_duration < 1 or max_duration > 99: errors.append("Предел накопления: от 1 до 99 ходов.")
	if reapply == Reapply.EXTEND and max_duration < default_duration: errors.append("Предел накопления не должен быть меньше длительности по умолчанию.")
	if power_bonus < -999 or power_bonus > 999: errors.append("Прибавка к силе приёма: от -999 до 999.")
	for percent in [outgoing_damage_percent, incoming_damage_percent]:
		if percent < 0 or percent > 400: errors.append("Множитель урона: от 0 до 400 процентов.")
	return errors


func content_signature() -> String:
	return "|".join([
		status_id, display_name, description, kind_id(), glyph,
		ui_color.to_html(true), icon.resource_path if icon != null else "",
		str(default_duration), str(reapply), str(max_duration), str(power_bonus),
		str(outgoing_damage_percent), str(incoming_damage_percent), str(remove_on_damage),
	])


func behavior_summary() -> String:
	var lines: Array[String] = ["По умолчанию %d хода бойца; счётчик уменьшается в конце его действия, включая наложение на себя." % default_duration,
		"Повтор: %s%s. Один экземпляр статуса, без отдельных стаков." % [REAPPLY_LABELS[clampi(reapply, 0, REAPPLY_LABELS.size() - 1)], " (предел %d)" % max_duration if reapply == Reapply.EXTEND else ""]]
	if power_bonus != 0: lines.append("Сила наносящего урон приёма: %+d." % power_bonus)
	if outgoing_damage_percent != 100: lines.append("Исходящий прямой урон: %d%%." % outgoing_damage_percent)
	if incoming_damage_percent != 100: lines.append("Входящий урон: %d%%." % incoming_damage_percent)
	if remove_on_damage: lines.append("Снимается после получения ненулевого урона.")
	if status_id in ["wet", "frozen", "burning", "guard", "overheated"]:
		lines.append("Особая стихийная реакция этого ID сохраняется в боевых правилах. Новый ID использует только явно настроенное поведение.")
	return "\n".join(lines)


func _valid_id(value: String) -> bool:
	var clean := value.strip_edges()
	if clean.is_empty():
		return false
	var expression := RegEx.new()
	return expression.compile("^[a-z0-9][a-z0-9_-]*$") == OK and expression.search(clean) != null
