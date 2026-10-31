extends Control
## Read-only HUD over QuestCatalog.projection. The journal and action scripts
## remain the only quest definition/progress path; nothing new is serialized.
var progress_state: EmberExploreState
var _card: PanelContainer
var _title: Label
var _objective: Label
var _toast: PanelContainer
var _toast_text: Label
var _tracked_id := ""
var _signature := ""
var _initialized := false
var _toast_tween: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card = _panel("QuestTracker")
	_card.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_card.offset_left = -360
	_card.offset_right = -16
	_card.offset_top = 112
	var column := VBoxContainer.new()
	_card.add_child(column)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size",18)
	_title.modulate = Color("ffe4a0")
	column.add_child(_title)
	_objective = Label.new()
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective.custom_minimum_size.x = 310
	column.add_child(_objective)
	_toast = _panel("QuestUpdate")
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_left = -240
	_toast.offset_right = 240
	_toast.offset_top = 72
	_toast_text = Label.new()
	_toast_text.custom_minimum_size.x = 448
	_toast_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_child(_toast_text)
	_toast.hide()
	if progress_state != null: progress_state.progress_changed.connect(refresh)
	refresh()

func _panel(node_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045,0.065,0.09,0.87)
	style.border_color = Color(0.9,0.74,0.36,0.6)
	style.border_width_left = 2
	style.set_corner_radius_all(6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel",style)
	add_child(panel)
	return panel

func refresh() -> void:
	if not is_inside_tree() or progress_state == null: return
	var entries := EmberQuestCatalog.visible_projections(progress_state.flags, progress_state.inventory)
	var selected: Dictionary = {}
	for entry in entries:
		if entry.status != "active": continue
		if selected.is_empty() or entry.id == _tracked_id: selected = entry
		if entry.id == _tracked_id: break
	var previous_id := _tracked_id
	if selected.is_empty() and not previous_id.is_empty():
		for entry in entries:
			if entry.id == previous_id: selected = entry; break
	_card.visible = not selected.is_empty() and selected.status == "active"
	var current: Dictionary = {}
	for objective in selected.get("objectives",[]):
		if objective.get("available",false): current = objective;break
	_tracked_id = str(selected.get("id",""))
	var signature := "%s|%s|%s" % [_tracked_id,selected.get("status",""),current.get("id","")]
	if _card.visible:
		_title.text = str(selected.titleRu)
		var objective_text := str(current.get("textRu", ""))
		if str(current.get("progressMode", "flag")) in ["counter", "purchase", "handover"]:
			objective_text += " · %d/%d" % [int(current.get("currentCount", 0)), int(current.get("requiredCount", 1))]
		_objective.text = "Этап %d/%d · %s\nQ — журнал заданий" % [mini(int(selected.completed)+1,int(selected.required)),int(selected.required),objective_text]
	if _initialized and signature != _signature and not selected.is_empty():
		var heading := "Задание выполнено" if selected.status == "done" else ("Новое задание" if previous_id != _tracked_id else "Цель обновлена")
		show_update(heading + " · " + str(selected.titleRu) + ("\n"+str(current.get("textRu","")) if not current.is_empty() else ""))
	_signature = signature
	_initialized = true

func show_update(message: String) -> void:
	if _toast_tween != null: _toast_tween.kill()
	_toast_text.text = message
	_toast.modulate.a = 1
	_toast.show()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(3.5)
	_toast_tween.tween_property(_toast,"modulate:a",0.0,0.35)
	_toast_tween.tween_callback(_toast.hide)
