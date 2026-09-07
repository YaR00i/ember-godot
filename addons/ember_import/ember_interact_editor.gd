@tool
class_name EmberInteractEditor
extends VBoxContainer
## Focused kind-dependent form over the existing EmberInteract fields/catalogs.
## It emits normalized values; scene mutation stays in Inspector actions.

const QuestState = preload("res://scripts/ember_quest_state.gd")
const QuestStore = preload("res://addons/ember_import/ember_quest_store.gd")
const TypedValueEditor = preload("res://addons/ember_import/ember_typed_value_editor.gd")
const VisualLibraryPopup = preload("res://addons/ember_import/ember_visual_library_popup.gd")
const MapVisuals = preload("res://scripts/ember_map_visuals.gd")

signal save_requested(values: Dictionary)

var _inputs: Dictionary = {}
var _field_rows: Dictionary = {}
var _field_labels: Dictionary = {}
var _validation: Label
var _suggested_completion_flag := ""
var _map_library: EmberVisualLibraryPopup
var _map_library_mode := ""
var _target_region_library_button: Button
var _quest_flag_library: EmberVisualLibraryPopup
var _quest_flag_target: LineEdit
var _quest_binding_hint: Label
var _summary: Label
var _advanced_toggle: Button
var _advanced_open := false


func setup(
	values: Dictionary,
	is_new: bool,
	current_map_id: String,
	suggested_completion_flag := "",
) -> void:
	name = "InteractEditor"
	_suggested_completion_flag = suggested_completion_flag
	var bound_quest_id := str(values.get("quest_id", "")).strip_edges()
	var legacy_quest := {}
	if bound_quest_id.is_empty():
		legacy_quest = QuestStore.document_for_status_flag(str(values.get("script_id", "")))
		bound_quest_id = str(legacy_quest.get("id", ""))
	var action_script_id := str(values.get("script_id", ""))
	if not legacy_quest.is_empty():
		action_script_id = ""
	_advanced_open = _has_authored_advanced_values(values)
	add_theme_constant_override("separation", 4)
	var current_kind := str(values.get("kind", "door"))
	var authorable_kinds := EmberInteract.KINDS.duplicate()
	# Chest contents/state belong to imported map loot. Do not offer a shell
	# Interact that looks authorable but cannot receive loot in this form.
	if current_kind != "chest":
		authorable_kinds.erase("chest")
	add_child(_option_row("kind", "Тип", authorable_kinds, current_kind, true))
	add_child(_summary_panel())
	add_child(_option_row(
		"trigger_id", "Триггер", EmberInteractionContent.region_ids(current_map_id), str(values.get("trigger_id", "")),
	))
	var quest_row := _option_row(
		"quest_id", "Задание", QuestStore.ids(), bound_quest_id,
	)
	add_child(quest_row)
	(_inputs.get("quest_id") as OptionButton).tooltip_text = "Источник статуса маркера. statusFlagId и текущая иконка вычисляются из выбранного EmberQuestResource."
	var target_map_row := _option_row(
		"target_map_id", "Карта", EmberInteractionContent.map_ids(), str(values.get("target_map_id", "")),
	)
	var target_map_library := _library_button("OpenTargetMapLibrary", "Карты…", _open_target_map_library)
	target_map_row.add_child(target_map_library)
	add_child(target_map_row)
	var target_region_row := _option_row(
		"target_region_id",
		"Точка входа",
		EmberInteractionContent.region_ids(str(values.get("target_map_id", ""))),
		str(values.get("target_region_id", "")),
	)
	_target_region_library_button = _library_button(
		"OpenTargetRegionLibrary", "Точки…", _open_target_region_library,
	)
	target_region_row.add_child(_target_region_library_button)
	add_child(target_region_row)
	add_child(_option_row(
		"script_id", "Цепочка", EmberInteractionContent.script_ref_ids(), action_script_id,
	))
	add_child(_option_row(
		"shop_id", "Магазин", EmberInteractionContent.shop_ids(), str(values.get("shop_id", "")),
	))
	add_child(_text_row("note", "Заметка для автора", str(values.get("note", ""))))
	_advanced_toggle = Button.new()
	_advanced_toggle.name = "ToggleInteractAdvanced"
	_advanced_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_advanced_toggle.pressed.connect(_toggle_advanced)
	add_child(_advanced_toggle)
	add_child(_option_row(
		"quest_status", "Fallback (без события)", QuestState.STATUSES, str(values.get("quest_status", "available")),
	))
	add_child(_text_row("icon_id", "Своя иконка (обычно пусто)", str(values.get("icon_id", ""))))
	var rules_title := Label.new()
	rules_title.name = "LaunchRulesTitle"
	rules_title.text = "ПРАВИЛА ЗАПУСКА"
	rules_title.modulate = Color(0.55, 0.82, 0.88)
	rules_title.add_theme_font_size_override("font_size", 11)
	add_child(rules_title)
	_quest_binding_hint = Label.new()
	_quest_binding_hint.name = "QuestBindingHint"
	_quest_binding_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quest_binding_hint.modulate = Color(0.62, 0.72, 0.82)
	_quest_binding_hint.add_theme_font_size_override("font_size", 11)
	add_child(_quest_binding_hint)
	add_child(_activation_row(str(values.get("activation_mode", "press"))))
	var condition_row := _text_row(
		"condition_flag_id",
		"Если флаг",
		str(values.get("condition_flag_id", "")),
	)
	var condition_input := _inputs.get("condition_flag_id") as LineEdit
	var condition_library := _library_button(
		"OpenConditionQuestFlagLibrary",
		"Выбрать статус задания или цель",
		_open_quest_flag_library.bind(condition_input),
	)
	condition_row.add_child(condition_library)
	add_child(condition_row)
	add_child(_typed_value_row(
		"condition_value",
		"Равно",
		values.get("condition_value", values.get("condition_expected", true)),
	))
	add_child(_option_row(
		"fallback_script_id",
		"Иначе",
		EmberInteractionContent.script_ref_ids(),
		str(values.get("fallback_script_id", "")),
	))
	add_child(_check_row("one_shot", "Только 1 раз", bool(values.get("one_shot", false))))
	add_child(_text_row(
		"completion_flag_id",
		"Флаг выполнения",
		str(values.get("completion_flag_id", "")),
	))
	var kind_option := _inputs.get("kind") as OptionButton
	kind_option.item_selected.connect(_kind_changed)
	var map_option := _inputs.get("target_map_id") as OptionButton
	map_option.item_selected.connect(_target_map_changed)
	_target_region_library_button.disabled = _option_value("target_map_id").is_empty()
	var condition := _inputs.get("condition_flag_id") as LineEdit
	condition.placeholder_text = "например: met_blacksmith"
	condition.tooltip_text = "Пусто — основная цепочка доступна всегда. Да означает строгое boolean true; Нет также принимает ещё не созданный флаг."
	condition.text_changed.connect(_sync_rule_rows.unbind(1))
	var expected := _inputs.get("condition_value") as EmberTypedValueEditor
	expected.tooltip_text = "Точное ожидаемое значение. Для статуса задания обычно текст active или done; Нет также принимает отсутствующий boolean-флаг."
	var fallback := _inputs.get("fallback_script_id") as OptionButton
	fallback.tooltip_text = "Необязательно. Эта цепочка выполняется, когда условие не прошло; без неё F-подсказка скрывается."
	var once := _inputs.get("one_shot") as CheckBox
	once.tooltip_text = "Основная цепочка исчезнет после успешного завершения. Отмена и запасная ветка запуск не расходуют."
	once.toggled.connect(_on_one_shot_toggled)
	var completion := _inputs.get("completion_flag_id") as LineEdit
	completion.placeholder_text = suggested_completion_flag
	completion.tooltip_text = "Устойчивый ключ в Ember save. После успешной основной цепочки сюда записывается Да."
	var activation := _inputs.get("activation_mode") as OptionButton
	activation.tooltip_text = "F показывает подсказку рядом с зоной. При входе запускает тот же сценарий автоматически один раз на пересечение объёма."
	for field in ["trigger_id", "quest_id", "target_map_id", "target_region_id", "script_id", "shop_id", "activation_mode"]:
		var option := _inputs.get(field) as OptionButton
		if option != null:
			option.item_selected.connect(_update_summary.unbind(1))
	_kind_changed(kind_option.selected)

	_validation = Label.new()
	_validation.name = "InteractValidation"
	_validation.visible = false
	_validation.modulate = Color(1.0, 0.48, 0.42)
	_validation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_validation)

	var actions := HBoxContainer.new()
	add_child(actions)
	var save := Button.new()
	save.name = "SaveInteract"
	save.text = "Добавить" if is_new else "Сохранить"
	save.pressed.connect(_submit)
	actions.add_child(save)
	var hint := Label.new()
	hint.text = "Ctrl+Z отменяет"
	hint.modulate = Color(0.64, 0.64, 0.68)
	actions.add_child(hint)


func _option_row(
	field: String,
	title: String,
	values: Array,
	current: String,
	use_kind_labels := false,
) -> Control:
	var row := HBoxContainer.new()
	row.name = "FieldRow_%s" % field
	_field_rows[field] = row
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 105.0
	label.modulate = Color(0.72, 0.72, 0.75)
	row.add_child(label)
	_field_labels[field] = label
	var option := OptionButton.new()
	option.name = "Field_%s" % field
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fill_option(option, values, current, use_kind_labels, field)
	row.add_child(option)
	_inputs[field] = option
	return row


func _text_row(field: String, title: String, current: String) -> Control:
	var row := HBoxContainer.new()
	row.name = "FieldRow_%s" % field
	_field_rows[field] = row
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 105.0
	label.modulate = Color(0.72, 0.72, 0.75)
	row.add_child(label)
	_field_labels[field] = label
	var input := LineEdit.new()
	input.name = "Field_%s" % field
	input.text = current
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input)
	_inputs[field] = input
	return row


func _check_row(field: String, title: String, current: bool) -> Control:
	var row := HBoxContainer.new()
	row.name = "FieldRow_%s" % field
	_field_rows[field] = row
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 105.0
	label.modulate = Color(0.72, 0.72, 0.75)
	row.add_child(label)
	_field_labels[field] = label
	var input := CheckBox.new()
	input.name = "Field_%s" % field
	input.button_pressed = current
	input.text = "Да" if current else "Нет"
	input.toggled.connect(func(enabled: bool) -> void: input.text = "Да" if enabled else "Нет")
	row.add_child(input)
	_inputs[field] = input
	return row


func _typed_value_row(field: String, title: String, current: Variant) -> Control:
	var row := HBoxContainer.new()
	row.name = "FieldRow_%s" % field
	_field_rows[field] = row
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 105.0
	label.modulate = Color(0.72, 0.72, 0.75)
	row.add_child(label)
	_field_labels[field] = label
	var input := TypedValueEditor.new() as EmberTypedValueEditor
	input.name = "Field_%s" % field
	input.setup(current, "ConditionExpected")
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input)
	_inputs[field] = input
	return row


func _library_button(node_name: String, title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = "▦"
	button.tooltip_text = title
	button.pressed.connect(callback)
	return button


func _activation_row(current: String) -> Control:
	var row := _option_row(
		"activation_mode",
		"Активация",
		EmberInteract.ACTIVATION_MODES,
		current,
	)
	var option := _inputs.get("activation_mode") as OptionButton
	if option != null:
		for index in option.item_count:
			match str(option.get_item_metadata(index)):
				"press": option.set_item_text(index, "Клавиша F")
				"enter": option.set_item_text(index, "При входе")
	return row


func _fill_option(
	option: OptionButton,
	values: Array,
	current: String,
	use_kind_labels := false,
	field := "",
) -> void:
	option.clear()
	if not use_kind_labels:
		option.add_item("— не выбрано —")
		option.set_item_metadata(option.item_count - 1, "")
	for value in values:
		var value_id := str(value)
		option.add_item(
			_kind_title(value_id) if use_kind_labels else _option_display_title(field, value_id)
		)
		option.set_item_metadata(option.item_count - 1, value_id)
	var selected := -1
	for index in option.item_count:
		if str(option.get_item_metadata(index)) == current:
			selected = index
			break
	if selected < 0 and not current.is_empty():
		option.add_item("%s  ⚠" % current)
		option.set_item_metadata(option.item_count - 1, current)
		selected = option.item_count - 1
	option.select(maxi(selected, 0))


func _kind_title(kind: String) -> String:
	return EmberSceneAuthoring.interact_kind_title(kind)


func _option_value(field: String) -> String:
	var option := _inputs.get(field) as OptionButton
	if option == null or option.selected < 0:
		return ""
	return str(option.get_item_metadata(option.selected))


func _kind_changed(_index: int) -> void:
	var kind := _option_value("kind")
	var visible_fields: Array[String]
	match kind:
		"door": visible_fields = ["trigger_id", "target_map_id", "target_region_id", "activation_mode", "condition_flag_id", "condition_value", "fallback_script_id", "note"]
		"talk": visible_fields = ["script_id", "activation_mode", "condition_flag_id", "condition_value", "fallback_script_id", "one_shot", "completion_flag_id", "note"]
		"shop": visible_fields = ["shop_id", "script_id", "activation_mode", "condition_flag_id", "condition_value", "fallback_script_id", "one_shot", "completion_flag_id", "note"]
		"quest_marker": visible_fields = ["quest_id", "script_id", "quest_status", "icon_id", "note"]
		"trigger", "custom": visible_fields = ["script_id", "activation_mode", "condition_flag_id", "condition_value", "fallback_script_id", "one_shot", "completion_flag_id", "note"]
		_: visible_fields = ["trigger_id", "script_id", "note"]
	for field in _field_rows:
		if field != "kind":
			(_field_rows[field] as Control).visible = field in visible_fields
	var rules_title := get_node_or_null("LaunchRulesTitle") as Control
	if rules_title != null:
		rules_title.visible = _advanced_open and kind in ["door", "talk", "shop", "trigger", "custom"]
	_update_field_titles(kind)
	_sync_rule_rows()
	_update_summary()


func _sync_rule_rows() -> void:
	var kind := _option_value("kind")
	var supports_rules := kind in ["door", "talk", "shop", "trigger", "custom"]
	if _advanced_toggle != null:
		_advanced_toggle.visible = supports_rules or kind == "quest_marker"
		_advanced_toggle.text = "%s Дополнительно" % ("▾" if _advanced_open else "▸")
	if _quest_binding_hint != null:
		_quest_binding_hint.visible = kind == "quest_marker" or (supports_rules and _advanced_open)
		_quest_binding_hint.text = (
			"Маркер сам берёт роль и стандартную иконку из «События задания» в цепочке: начать, цель или завершить. Future/locked/completed события в игре скрыты."
			if kind == "quest_marker"
			else "Квест: привяжите к объекту/зоне цепочку и добавьте в ней «Событие задания». Для места выберите «При входе»."
		)
	var condition := _inputs.get("condition_flag_id") as LineEdit
	var has_condition := supports_rules and _advanced_open and condition != null and not condition.text.strip_edges().is_empty()
	if _field_rows.has("condition_flag_id"):
		(_field_rows.condition_flag_id as Control).visible = supports_rules and _advanced_open
	for field in ["condition_value", "fallback_script_id"]:
		if _field_rows.has(field):
			(_field_rows[field] as Control).visible = has_condition
	var supports_once := kind in ["talk", "shop", "trigger", "custom"]
	if _field_rows.has("one_shot"):
		(_field_rows.one_shot as Control).visible = supports_once and _advanced_open
	var once := _inputs.get("one_shot") as CheckBox
	if _field_rows.has("completion_flag_id"):
		(_field_rows.completion_flag_id as Control).visible = supports_once and _advanced_open and once != null and once.button_pressed
	for field in ["quest_status", "icon_id"]:
		if _field_rows.has(field):
			(_field_rows[field] as Control).visible = kind == "quest_marker" and _advanced_open
	var rules_title := get_node_or_null("LaunchRulesTitle") as Control
	if rules_title != null:
		rules_title.visible = supports_rules and _advanced_open


func _toggle_advanced() -> void:
	_advanced_open = not _advanced_open
	_sync_rule_rows()


func _has_authored_advanced_values(values: Dictionary) -> bool:
	var icon := str(values.get("icon_id", "")).strip_edges()
	var custom_icon := not icon.is_empty() and icon not in [
		"quest", "quest_available", "quest_active", "quest_done",
	]
	return (
		custom_icon
		or not str(values.get("condition_flag_id", "")).strip_edges().is_empty()
		or not str(values.get("fallback_script_id", "")).strip_edges().is_empty()
		or bool(values.get("one_shot", false))
		or not str(values.get("completion_flag_id", "")).strip_edges().is_empty()
	)


func _summary_panel() -> Control:
	var panel := PanelContainer.new()
	panel.name = "InteractSummaryPanel"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.13, 0.15)
	style.border_color = Color(0.26, 0.55, 0.64)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	panel.add_theme_stylebox_override("panel", style)
	_summary = Label.new()
	_summary.name = "InteractOutcomeSummary"
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.modulate = Color(0.72, 0.88, 0.92)
	panel.add_child(_summary)
	return panel


func _update_summary() -> void:
	if _summary == null:
		return
	var kind := _option_value("kind")
	var activation := "При входе" if _option_value("activation_mode") == "enter" else "Клавиша F"
	match kind:
		"door":
			var map_id := _option_value("target_map_id")
			var region_id := _option_value("target_region_id")
			_summary.text = "РЕЗУЛЬТАТ В ИГРЕ\n%s → перейти в %s / %s" % [activation, map_id if not map_id.is_empty() else "не выбрано", region_id if not region_id.is_empty() else "старт"]
		"talk": _summary.text = "РЕЗУЛЬТАТ В ИГРЕ\n%s → запустить диалог или цепочку «%s»" % [activation, _selected_option_text("script_id")]
		"shop": _summary.text = "РЕЗУЛЬТАТ В ИГРЕ\n%s → открыть магазин «%s»" % [activation, _selected_option_text("shop_id")]
		"quest_marker": _summary.text = "РЕЗУЛЬТАТ В ИГРЕ\nF → событие цепочки «%s»; роль и иконка вычисляются из задания «%s»" % [_selected_option_text("script_id"), _selected_option_text("quest_id")]
		"trigger", "custom": _summary.text = "РЕЗУЛЬТАТ В ИГРЕ\n%s → выполнить цепочку «%s»" % [activation, _selected_option_text("script_id")]
		"chest": _summary.text = "РЕЗУЛЬТАТ В ИГРЕ\nСундук использует loot и one-shot состояние импортированной карты."
		_: _summary.text = "РЕЗУЛЬТАТ В ИГРЕ\nЗаполните основные поля взаимодействия."


func _selected_option_text(field: String) -> String:
	var option := _inputs.get(field) as OptionButton
	if option == null or option.selected < 0 or _option_value(field).is_empty():
		return "не выбрано"
	return option.get_item_text(option.selected)


func _update_field_titles(kind: String) -> void:
	_set_field_title("quest_id", "Какое задание")
	_set_field_title("script_id", str({
		"talk": "Диалог / цепочка",
		"shop": "Перед магазином",
		"quest_marker": "Событие / цепочка",
	}.get(kind, "Что выполнить")))
	_set_field_title("trigger_id", "Связанный триггер" if kind == "door" else "Триггер карты")
	_set_field_title("shop_id", "Какой магазин")


func _set_field_title(field: String, title: String) -> void:
	var label := _field_labels.get(field) as Label
	if label != null:
		label.text = title


func _option_display_title(field: String, value_id: String) -> String:
	match field:
		"script_id":
			var resolved := EmberInteractionContent.resolve_script_ref(value_id)
			var data: Dictionary = resolved.get("data", {})
			var title := str(data.get("nameRu", "")).strip_edges()
			return "%s · %s" % [title, value_id] if not title.is_empty() else value_id
		"shop_id":
			var shop := EmberInteractionContent.shop_view(value_id)
			var title := str(shop.get("nameRu", "")).strip_edges()
			return "%s · %s" % [title, value_id] if not title.is_empty() else value_id
		"quest_id":
			var quest := QuestStore.document(value_id)
			var title := str(quest.get("titleRu", "")).strip_edges()
			return "%s · %s" % [title, value_id] if not title.is_empty() else value_id
		"quest_status":
			match value_id:
				"available": return "Доступно (!)"
				"active": return "В работе (компас)"
				"done": return "Завершено (галочка)"
	return value_id


func _on_one_shot_toggled(enabled: bool) -> void:
	var completion := _inputs.get("completion_flag_id") as LineEdit
	if enabled and completion != null and completion.text.strip_edges().is_empty():
		completion.text = _suggested_completion_flag
	_sync_rule_rows()


func _target_map_changed(_index: int) -> void:
	var region := _inputs.get("target_region_id") as OptionButton
	if region != null:
		_fill_option(region, EmberInteractionContent.region_ids(_option_value("target_map_id")), "", false, "target_region_id")
	if _target_region_library_button != null:
		_target_region_library_button.disabled = _option_value("target_map_id").is_empty()
	_update_summary()


func _open_target_map_library() -> void:
	_ensure_map_library()
	_map_library_mode = "map"
	_map_library.open_library("КАРТЫ EMBER", MapVisuals.map_entries(), _option_value("target_map_id"))


func _open_target_region_library() -> void:
	var map_id := _option_value("target_map_id")
	if map_id.is_empty():
		return
	_ensure_map_library()
	_map_library_mode = "region"
	_map_library.open_library(
		"ТОЧКИ ВХОДА · %s" % map_id,
		MapVisuals.region_entries(map_id),
		_option_value("target_region_id"),
	)


func _ensure_map_library() -> void:
	if _map_library != null:
		return
	_map_library = VisualLibraryPopup.new() as EmberVisualLibraryPopup
	_map_library.value_chosen.connect(_choose_map_library_value)
	add_child(_map_library)


func _open_quest_flag_library(target: LineEdit) -> void:
	if target == null:
		return
	if _quest_flag_library == null:
		_quest_flag_library = VisualLibraryPopup.new() as EmberVisualLibraryPopup
		_quest_flag_library.name = "InteractQuestFlagLibrary"
		_quest_flag_library.value_chosen.connect(_choose_quest_flag_value)
		add_child(_quest_flag_library)
	_quest_flag_target = target
	_quest_flag_library.open_library(
		"УСЛОВИЕ ЗАДАНИЯ",
		QuestStore.flag_reference_entries(),
		target.text.strip_edges(),
		Vector2i(0, 0),
		220,
	)


func _choose_quest_flag_value(value: String) -> void:
	if _quest_flag_target != null and is_instance_valid(_quest_flag_target):
		_quest_flag_target.text = value
		_quest_flag_target.text_changed.emit(value)
	_quest_flag_target = null


func _choose_map_library_value(value: String) -> void:
	if _map_library_mode == "map":
		_select_option_value(_inputs.get("target_map_id") as OptionButton, value)
		_target_map_changed(0)
	elif _map_library_mode == "region":
		_select_option_value(_inputs.get("target_region_id") as OptionButton, value)


func _select_option_value(option: OptionButton, value: String) -> void:
	if option == null:
		return
	for index in option.item_count:
		if str(option.get_item_metadata(index)) == value:
			option.select(index)
			return


func _values() -> Dictionary:
	var condition_value_editor := _inputs.get("condition_value") as EmberTypedValueEditor
	var condition_value: Variant = condition_value_editor.value() if condition_value_editor != null else true
	return EmberSceneAuthoring.normalized_interact_values({
		"kind": _option_value("kind"),
		"trigger_id": _option_value("trigger_id"),
		"target_map_id": _option_value("target_map_id"),
		"target_region_id": _option_value("target_region_id"),
		"shop_id": _option_value("shop_id"),
		"script_id": _option_value("script_id"),
		"quest_id": _option_value("quest_id"),
		"quest_status": _option_value("quest_status"),
		"icon_id": (_inputs.get("icon_id") as LineEdit).text,
		"condition_flag_id": (_inputs.get("condition_flag_id") as LineEdit).text,
		"condition_expected": condition_value if typeof(condition_value) == TYPE_BOOL else true,
		"condition_value": condition_value,
		"fallback_script_id": _option_value("fallback_script_id"),
		"one_shot": (_inputs.get("one_shot") as CheckBox).button_pressed,
		"completion_flag_id": (_inputs.get("completion_flag_id") as LineEdit).text,
		"activation_mode": _option_value("activation_mode"),
		"note": (_inputs.get("note") as LineEdit).text,
	})


func _submit() -> void:
	var values := _values()
	var errors := EmberSceneAuthoring.interact_validation_errors(values)
	if not errors.is_empty():
		_validation.text = "\n".join(errors)
		_validation.visible = true
		return
	_validation.visible = false
	save_requested.emit(values)
