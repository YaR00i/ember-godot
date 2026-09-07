@tool
class_name EmberQuestEditor
extends VBoxContainer
## Compact authoring for quest descriptions/objective flag projections.

const Store = preload("res://addons/ember_import/ember_quest_store.gd")
const CombatResult = preload("res://scripts/prototypes/ember_combat_result.gd")

signal save_requested(document: Dictionary)
signal cancel_requested

var _id: LineEdit
var _status_flag: LineEdit
var _title: LineEdit
var _summary: TextEdit
var _show_available: CheckBox
var _objectives: VBoxContainer
var _validation: Label
var _editor_layout: Dictionary = {}


func setup(
	quest_id: String,
	suggested_id: String,
	suggested_status_flag := "",
	document_override: Dictionary = {},
) -> void:
	name = "QuestEditor"
	add_theme_constant_override("separation", 6)
	var document := (
		document_override.duplicate(true)
		if not document_override.is_empty()
		else Store.document(quest_id)
	)
	_editor_layout = (
		(document.get("editorLayout", {}) as Dictionary).duplicate(true)
		if typeof(document.get("editorLayout", {})) == TYPE_DICTIONARY
		else {}
	)
	_id = _line_row("QuestId", "ID задания", quest_id if not quest_id.is_empty() else suggested_id)
	_id.editable = quest_id.is_empty()
	_id.tooltip_text = "Стабильное имя Resource. Оно не является состоянием и не записывается в save."
	var default_status_flag := (
		suggested_status_flag
		if not suggested_status_flag.is_empty()
		else "%s_status" % _id.text
	)
	_status_flag = _line_row(
		"QuestStatusFlag",
		"Флаг статуса",
		str(document.get("statusFlagId", default_status_flag)),
	)
	_status_flag.tooltip_text = "Отдельный save-ключ: отсутствует = доступно, active = в работе, done/true = завершено."
	var status_hint := Label.new()
	status_hint.text = "Статус: нет ключа → доступно · active → в работе · done/true → завершено"
	status_hint.modulate = Color(0.58, 0.68, 0.78)
	status_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status_hint)
	_title = _line_row("QuestTitle", "Название", str(document.get("titleRu", "Новое задание")))
	var summary_label := Label.new()
	summary_label.text = "Описание"
	summary_label.modulate = Color(0.72, 0.72, 0.75)
	add_child(summary_label)
	_summary = TextEdit.new()
	_summary.name = "QuestSummary"
	_summary.text = str(document.get("summaryRu", ""))
	_summary.custom_minimum_size.y = 72.0
	_summary.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	add_child(_summary)
	_show_available = CheckBox.new()
	_show_available.name = "QuestShowAvailable"
	_show_available.text = "Показывать в журнале, пока задание ещё не принято"
	_show_available.tooltip_text = "Если выключено, запись появится только после установки флага статуса или выполнения первой цели."
	_show_available.button_pressed = bool(document.get("showWhenAvailable", false))
	add_child(_show_available)
	var heading := HBoxContainer.new()
	add_child(heading)
	var label := Label.new()
	label.text = "ЦЕЛИ"
	label.modulate = Color(0.55, 0.82, 0.88)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(label)
	var add := Button.new()
	add.name = "AddQuestObjective"
	add.text = "+ Цель"
	add.pressed.connect(func() -> void: _add_objective({}))
	heading.add_child(add)
	_objectives = VBoxContainer.new()
	_objectives.name = "QuestObjectives"
	_objectives.add_theme_constant_override("separation", 5)
	add_child(_objectives)
	var raw_objectives: Variant = document.get("objectives", [])
	if typeof(raw_objectives) == TYPE_ARRAY:
		for raw_objective in raw_objectives:
			if typeof(raw_objective) == TYPE_DICTIONARY:
				_add_objective(raw_objective)
	if _objectives.get_child_count() == 0:
		_add_objective({
			"id": "main",
			"textRu": "Выполнить цель",
			"flagId": "%s_goal" % _id.text,
		})
	_validation = Label.new()
	_validation.name = "QuestValidation"
	_validation.visible = false
	_validation.modulate = Color(1.0, 0.48, 0.42)
	_validation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_validation)
	var actions := HBoxContainer.new()
	add_child(actions)
	var save := Button.new()
	save.name = "SaveQuest"
	save.text = "Сохранить задание"
	save.pressed.connect(_submit)
	actions.add_child(save)
	var cancel := Button.new()
	cancel.name = "CancelQuest"
	cancel.text = "Отмена"
	cancel.pressed.connect(cancel_requested.emit)
	actions.add_child(cancel)
	var hint := Label.new()
	hint.text = "Прогресс меняют шаги «Изменить флаг». В Play откройте журнал клавишей Q: он покажет значения текущего save и даст тестовый сброс только этого задания."
	hint.modulate = Color(0.64, 0.64, 0.68)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)


func _line_row(node_name: String, title_text: String, value: String) -> LineEdit:
	var row := HBoxContainer.new()
	add_child(row)
	var label := Label.new()
	label.text = title_text
	label.custom_minimum_size.x = 105.0
	label.modulate = Color(0.72, 0.72, 0.75)
	row.add_child(label)
	var input := LineEdit.new()
	input.name = node_name
	input.text = value
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input)
	return input


func _add_objective(value: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.name = "QuestObjective"
	panel.add_theme_stylebox_override("panel", _panel_style())
	_objectives.add_child(panel)
	var body := VBoxContainer.new()
	panel.add_child(body)
	var top := HBoxContainer.new()
	body.add_child(top)
	var title := Label.new()
	title.text = "Цель %d" % _objectives.get_child_count()
	title.modulate = Color(0.72, 0.82, 0.94)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var optional := CheckBox.new()
	optional.name = "ObjectiveOptional"
	optional.text = "Необязательная (не нужна для завершения)"
	optional.tooltip_text = "Такая цель отображается в журнале, но не мешает заданию перейти в статус «Завершено»."
	optional.button_pressed = bool(value.get("optional", false))
	top.add_child(optional)
	var remove := Button.new()
	remove.name = "RemoveQuestObjective"
	remove.text = "×"
	remove.modulate = Color(1.0, 0.58, 0.54)
	remove.pressed.connect(func() -> void:
		_objectives.remove_child(panel)
		panel.queue_free()
	)
	top.add_child(remove)
	var objective_id := _objective_field(
		body,
		"ObjectiveId",
		"Внутренний ID",
		str(value.get("id", "objective_%d" % _objectives.get_child_count())),
	)
	objective_id.tooltip_text = "Техническое устойчивое имя этой строки внутри задания. Игрок его не видит."
	var text := _objective_field(
		body,
		"ObjectiveText",
		"Текст в журнале",
		str(value.get("textRu", "")),
	)
	text.placeholder_text = "Например: поговорить с кузнецом"
	var flag := _objective_field(
		body,
		"ObjectiveFlag",
		"Прогресс цели (save key)",
		str(value.get("flagId", "")),
	)
	flag.placeholder_text = "save-ключ, который станет true/done"
	flag.tooltip_text = "Когда action/dialogue запишет сюда true или done, цель получит ✓. Это не флаг статуса всего задания."
	var progress_mode := OptionButton.new()
	progress_mode.name = "ObjectiveProgressMode"
	progress_mode.add_item("Событие / флаг")
	progress_mode.set_item_metadata(0, "flag")
	progress_mode.add_item("Боевой счётчик")
	progress_mode.set_item_metadata(1, "counter")
	progress_mode.select(1 if str(value.get("progressMode", "flag")) == "counter" else 0)
	progress_mode.tooltip_text = "Флаг отмечается событием один раз. Боевой счётчик растёт автоматически после победы."
	body.add_child(progress_mode)
	var counter_picker := OptionButton.new()
	counter_picker.name = "ObjectiveCombatCounter"
	counter_picker.tooltip_text = "Готовые ключи формирует результат боя; помнить или печатать их вручную не нужно."
	for counter in CombatResult.counter_options():
		counter_picker.add_item(str(counter.get("label", counter.get("id", ""))))
		counter_picker.set_item_metadata(counter_picker.item_count - 1, str(counter.get("id", "")))
	var selected_counter := str(value.get("counterEventId", ""))
	var matched_counter := false
	for index in counter_picker.item_count:
		if str(counter_picker.get_item_metadata(index)) == selected_counter:
			counter_picker.select(index)
			matched_counter = true
			break
	if str(value.get("progressMode", "flag")) == "counter" and not selected_counter.is_empty() and not matched_counter:
		counter_picker.add_item("Сохранённый счётчик · %s" % selected_counter)
		counter_picker.set_item_metadata(counter_picker.item_count - 1, selected_counter)
		counter_picker.select(counter_picker.item_count - 1)
	body.add_child(counter_picker)
	var required := SpinBox.new()
	required.name = "ObjectiveRequiredCount"
	required.min_value = 1
	required.max_value = 9999
	required.value = maxi(1, int(value.get("requiredCount", 1)))
	required.prefix = "Нужно: "
	body.add_child(required)
	var counter_hint := Label.new()
	counter_hint.text = "Событие увеличивает только открытую цель; закрытая последовательностью не копит прогресс."
	counter_hint.modulate = Color(0.54, 0.70, 0.82)
	counter_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	counter_hint.add_theme_font_size_override("font_size", 11)
	body.add_child(counter_hint)
	var update_counter_visibility := func() -> void:
		var counter_mode := str(progress_mode.get_selected_metadata()) == "counter"
		counter_picker.visible = counter_mode
		required.visible = counter_mode
		counter_hint.visible = counter_mode
		flag.tooltip_text = (
			"Собственный числовой прогресс этой цели. Боевое событие увеличивает его автоматически."
			if counter_mode
			else "Когда action/dialogue запишет сюда true или done, цель получит ✓."
		)
	progress_mode.item_selected.connect(func(_index: int) -> void: update_counter_visibility.call())
	update_counter_visibility.call()
	var dependencies := _objective_field(
		body,
		"ObjectiveDependencies",
		"После целей",
		", ".join(value.get("requiresObjectiveIds", [])),
	)
	dependencies.placeholder_text = "ID предыдущих целей через запятую"
	dependencies.tooltip_text = "Цель заблокирована, пока не выполнены все перечисленные цели. Удобнее соединять цели проводами в Ember Graph."


func _objective_field(
	parent: VBoxContainer,
	node_name: String,
	label_text: String,
	value: String,
) -> LineEdit:
	var label := Label.new()
	label.text = label_text
	label.modulate = Color(0.64, 0.64, 0.69)
	label.add_theme_font_size_override("font_size", 11)
	parent.add_child(label)
	var input := LineEdit.new()
	input.name = node_name
	input.text = value
	parent.add_child(input)
	return input


func _document() -> Dictionary:
	var objectives: Array[Dictionary] = []
	for raw_panel in _objectives.get_children():
		var panel := raw_panel as PanelContainer
		var progress_mode := str((panel.find_child("ObjectiveProgressMode", true, false) as OptionButton).get_selected_metadata())
		objectives.append({
			"id": (panel.find_child("ObjectiveId", true, false) as LineEdit).text,
			"textRu": (panel.find_child("ObjectiveText", true, false) as LineEdit).text,
			"flagId": (panel.find_child("ObjectiveFlag", true, false) as LineEdit).text,
			"progressMode": progress_mode,
			"counterEventId": (
				str((panel.find_child("ObjectiveCombatCounter", true, false) as OptionButton).get_selected_metadata())
				if progress_mode == "counter"
				else ""
			),
			"requiredCount": int((panel.find_child("ObjectiveRequiredCount", true, false) as SpinBox).value),
			"optional": (panel.find_child("ObjectiveOptional", true, false) as CheckBox).button_pressed,
			"requiresObjectiveIds": _dependency_ids(
				(panel.find_child("ObjectiveDependencies", true, false) as LineEdit).text
			),
		})
	return Store.normalized_document({
		"id": _id.text,
		"statusFlagId": _status_flag.text,
		"titleRu": _title.text,
		"summaryRu": _summary.text,
		"showWhenAvailable": _show_available.button_pressed,
		"objectives": objectives,
		"editorLayout": _editor_layout.duplicate(true),
	})


func _dependency_ids(value: String) -> Array[String]:
	var result: Array[String] = []
	for raw_part in value.split(",", false):
		var objective_id := str(raw_part).strip_edges()
		if not objective_id.is_empty() and objective_id not in result:
			result.append(objective_id)
	return result


func _submit() -> void:
	var document := _document()
	var errors := Store.validation_errors(document)
	if not errors.is_empty():
		_validation.text = "\n".join(errors)
		_validation.visible = true
		return
	_validation.visible = false
	save_requested.emit(document)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.13, 0.16)
	style.border_color = Color(0.26, 0.31, 0.40)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 7.0
	style.content_margin_top = 6.0
	style.content_margin_right = 7.0
	style.content_margin_bottom = 6.0
	return style
