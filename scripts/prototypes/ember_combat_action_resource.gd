@tool
class_name EmberCombatActionResource
extends Resource
## Canonical authored combat command. It describes numbers and selects one of
## the resolver's supported effects; reaction formulas remain in one pure owner.

enum Element { PHYSICAL, WATER, COLD, LIGHTNING, FIRE, AIR, SUPPORT, DUO, EARTH }
enum Target { ENEMY, ALLY, SELF, UNIT, CELL }
enum Effect { DAMAGE, DOUSE, CHILL, SPARK, KINDLE, GUST, GUARD, DEFEND, DUO_PULSE, LIFT_THROW, STEAM_BREACH, EFFECT_CHAIN }
enum Scaling { NONE, STRENGTH, MAGIC }
enum MenuGroup { BASIC, SKILL, MAGIC }

const ELEMENT_IDS := ["physical", "water", "cold", "lightning", "fire", "air", "support", "duo", "earth"]
const TARGET_IDS := ["enemy", "ally", "self", "unit", "cell"]
const EFFECT_IDS := ["damage", "douse", "chill", "spark", "kindle", "gust", "guard", "defend", "duo_pulse", "lift_throw", "steam_breach", "effect_chain"]
const ELEMENT_LABELS := ["Физический", "Вода", "Холод", "Молния", "Огонь", "Воздух", "Поддержка", "Парное", "Земля"]
const TARGET_LABELS := ["Враг", "Союзник", "На себя", "Любой боец", "Клетка"]
const EFFECT_LABELS := ["Урон", "Обливание", "Холод", "Искра", "Уголёк", "Порыв", "Прикрытие", "Защита", "Грозовая связка", "Подъём и бросок", "Паровой пробой", "Цепочка эффектов"]
const SCALING_IDS := ["none", "strength", "magic"]
const SCALING_LABELS := ["Без характеристики", "Сила", "Магия"]
const MENU_GROUP_IDS := ["basic", "skill", "magic"]
const MENU_GROUP_LABELS := ["Основное", "Умение", "Магия"]

@export_group("Действие")
@export var action_id := ""
@export var display_name := "Новое действие"
@export_multiline var hint := ""
@export_multiline var requirements_text := ""
@export_enum("Основное", "Умение", "Магия") var menu_group: int = MenuGroup.BASIC

@export_group("Правила")
@export_enum("Физический", "Вода", "Холод", "Молния", "Огонь", "Воздух", "Поддержка", "Парное", "Земля") var element: int = Element.PHYSICAL
@export_enum("Враг", "Союзник", "На себя", "Любой боец", "Клетка") var target: int = Target.ENEMY
@export_enum("Урон", "Обливание", "Холод", "Искра", "Уголёк", "Порыв", "Прикрытие", "Защита", "Грозовая связка", "Подъём и бросок", "Паровой пробой", "Цепочка эффектов") var effect: int = Effect.DAMAGE
@export_range(0, 999, 1) var power := 0
@export_range(0, 999, 1) var mp_cost := 0
@export_range(-50, 50, 1) var accuracy_modifier := 0
@export_enum("Без характеристики", "Сила", "Магия") var scaling: int = Scaling.STRENGTH
@export_range(1, 999, 1) var delay := 100
@export_range(0, 99, 1) var range_cells := 1
@export_range(0, 12, 1) var throw_range_cells := 0
@export_range(0, 3, 1) var max_lift_weight := 0
## Authored deterministic force. A push happens only when this value is greater
## than the target's push resistance.
@export_range(0, 3, 1) var force := 0

@export_group("Библиотека эффектов")
## Ordered reusable steps. Existing actions retain their stable resolver preset;
## new authored actions can use EFFECT_CHAIN or append shared steps to a preset.
@export var effect_steps: Array[Resource] = []

@export_group("Парная техника")
## The active unit is the initiator. The authored fixed partner joins
## automatically, pays their own MP and receives their own timeline delay.
@export var partner_unit_id := ""
## Height-aware grid distance from the initiator after their staged movement.
@export_range(0, 12, 1) var partner_range_cells := 0
@export_range(0, 999, 1) var partner_mp_cost := 0
@export_range(0, 999, 1) var partner_delay := 0

@export_group("Вид")
@export var ui_color := Color("d8dee9")
@export var icon: Texture2D


func element_id() -> String:
	return str(ELEMENT_IDS[clampi(element, 0, ELEMENT_IDS.size() - 1)])


func target_id() -> String:
	return str(TARGET_IDS[clampi(target, 0, TARGET_IDS.size() - 1)])


func effect_id() -> String:
	return str(EFFECT_IDS[clampi(effect, 0, EFFECT_IDS.size() - 1)])


func element_label() -> String:
	return str(ELEMENT_LABELS[clampi(element, 0, ELEMENT_LABELS.size() - 1)])


func target_label() -> String:
	return str(TARGET_LABELS[clampi(target, 0, TARGET_LABELS.size() - 1)])


func effect_label() -> String:
	return str(EFFECT_LABELS[clampi(effect, 0, EFFECT_LABELS.size() - 1)])


func scaling_id() -> String:
	return str(SCALING_IDS[clampi(scaling, 0, SCALING_IDS.size() - 1)])


func scaling_label() -> String:
	return str(SCALING_LABELS[clampi(scaling, 0, SCALING_LABELS.size() - 1)])


func menu_group_id() -> String:
	return str(MENU_GROUP_IDS[clampi(menu_group, 0, MENU_GROUP_IDS.size() - 1)])


func menu_group_label() -> String:
	return str(MENU_GROUP_LABELS[clampi(menu_group, 0, MENU_GROUP_LABELS.size() - 1)])


func to_definition() -> Dictionary:
	var step_definitions: Array[Dictionary] = []
	for step in effect_steps:
		if step != null:
			step_definitions.append(step.call("to_definition") as Dictionary)
	return {
		"id": action_id.strip_edges(),
		"name": display_name.strip_edges(),
		"element": element_id(),
		"target": target_id(),
		"effect": effect_id(),
		"power": power,
		"mpCost": mp_cost,
		"accuracyModifier": accuracy_modifier,
		"scaling": scaling_id(),
		"delay": delay,
		"range": range_cells,
		"throwRange": throw_range_cells,
		"maxLiftWeight": max_lift_weight,
		"hint": hint.strip_edges(),
		"requirements": requirements_text.strip_edges(),
		"menuGroup": menu_group_id(),
		"menuGroupLabel": menu_group_label(),
		"force": force,
		"effects": step_definitions,
		"partnerId": partner_unit_id.strip_edges(),
		"partnerRange": partner_range_cells,
		"partnerMpCost": partner_mp_cost,
		"partnerDelay": partner_delay,
		"uiColor": ui_color,
		"icon": icon,
		"iconPath": icon.resource_path if icon != null else "",
	}


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if not _valid_id(action_id):
		errors.append("ID действия: используйте a-z, 0-9, _ или -.")
	if display_name.strip_edges().is_empty():
		errors.append("Укажите понятное название действия.")
	if hint.strip_edges().is_empty():
		errors.append("Добавьте короткое описание для боевого интерфейса.")
	if requirements_text.strip_edges().is_empty():
		errors.append("Опишите условия применения для боевого интерфейса.")
	if delay <= 0:
		errors.append("Задержка должна быть больше нуля.")
	if mp_cost < 0:
		errors.append("Стоимость MP не может быть отрицательной.")
	if power > 0 and scaling == Scaling.NONE:
		errors.append("Действию с уроном нужна характеристика Сила или Магия.")
	if power == 0 and scaling != Scaling.NONE:
		errors.append("Действию без урона не нужна атакующая характеристика.")
	if target == Target.SELF and range_cells != 0:
		errors.append("Для действия на себя дальность должна быть 0.")
	var expected_element: int = int({
		Effect.DOUSE: Element.WATER,
		Effect.CHILL: Element.COLD,
		Effect.SPARK: Element.LIGHTNING,
		Effect.KINDLE: Element.FIRE,
		Effect.GUST: Element.AIR,
		Effect.GUARD: Element.SUPPORT,
		Effect.DEFEND: Element.SUPPORT,
		Effect.DUO_PULSE: Element.DUO,
		Effect.STEAM_BREACH: Element.DUO,
	}.get(effect, -1))
	if expected_element >= 0 and element != expected_element:
		errors.append("Стихия не соответствует выбранному эффекту.")
	var expected_target: int = int({
		Effect.GUARD: Target.ALLY,
		Effect.DEFEND: Target.SELF,
		Effect.LIFT_THROW: Target.UNIT,
	}.get(effect, -1 if effect == Effect.EFFECT_CHAIN else Target.ENEMY))
	if expected_target >= 0 and target != expected_target:
		errors.append("Тип цели не соответствует выбранному эффекту.")
	if effect == Effect.LIFT_THROW:
		if throw_range_cells <= 0:
			errors.append("Для броска задайте дальность больше нуля.")
		if max_lift_weight <= 0:
			errors.append("Для броска задайте допустимый вес цели.")
	elif throw_range_cells != 0 or max_lift_weight != 0:
		errors.append("Дальность броска и вес используются только эффектом Подъём и бросок.")
	if effect not in [Effect.GUST, Effect.KINDLE, Effect.STEAM_BREACH] and force != 0:
		errors.append("Сила отбрасывания используется только Порывом, Угольком и Паровым пробоем.")
	if effect == Effect.EFFECT_CHAIN and effect_steps.is_empty():
		errors.append("Для цепочки добавьте хотя бы один эффект из библиотеки.")
	var seen_steps := {}
	for step in effect_steps:
		if step == null:
			errors.append("В цепочке есть пустая ссылка на эффект.")
			continue
		for step_error in step.call("validation_errors"):
			errors.append("Эффект %s: %s" % [str(step.get("display_name")), step_error])
		var step_id := str(step.get("effect_id"))
		if seen_steps.has(step_id):
			errors.append("Эффект %s добавлен в действие дважды." % step_id)
		seen_steps[step_id] = true
	if target == Target.CELL:
		if effect_steps.is_empty():
			errors.append("Действию по клетке нужен эффект из библиотеки.")
		if power != 0:
			errors.append("Прямой урон по клетке пока не поддерживается; используйте шаг эффекта.")
	var is_duo := effect in [Effect.DUO_PULSE, Effect.STEAM_BREACH]
	if is_duo:
		if not _valid_id(partner_unit_id):
			errors.append("Для парной техники укажите стабильный ID другого героя.")
		if partner_range_cells <= 0:
			errors.append("Для парной техники задайте радиус партнёра больше нуля.")
		if partner_mp_cost <= 0:
			errors.append("Парная техника должна расходовать MP партнёра.")
		if partner_delay <= 0:
			errors.append("Парная техника должна задерживать партнёра в очереди.")
	elif (
		not partner_unit_id.is_empty()
		or partner_range_cells != 0
		or partner_mp_cost != 0
		or partner_delay != 0
	):
		errors.append("Партнёр, радиус и его стоимость используются только парной техникой.")
	return errors


func content_signature() -> String:
	var step_signatures := PackedStringArray()
	for step in effect_steps:
		step_signatures.append(str(step.call("content_signature")) if step != null else "null")
	return "|".join([
		action_id, display_name, hint, requirements_text, menu_group_id(),
		element_id(), target_id(), effect_id(),
		str(power), str(mp_cost), str(accuracy_modifier), scaling_id(),
		str(delay), str(range_cells), str(throw_range_cells),
		str(max_lift_weight), str(force), partner_unit_id, str(partner_range_cells),
		str(partner_mp_cost), str(partner_delay), ui_color.to_html(true),
		icon.resource_path if icon != null else "", "||".join(step_signatures),
	])


func _valid_id(value: String) -> bool:
	var clean := value.strip_edges()
	if clean.is_empty():
		return false
	var expression := RegEx.new()
	return expression.compile("^[a-z0-9][a-z0-9_-]*$") == OK and expression.search(clean) != null
