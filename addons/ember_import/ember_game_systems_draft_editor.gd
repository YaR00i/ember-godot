@tool
extends VBoxContainer
## Native fields project existing Resource metadata into an isolated authoring draft.
const Catalog = preload("res://addons/ember_import/ember_game_systems_catalog.gd")
const Store = preload("res://addons/ember_import/ember_game_systems_store.gd")
const Conditions = preload("res://scripts/prototypes/ember_combat_action_conditions.gd")
signal save_requested
signal discard_requested
var _session
var _draft: Resource
var _fields: VBoxContainer
var _status: Label
var _undo: Button
var _redo: Button
var _save: Button
var _item_form: EmberItemEditor
var _item_context := {}
var _rules_summary: Label
var _field_controls := {}
var _group_headers := {}
var _group_keys := {}
var _condition_group := -1
var _condition_refresh: Callable
var _value_condition_refresh: Callable
var _equipment_condition_refresh: Callable
var _effect_query := ""
var _effect_selected_path := ""
const RESISTANCE_LABELS := {"fire_resistance": "Огонь, %", "water_resistance": "Вода, %", "cold_resistance": "Холод, %", "lightning_resistance": "Молния, %", "air_resistance": "Воздух, %", "earth_resistance": "Земля, %", "wet_resistance": "Мокрый: сократить на ходы", "frozen_resistance": "Замёрзший: сократить на ходы", "burning_resistance": "Горение: сократить на ходы"}
const CONTENT_LABELS := {"combat_level": "Уровень", "creature_type": "Тип существа", "weight_class": "Класс веса", "push_resistance": "Стойкость к отбрасыванию", "combat_tags": "Боевые теги (ID)", "battle_color": "Цвет бойца", "portrait": "Портрет", "prototype_roster_order": "Порядок в лаборатории", "prototype_zone": "Лабораторная зона", "prototype_next_at": "Начальная отметка очереди", "target_priority": "Приоритет цели", "action_priority": "Приоритет приёма", "prefer_elemental_reactions": "Предпочитать стихийные реакции", "positioning_behavior": "Выбор позиции", "low_hp_threshold_percent": "Порог здоровья, %", "low_hp_behavior": "Действие при низком здоровье", "accent_color": "Цвет карточки", "intro_text": "Вступительный текст", "party_unit_ids": "Разрешённые герои (порядок расстановки)", "enemy_unit_ids": "Враги (порядок расстановки)", "victory_rule": "Условие победы", "defeat_rule": "Условие поражения", "victory_flag_id": "Флаг победы (ID)", "defeat_flag_id": "Флаг поражения (ID)", "victory_action_script_id": "Цепочка после победы", "defeat_action_script_id": "Цепочка после поражения", "victory_xp": "XP каждому активному герою", "repeatable": "Разрешить повторный бой"}
const ACTION_LABELS := {"menu_group": "Раздел боевого меню", "element": "Стихия", "target": "Тип цели", "effect": "Базовое действие", "power": "Сила прямого урона", "accuracy_modifier": "Поправка к точности", "scaling": "Атакующая характеристика", "throw_range_cells": "Дальность броска", "max_lift_weight": "Допустимый вес цели", "force": "Сила отбрасывания", "partner_range_cells": "Радиус партнёра", "partner_mp_cost": "Стоимость MP партнёра", "partner_delay": "Задержка партнёра", "requirements_text": "Подсказка об условиях (текст)"}
const RULE_LABELS := {"max_stacks": "Предел независимых доз (1 — прежний одиночный статус)","turn_end_hp_change": "HP в конце своего хода (+ лечение / − урон, 0 — выключено)", "target_required_status_ids": "У цели есть все выбранные статусы", "target_forbidden_status_ids": "У цели нет ни одного выбранного статуса", "operation": "Операция", "status_duration": "Длительность (0 — из статуса)", "remove_status_ids": "Снять статусы", "force": "Сила толчка", "elevation_delta": "Изменение высоты", "block_mode": "Преграда", "add_cell_tags": "Добавить теги клетки", "remove_cell_tags": "Убрать теги клетки", "spread_radius": "Радиус распространения", "spread_status_ids": "Перенести статусы", "spread_cell_tags": "Перенести теги", "spread_status_duration": "Длительность из клетки", "spread_to_units": "Переносить на бойцов", "spread_to_cells": "Переносить на клетки", "restore_hp_amount": "Восстановить HP", "move_max_height_delta": "Допустимый перепад высоты", "default_duration": "Ходов по умолчанию", "reapply": "Повторное наложение", "max_duration": "Предел накопленных ходов", "power_bonus": "Прибавка к силе приёма", "outgoing_damage_percent": "Исходящий прямой урон, %", "incoming_damage_percent": "Входящий урон, %", "remove_on_damage": "Снимать при получении урона"}
const EFFECT_FIELDS := {"apply_status": ["status_id", "status_duration"], "remove_status": ["remove_status_ids"], "push": ["force"], "cell_patch": ["elevation_delta", "block_mode", "add_cell_tags", "remove_cell_tags"], "spread": ["spread_radius", "spread_status_ids", "spread_cell_tags", "spread_status_duration", "spread_to_units", "spread_to_cells"], "restore_hp": ["restore_hp_amount"], "move_actor": ["move_max_height_delta"], "activate_focus": []}
const LABELS := {"display_name": "Название", "description": "Описание", "hint": "Описание для игрока", "power": "Сила эффекта", "mp_cost": "Стоимость MP", "delay": "Задержка", "range_cells": "Дальность", "action_ids": "Приёмы", "effect_steps": "Последовательность эффектов", "status_id": "Статус", "ai_profile_id": "Профиль ИИ", "loot_table": "Таблица лута", "partner_unit_id": "Напарник", "entries": "Предметы в таблице", "battlefield": "Боевое поле", "arena_scene": "Сцена арены", "party_unit_ids": "Герои", "enemy_unit_ids": "Враги", "max_hp": "Максимум HP", "max_mp": "Максимум MP", "strength": "Сила", "magic": "Магия", "defense": "Защита", "resistance": "Сопротивление", "speed": "Скорость", "accuracy": "Точность", "luck": "Удача", "move_range": "Перемещение", "jump_height": "Прыжок", "icon": "Иконка", "glyph": "Символ", "ui_color": "Цвет", "team": "Сторона", "requirements_text": "Условия применения"}

func setup(session: RefCounted) -> void:
	_session = session
	_draft = session.draft
	name = "GameSystemsDraftEditor"
	add_theme_constant_override("separation", 8)
	var actions := HFlowContainer.new()
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.name = "GameSystemsDraftActions"
	add_child(actions)
	_undo = _button(actions, "Отменить", "GameSystemsDraftUndo", _undo_draft)
	_redo = _button(actions, "Повторить", "GameSystemsDraftRedo", _redo_draft)
	_save = _button(actions, "Сохранить", "GameSystemsDraftSave", save_requested.emit)
	var close := _button(actions, "К библиотеке", "GameSystemsDraftDiscard", discard_requested.emit)
	close.tooltip_text = "Вернуться к списку. Несохранённые изменения можно сохранить или отбросить с подтверждением."
	_status = Label.new()
	_status.name = "GameSystemsDraftStatus"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	_rules_summary = Label.new()
	_rules_summary.name = "DraftRulesSummary"
	_rules_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rules_summary.modulate = Color("a7c1d1")
	add_child(_rules_summary)
	_fields = VBoxContainer.new()
	_fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fields.add_theme_constant_override("separation", 7)
	add_child(_fields)
	_session.changed.connect(update_status)
	_build_fields()
	update_status()

func update_status() -> void:
	if _session.draft == null or _session.draft != _draft: return
	_undo.disabled = not _session.can_undo()
	_redo.disabled = not _session.can_redo()
	var errors := Store.validation(_session.module, _session.draft)
	_save.disabled = not errors.is_empty() or not _session.has_changes()
	_status.text = ("Не сохранено" if _session.has_changes() else "Сохранено") + ("\n" + _session.last_error if not _session.last_error.is_empty() else "")
	if not errors.is_empty(): _status.text += "\n• " + "\n• ".join(errors)
	_status.modulate = Color("e6bb78") if _session.has_changes() else Color("79d99a")
	_rules_summary.visible = _session.module in ["start", "status", "effect", "action", "unit", "ai", "loot", "encounter"]
	if _rules_summary.visible: _rules_summary.text = str(_session.draft.call("behavior_summary"))
	_update_rule_fields()

func _build_fields() -> void:
	_condition_refresh = Callable()
	_value_condition_refresh = Callable()
	_equipment_condition_refresh = Callable()
	_field_controls = {}
	_group_headers = {}
	_group_keys = {}
	for child in _fields.get_children():
		_fields.remove_child(child)
		child.queue_free()
	if _session.module == "start":
		var form := preload("res://addons/ember_import/ember_game_start_editor.gd").new()
		_fields.add_child(form)
		form.setup(_session)
		return
	if Store.kind(_session.module) == "item":
		_item_form = preload("res://addons/ember_import/ember_item_editor.gd").new()
		_fields.add_child(_item_form)
		_item_form.name = "GameSystemsItemDraft"
		_item_form.setup_document(_session.draft.get("definition"), _item_context)
		_item_form.find_child("SaveItem", true, false).hide()
		_item_form.find_child("CancelItem", true, false).hide()
		_item_form.document_changed.connect(_item_changed)
		return
	var id := Label.new()
	id.text = "ID: " + Store.id_for(_session.module, _session.draft)
	_fields.add_child(id)
	var group := ""
	for property in _session.draft.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_GROUP:
			if str(property.name) == "Resource": continue
			var heading := Label.new()
			heading.text = str(property.name)
			heading.add_theme_font_size_override("font_size", 16)
			_fields.add_child(heading)
			group = str(property.name)
			_group_headers[group] = heading
			_group_keys[group] = []
			continue
		if not (int(property.usage) & PROPERTY_USAGE_EDITOR) or not (int(property.usage) & PROPERTY_USAGE_STORAGE): continue
		var key := str(property.name)
		if key in ["script", "resource_name", "resource_local_to_scene"] or key == Store.SPECS[Store.kind(_session.module)][1]: continue
		if _session.module == "action" and key in Conditions.FIELDS:
			if key == Conditions.FIELDS[0]:
				var builder := _condition_builder()
				_fields.add_child(builder)
				_field_controls["application_conditions"] = [builder]
				_group_keys[group].append("application_conditions")
			continue
		var label := Label.new()
		label.text = str(LABELS.get(key, RULE_LABELS.get(key, key.capitalize())))
		if _session.module == "status" and key == "kind": label.text = "Категория"
		if _session.module == "action" and ACTION_LABELS.has(key): label.text = ACTION_LABELS[key]
		if _session.module in ["unit", "ai", "loot", "encounter"] and CONTENT_LABELS.has(key): label.text = CONTENT_LABELS[key]
		if _session.module == "unit" and RESISTANCE_LABELS.has(key): label.text = RESISTANCE_LABELS[key]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_fields.add_child(label)
		_field_controls[key] = [label]
		if _group_keys.has(group): _group_keys[group].append(key)
		var value: Variant = _session.draft.get(key)
		var control := _field(property, value)
		if control != null:
			control.name = "DraftField_" + key
			control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_fields.add_child(control)
			_field_controls[key].append(control)
	_update_rule_fields()

func _update_rule_fields() -> void:
	if _session.draft == null or _session.draft != _draft: return
	if _session.module == "effect":
		var allowed: Array = ["display_name", "description", "operation", "ui_color", "icon", "target_required_status_ids", "target_forbidden_status_ids"] + EFFECT_FIELDS.get(_session.draft.call("operation_id"), [])
		for key in _field_controls:
			for control in _field_controls[key]: control.visible = key in allowed
	elif _session.module == "status" and _field_controls.has("max_duration"):
		var multiple: bool = int(_session.draft.max_stacks) > 1
		for control in _field_controls.reapply: control.visible = not multiple
		for control in _field_controls.max_duration: control.visible = not multiple and int(_session.draft.reapply) == 2
	elif _session.module == "action":
		if _condition_refresh.is_valid(): _condition_refresh.call()
		if _value_condition_refresh.is_valid(): _value_condition_refresh.call()
		if _equipment_condition_refresh.is_valid(): _equipment_condition_refresh.call()
		var preset := str(_session.draft.call("effect_id"))
		for key in ["throw_range_cells", "max_lift_weight", "force", "partner_unit_id", "partner_range_cells", "partner_mp_cost", "partner_delay"]:
			var relevant := (preset == "lift_throw" if key in ["throw_range_cells", "max_lift_weight"] else preset in ["gust", "kindle", "steam_breach"] if key == "force" else preset in ["duo_pulse", "steam_breach"])
			var stored: Variant = _session.draft.get(key)
			# Keep incompatible nonzero values reachable so the author can correct them.
			for control in _field_controls[key]: control.visible = relevant or (str(stored) != "" if key == "partner_unit_id" else int(stored) != 0)
	else: return
	for group in _group_keys:
		_group_headers[group].visible = (_group_keys[group] as Array).any(func(key: String) -> bool: return _field_controls[key][0].visible)

func _field(property: Dictionary, value: Variant) -> Control:
	var key := str(property.name)
	if _session.module == "unit" and key == "action_ids": return _action_list(value)
	if _session.module == "unit" and key == "ai_profile_id": return _catalog_picker(key, "ai", value, false)
	if _session.module == "unit" and key == "loot_table": return _catalog_picker(key, "loot", value, true)
	if _session.module == "encounter":
		if key in ["party_unit_ids", "enemy_unit_ids"]: return _action_list(value, key, "unit", "hero" if key == "party_unit_ids" else "enemy")
		if key == "battlefield": return _catalog_picker(key, "field", value, true)
		if key == "arena_scene": return _arena_picker(value)
		if key in ["victory_action_script_id", "defeat_action_script_id"]: return _continuation_picker(key, str(value))
		if key in ["victory_rule", "defeat_rule"]:
			var rules := OptionButton.new()
			rules.add_item("Все враги побеждены" if key == "victory_rule" else "Все герои побеждены", 0)
			if int(value) != 0:
				rules.add_item("Не поддерживается: " + str(value), int(value))
				rules.select(1)
			rules.item_selected.connect(func(index: int) -> void: _set_value(key, rules.get_item_id(index)))
			return rules
	if _session.module == "effect" and key == "status_id": return _status_picker(str(value))
	if _session.module == "effect" and key in ["remove_status_ids", "spread_status_ids", "target_required_status_ids", "target_forbidden_status_ids"]: return _status_choices(key, value)
	if _session.module == "field" and key in ["width", "height", "terrain_kinds", "elevations", "blocked", "groups", "party_deployment_cells", "enemy_deployment_cells"]:
		var label := Label.new()
		label.text = "Клетки и размер редактируются в прежнем редакторе поля после сохранения."
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return label
	if int(property.type) == TYPE_INT and int(property.hint) == PROPERTY_HINT_ENUM:
		var options := OptionButton.new()
		var index := 0
		for option in str(property.hint_string).split(","):
			var pieces := option.split(":")
			var enum_value := int(pieces[1]) if pieces.size() > 1 else index
			options.add_item(pieces[0], enum_value)
			if enum_value == int(value): options.select(index)
			index += 1
		options.item_selected.connect(func(at: int) -> void: _set_value(key, options.get_item_id(at)))
		return options
	if int(property.type) in [TYPE_INT, TYPE_FLOAT]:
		var number := SpinBox.new()
		number.min_value = -999999
		number.max_value = 999999
		number.step = 1 if int(property.type) == TYPE_INT else 0.1
		if int(property.hint) == PROPERTY_HINT_RANGE:
			var range_parts := str(property.hint_string).split(",")
			if range_parts.size() >= 2:
				number.min_value = float(range_parts[0])
				number.max_value = float(range_parts[1])
		number.value = float(value)
		number.value_changed.connect(func(next: float) -> void: _set_value(key, int(next) if int(property.type) == TYPE_INT else next))
		return number
	if int(property.type) == TYPE_BOOL:
		var toggle := CheckBox.new()
		toggle.button_pressed = bool(value)
		toggle.toggled.connect(func(next: bool) -> void: _set_value(key, next))
		return toggle
	if int(property.type) == TYPE_COLOR:
		var color := ColorPickerButton.new()
		color.color = value
		color.color_changed.connect(func(next: Color) -> void: _set_value(key, next))
		return color
	if int(property.type) == TYPE_STRING:
		if int(property.hint) == PROPERTY_HINT_MULTILINE_TEXT:
			var text := TextEdit.new()
			text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
			text.custom_minimum_size.y = 90
			text.text = str(value)
			text.text_changed.connect(func() -> void: _set_value(key, text.text))
			return text
		var line := LineEdit.new()
		line.text = str(value)
		line.text_changed.connect(func(next: String) -> void: _set_value(key, next))
		return line
	if int(property.type) == TYPE_PACKED_STRING_ARRAY:
		var line := LineEdit.new()
		line.text = ", ".join(value)
		line.placeholder_text = "ID через запятую"
		line.text_changed.connect(func(next: String) -> void:
			var ids := PackedStringArray()
			for id in next.split(",", false): ids.append(id.strip_edges())
			_set_value(key, ids)
		)
		return line
	if int(property.type) == TYPE_OBJECT and Engine.is_editor_hint():
		var picker := EditorResourcePicker.new()
		picker.base_type = str(property.hint_string) if int(property.hint) == PROPERTY_HINT_RESOURCE_TYPE else "Resource"
		picker.edited_resource = value
		picker.resource_changed.connect(func(next: Resource) -> void: _set_value(key, next))
		picker.resource_selected.connect(func(_resource: Resource, _inspect: bool) -> void:
			_session.last_error = "Это общий ресурс. Для изменения откройте его раздел после сохранения черновика."
			update_status()
		)
		return picker
	if int(property.type) == TYPE_ARRAY and key in ["effect_steps", "entries"]: return _resource_array(key, value)
	var label := Label.new()
	label.text = "Значение сохраняется без изменения; подробная настройка — в редакторе этого раздела."
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _catalog_picker(key: String, module: String, current: Variant, shared: bool) -> OptionButton:
	var choice := OptionButton.new()
	choice.add_item("— не назначено —")
	choice.set_item_metadata(0, null if shared else "")
	for record in Catalog.entries(module):
		var value: Variant = record.resource if shared else str(record.id)
		choice.add_item(str(record.name))
		choice.set_item_metadata(choice.item_count - 1, value)
		if value == current or (shared and current != null and not current.resource_path.is_empty() and current.resource_path == value.resource_path): choice.select(choice.item_count - 1)
	if choice.selected == 0 and ((shared and current != null) or (not shared and not str(current).is_empty())):
		choice.add_item("Вне библиотеки: " + (current.resource_path if shared else str(current)))
		choice.set_item_metadata(choice.item_count - 1, current)
		choice.select(choice.item_count - 1)
	choice.item_selected.connect(func(index: int) -> void: _set_value(key, choice.get_item_metadata(index)))
	return choice

func _arena_picker(current: Resource) -> OptionButton:
	var choice := OptionButton.new()
	choice.tooltip_text = "Наследованная сцена общего боевого поля: окружение, свет и камера. В игре и тесте используется поле выбранной встречи."
	choice.add_item("— выберите сцену арены —")
	choice.set_item_metadata(0, null)
	var directory := DirAccess.open("res://scenes/combat/arenas")
	if directory != null:
		for filename in directory.get_files():
			if not filename.ends_with(".tscn"): continue
			var scene := load("res://scenes/combat/arenas/" + filename) as PackedScene
			if scene == null: continue
			choice.add_item(filename.get_basename())
			choice.set_item_metadata(choice.item_count - 1, scene)
			if current != null and scene.resource_path == current.resource_path: choice.select(choice.item_count - 1)
	if current != null and choice.selected == 0:
		choice.add_item("Другая сцена: " + current.resource_path)
		choice.set_item_metadata(choice.item_count - 1, current)
		choice.select(choice.item_count - 1)
	choice.item_selected.connect(func(index: int) -> void: _set_value("arena_scene", choice.get_item_metadata(index)))
	return choice

func _continuation_picker(key: String, current: String) -> OptionButton:
	var choice := OptionButton.new()
	choice.add_item("— без цепочки —")
	choice.set_item_metadata(0, "")
	for id in EmberInteractionContent.action_script_ids():
		choice.add_item(id)
		choice.set_item_metadata(choice.item_count - 1, id)
		if id == current: choice.select(choice.item_count - 1)
	if not current.is_empty() and choice.selected == 0:
		choice.add_item("Не найден: " + current)
		choice.set_item_metadata(choice.item_count - 1, current)
		choice.select(choice.item_count - 1)
	choice.item_selected.connect(func(index: int) -> void: _set_value(key, str(choice.get_item_metadata(index))))
	return choice

func _item_picker(current: String, row: int) -> OptionButton:
	var choice := OptionButton.new()
	choice.name = "DraftLootItem_%d" % row
	choice.add_item("— выберите предмет —")
	choice.set_item_metadata(0, "")
	for record in Catalog.entries("item"):
		choice.add_item(str(record.name))
		choice.set_item_metadata(choice.item_count - 1, str(record.id))
		if str(record.id) == current: choice.select(choice.item_count - 1)
	if not current.is_empty() and choice.selected == 0:
		choice.add_item("Не найден: " + current)
		choice.set_item_metadata(choice.item_count - 1, current)
		choice.select(choice.item_count - 1)
	choice.item_selected.connect(func(index: int) -> void: _edit_entry(str(choice.get_item_metadata(index)), row, "item_id"))
	return choice

func _status_picker(current: String) -> OptionButton:
	var choice := OptionButton.new()
	choice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	choice.add_item("— выберите статус —")
	choice.set_item_metadata(0, "")
	var found := current.is_empty()
	for status in Catalog.Statuses.resources():
		choice.add_item(str(status.display_name))
		choice.set_item_metadata(choice.item_count - 1, status.status_id)
		if str(status.status_id) == current:
			choice.select(choice.item_count - 1)
			found = true
	if not found:
		choice.add_item("Не найден: " + current)
		choice.set_item_metadata(choice.item_count - 1, current)
		choice.select(choice.item_count - 1)
	choice.item_selected.connect(func(index: int) -> void: _set_value("status_id", str(choice.get_item_metadata(index))))
	return choice

func _condition_rules() -> Dictionary:
	var rules: Dictionary = _draft.condition_groups[_condition_group].duplicate(true) if _condition_group >= 0 and _condition_group < _draft.condition_groups.size() else _draft.application_conditions()
	rules.erase(Conditions.GROUP_FIELD)
	# A malformed saved group stays in the draft/validation feedback until repaired
	# or explicitly removed. Only this display copy filters unrenderable rows.
	for key in Conditions.LEAF_FIELDS:
		var values: Variant = rules.get(key, [])
		var rows: Array = []
		if typeof(values) in [TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY]:
			for value in values:
				if (value is String if key in Conditions.STATUS_FIELDS else value is Dictionary): rows.append(value)
		rules[key] = PackedStringArray(rows) if key in Conditions.STATUS_FIELDS else rows
	return rules

func _condition_get(key: String) -> Variant:
	var rules := _condition_rules()
	if key in Conditions.STATUS_FIELDS: return PackedStringArray(rules.get(key, []))
	var rows: Array[Dictionary] = []
	rows.assign(rules.get(key, []))
	return rows

func _condition_errors(rules: Dictionary) -> Array[String]:
	return Conditions.group_validation(rules, _draft.target_id()) if _condition_group >= 0 else Conditions.validation_errors(rules, _draft.target_id())

func _set_condition_value(key: String, value: Variant, field_key := "") -> void:
	if _condition_group < 0:
		_set_value(key, value, field_key)
		return
	var next: Array[Dictionary] = _draft.condition_groups.duplicate(true)
	if _condition_group >= next.size(): return
	next[_condition_group][key] = value
	_set_value(Conditions.GROUP_FIELD, next, ":group%d:%s%s" % [_condition_group, key, field_key] if not field_key.is_empty() else "")

func _condition_group_controls(box: VBoxContainer) -> void:
	if _condition_group >= _draft.condition_groups.size(): _condition_group = -1
	var hint := Label.new()
	hint.text = "Обязательные условия и все группы соединены И. Внутри группы выберите И или ИЛИ. Вложенных групп нет."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	var selector := OptionButton.new()
	selector.name = "DraftConditionGroup"
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selector.fit_to_longest_item = false
	selector.add_item("Обязательные условия (И)")
	for index in _draft.condition_groups.size():
		selector.add_item("Группа %d — %s" % [index + 1, Conditions.GROUP_MODES.get(_draft.condition_groups[index].get("mode", ""), "неизвестный режим")])
	selector.select(_condition_group + 1)
	box.add_child(selector)
	selector.item_selected.connect(func(index: int) -> void:
		if _session.draft != _draft: return
		_condition_group = index - 1
		_build_fields()
	)
	var row := HBoxContainer.new()
	box.add_child(row)
	_button(row, "Добавить группу", "DraftAddConditionGroup", func() -> void:
		if _session.draft != _draft: return
		var next: Array[Dictionary] = _draft.condition_groups.duplicate(true)
		next.append({"mode": "any"})
		_set_value(Conditions.GROUP_FIELD, next)
		_condition_group = next.size() - 1
		_build_fields()
	)
	if _condition_group < 0: return
	var mode := _value_option("DraftConditionGroupMode", Conditions.GROUP_MODES, str(_draft.condition_groups[_condition_group].get("mode", "")))
	mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode.fit_to_longest_item = false
	box.add_child(mode)
	mode.item_selected.connect(func(index: int) -> void:
		if _session.draft != _draft: return
		_set_condition_value("mode", mode.get_item_metadata(index))
		_build_fields()
	)
	_button(row, "Удалить группу", "DraftRemoveConditionGroup", func() -> void:
		if _session.draft != _draft: return
		var next: Array[Dictionary] = _draft.condition_groups.duplicate(true)
		next.remove_at(_condition_group)
		_set_value(Conditions.GROUP_FIELD, next)
		_condition_group = -1
		_build_fields()
	)

func _condition_builder() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "DraftStatusConditions"
	_condition_group_controls(box)
	var hint := Label.new()
	hint.text = "Активный статус имеет оставшиеся ходы больше нуля. Режим выбранной группы применяется ко всем её строкам: статусам, HP/MP и экипировке."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	for key in Conditions.STATUS_FIELDS:
		for id in _condition_get(key):
			var row := HBoxContainer.new()
			box.add_child(row)
			var label := Label.new()
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			var status := Catalog.Statuses.resource(str(id))
			label.text = "%s: %s" % [Conditions.LABELS[key], str(status.display_name) if status != null else "Не найден: " + str(id)]
			row.add_child(label)
			_button(row, "Убрать", "DraftRemoveCondition_%s_%s" % [key, id], func() -> void:
				if _session.draft != _draft: return
				var next := PackedStringArray(_condition_get(key))
				while id in next: next.remove_at(next.find(id))
				_set_condition_value(key, next)
				_build_fields()
			)
	var row := HBoxContainer.new()
	box.add_child(row)
	var subject := OptionButton.new()
	subject.name = "DraftConditionSubject"
	for name in ["Исполнитель", "Цель"]: subject.add_item(name)
	row.add_child(subject)
	var presence := OptionButton.new()
	presence.name = "DraftConditionPresence"
	for name in ["Должен иметь", "Не должен иметь"]: presence.add_item(name)
	row.add_child(presence)
	var status := OptionButton.new()
	status.name = "DraftConditionStatus"
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for record in Catalog.entries("status"):
		status.add_item(str(record.name))
		status.set_item_metadata(status.item_count - 1, str(record.id))
	status.fit_to_longest_item = false
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(status)
	var add := Button.new()
	add.name = "DraftAddCondition"
	add.text = "Добавить условие"
	box.add_child(add)
	add.pressed.connect(func() -> void:
		if _session.draft != _draft: return
		if add.disabled or status.selected < 0: return
		var key := ("actor" if subject.selected == 0 else "target") + ("_required_status_ids" if presence.selected == 0 else "_forbidden_status_ids")
		var next := PackedStringArray(_condition_get(key))
		next.append(str(status.get_item_metadata(status.selected)))
		_set_condition_value(key, next)
		_build_fields()
	)
	var feedback := Label.new()
	feedback.name = "DraftConditionFeedback"
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(feedback)
	_condition_refresh = func() -> void:
		var cell_target: bool = _session.draft.target_id() == "cell"
		subject.set_item_disabled(1, cell_target)
		if cell_target and subject.selected == 1: subject.select(0)
		add.disabled = status.selected < 0
		feedback.text = "Создайте статус в общей библиотеке." if add.disabled else ""
		if status.selected < 0: return
		var key := ("actor" if subject.selected == 0 else "target") + ("_required_status_ids" if presence.selected == 0 else "_forbidden_status_ids")
		var id := str(status.get_item_metadata(status.selected))
		var rules: Dictionary = _condition_rules()
		if id in rules[key]:
			add.disabled = true
			feedback.text = "Такое условие уже добавлено."
			return
		rules[key].append(id)
		var errors := _condition_errors(rules)
		add.disabled = not errors.is_empty()
		feedback.text = errors[0] if not errors.is_empty() else "Для цели-клетки доступны условия исполнителя." if cell_target else ""
	for choice in [subject, presence, status]:
		choice.item_selected.connect(func(_index: int) -> void: _condition_refresh.call())
	_condition_refresh.call()
	box.add_child(_value_condition_builder())
	box.add_child(_equipment_condition_builder())
	return box

func _value_condition_builder() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "DraftValueConditions"
	var hint := Label.new()
	hint.text = "HP и MP проверяются до расхода и эффектов. ≥ — не меньше; ≤ — не больше. Процент требует ненулевого максимума."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	for index in _condition_get(Conditions.VALUE_FIELD).size():
		var data: Dictionary = _condition_get(Conditions.VALUE_FIELD)[index]
		var card := VBoxContainer.new()
		box.add_child(card)
		var heading := HBoxContainer.new()
		card.add_child(heading)
		var row := HBoxContainer.new()
		card.add_child(row)
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.add_child(label)
		if Conditions.value_errors(data).is_empty():
			label.text = "%s · %s" % [Conditions.SUBJECT_LABELS[data.subject], data.stat.to_upper()]
			var comparison := _value_option("DraftValueComparison_%d" % index, Conditions.COMPARISON_LABELS, data.comparison)
			row.add_child(comparison)
			comparison.item_selected.connect(func(selected: int) -> void: _edit_value_condition(index, "comparison", comparison.get_item_metadata(selected)))
			var number := SpinBox.new()
			number.name = "DraftValueThreshold_%d" % index
			number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			number.max_value = 100 if data.unit == "percent" else Conditions.MAX_POINTS
			number.allow_greater = true
			number.allow_lesser = true
			number.value = data.value
			row.add_child(number)
			number.value_changed.connect(func(value: float) -> void: _edit_value_condition(index, "value", int(value)))
			var measure := _value_option("DraftValueUnit_%d" % index, {"points": "Очки", "percent": "% максимума"}, data.unit)
			row.add_child(measure)
			measure.item_selected.connect(func(selected: int) -> void:
				_edit_value_condition(index, "unit", measure.get_item_metadata(selected))
				number.max_value = 100 if selected == 1 else Conditions.MAX_POINTS
			)
		else: label.text = "Некорректное сохранённое условие: " + str(data)
		_button(heading, "Убрать", "DraftRemoveValueCondition_%d" % index, func() -> void:
			if _session.draft != _draft: return
			var next: Array[Dictionary] = _condition_get(Conditions.VALUE_FIELD).duplicate(true)
			next.remove_at(index)
			_set_condition_value(Conditions.VALUE_FIELD, next)
			_build_fields()
		)
	var row := HBoxContainer.new()
	box.add_child(row)
	var subject := _value_option("DraftValueSubject", Conditions.SUBJECT_LABELS, "actor")
	row.add_child(subject)
	var stat := _value_option("DraftValueStat", {"hp": "HP · Здоровье", "mp": "MP · Энергия"}, "hp")
	row.add_child(stat)
	var measure := _value_option("DraftValueUnit", {"points": "Очки", "percent": "% максимума"}, "percent")
	measure.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(measure)
	row = HBoxContainer.new()
	box.add_child(row)
	var comparison := _value_option("DraftValueComparison", {"gte": "≥ Не меньше", "lte": "≤ Не больше"}, "gte")
	row.add_child(comparison)
	var number := SpinBox.new()
	number.name = "DraftValueThreshold"
	number.max_value = 100
	number.value = 30
	number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(number)
	var add := _button(row, "Добавить порог", "DraftAddValueCondition", func() -> void:
		if _session.draft != _draft: return
		var next: Array[Dictionary] = _condition_get(Conditions.VALUE_FIELD).duplicate(true)
		next.append(_value_input(subject, stat, comparison, measure, number))
		var proposed: Dictionary = _condition_rules()
		proposed[Conditions.VALUE_FIELD] = next
		if not _condition_errors(proposed).is_empty(): return
		_set_condition_value(Conditions.VALUE_FIELD, next)
		_build_fields()
	)
	var feedback := Label.new()
	feedback.name = "DraftValueFeedback"
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(feedback)
	_value_condition_refresh = func() -> void:
		if _session.draft != _draft: return
		var cell_target: bool = _session.draft.target_id() == "cell"
		subject.set_item_disabled(1, cell_target)
		if cell_target and subject.selected == 1: subject.select(0)
		var proposed: Dictionary = _condition_rules()
		proposed[Conditions.VALUE_FIELD].append(_value_input(subject, stat, comparison, measure, number))
		var errors := _condition_errors(proposed)
		add.disabled = not errors.is_empty()
		feedback.text = errors[0] if not errors.is_empty() else "Для цели-клетки доступны только пороги исполнителя." if cell_target else ""
	for choice in [subject, stat, comparison, measure]:
		choice.item_selected.connect(func(_index: int) -> void:
			number.max_value = 100 if measure.get_item_metadata(measure.selected) == "percent" else Conditions.MAX_POINTS
			_value_condition_refresh.call()
		)
	number.value_changed.connect(func(_value: float) -> void: _value_condition_refresh.call())
	_value_condition_refresh.call()
	return box

func _value_option(node_name: String, options: Dictionary, selected: String) -> OptionButton:
	var choice := OptionButton.new()
	choice.name = node_name
	for id in options:
		choice.add_item(options[id])
		choice.set_item_metadata(choice.item_count - 1, id)
		if id == selected: choice.select(choice.item_count - 1)
	return choice

func _value_input(subject: OptionButton, stat: OptionButton, comparison: OptionButton, measure: OptionButton, number: SpinBox) -> Dictionary:
	return {"subject": subject.get_item_metadata(subject.selected), "stat": stat.get_item_metadata(stat.selected), "comparison": comparison.get_item_metadata(comparison.selected), "unit": measure.get_item_metadata(measure.selected), "value": int(number.value)}

func _edit_value_condition(index: int, key: String, value: Variant) -> void:
	if _session.draft != _draft: return
	var next: Array[Dictionary] = _condition_get(Conditions.VALUE_FIELD).duplicate(true)
	next[index][key] = value
	_set_condition_value(Conditions.VALUE_FIELD, next, ":%d:%s" % [index, key] if key == "value" else "")

func _equipment_condition_builder() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "DraftEquipmentConditions"
	var hint := Label.new()
	hint.text = "Экипировка: предмет должен быть надет, наличие в сумке не считается."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	for index in _condition_get(Conditions.EQUIPMENT_FIELD).size():
		var data: Dictionary = _condition_get(Conditions.EQUIPMENT_FIELD)[index]
		var card := VBoxContainer.new()
		box.add_child(card)
		var heading := HBoxContainer.new()
		card.add_child(heading)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = Conditions.equipment_summary(data) if Conditions.equipment_shape_errors(data).is_empty() else "Некорректное сохранённое условие: " + str(data)
		heading.add_child(label)
		_button(heading, "Убрать", "DraftRemoveEquipmentCondition_%d" % index, func() -> void:
			if _session.draft != _draft: return
			var next: Array[Dictionary] = _condition_get(Conditions.EQUIPMENT_FIELD).duplicate(true)
			next.remove_at(index)
			_set_condition_value(Conditions.EQUIPMENT_FIELD, next)
			_build_fields()
		)
		if not Conditions.equipment_shape_errors(data).is_empty(): continue
		var row := HBoxContainer.new()
		card.add_child(row)
		var subject := _equipment_option("DraftEquipmentSubject_%d" % index, Conditions.SUBJECT_LABELS, data.subject)
		row.add_child(subject)
		var mode := _equipment_option("DraftEquipmentMode_%d" % index, Conditions.EQUIPMENT_MODES, data.mode)
		row.add_child(mode)
		row = HBoxContainer.new()
		card.add_child(row)
		var slot := _equipment_slot_picker("DraftEquipmentSlot_%d" % index, data.mode, data.slot)
		row.add_child(slot)
		var item := _equipment_item_picker("DraftEquipmentItem_%d" % index, data.slot, data.item_id)
		item.visible = data.mode == "item"
		row.add_child(item)
		for pair in [[subject, "subject"], [mode, "mode"], [slot, "slot"], [item, "item_id"]]:
			var choice: OptionButton = pair[0]
			var key: String = pair[1]
			choice.item_selected.connect(func(selected: int) -> void: _edit_equipment_condition(index, key, str(choice.get_item_metadata(selected))))
	var row := HBoxContainer.new()
	box.add_child(row)
	var subject := _equipment_option("DraftEquipmentSubject", Conditions.SUBJECT_LABELS, "actor")
	row.add_child(subject)
	var mode := _equipment_option("DraftEquipmentMode", Conditions.EQUIPMENT_MODES, "item")
	row.add_child(mode)
	row = HBoxContainer.new()
	box.add_child(row)
	var slot := _equipment_slot_picker("DraftEquipmentSlot", "item", "")
	row.add_child(slot)
	var item := _equipment_item_picker("DraftEquipmentItem", "", "")
	row.add_child(item)
	var add := _button(box, "Добавить условие экипировки", "DraftAddEquipmentCondition", func() -> void:
		if _session.draft != _draft: return
		var next: Array[Dictionary] = _condition_get(Conditions.EQUIPMENT_FIELD).duplicate(true)
		next.append(_equipment_input(subject, mode, slot, item))
		var proposed: Dictionary = _condition_rules()
		proposed[Conditions.EQUIPMENT_FIELD] = next
		if not _condition_errors(proposed).is_empty(): return
		_set_condition_value(Conditions.EQUIPMENT_FIELD, next)
		_build_fields()
	)
	var feedback := Label.new()
	feedback.name = "DraftEquipmentFeedback"
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(feedback)
	_equipment_condition_refresh = func() -> void:
		if _session.draft != _draft: return
		var cell_target: bool = _session.draft.target_id() == "cell"
		subject.set_item_disabled(1, cell_target)
		if cell_target and subject.selected == 1: subject.select(0)
		var needs_item: bool = mode.get_item_metadata(mode.selected) == "item"
		slot.set_item_disabled(0, not needs_item)
		if not needs_item and slot.selected == 0: slot.select(1)
		item.visible = needs_item
		var proposed: Dictionary = _condition_rules()
		proposed[Conditions.EQUIPMENT_FIELD].append(_equipment_input(subject, mode, slot, item))
		var errors := _condition_errors(proposed)
		add.disabled = not errors.is_empty()
		feedback.text = errors[0] if not errors.is_empty() else "Для цели-клетки доступны условия исполнителя." if cell_target else ""
	for choice in [subject, mode, slot, item]:
		choice.item_selected.connect(func(_index: int) -> void: _equipment_condition_refresh.call())
	# Refill only on explicit slot selection; current unavailable ID stays visible.
	slot.item_selected.connect(func(_index: int) -> void:
		var current := str(item.get_item_metadata(item.selected))
		var replacement := _equipment_item_picker("DraftEquipmentReplacement", str(slot.get_item_metadata(slot.selected)), current)
		item.clear()
		for index in replacement.item_count:
			item.add_item(replacement.get_item_text(index))
			item.set_item_metadata(index, replacement.get_item_metadata(index))
		item.select(replacement.selected)
		replacement.free()
		_equipment_condition_refresh.call()
	)
	_equipment_condition_refresh.call()
	return box

func _equipment_option(node_name: String, options: Dictionary, selected: String) -> OptionButton:
	var choice := _value_option(node_name, options, selected)
	choice.fit_to_longest_item = false
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return choice

func _equipment_slot_picker(node_name: String, mode: String, selected: String) -> OptionButton:
	var options := {"": "Любой подходящий слот"}
	options.merge(Conditions.Equipment.SLOT_LABELS)
	var choice := _equipment_option(node_name, options, selected)
	choice.set_item_disabled(0, mode != "item")
	return choice

func _equipment_item_picker(node_name: String, slot: String, current: String) -> OptionButton:
	var options := {"": "— выберите предмет —"}
	for record in Catalog.entries("item"):
		var allowed := Conditions.Equipment.slots_for_item(record.data)
		if not allowed.is_empty() and (slot.is_empty() or slot in allowed): options[str(record.id)] = str(record.name)
	if not current.is_empty() and not options.has(current): options[current] = "Недоступен или не найден: " + current
	return _equipment_option(node_name, options, current)

func _equipment_input(subject: OptionButton, mode: OptionButton, slot: OptionButton, item: OptionButton) -> Dictionary:
	var kind := str(mode.get_item_metadata(mode.selected))
	return {"subject": str(subject.get_item_metadata(subject.selected)), "slot": str(slot.get_item_metadata(slot.selected)), "mode": kind, "item_id": str(item.get_item_metadata(item.selected)) if kind == "item" else ""}

func _edit_equipment_condition(index: int, key: String, value: String) -> void:
	if _session.draft != _draft: return
	var next: Array[Dictionary] = _condition_get(Conditions.EQUIPMENT_FIELD).duplicate(true)
	next[index][key] = value
	if key == "mode" and value != "item":
		next[index].item_id = ""
		if next[index].slot.is_empty(): next[index].slot = "weapon"
	_set_condition_value(Conditions.EQUIPMENT_FIELD, next)
	_build_fields()


func _status_choices(key: String, current: Variant) -> VBoxContainer:
	var box := VBoxContainer.new()
	var ids: Array = Array(Catalog.Statuses.ids())
	for id in current:
		if str(id) not in ids: ids.append(str(id))
	for id in ids:
		var toggle := CheckBox.new()
		toggle.name = "DraftStatusChoice_" + str(id)
		var status := Catalog.Statuses.resource(str(id))
		toggle.text = str(status.display_name) if status != null else "Не найден: " + str(id)
		toggle.tooltip_text = str(id)
		toggle.button_pressed = id in current
		toggle.toggled.connect(func(checked: bool) -> void:
			if _session.draft != _draft: return
			var next := PackedStringArray(_session.draft.get(key))
			if checked and id not in next: next.append(str(id))
			elif not checked:
				while id in next: next.remove_at(next.find(id))
			_set_value(key, next)
		)
		box.add_child(toggle)
	return box

func _resource_array(key: String, values: Array) -> Control:
	var box := VBoxContainer.new()
	for index in values.size():
		var card := VBoxContainer.new()
		box.add_child(card)
		var row := HBoxContainer.new()
		card.add_child(row)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = "%d · %s" % [index + 1, str(values[index].get("display_name")) if key == "effect_steps" and values[index] != null else "Пустая ссылка" if key == "effect_steps" else "Строка лута"]
		row.add_child(label)
		_button(row, "↑", "DraftRowUp_%s_%d" % [key, index], _move_row.bind(key, index, -1)).disabled = index == 0
		_button(row, "↓", "DraftRowDown_%s_%d" % [key, index], _move_row.bind(key, index, 1)).disabled = index == values.size() - 1
		_button(row, "Убрать", "DraftRowRemove_%s_%d" % [key, index], _remove_row.bind(key, index))
		if key == "effect_steps" and values[index] != null:
			var summary := Label.new()
			summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			summary.text = str(values[index].call("behavior_summary"))
			summary.tooltip_text = values[index].resource_path
			card.add_child(summary)
		if key == "entries" and values[index] != null:
			var entry: Resource = values[index]
			var picker := _item_picker(str(entry.item_id), index)
			card.add_child(picker)
			for pair in [["chance_percent", "Шанс, %", 0.1, 100.0, 0.1], ["minimum_count", "Минимум", 1.0, 999.0, 1.0], ["maximum_count", "Максимум", 1.0, 999.0, 1.0]]:
				var caption := Label.new()
				caption.text = pair[1]
				card.add_child(caption)
				var number := SpinBox.new()
				number.name = "DraftLoot_%s_%d" % [pair[0], index]
				number.min_value = pair[2]
				number.max_value = pair[3]
				number.step = pair[4]
				number.value = entry.get(pair[0])
				number.value_changed.connect(func(next: float) -> void: _edit_entry(str(next), index, str(pair[0])))
				card.add_child(number)
	if key == "effect_steps":
		_effect_picker(box, values)
	else:
		_button(box, "Добавить строку лута", "DraftAddLootRow", func() -> void:
			if _session.draft != _draft: return
			var next: Array = _session.draft.get(key).duplicate()
			next.append(preload("res://scripts/prototypes/ember_combat_loot_entry_resource.gd").new())
			_set_value(key, next)
			_build_fields()
		)
	return box


func _effect_picker(box: VBoxContainer, values: Array) -> void:
	var search := LineEdit.new()
	search.name = "DraftEffectSearch"
	search.placeholder_text = "Найти эффект: название, ID, описание или условие…"
	search.clear_button_enabled = true
	search.text = _effect_query
	box.add_child(search)
	var choice := OptionButton.new()
	choice.name = "DraftEffectChoice"
	choice.fit_to_longest_item = false
	choice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(choice)
	var preview := Label.new()
	preview.name = "DraftEffectPreview"
	preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(preview)
	var hint := Label.new()
	hint.text = "Добавляется ссылка на общий эффект. Для отдельного варианта сначала создайте его копию в «Эффектах»."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color("a7c1d1")
	box.add_child(hint)
	var add := _button(box, "Добавить общий эффект", "DraftAddEffect", func() -> void:
		if _session.draft != _draft or choice.selected < 0 or choice.is_item_disabled(choice.selected): return
		var next: Array = _session.draft.effect_steps.duplicate()
		next.append(choice.get_item_metadata(choice.selected))
		_set_value("effect_steps", next)
		_build_fields()
	)
	var records := Catalog.entries("effect")
	var used := []
	for value in values:
		if value != null: used.append(str(value.get("effect_id")))
	var describe := func() -> void:
		add.disabled = choice.selected < 0 or choice.is_item_disabled(choice.selected)
		if choice.selected < 0:
			preview.text = "Эффекты не найдены. Измените поиск." if choice.item_count == 0 else "Все найденные эффекты уже добавлены в цепочку."
			preview.tooltip_text = ""
			return
		var effect: Resource = choice.get_item_metadata(choice.selected)
		_effect_selected_path = effect.resource_path
		preview.text = "%s · %s\n%s\n%s" % [effect.display_name, effect.effect_id, effect.description, effect.call("behavior_summary")]
		preview.tooltip_text = effect.resource_path
	var filter := func() -> void:
		choice.clear()
		var selected := -1
		var first := -1
		for record in records:
			var summary := str(record.resource.call("behavior_summary"))
			var text := "%s %s %s %s" % [record.name, record.id, record.description, summary]
			if not _effect_query.strip_edges().is_empty() and not text.to_lower().contains(_effect_query.strip_edges().to_lower()): continue
			var index := choice.item_count
			var already_added: bool = str(record.id) in used
			choice.add_item(str(record.name) + (" · уже в цепочке" if already_added else ""))
			choice.set_item_metadata(index, record.resource)
			choice.set_item_tooltip(index, str(record.id) + "\n" + summary + "\n" + str(record.path))
			choice.set_item_disabled(index, already_added)
			if not already_added:
				if first < 0: first = index
				if str(record.path) == _effect_selected_path: selected = index
		choice.select(selected if selected >= 0 else first)
		describe.call()
	choice.item_selected.connect(func(_index: int) -> void:
		if _session.draft == _draft: describe.call()
	)
	search.text_changed.connect(func(text: String) -> void:
		if _session.draft != _draft: return
		_effect_query = text
		filter.call()
	)
	filter.call()


func _action_list(values: PackedStringArray, key := "action_ids", module := "action", team := "") -> Control:
	var box := VBoxContainer.new()
	if key == "enemy_unit_ids":
		var hint := Label.new()
		hint.text = "Один шаблон можно добавить несколько раз. Каждая строка — отдельный враг; порядок задаёт точку расстановки. Карточка шаблона общая."
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(hint)
	var tag := "Action" if key == "action_ids" else "Roster_" + key
	var records := Catalog.entries(module)
	var names := {}
	for record in records: names[str(record.id)] = str(record.name)
	for index in values.size():
		var row := HBoxContainer.new()
		box.add_child(row)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = "%d · %s" % [index + 1, names.get(values[index], "Не найден: " + values[index])]
		label.tooltip_text = values[index]
		row.add_child(label)
		_button(row, "↑", "Draft%sUp_%d" % [tag, index], _move_action.bind(index, -1, key)).disabled = index == 0
		_button(row, "↓", "Draft%sDown_%d" % [tag, index], _move_action.bind(index, 1, key)).disabled = index == values.size() - 1
		_button(row, "Убрать", "Draft%sRemove_%d" % [tag, index], _remove_action.bind(index, key))
	var choice := OptionButton.new()
	choice.name = "Draft%sChoice" % tag
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for record in records:
		if key != "enemy_unit_ids" and str(record.id) in values: continue
		if not team.is_empty() and str(record.resource.call("team_id")) != team: continue
		choice.add_item(str(record.name) + (" · уже %d" % values.count(str(record.id)) if key == "enemy_unit_ids" and str(record.id) in values else ""))
		choice.set_item_metadata(choice.item_count - 1, str(record.id))
	box.add_child(choice)
	_button(box, "Добавить приём" if module == "action" else "Добавить участника", "DraftAdd%s" % tag, func() -> void:
		if _session.draft != _draft or choice.selected < 0: return
		var next := PackedStringArray(_session.draft.get(key))
		next.append(str(choice.get_item_metadata(choice.selected)))
		_set_value(key, next)
		_build_fields()
	).disabled = choice.item_count == 0
	return box

func _move_action(index: int, offset: int, key := "action_ids") -> void:
	if _session.draft != _draft: return
	var next := PackedStringArray(_session.draft.get(key))
	var entry := next[index]
	next.remove_at(index)
	next.insert(index + offset, entry)
	_set_value(key, next)
	_build_fields()

func _remove_action(index: int, key := "action_ids") -> void:
	if _session.draft != _draft: return
	var next := PackedStringArray(_session.draft.get(key))
	next.remove_at(index)
	_set_value(key, next)
	_build_fields()

func _edit_entry(text: String, index: int, key: String) -> void:
	if _session.draft != _draft: return
	var next: Array = _session.draft.entries.duplicate()
	var entry: Resource = Store.clone(next[index])
	entry.set(key, text if key == "item_id" else float(text) if key == "chance_percent" else int(text))
	next[index] = entry
	_set_value("entries", next, "loot:%d:%s" % [index, key])

func _move_row(key: String, index: int, offset: int) -> void:
	if _session.draft != _draft: return
	var next: Array = _session.draft.get(key).duplicate()
	var entry: Variant = next.pop_at(index)
	next.insert(index + offset, entry)
	_set_value(key, next)
	_build_fields()

func _remove_row(key: String, index: int) -> void:
	if _session.draft != _draft: return
	var next: Array = _session.draft.get(key).duplicate()
	next.remove_at(index)
	_set_value(key, next)
	_build_fields()

func _item_changed(document: Dictionary, field_key: String) -> void:
	if _session.draft != _draft: return
	_set_value("definition", document, field_key)

func _undo_draft() -> void:
	if _session.draft != _draft: return
	_session.undo()
	_build_fields()

func _redo_draft() -> void:
	if _session.draft != _draft: return
	_session.redo()
	_build_fields()

func _button(parent: Node, text: String, node_name: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	if not node_name.is_empty(): button.name = node_name
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _set_value(property: String, value: Variant, field_key := "") -> void:
	if _draft != null and _session.draft == _draft:
		_session.set_value(property, value, field_key)
