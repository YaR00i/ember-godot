@tool
class_name EmberActionChainEditor
extends VBoxContainer
## Inline authoring UI for the canonical native-or-legacy action document.

const Store = preload("res://addons/ember_import/ember_action_script_store.gd")
const TypedValueEditor = preload("res://addons/ember_import/ember_typed_value_editor.gd")
const DialogueStore = preload("res://addons/ember_import/ember_dialogue_store.gd")
const DialogueEditor = preload("res://addons/ember_import/ember_dialogue_editor.gd")
const ShopStore = preload("res://addons/ember_import/ember_shop_store.gd")
const ShopEditor = preload("res://addons/ember_import/ember_shop_editor.gd")
const VisualLibraryPopup = preload("res://addons/ember_import/ember_visual_library_popup.gd")
const QuestStore = preload("res://addons/ember_import/ember_quest_store.gd")
const MapVisuals = preload("res://scripts/ember_map_visuals.gd")
const EncounterCatalog = preload("res://scripts/prototypes/ember_encounter_catalog.gd")
const EncounterVisuals = preload("res://scripts/prototypes/ember_encounter_visuals.gd")

signal save_requested(document: Dictionary)
signal cancel_requested
signal delete_requested(script_id: String)
signal dialogue_save_requested(document: Dictionary)
signal shop_save_requested(document: Dictionary)
signal shop_migrate_requested(shop_id: String)
signal item_save_requested(document: Dictionary)
signal item_migrate_requested(item_id: String)

var _base_document: Dictionary = {}
var _existing := false
var _id_input: LineEdit
var _name_input: LineEdit
var _steps: VBoxContainer
var _add_type: OptionButton
var _validation: Label
var _map_library: EmberVisualLibraryPopup
var _map_library_mode := ""
var _map_target_option: OptionButton
var _map_region_option: OptionButton
var _map_region_library_button: Button
var _quest_flag_library: EmberVisualLibraryPopup
var _quest_flag_target: LineEdit
var _quest_event_library: EmberVisualLibraryPopup
var _quest_event_target_panel: PanelContainer
var _encounter_library: EmberVisualLibraryPopup
var _encounter_target_option: OptionButton
var _quest_binding_id := ""


func setup(
	script_id: String,
	suggested_id: String,
	document_override: Dictionary = {},
	quest_binding_id := "",
) -> void:
	name = "ActionChainEditor"
	add_theme_constant_override("separation", 6)
	_base_document = (
		document_override.duplicate(true)
		if not document_override.is_empty()
		else Store.document(script_id)
	)
	_existing = not _base_document.is_empty()
	_quest_binding_id = quest_binding_id.strip_edges()
	_build_header(_existing)
	_id_input.text = script_id if not script_id.is_empty() else suggested_id
	_id_input.editable = _base_document.is_empty()
	_name_input.text = str(_base_document.get("nameRu", "Новая цепочка"))
	_steps = VBoxContainer.new()
	_steps.name = "ActionSteps"
	_steps.add_theme_constant_override("separation", 5)
	add_child(_steps)
	var raw_steps: Variant = _base_document.get("steps", [])
	if typeof(raw_steps) == TYPE_ARRAY:
		for raw_step in raw_steps:
			if typeof(raw_step) == TYPE_DICTIONARY:
				_add_step(raw_step)
	_build_add_row()
	_validation = Label.new()
	_validation.name = "ActionChainValidation"
	_validation.visible = false
	_validation.modulate = Color(1.0, 0.48, 0.42)
	_validation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_validation)
	var actions := HBoxContainer.new()
	actions.name = "ActionChainActions"
	add_child(actions)
	var save := Button.new()
	save.name = "SaveActionChain"
	save.text = "Сохранить цепочку"
	save.tooltip_text = "Пишет текущий canonical owner цепочки и назначает её Interact одной Undo-операцией."
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save.pressed.connect(_submit)
	actions.add_child(save)
	if _existing:
		var remove := Button.new()
		remove.name = "DeleteActionChain"
		remove.text = "Удалить цепочку"
		remove.tooltip_text = "Удаляет документ цепочки и снимает только её с Interact. Сам Interact и магазин остаются; Ctrl+Z восстанавливает."
		remove.modulate = Color(1.0, 0.62, 0.58)
		remove.pressed.connect(_request_delete)
		actions.add_child(remove)
	else:
		var cancel := Button.new()
		cancel.name = "CancelActionChain"
		cancel.text = "Отменить"
		cancel.tooltip_text = "Закрывает несохранённую форму. Файл и Interact ещё не изменялись."
		cancel.pressed.connect(cancel_requested.emit)
		actions.add_child(cancel)


func _build_header(existing: bool) -> void:
	var title := Label.new()
	title.text = "ЦЕПОЧКА ДЕЙСТВИЙ"
	title.add_theme_font_size_override("font_size", 12)
	title.modulate = Color(0.78, 0.84, 1.0)
	add_child(title)
	_id_input = _line_row("ActionChainId", "ID", "snake_case; после создания не переименовывается")
	add_child(_id_input.get_parent())
	_name_input = _line_row("ActionChainName", "Название", "Видно автору в Inspector")
	add_child(_name_input.get_parent())
	if existing:
		var path := Label.new()
		path.text = "Источник: %s" % Store.source_path(str(_base_document.get("id", "")))
		path.modulate = Color(0.62, 0.72, 0.82)
		path.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(path)


func _line_row(node_name: String, title: String, tooltip: String) -> LineEdit:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 88.0
	label.modulate = Color(0.72, 0.72, 0.75)
	row.add_child(label)
	var input := LineEdit.new()
	input.name = node_name
	input.tooltip_text = tooltip
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input)
	return input


func _build_add_row() -> void:
	var row := HBoxContainer.new()
	row.name = "AddActionStep"
	add_child(row)
	_add_type = OptionButton.new()
	_add_type.name = "NewStepType"
	_add_type.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for step_type in Store.STEP_TYPES:
		_add_type.add_item(_type_title(step_type))
		_add_type.set_item_metadata(_add_type.item_count - 1, step_type)
	row.add_child(_add_type)
	var add := Button.new()
	add.name = "AddActionStepButton"
	add.text = "+ Шаг"
	add.pressed.connect(_add_selected_step)
	row.add_child(add)
	var quest_event := Button.new()
	quest_event.name = "AddQuestEventStep"
	quest_event.text = "+ Событие задания"
	quest_event.tooltip_text = "Выбрать «начать / выполнить цель / завершить». Сохранится обычный set_flag."
	quest_event.pressed.connect(_open_quest_event_library)
	row.add_child(quest_event)


func _add_selected_step() -> void:
	var step_type := str(_add_type.get_item_metadata(_add_type.selected))
	_add_step(_default_step(step_type))


func _add_step(step: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.name = "ActionStep"
	panel.set_meta("step_type", str(step.get("type", "talk")))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.13, 0.145)
	style.border_color = Color(0.28, 0.3, 0.36)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(6.0)
	panel.add_theme_stylebox_override("panel", style)
	var body := VBoxContainer.new()
	panel.add_child(body)
	var head := HBoxContainer.new()
	body.add_child(head)
	var title := Label.new()
	title.name = "StepTitle"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var up := Button.new()
	up.name = "StepMoveUp"
	up.text = "↑"
	up.tooltip_text = "Переместить выше"
	up.pressed.connect(_move_step.bind(panel, -1))
	head.add_child(up)
	var down := Button.new()
	down.name = "StepMoveDown"
	down.text = "↓"
	down.tooltip_text = "Переместить ниже"
	down.pressed.connect(_move_step.bind(panel, 1))
	head.add_child(down)
	var remove := Button.new()
	remove.name = "StepRemove"
	remove.text = "×"
	remove.tooltip_text = "Удалить шаг"
	remove.modulate = Color(1.0, 0.62, 0.58)
	remove.pressed.connect(_remove_step.bind(panel))
	head.add_child(remove)
	var payload := VBoxContainer.new()
	payload.name = "StepPayload"
	body.add_child(payload)
	_build_payload(panel, step)
	_steps.add_child(panel)
	_reindex_steps()


func _build_payload(panel: PanelContainer, step: Dictionary) -> void:
	var payload := panel.find_child("StepPayload", true, false) as VBoxContainer
	for child in payload.get_children():
		child.free()
	var step_type := str(step.get("type", "talk"))
	panel.set_meta("step_type", step_type)
	match step_type:
		"talk":
			payload.add_child(_dialogue_rows(str(step.get("dialogueId", ""))))
		"give_item":
			payload.add_child(_option_row("itemId", "Предмет", EmberInteractionContent.item_ids(), str(step.get("itemId", ""))))
			payload.add_child(_number_row("count", "Количество", float(step.get("count", 1)), 1.0, 999.0, 1.0))
		"set_flag":
			var quest_event := Button.new()
			quest_event.name = "ChooseQuestEvent"
			quest_event.text = "Событие задания…"
			quest_event.tooltip_text = "Подставляет правильный status/objective flag и значение, но сохраняет прежний set_flag."
			quest_event.pressed.connect(_open_quest_event_library.bind(panel))
			payload.add_child(quest_event)
			var flag_row := _text_row("flag", "Имя флага", str(step.get("flag", "")))
			var flag_input := flag_row.find_child("StepField_flag", true, false) as LineEdit
			if flag_input != null:
				flag_input.placeholder_text = "например: met_blacksmith"
			var quest_library := _library_button(
				"OpenQuestFlagLibrary",
				"Выбрать общий статус задания или флаг выполнения цели",
			)
			quest_library.pressed.connect(_open_quest_flag_library.bind(flag_input))
			flag_row.add_child(quest_library)
			flag_row.tooltip_text = "Уникальный ключ в сохранении. Другой объект или квест должен читать точно такое же имя."
			payload.add_child(flag_row)
			payload.add_child(_flag_value_row(step.get("value", true)))
		"wait":
			var wait_row := _number_row("sec", "Секунды", float(step.get("sec", 0.0)), 0.0, 60.0, 0.1)
			wait_row.tooltip_text = "Останавливает цепочку на указанное реальное время. Продолжение автоматическое; F не пропускает паузу."
			payload.add_child(wait_row)
		"open_shop":
			payload.add_child(_shop_rows(str(step.get("shopId", ""))))
		"change_map":
			payload.add_child(_map_destination_rows(step))
		"start_battle":
			payload.add_child(_encounter_rows(str(step.get("encounterId", ""))))
		"run_script":
			payload.add_child(_option_row("scriptId", "Цепочка", EmberInteractionContent.action_script_ids(), str(step.get("scriptId", ""))))
		_:
			var unsupported := Label.new()
			unsupported.text = "Неподдерживаемый шаг сохранён только до следующей правки: %s" % step_type
			unsupported.modulate = Color(1.0, 0.55, 0.45)
			payload.add_child(unsupported)


func _dialogue_rows(current: String) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	var select_row := _option_row("dialogueId", "Диалог", EmberInteractionContent.dialogue_ids(), current)
	var option := select_row.find_child("StepField_dialogueId", true, false) as OptionButton
	column.add_child(select_row)
	var edit := Button.new()
	edit.name = "EditDialogue"
	edit.text = "Создать / редактировать диалог"
	edit.tooltip_text = "Открывает безопасный карточный editor для обычных реплик и простого выбора. Сложные VN-сцены остаются read-only."
	column.add_child(edit)
	var holder := VBoxContainer.new()
	holder.name = "DialogueEditorHolder"
	holder.visible = false
	column.add_child(holder)
	edit.pressed.connect(_toggle_dialogue_editor.bind(holder, edit, option))
	return column


func _shop_rows(current: String) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	var select_row := _option_row("shopId", "Магазин", EmberInteractionContent.shop_ids(), current)
	select_row.tooltip_text = "Открывает существующий магазин. После выхода по Esc цепочка продолжается."
	var option := select_row.find_child("StepField_shopId", true, false) as OptionButton
	column.add_child(select_row)
	var edit := Button.new()
	edit.name = "EditShop"
	edit.text = "Создать / редактировать магазин"
	edit.tooltip_text = "Редактирует название, цены и конечный/бесконечный запас через Godot Resource."
	column.add_child(edit)
	var holder := VBoxContainer.new()
	holder.name = "ShopEditorHolder"
	holder.visible = false
	column.add_child(holder)
	edit.pressed.connect(_toggle_shop_editor.bind(holder, edit, option))
	return column


func _toggle_shop_editor(holder: VBoxContainer, button: Button, option: OptionButton) -> void:
	if holder.get_child_count() == 0:
		var shop_id := _selected_metadata(option)
		var editable_id := shop_id if ShopStore.exists(shop_id) else ""
		var source_id := _id_input.text if _id_input != null else "shop"
		var editor := ShopEditor.new() as EmberShopEditor
		editor.setup(editable_id, ShopStore.suggested_id(source_id))
		editor.save_requested.connect(_on_shop_save.bind(holder, button, option))
		editor.migrate_requested.connect(shop_migrate_requested.emit)
		editor.item_save_requested.connect(item_save_requested.emit)
		editor.item_migrate_requested.connect(item_migrate_requested.emit)
		editor.cancel_requested.connect(_dismiss_shop_editor.bind(holder, button))
		holder.add_child(editor)
		holder.visible = true
	else:
		holder.visible = not holder.visible
	button.text = "Скрыть редактор магазина" if holder.visible else "Создать / редактировать магазин"


func _on_shop_save(document: Dictionary, holder: VBoxContainer, button: Button, option: OptionButton) -> void:
	shop_save_requested.emit(document)
	_select_shop(option, str(document.get("id", "")))
	_dismiss_shop_editor(holder, button)


func _dismiss_shop_editor(holder: VBoxContainer, button: Button) -> void:
	for child in holder.get_children():
		holder.remove_child(child)
		child.queue_free()
	holder.visible = false
	button.text = "Создать / редактировать магазин"


func _select_shop(option: OptionButton, shop_id: String) -> void:
	option.clear()
	option.add_item("— выберите —")
	option.set_item_metadata(0, "")
	var ids := EmberInteractionContent.shop_ids()
	if not shop_id.is_empty() and shop_id not in ids:
		ids.append(shop_id)
		ids.sort()
	for item_id in ids:
		option.add_item(item_id)
		option.set_item_metadata(option.item_count - 1, item_id)
		if item_id == shop_id:
			option.select(option.item_count - 1)


func _toggle_dialogue_editor(holder: VBoxContainer, button: Button, option: OptionButton) -> void:
	if holder.get_child_count() == 0:
		var dialogue_id := _selected_metadata(option)
		var editable_id := dialogue_id if DialogueStore.exists(dialogue_id) else ""
		var source_id := _id_input.text if _id_input != null else "dialogue"
		var editor := DialogueEditor.new() as EmberDialogueEditor
		editor.setup(editable_id, DialogueStore.suggested_id(source_id))
		editor.save_requested.connect(_on_dialogue_save.bind(holder, button, option))
		editor.cancel_requested.connect(_dismiss_dialogue_editor.bind(holder, button))
		holder.add_child(editor)
		holder.visible = true
	else:
		holder.visible = not holder.visible
	button.text = "Скрыть редактор диалога" if holder.visible else "Создать / редактировать диалог"


func _on_dialogue_save(document: Dictionary, holder: VBoxContainer, button: Button, option: OptionButton) -> void:
	dialogue_save_requested.emit(document)
	_select_dialogue(option, str(document.get("id", "")))
	_dismiss_dialogue_editor(holder, button)


func _dismiss_dialogue_editor(holder: VBoxContainer, button: Button) -> void:
	for child in holder.get_children():
		holder.remove_child(child)
		child.queue_free()
	holder.visible = false
	button.text = "Создать / редактировать диалог"


func _select_dialogue(option: OptionButton, dialogue_id: String) -> void:
	option.clear()
	option.add_item("— выберите —")
	option.set_item_metadata(0, "")
	var ids := EmberInteractionContent.dialogue_ids()
	if not dialogue_id.is_empty() and dialogue_id not in ids:
		ids.append(dialogue_id)
		ids.sort()
	for item_id in ids:
		option.add_item(item_id)
		option.set_item_metadata(option.item_count - 1, item_id)
		if item_id == dialogue_id:
			option.select(option.item_count - 1)


func _selected_metadata(option: OptionButton) -> String:
	return "" if option == null or option.selected < 0 else str(option.get_item_metadata(option.selected))


func _option_row(field: String, title: String, values: Array[String], current: String) -> Control:
	var row := _field_row(title)
	var option := OptionButton.new()
	option.name = "StepField_%s" % field
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.add_item("— выберите —")
	option.set_item_metadata(0, "")
	for value in values:
		option.add_item(value)
		option.set_item_metadata(option.item_count - 1, value)
		if value == current:
			option.select(option.item_count - 1)
	if option.selected == 0 and not current.is_empty():
		option.add_item("%s  ⚠" % current)
		option.set_item_metadata(option.item_count - 1, current)
		option.select(option.item_count - 1)
	row.add_child(option)
	return row


func _map_destination_rows(step: Dictionary) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	var target_map_id := str(step.get("targetMapId", ""))
	var map_row := _option_row("targetMapId", "Карта", EmberInteractionContent.map_ids(), target_map_id)
	var map_option := map_row.find_child("StepField_targetMapId", true, false) as OptionButton
	var map_library := _library_button("OpenStepMapLibrary", "Выбрать карту визуально")
	map_row.add_child(map_library)
	column.add_child(map_row)
	var region_row := _field_row("Точка входа")
	var region_option := OptionButton.new()
	region_option.name = "StepField_targetRegionId"
	region_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	region_row.add_child(region_option)
	var region_library := _library_button("OpenStepRegionLibrary", "Выбрать точку входа визуально")
	region_library.disabled = target_map_id.is_empty()
	region_library.pressed.connect(_open_step_region_library.bind(map_option, region_option))
	region_row.add_child(region_library)
	column.add_child(region_row)
	_fill_region_option(region_option, target_map_id, str(step.get("targetRegionId", "")))
	map_library.pressed.connect(
		_open_step_map_library.bind(map_option, region_option, region_library)
	)
	if map_option != null:
		map_option.item_selected.connect(
			_on_target_map_selected.bind(map_option, region_option, region_library)
		)
	column.tooltip_text = "Смена карты завершает цепочку: оставшиеся шаги должны находиться до неё. Точка входа необязательна."
	return column


func _encounter_rows(current: String) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	var row := _option_row("encounterId", "Встреча", EncounterCatalog.ids(), current)
	var option := row.find_child("StepField_encounterId", true, false) as OptionButton
	var library := _library_button("OpenEncounterLibrary", "Выбрать встречу по мини-карте поля")
	library.pressed.connect(_open_encounter_library.bind(option))
	row.add_child(library)
	column.add_child(row)
	var hint := Label.new()
	hint.text = "Бой завершает эту цепочку. Диалог или награда после победы назначаются в ресурсе встречи."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(0.62, 0.72, 0.82)
	hint.add_theme_font_size_override("font_size", 12)
	column.add_child(hint)
	return column


func _open_encounter_library(option: OptionButton) -> void:
	if _encounter_library == null:
		_encounter_library = VisualLibraryPopup.new() as EmberVisualLibraryPopup
		_encounter_library.name = "EncounterLibrary"
		_encounter_library.value_chosen.connect(_choose_encounter)
		add_child(_encounter_library)
	_encounter_target_option = option
	_encounter_library.open_library(
		"БОЕВЫЕ ВСТРЕЧИ",
		EncounterVisuals.entries(),
		_selected_metadata(option),
		Vector2i(112, 88),
		180,
	)


func _choose_encounter(encounter_id: String) -> void:
	if _encounter_target_option != null and is_instance_valid(_encounter_target_option):
		_select_option_value(_encounter_target_option, encounter_id)
	_encounter_target_option = null


func _on_target_map_selected(
	_index: int,
	map_option: OptionButton,
	region_option: OptionButton,
	region_library: Button,
) -> void:
	var map_id := "" if map_option.selected < 0 else str(map_option.get_item_metadata(map_option.selected))
	_fill_region_option(region_option, map_id, "")
	region_library.disabled = map_id.is_empty()


func _library_button(node_name: String, tooltip: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = "▦"
	button.tooltip_text = tooltip
	return button


func _open_step_map_library(
	map_option: OptionButton,
	region_option: OptionButton,
	region_library: Button,
) -> void:
	_ensure_map_library()
	_map_library_mode = "map"
	_map_target_option = map_option
	_map_region_option = region_option
	_map_region_library_button = region_library
	_map_library.open_library(
		"КАРТЫ EMBER",
		MapVisuals.map_entries(),
		_selected_metadata(map_option),
	)


func _open_step_region_library(
	map_option: OptionButton,
	region_option: OptionButton,
) -> void:
	var map_id := _selected_metadata(map_option)
	if map_id.is_empty():
		return
	_ensure_map_library()
	_map_library_mode = "region"
	_map_target_option = map_option
	_map_region_option = region_option
	_map_library.open_library(
		"ТОЧКИ ВХОДА · %s" % map_id,
		MapVisuals.region_entries(map_id),
		_selected_metadata(region_option),
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
		_quest_flag_library.name = "QuestFlagLibrary"
		_quest_flag_library.value_chosen.connect(_choose_quest_flag_value)
		add_child(_quest_flag_library)
	_quest_flag_target = target
	_quest_flag_library.open_library(
		"ФЛАГИ ЗАДАНИЙ",
		QuestStore.flag_reference_entries(),
		target.text.strip_edges(),
		Vector2i(0, 0),
		210,
	)


func _open_quest_event_library(
	target_panel: PanelContainer = null,
	quest_id_filter := "",
) -> void:
	if _quest_event_library == null:
		_quest_event_library = VisualLibraryPopup.new() as EmberVisualLibraryPopup
		_quest_event_library.name = "QuestEventLibrary"
		_quest_event_library.value_chosen.connect(_choose_quest_event)
		add_child(_quest_event_library)
	_quest_event_target_panel = target_panel
	_quest_event_library.open_library(
		"СОБЫТИЯ ЗАДАНИЙ",
		QuestStore.event_reference_entries(quest_id_filter),
		"",
		Vector2i(0, 0),
		240,
	)


func open_quest_event_picker(quest_id_filter := "") -> void:
	## Public Inspector shortcut. Selection still becomes the same set_flag step.
	_open_quest_event_library(null, quest_id_filter)


func _choose_quest_event(token: String) -> void:
	var step := QuestStore.action_for_event(token)
	if step.is_empty():
		_quest_event_target_panel = null
		return
	var selected_quest_id := QuestStore.quest_id_for_event(token)
	if _quest_binding_id.is_empty():
		_quest_binding_id = selected_quest_id
	elif _quest_binding_id != selected_quest_id:
		# A multi-quest utility chain is valid, but it cannot implicitly decide
		# which single quest controls a world marker.
		_quest_binding_id = ""
	if _quest_event_target_panel != null and is_instance_valid(_quest_event_target_panel):
		_build_payload(_quest_event_target_panel, step)
	else:
		_add_step(step)
	_quest_event_target_panel = null


func _choose_quest_flag_value(value: String) -> void:
	if _quest_flag_target != null and is_instance_valid(_quest_flag_target):
		_quest_flag_target.text = value
	_quest_flag_target = null


func _choose_map_library_value(value: String) -> void:
	if _map_library_mode == "map" and _map_target_option != null:
		_select_option_value(_map_target_option, value)
		if _map_region_option != null:
			_fill_region_option(_map_region_option, value, "")
		if _map_region_library_button != null:
			_map_region_library_button.disabled = value.is_empty()
	elif _map_library_mode == "region" and _map_region_option != null:
		_select_option_value(_map_region_option, value)


func _select_option_value(option: OptionButton, value: String) -> void:
	for index in option.item_count:
		if str(option.get_item_metadata(index)) == value:
			option.select(index)
			return


func _fill_region_option(option: OptionButton, map_id: String, current: String) -> void:
	option.clear()
	option.add_item("— стандартный вход —")
	option.set_item_metadata(0, "")
	for region_id in EmberInteractionContent.region_ids(map_id):
		option.add_item(region_id)
		option.set_item_metadata(option.item_count - 1, region_id)
		if region_id == current:
			option.select(option.item_count - 1)
	if option.selected == 0 and not current.is_empty():
		option.add_item("%s  ⚠" % current)
		option.set_item_metadata(option.item_count - 1, current)
		option.select(option.item_count - 1)


func _text_row(field: String, title: String, current: String) -> Control:
	var row := _field_row(title)
	var input := LineEdit.new()
	input.name = "StepField_%s" % field
	input.text = current
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input)
	return row


func _number_row(field: String, title: String, current: float, minimum: float, maximum: float, step: float) -> Control:
	var row := _field_row(title)
	var input := SpinBox.new()
	input.name = "StepField_%s" % field
	input.min_value = minimum
	input.max_value = maximum
	input.step = step
	input.value = current
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input)
	return row


func _flag_value_row(current: Variant) -> Control:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 3)
	var hint := Label.new()
	hint.text = "Флаг сохраняет состояние. Сам шаг ничего не показывает, пока этот ключ не прочитает квест, диалог или другой объект."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(0.62, 0.72, 0.82)
	hint.add_theme_font_size_override("font_size", 12)
	block.add_child(hint)
	var editor := TypedValueEditor.new() as EmberTypedValueEditor
	editor.name = "StepTypedValueEditor"
	editor.setup(current, "StepField_value")
	block.add_child(editor)
	return block


func _field_row(title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 88.0
	label.modulate = Color(0.72, 0.72, 0.75)
	row.add_child(label)
	return row


func _move_step(panel: PanelContainer, delta: int) -> void:
	var index := panel.get_index()
	_steps.move_child(panel, clampi(index + delta, 0, _steps.get_child_count() - 1))
	_reindex_steps()


func _remove_step(panel: PanelContainer) -> void:
	_steps.remove_child(panel)
	panel.queue_free()
	_reindex_steps()


func _reindex_steps() -> void:
	for index in _steps.get_child_count():
		var title := _steps.get_child(index).find_child("StepTitle", true, false) as Label
		if title != null:
			title.text = "%d. %s" % [index + 1, _type_title(str(_steps.get_child(index).get_meta("step_type", "")))]


func _document() -> Dictionary:
	var result := _base_document.duplicate(true)
	result["id"] = _id_input.text.strip_edges()
	result["nameRu"] = _name_input.text.strip_edges()
	var values: Array = []
	for raw_panel in _steps.get_children():
		values.append(_step_value(raw_panel as PanelContainer))
	result["steps"] = values
	var normalized := Store.normalized_document(result)
	if not _quest_binding_id.is_empty():
		# Editor-only handoff consumed by EmberObjectInspectorActions. It is
		# stripped before the action Resource is written.
		normalized["_editorQuestId"] = _quest_binding_id
	return normalized


func _step_value(panel: PanelContainer) -> Dictionary:
	var step_type := str(panel.get_meta("step_type", ""))
	match step_type:
		"talk": return {"type": step_type, "dialogueId": _option_value(panel, "dialogueId")}
		"give_item": return {"type": step_type, "itemId": _option_value(panel, "itemId"), "count": roundi(_number_value(panel, "count"))}
		"set_flag": return {"type": step_type, "flag": _text_value(panel, "flag"), "value": _flag_value(panel)}
		"wait": return {"type": step_type, "sec": _number_value(panel, "sec")}
		"open_shop": return {"type": step_type, "shopId": _option_value(panel, "shopId")}
		"change_map": return {
			"type": step_type,
			"targetMapId": _option_value(panel, "targetMapId"),
			"targetRegionId": _option_value(panel, "targetRegionId"),
		}
		"start_battle": return {"type": step_type, "encounterId": _option_value(panel, "encounterId")}
		"run_script": return {"type": step_type, "scriptId": _option_value(panel, "scriptId")}
	return {"type": step_type}


func _option_value(root: Node, field: String) -> String:
	var option := root.find_child("StepField_%s" % field, true, false) as OptionButton
	return "" if option == null or option.selected < 0 else str(option.get_item_metadata(option.selected))


func _text_value(root: Node, field: String) -> String:
	var input := root.find_child("StepField_%s" % field, true, false) as LineEdit
	return "" if input == null else input.text.strip_edges()


func _number_value(root: Node, field: String) -> float:
	var input := root.find_child("StepField_%s" % field, true, false) as SpinBox
	return 0.0 if input == null else input.value


func _flag_value(root: Node) -> Variant:
	var editor := root.find_child("StepTypedValueEditor", true, false) as EmberTypedValueEditor
	return editor.value() if editor != null else true


func _submit() -> void:
	var result := _document()
	var errors := Store.validation_errors(result)
	if not errors.is_empty():
		_validation.text = "\n".join(errors)
		_validation.visible = true
		return
	_validation.visible = false
	save_requested.emit(result)


func _request_delete() -> void:
	if _existing:
		delete_requested.emit(str(_base_document.get("id", "")))


func _default_step(step_type: String) -> Dictionary:
	return Store.default_step(step_type)


func _type_title(step_type: String) -> String:
	match step_type:
		"talk": return "Диалог"
		"give_item": return "Выдать предмет"
		"set_flag": return "Изменить флаг"
		"wait": return "Пауза (авто)"
		"open_shop": return "Открыть магазин"
		"change_map": return "Сменить карту (финал)"
		"start_battle": return "Начать бой (финал)"
		"run_script": return "Запустить цепочку"
	return step_type
