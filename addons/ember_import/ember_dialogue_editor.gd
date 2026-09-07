@tool
class_name EmberDialogueEditor
extends VBoxContainer
## Inline card editor for the lossless linear/simple-choice subset of JOI scenes.

const Store = preload("res://addons/ember_import/ember_dialogue_store.gd")
const TypedValueEditor = preload("res://addons/ember_import/ember_typed_value_editor.gd")
const QuestStore = preload("res://addons/ember_import/ember_quest_store.gd")
const VisualLibraryPopup = preload("res://addons/ember_import/ember_visual_library_popup.gd")

signal save_requested(document: Dictionary)
signal cancel_requested

var _base_document: Dictionary = {}
var _id_input: LineEdit
var _name_input: LineEdit
var _use_input: OptionButton
var _cards: VBoxContainer
var _validation: Label
var _quest_flag_library: EmberVisualLibraryPopup
var _quest_flag_target: LineEdit


func setup(dialogue_id: String, suggested_id: String, document_override: Dictionary = {}) -> void:
	name = "DialogueEditor"
	add_theme_constant_override("separation", 6)
	_base_document = document_override.duplicate(true) if not document_override.is_empty() else Store.document(dialogue_id)
	_build_header(not _base_document.is_empty())
	_id_input.text = dialogue_id if not dialogue_id.is_empty() else suggested_id
	_id_input.editable = _base_document.is_empty()
	_name_input.text = str(_base_document.get("nameRu", "Новый диалог"))
	_select_metadata(_use_input, str(_base_document.get("use", "talk")))
	_cards = VBoxContainer.new()
	_cards.name = "DialogueCards"
	_cards.add_theme_constant_override("separation", 5)
	add_child(_cards)
	var projected := Store.projection(_base_document)
	if not bool(projected.get("ok", false)):
		var blocked := Label.new()
		blocked.name = "DialogueUnsupported"
		blocked.text = "Безопасное редактирование недоступно:\n%s\nОригинальный JSON не будет изменён." % projected.get("error", "")
		blocked.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		blocked.modulate = Color(1.0, 0.58, 0.42)
		add_child(blocked)
		return
	for raw_card in projected.get("cards", []):
		if typeof(raw_card) == TYPE_DICTIONARY:
			_add_card(raw_card)
	_build_add_row()
	_validation = Label.new()
	_validation.name = "DialogueValidation"
	_validation.visible = false
	_validation.modulate = Color(1.0, 0.48, 0.42)
	_validation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_validation)
	var actions := HBoxContainer.new()
	add_child(actions)
	var save := Button.new()
	save.name = "SaveDialogue"
	save.text = "Сохранить диалог"
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save.tooltip_text = "Пишет canonical content/ember/scenes/<id>.json через одну Undo/Redo operation."
	save.pressed.connect(_submit)
	actions.add_child(save)
	var cancel := Button.new()
	cancel.name = "CancelDialogue"
	cancel.text = "Закрыть"
	cancel.pressed.connect(cancel_requested.emit)
	actions.add_child(cancel)


func _build_header(existing: bool) -> void:
	var title := Label.new()
	title.text = "ДИАЛОГ · РЕПЛИКИ И ПРОСТОЙ ВЫБОР"
	title.modulate = Color(0.92, 0.74, 0.42)
	title.add_theme_font_size_override("font_size", 12)
	add_child(title)
	var scope := Label.new()
	scope.text = "Карточки безопасно редактируют talk/shop_intro без stage actors, фонов, splash и произвольных циклов."
	scope.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scope.modulate = Color(0.66, 0.72, 0.80)
	add_child(scope)
	_id_input = _line_row("DialogueId", "ID", "После первого сохранения не переименовывается")
	add_child(_id_input.get_parent())
	_name_input = _line_row("DialogueName", "Название", "Видно автору")
	add_child(_name_input.get_parent())
	var use_row := _row("Назначение")
	_use_input = OptionButton.new()
	_use_input.name = "DialogueUse"
	for data in [["Обычный разговор", "talk"], ["Вступление магазина", "shop_intro"]]:
		_use_input.add_item(data[0])
		_use_input.set_item_metadata(_use_input.item_count - 1, data[1])
	_use_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	use_row.add_child(_use_input)
	add_child(use_row)
	if existing:
		var source := Label.new()
		source.text = "Источник: %s" % EmberPack.scene_path(str(_base_document.get("id", "")))
		source.modulate = Color(0.62, 0.72, 0.82)
		source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(source)


func _build_add_row() -> void:
	var row := HBoxContainer.new()
	row.name = "AddDialogueCard"
	add_child(row)
	var kind := OptionButton.new()
	kind.name = "NewDialogueCardType"
	kind.add_item("Реплика")
	kind.set_item_metadata(0, "line")
	kind.add_item("Выбор с ответами")
	kind.set_item_metadata(1, "choice")
	kind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(kind)
	var add := Button.new()
	add.name = "AddDialogueCardButton"
	add.text = "+ Карточка"
	add.pressed.connect(func() -> void: _add_card(_default_card(str(kind.get_item_metadata(kind.selected)))))
	row.add_child(add)


func _add_card(card: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.name = "DialogueCard"
	panel.set_meta("kind", str(card.get("kind", "line")))
	panel.add_theme_stylebox_override("panel", _panel_style())
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	panel.add_child(body)
	var head := HBoxContainer.new()
	body.add_child(head)
	var title := Label.new()
	title.name = "DialogueCardTitle"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	for data in [["↑", -1], ["↓", 1]]:
		var move := Button.new()
		move.name = "DialogueCardMove"
		move.text = data[0]
		move.pressed.connect(_move_card.bind(panel, int(data[1])))
		head.add_child(move)
	var remove := Button.new()
	remove.name = "DialogueCardRemove"
	remove.text = "×"
	remove.modulate = Color(1.0, 0.62, 0.58)
	remove.pressed.connect(_remove_card.bind(panel))
	head.add_child(remove)
	if str(card.get("kind", "line")) == "choice":
		_build_choice(body, card)
	else:
		_build_line(body, card, "DialogueField")
	_cards.add_child(panel)
	_reindex_cards()


func _build_line(parent: VBoxContainer, value: Dictionary, prefix: String) -> void:
	parent.add_child(_text_row("%s_speaker" % prefix, "Speaker ID", str(value.get("speaker", ""))))
	parent.add_child(_text_row("%s_nameRu" % prefix, "Имя в окне", str(value.get("nameRu", ""))))
	parent.add_child(_text_row("%s_portraitKey" % prefix, "Выражение", str(value.get("portraitKey", "neutral"))))
	parent.add_child(_multiline_row("%s_textRu" % prefix, "Реплика", str(value.get("textRu", ""))))


func _build_choice(parent: VBoxContainer, card: Dictionary) -> void:
	parent.add_child(_multiline_row("ChoicePrompt", "Вопрос", str(card.get("promptRu", ""))))
	var options := VBoxContainer.new()
	options.name = "ChoiceOptions"
	options.add_theme_constant_override("separation", 4)
	parent.add_child(options)
	for raw_option in card.get("options", []):
		if typeof(raw_option) == TYPE_DICTIONARY:
			_add_choice_option(options, raw_option)
	var add := Button.new()
	add.name = "AddChoiceOption"
	add.text = "+ Ответ"
	add.pressed.connect(_add_choice_option.bind(options, _default_option()))
	parent.add_child(add)


func _add_choice_option(options: VBoxContainer, value: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.name = "ChoiceOption"
	var body := VBoxContainer.new()
	panel.add_child(body)
	var head := HBoxContainer.new()
	body.add_child(head)
	var title := Label.new()
	title.name = "ChoiceOptionTitle"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var remove := Button.new()
	remove.name = "DialogueOptionRemove"
	remove.text = "×"
	remove.pressed.connect(func() -> void:
		options.remove_child(panel)
		panel.queue_free()
		_reindex_options(options)
	)
	head.add_child(remove)
	body.add_child(_text_row("OptionLabel", "Текст выбора", str(value.get("labelRu", ""))))
	_build_line(body, value, "ReplyField")
	var flag_toggle := CheckBox.new()
	flag_toggle.name = "ChoiceFlagEnabled"
	flag_toggle.text = "После выбора изменить флаг"
	flag_toggle.button_pressed = not str(value.get("flag", "")).is_empty()
	body.add_child(flag_toggle)
	var flag_fields := VBoxContainer.new()
	flag_fields.name = "ChoiceFlagFields"
	body.add_child(flag_fields)
	var flag_row := _text_row("ChoiceFlagId", "Имя флага", str(value.get("flag", "")))
	var flag_input := flag_row.find_child("ChoiceFlagId", true, false) as LineEdit
	var flag_library := Button.new()
	flag_library.name = "OpenChoiceQuestFlagLibrary"
	flag_library.text = "▦"
	flag_library.tooltip_text = "Выбрать общий статус задания или флаг выполнения цели"
	flag_library.pressed.connect(_open_quest_flag_library.bind(flag_input))
	flag_row.add_child(flag_library)
	flag_fields.add_child(flag_row)
	var typed := TypedValueEditor.new() as EmberTypedValueEditor
	typed.name = "ChoiceTypedValueEditor"
	typed.setup(value.get("value", true), "ChoiceFlagValue")
	flag_fields.add_child(typed)
	flag_fields.visible = flag_toggle.button_pressed
	flag_toggle.toggled.connect(func(enabled: bool) -> void: flag_fields.visible = enabled)
	options.add_child(panel)
	_reindex_options(options)


func _document() -> Dictionary:
	var cards: Array[Dictionary] = []
	for raw_panel in _cards.get_children():
		var panel := raw_panel as PanelContainer
		if str(panel.get_meta("kind", "")) == "choice":
			var options: Array[Dictionary] = []
			var option_box := panel.find_child("ChoiceOptions", true, false) as VBoxContainer
			for raw_option in option_box.get_children():
				options.append(_choice_option_value(raw_option))
			cards.append({
				"kind": "choice",
				"promptRu": _multiline_value(panel, "ChoicePrompt"),
				"options": options,
			})
		else:
			var line := _line_value(panel, "DialogueField")
			line["kind"] = "line"
			cards.append(line)
	return Store.document_from_cards({
		"id": _id_input.text,
		"nameRu": _name_input.text,
		"use": str(_use_input.get_item_metadata(_use_input.selected)),
	}, cards)


func _choice_option_value(option: Node) -> Dictionary:
	var result := _line_value(option, "ReplyField")
	result["labelRu"] = _text_value(option, "OptionLabel")
	var enabled := option.find_child("ChoiceFlagEnabled", true, false) as CheckBox
	if enabled != null and enabled.button_pressed:
		result["flag"] = _text_value(option, "ChoiceFlagId")
		var typed := option.find_child("ChoiceTypedValueEditor", true, false) as EmberTypedValueEditor
		result["value"] = typed.value() if typed != null else true
	else:
		result["flag"] = ""
		result["value"] = true
	return result


func _line_value(root: Node, prefix: String) -> Dictionary:
	return {
		"speaker": _text_value(root, "%s_speaker" % prefix),
		"nameRu": _text_value(root, "%s_nameRu" % prefix),
		"portraitKey": _text_value(root, "%s_portraitKey" % prefix),
		"textRu": _multiline_value(root, "%s_textRu" % prefix),
	}


func _submit() -> void:
	var result := _document()
	var errors := Store.validation_errors(result)
	if not errors.is_empty():
		_validation.text = "\n".join(errors)
		_validation.visible = true
		return
	_validation.visible = false
	save_requested.emit(result)


func _open_quest_flag_library(target: LineEdit) -> void:
	if target == null:
		return
	if _quest_flag_library == null:
		_quest_flag_library = VisualLibraryPopup.new() as EmberVisualLibraryPopup
		_quest_flag_library.name = "DialogueQuestFlagLibrary"
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


func _choose_quest_flag_value(value: String) -> void:
	if _quest_flag_target != null and is_instance_valid(_quest_flag_target):
		_quest_flag_target.text = value
	_quest_flag_target = null


func _move_card(panel: PanelContainer, delta: int) -> void:
	_cards.move_child(panel, clampi(panel.get_index() + delta, 0, _cards.get_child_count() - 1))
	_reindex_cards()


func _remove_card(panel: PanelContainer) -> void:
	_cards.remove_child(panel)
	panel.queue_free()
	_reindex_cards()


func _reindex_cards() -> void:
	for index in _cards.get_child_count():
		var panel := _cards.get_child(index)
		var title := panel.find_child("DialogueCardTitle", true, false) as Label
		if title != null:
			title.text = "%d. %s" % [index + 1, "Выбор" if str(panel.get_meta("kind", "")) == "choice" else "Реплика"]


func _reindex_options(options: VBoxContainer) -> void:
	for index in options.get_child_count():
		var title := options.get_child(index).find_child("ChoiceOptionTitle", true, false) as Label
		if title != null:
			title.text = "Ответ %d" % (index + 1)


func _default_card(kind: String) -> Dictionary:
	if kind == "choice":
		return {"kind": "choice", "promptRu": "", "options": [_default_option(), _default_option()]}
	return {"kind": "line", "speaker": "guide", "portraitKey": "neutral", "nameRu": "Проводник", "textRu": ""}


func _default_option() -> Dictionary:
	return {"labelRu": "", "speaker": "guide", "portraitKey": "neutral", "nameRu": "Проводник", "textRu": "", "flag": "", "value": true}


func _line_row(node_name: String, title: String, tooltip: String) -> LineEdit:
	var input := LineEdit.new()
	input.name = node_name
	input.tooltip_text = tooltip
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := _row(title)
	row.add_child(input)
	return input


func _text_row(node_name: String, title: String, current: String) -> Control:
	var row := _row(title)
	var input := LineEdit.new()
	input.name = node_name
	input.text = current
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input)
	return row


func _multiline_row(node_name: String, title: String, current: String) -> Control:
	var column := VBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.modulate = Color(0.72, 0.72, 0.75)
	column.add_child(label)
	var input := TextEdit.new()
	input.name = node_name
	input.text = current
	input.custom_minimum_size.y = 58.0
	input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	column.add_child(input)
	return column


func _row(title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 96.0
	label.modulate = Color(0.72, 0.72, 0.75)
	row.add_child(label)
	return row


func _text_value(root: Node, name_value: String) -> String:
	var input := root.find_child(name_value, true, false) as LineEdit
	return input.text.strip_edges() if input != null else ""


func _multiline_value(root: Node, name_value: String) -> String:
	var input := root.find_child(name_value, true, false) as TextEdit
	return input.text.strip_edges() if input != null else ""


func _select_metadata(option: OptionButton, value: String) -> void:
	for index in option.item_count:
		if str(option.get_item_metadata(index)) == value:
			option.select(index)
			return


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.13, 0.145)
	style.border_color = Color(0.34, 0.29, 0.20)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(6.0)
	return style
