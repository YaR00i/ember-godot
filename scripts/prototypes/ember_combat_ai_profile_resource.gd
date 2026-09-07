@tool
class_name EmberCombatAiProfileResource
extends Resource
## Reusable deterministic decision policy. It ranks previews produced by the
## shared resolver; it never applies damage/statuses or owns movement rules.

enum TargetPriority { LOWEST_HP, HIGHEST_HP, NEAREST, FARTHEST }
enum ActionPriority { UNIT_ORDER, HIGHEST_POWER, FASTEST }
enum LowHpBehavior { KEEP_FIGHTING, DEFEND_IF_AVAILABLE }
enum PositioningBehavior { HOLD_POSITION, MOVE_TO_ACTION }

const TARGET_IDS := ["lowest_hp", "highest_hp", "nearest", "farthest"]
const TARGET_LABELS := ["Самая раненая цель", "Самая стойкая цель", "Ближайшая цель", "Дальняя цель"]
const ACTION_IDS := ["unit_order", "highest_power", "fastest"]
const ACTION_LABELS := ["Порядок карточек бойца", "Максимальная сила", "Минимальная задержка"]
const LOW_HP_IDS := ["keep_fighting", "defend_if_available"]
const LOW_HP_LABELS := ["Продолжать бой", "Защищаться, если возможно"]
const POSITIONING_IDS := ["hold_position", "move_to_action"]
const POSITIONING_LABELS := ["Держать позицию", "Искать клетку для действия"]

@export_group("Профиль AI")
@export var profile_id := ""
@export var display_name := "Новый профиль"
@export_multiline var description := ""

@export_group("Решение хода")
@export_enum("Самая раненая", "Самая стойкая", "Ближайшая", "Дальняя") var target_priority: int = TargetPriority.LOWEST_HP
@export_enum("Порядок карточек", "Максимальная сила", "Минимальная задержка") var action_priority: int = ActionPriority.UNIT_ORDER
@export var prefer_elemental_reactions := false
@export_enum("Держать позицию", "Искать клетку для действия") var positioning_behavior: int = PositioningBehavior.MOVE_TO_ACTION

@export_group("Низкое здоровье")
@export_range(0, 100, 1, "suffix:%") var low_hp_threshold_percent := 0
@export_enum("Продолжать бой", "Защищаться при возможности") var low_hp_behavior: int = LowHpBehavior.KEEP_FIGHTING

@export_group("Вид")
@export var accent_color := Color("ef8d78")
@export var icon: Texture2D


func target_priority_id() -> String:
	return str(TARGET_IDS[clampi(target_priority, 0, TARGET_IDS.size() - 1)])


func target_priority_label() -> String:
	return str(TARGET_LABELS[clampi(target_priority, 0, TARGET_LABELS.size() - 1)])


func action_priority_id() -> String:
	return str(ACTION_IDS[clampi(action_priority, 0, ACTION_IDS.size() - 1)])


func action_priority_label() -> String:
	return str(ACTION_LABELS[clampi(action_priority, 0, ACTION_LABELS.size() - 1)])


func low_hp_behavior_id() -> String:
	return str(LOW_HP_IDS[clampi(low_hp_behavior, 0, LOW_HP_IDS.size() - 1)])


func low_hp_behavior_label() -> String:
	return str(LOW_HP_LABELS[clampi(low_hp_behavior, 0, LOW_HP_LABELS.size() - 1)])


func positioning_behavior_id() -> String:
	return str(POSITIONING_IDS[clampi(positioning_behavior, 0, POSITIONING_IDS.size() - 1)])


func positioning_behavior_label() -> String:
	return str(POSITIONING_LABELS[clampi(positioning_behavior, 0, POSITIONING_LABELS.size() - 1)])


func to_definition() -> Dictionary:
	return {
		"id": profile_id.strip_edges(),
		"name": display_name.strip_edges(),
		"description": description.strip_edges(),
		"targetPriority": target_priority_id(),
		"actionPriority": action_priority_id(),
		"preferReactions": prefer_elemental_reactions,
		"positioningBehavior": positioning_behavior_id(),
		"lowHpThresholdPercent": low_hp_threshold_percent,
		"lowHpBehavior": low_hp_behavior_id(),
		"accentColor": accent_color,
		"icon": icon,
	}


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if not _valid_id(profile_id):
		errors.append("ID профиля: используйте a-z, 0-9, _ или -.")
	if display_name.strip_edges().is_empty():
		errors.append("Укажите понятное название профиля.")
	if description.strip_edges().is_empty():
		errors.append("Опишите поведение профиля для автора встречи.")
	if low_hp_behavior == LowHpBehavior.DEFEND_IF_AVAILABLE and low_hp_threshold_percent <= 0:
		errors.append("Для защитного поведения задайте порог здоровья выше 0%.")
	return errors


func content_signature() -> String:
	return "|".join([
		profile_id, display_name, description, target_priority_id(), action_priority_id(),
		positioning_behavior_id(),
		str(prefer_elemental_reactions), str(low_hp_threshold_percent), low_hp_behavior_id(),
		accent_color.to_html(true), icon.resource_path if icon != null else "",
	])


func _valid_id(value: String) -> bool:
	var clean := value.strip_edges()
	if clean.is_empty():
		return false
	var expression := RegEx.new()
	return expression.compile("^[a-z0-9][a-z0-9_-]*$") == OK and expression.search(clean) != null
