class_name EmberQuestJournalUi
extends Control
## EmberExploreState.flags remains the progress owner, including test resets.

var progress_state: EmberExploreState
@export var show_debug_progress := false
var _list: VBoxContainer
var _empty: Label
var _status_filter: OptionButton
var _test_tools: CheckButton
var _feedback: Label
const STATUS_FILTERS := ["", "available", "active", "done"]
const STATUS_TITLES := {"available": "Доступно", "active": "В работе", "done": "Завершено"}


func _ready() -> void:
	if progress_state == null:
		progress_state = get_node_or_null("/root/EmberExploreProgress") as EmberExploreState
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _list == null:
		_build()
	visible = false


func open() -> void:
	if _list == null:
		_build()
	_feedback.text = "Режим проверки · сохранения отключены" if EmberMapTransition.test_mode(progress_state) else ""
	_refresh()
	visible = true


func close() -> void:
	visible = false


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func is_open() -> bool:
	return visible


func blocks_movement() -> bool:
	return visible


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.025, 0.022, 0.05, 0.92)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 70)
	margin.add_theme_constant_override("margin_top", 52)
	margin.add_theme_constant_override("margin_right", 70)
	margin.add_theme_constant_override("margin_bottom", 52)
	add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	margin.add_child(body)
	var title := Label.new()
	title.text = "ЖУРНАЛ ЗАДАНИЙ"
	title.add_theme_font_size_override("font_size", 28)
	title.modulate = Color(1.0, 0.79, 0.31)
	body.add_child(title)
	var hint := Label.new()
	hint.text = "Q или Esc — закрыть"
	hint.modulate = Color(0.70, 0.70, 0.77)
	body.add_child(hint)
	var filters := HBoxContainer.new()
	body.add_child(filters)
	_status_filter = OptionButton.new()
	_status_filter.name = "QuestStatusFilter"
	for title_text in ["Все задания", "Доступные", "В работе", "Завершённые"]:
		_status_filter.add_item(title_text)
	_status_filter.item_selected.connect(func(_index: int) -> void: _refresh())
	filters.add_child(_status_filter)
	_test_tools = CheckButton.new()
	_test_tools.name = "QuestTestTools"
	_test_tools.text = "Инструменты проверки"
	_test_tools.toggled.connect(func(_enabled: bool) -> void: _refresh())
	filters.add_child(_test_tools)
	_feedback = Label.new()
	_feedback.modulate = Color("9dcdb8")
	body.add_child(_feedback)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	_list = VBoxContainer.new()
	_list.name = "QuestJournalList"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	_empty = Label.new()
	_empty.name = "QuestJournalEmpty"
	_empty.text = "В этой группе пока нет заданий."
	_empty.modulate = Color(0.72, 0.72, 0.76)
	_list.add_child(_empty)


func _refresh() -> void:
	for child in _list.get_children():
		if child != _empty:
			_list.remove_child(child)
			child.queue_free()
	var flags := progress_state.flags if progress_state != null else {}
	var entries := EmberQuestCatalog.visible_projections(flags, progress_state.inventory if progress_state != null else {}, true)
	var status_filter: String = STATUS_FILTERS[_status_filter.selected]
	_empty.visible = true
	for entry in entries:
		if not status_filter.is_empty() and entry.get("status") != status_filter:
			continue
		_list.add_child(_quest_card(entry))
		_empty.visible = false


func _quest_card(entry: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.name = "Quest_%s" % str(entry.get("id", ""))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.085, 0.08, 0.14, 0.96)
	style.border_color = EmberQuestState.color(str(entry.get("status", "available")))
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14.0
	style.content_margin_top = 10.0
	style.content_margin_right = 14.0
	style.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", style)
	var body := VBoxContainer.new()
	panel.add_child(body)
	var status := str(entry.get("status", "available"))
	var heading := Label.new()
	heading.name = "QuestJournalTitle"
	heading.text = "%s  %s" % [EmberQuestState.glyph(status), str(entry.get("titleRu", entry.get("id", "")))]
	heading.add_theme_font_size_override("font_size", 20)
	heading.modulate = EmberQuestState.color(status)
	body.add_child(heading)
	var state_label := Label.new()
	state_label.text = STATUS_TITLES.get(status, status)
	state_label.modulate = EmberQuestState.color(status)
	body.add_child(state_label)
	var summary := str(entry.get("summaryRu", "")).strip_edges()
	if not summary.is_empty():
		var summary_label := Label.new()
		summary_label.text = summary
		summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(summary_label)
	var objectives: Array = entry.get("objectives", [])
	for raw_objective in objectives:
		var objective: Dictionary = raw_objective
		if bool(objective.get("locked",false)) and not (show_debug_progress or _test_tools.button_pressed or EmberMapTransition.test_mode(progress_state)): continue
		var line := Label.new()
		line.name = "QuestObjective_%s" % str(objective.get("id", ""))
		var done := bool(objective.get("done", false))
		var locked := bool(objective.get("locked", false))
		var missing: Array = objective.get("missingPrerequisiteTexts", [])
		var suffix := "  (необязательно)" if bool(objective.get("optional", false)) else ""
		if str(objective.get("progressMode", "flag")) in ["counter", "purchase", "handover", "world_action"]:
			suffix = "  (%d/%d)%s" % [
				int(objective.get("currentCount", 0)),
				int(objective.get("requiredCount", 1)),
				suffix,
			]
		if locked:
			suffix += "  · сначала: %s" % ", ".join(missing)
		line.text = "%s %s%s" % [
			"✓" if done else "◇" if locked else "◆",
			str(objective.get("textRu", "")),
			suffix,
		]
		line.modulate = (
			Color(0.56, 0.88, 0.62)
			if done
			else Color(0.50, 0.56, 0.66)
			if locked
			else Color(0.46, 0.76, 1.0)
		)
		line.tooltip_text = (
			"Цель откроется после выполнения указанных предыдущих целей."
			if locked
			else "Текущая доступная цель."
		)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(line)
		var direction := str(objective.get("directionRu", "")).strip_edges()
		if status == "active" and bool(objective.get("available", false)) and not direction.is_empty():
			var note := Label.new()
			note.name = "QuestDirection_%s" % str(objective.get("id", ""))
			note.text = direction
			note.modulate = Color(0.82, 0.81, 0.69)
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			body.add_child(note)
	var flag_ids := EmberQuestCatalog.progress_flag_ids(EmberQuestCatalog.definition(str(entry.get("id", ""))))
	var stored: Array[String] = []
	var flags := progress_state.flags if progress_state != null else {}
	for flag_id in flag_ids:
		if flags.has(flag_id):
			stored.append("%s = %s" % [flag_id, str(flags[flag_id])])
	var source := Label.new()
	source.name = "QuestProgressSource"
	source.text = (
		"Слот %d: %s" % [progress_state.active_slot, ", ".join(stored)]
		if progress_state != null and not stored.is_empty()
		else "Сохранение: флаги этого задания ещё не записаны"
	)
	source.tooltip_text = "Именно эти typed flags определяют статус и галочки целей."
	source.modulate = Color(0.52, 0.60, 0.72)
	source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if show_debug_progress:
		body.add_child(source)
	else:
		source.free()
	if (show_debug_progress or _test_tools.button_pressed or EmberMapTransition.test_mode(progress_state)) and progress_state != null and not stored.is_empty():
		var reset := Button.new()
		reset.name = "ResetQuestProgress_%s" % str(entry.get("id", ""))
		reset.text = "Начать задание заново"
		reset.tooltip_text = "Сбрасывает статус и цели задания. Предметы и награды остаются. Сохранения отключаются до выхода из игры."
		reset.pressed.connect(_reset_quest_progress.bind(flag_ids))
		body.add_child(reset)
	return panel


func _reset_quest_progress(flag_ids: Array[String]) -> void:
	if progress_state == null or progress_state.combat_party_locked:
		return
	EmberMapTransition.enable_test_mode(progress_state)
	progress_state.clear_flags(flag_ids, false)
	_status_filter.select(0)
	_feedback.text = "Задание снова доступно. Сохранения отключены до выхода из игры."
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.physical_keycode in [KEY_Q, KEY_ESCAPE]:
		close()
		get_viewport().set_input_as_handled()
