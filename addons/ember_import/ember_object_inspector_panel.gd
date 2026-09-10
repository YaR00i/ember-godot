@tool
class_name EmberObjectInspectorPanel
extends VBoxContainer
## Compact read-only Ember projection embedded in Godot's native Inspector.

const InteractEditor = preload("res://addons/ember_import/ember_interact_editor.gd")
const ActionChainEditor = preload("res://addons/ember_import/ember_action_chain_editor.gd")
const ActionScriptStore = preload("res://addons/ember_import/ember_action_script_store.gd")
const QuestEditor = preload("res://addons/ember_import/ember_quest_editor.gd")
const QuestStore = preload("res://addons/ember_import/ember_quest_store.gd")

signal rebuild_requested(prop: EmberVoxelProp)
signal canvas_action_requested(prop: EmberVoxelProp, action: String)
signal interact_save_requested(prop: EmberVoxelProp, values: Dictionary)
signal interact_remove_requested(prop: EmberVoxelProp)
signal chain_save_requested(prop: EmberVoxelProp, document: Dictionary)
signal chain_remove_requested(prop: EmberVoxelProp)
signal standalone_save_requested(interact: EmberInteract, values: Dictionary)
signal standalone_remove_requested(interact: EmberInteract)
signal standalone_chain_save_requested(interact: EmberInteract, document: Dictionary)
signal standalone_chain_remove_requested(interact: EmberInteract)
signal standalone_bounds_save_requested(interact: EmberInteract, size: Vector3)
signal dialogue_save_requested(document: Dictionary)
signal shop_save_requested(document: Dictionary)
signal shop_migrate_requested(shop_id: String)
signal item_save_requested(document: Dictionary)
signal item_migrate_requested(item_id: String)
signal quest_save_requested(interact: EmberInteract, document: Dictionary)

var _prop: EmberVoxelProp
var _standalone: EmberInteract
var _snapshot: Dictionary = {}
var _components_box: VBoxContainer


func setup(selected: Object, snapshot: Dictionary) -> void:
	_prop = EmberObjectInspectorModel.voxel_owner(selected)
	_standalone = selected as EmberInteract if _prop == null and selected is EmberInteract else null
	_snapshot = snapshot
	name = "EmberObjectInspectorPanel"
	_build()


func _build() -> void:
	var title := Label.new()
	title.name = "Header"
	title.text = "EMBER OBJECT"
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)

	var identity := Label.new()
	identity.text = "%s · %s" % [
		str(_snapshot.get("name", "?")),
		str(_snapshot.get("kind", "Object")),
	]
	identity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(identity)

	var ids := Label.new()
	var id_lines: Array[String] = []
	var placement_id := str(_snapshot.get("placementId", ""))
	var model_id := str(_snapshot.get("modelId", ""))
	if not placement_id.is_empty():
		id_lines.append("placement  %s" % placement_id)
	if not model_id.is_empty():
		id_lines.append("model      %s" % model_id)
	var map_id := str(_snapshot.get("mapId", ""))
	if not map_id.is_empty():
		id_lines.append("map        %s" % map_id)
	ids.text = "\n".join(id_lines)
	ids.modulate = Color(0.75, 0.75, 0.78)
	ids.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(ids)

	var state := Label.new()
	state.name = "PrefabState"
	state.text = "Prefab: %s" % str(_snapshot.get("prefabState", "—"))
	state.modulate = (
		Color(1.0, 0.65, 0.4)
		if str(_snapshot.get("prefabState", "")) == "нужна пересборка"
		else Color(0.62, 0.9, 0.68)
	)
	add_child(state)

	_build_actions()
	add_child(HSeparator.new())

	var component_title := Label.new()
	component_title.text = "КОМПОНЕНТЫ"
	component_title.add_theme_font_size_override("font_size", 13)
	add_child(component_title)
	var view_filter := OptionButton.new()
	view_filter.name = "ViewFilter"
	view_filter.add_item("Все")
	view_filter.add_item("Ошибки")
	view_filter.tooltip_text = "Показать все карточки или только карточки с ошибочными полями."
	view_filter.item_selected.connect(_apply_filter)
	add_child(view_filter)
	_components_box = VBoxContainer.new()
	_components_box.name = "Components"
	_components_box.add_theme_constant_override("separation", 6)
	add_child(_components_box)
	var components: Array = _snapshot.get("components", [])
	for raw_component in components:
		if typeof(raw_component) == TYPE_DICTIONARY:
			_components_box.add_child(_component_card(raw_component))
	if _prop != null and _prop.get_node_or_null("Interact") == null:
		_components_box.add_child(_add_interact_card())

	add_child(HSeparator.new())
	_build_diagnostics()


func _build_actions() -> void:
	if _prop != null:
		var canvas_actions := VBoxContainer.new()
		canvas_actions.name = "VoxelCanvasActions"
		for entry in [["Редактировать в Canvas", "selected"], ["Редактировать общую модель…", "shared"], ["Создать экземпляр", "linked"], ["Создать независимую копию", "independent"]]:
			var button := Button.new()
			button.text = entry[0]
			button.pressed.connect(func(): canvas_action_requested.emit(_prop, entry[1]))
			canvas_actions.add_child(button)
		add_child(canvas_actions)
	var actions := HBoxContainer.new()
	actions.name = "Actions"
	if _prop != null and not bool(_snapshot.get("selectedIsOwner", true)):
		var select_owner := Button.new()
		select_owner.text = "Выбрать owner"
		select_owner.tooltip_text = "Generated child не является authoring API. Выбирает владеющий EmberVoxelProp."
		select_owner.pressed.connect(_select_owner)
		actions.add_child(select_owner)
	var sources: Dictionary = _snapshot.get("sources", {})
	var vox_path := str(sources.get("vox", ""))
	var json_path := str(sources.get("json", ""))
	var source_path := vox_path if not vox_path.is_empty() else json_path
	if not source_path.is_empty():
		var open_source := Button.new()
		open_source.text = "Открыть source"
		open_source.tooltip_text = source_path
		open_source.pressed.connect(_open_path.bind(source_path))
		actions.add_child(open_source)
	if _prop != null:
		var rebuild := Button.new()
		rebuild.text = "Rebuild prefab"
		rebuild.tooltip_text = "Использует существующую безопасную targeted rebuild-команду migration dock."
		rebuild.pressed.connect(_request_rebuild)
		actions.add_child(rebuild)
	if actions.get_child_count() > 0:
		add_child(actions)


func _component_card(component: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var component_id := str(component.get("id", "unknown"))
	var component_title := str(component.get("title", "Component"))
	var has_error := _component_has_errors(component)
	panel.name = "Component_%s" % component_id
	panel.set_meta("has_error", has_error)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.145, 0.145, 0.155), Color(0.25, 0.25, 0.28)))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 2)
	panel.add_child(body)

	var head := HBoxContainer.new()
	body.add_child(head)
	var toggle := Button.new()
	toggle.name = "Toggle_%s" % component_id
	toggle.flat = true
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var expanded := has_error or component_id in ["light", "interact"]
	_set_toggle_text(toggle, component_id, component_title, expanded)
	head.add_child(toggle)
	var source_name := str(component.get("source", ""))
	head.add_child(_source_badge(source_name))

	var content := VBoxContainer.new()
	content.name = "Content_%s" % component_id
	content.add_theme_constant_override("separation", 1)
	content.visible = expanded
	body.add_child(content)
	toggle.pressed.connect(_toggle_component.bind(content, toggle, component_id, component_title))

	var destination := _interaction_destination(component)
	if destination != null:
		content.add_child(destination)

	var rows: Array = component.get("rows", [])
	for raw_row in rows:
		if typeof(raw_row) == TYPE_DICTIONARY:
			if destination != null and str(raw_row.get("label", "")) in ["Trigger", "Target map", "Target region"]:
				continue
			content.add_child(_row(raw_row))
	if component_id == "interact" and (_prop != null or _standalone != null):
		content.add_child(_existing_interact_actions())
	return panel


func _row(row: Dictionary) -> Control:
	var line := HBoxContainer.new()
	var label := Label.new()
	label.text = _display_label(str(row.get("label", "")))
	label.custom_minimum_size.x = 118.0
	label.modulate = Color(0.72, 0.72, 0.75)
	line.add_child(label)
	var value := Label.new()
	value.text = _display_value(str(row.get("value", "—")))
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if str(row.get("status", "")) == "error":
		value.modulate = Color(1.0, 0.48, 0.42)
	line.add_child(value)
	var source_name := str(row.get("source", ""))
	if not source_name.is_empty():
		line.add_child(_source_badge(source_name, true))
	return line


func _toggle_component(content: Control, button: Button, component_id: String, title: String) -> void:
	content.visible = not content.visible
	_set_toggle_text(button, component_id, title, content.visible)


func _set_toggle_text(button: Button, component_id: String, title: String, expanded: bool) -> void:
	button.text = "%s  %s  %s" % ["▾" if expanded else "▸", _component_icon(component_id), _component_title(title)]


func _component_icon(component_id: String) -> String:
	match component_id:
		"renderer": return "▦"
		"collider": return "◇"
		"trigger_volume": return "▱"
		"light": return "●"
		"interact": return "F"
	return "◆"


func _component_title(title: String) -> String:
	match title:
		"Voxel Renderer": return "Воксельный рендер"
		"Collider": return "Коллизия"
		"Trigger Volume": return "Зона триггера"
		"Emissive Light": return "Свет"
		"Interact": return "Взаимодействие"
	return title


func _interaction_destination(component: Dictionary) -> Control:
	if str(component.get("id", "")) != "interact":
		return null
	var values: Dictionary = {}
	var rows: Array = component.get("rows", [])
	for raw_row in rows:
		if typeof(raw_row) == TYPE_DICTIONARY:
			values[str(raw_row.get("label", ""))] = _reference_value(str(raw_row.get("value", "")))
	var target_map := str(values.get("Target map", ""))
	var target_region := str(values.get("Target region", ""))
	if target_map.is_empty() and target_region.is_empty():
		return null
	var destination := PanelContainer.new()
	destination.name = "InteractDestination"
	destination.add_theme_stylebox_override("panel", _panel_style(Color(0.105, 0.16, 0.13), Color(0.32, 0.62, 0.42)))
	var destination_body := VBoxContainer.new()
	destination.add_child(destination_body)
	var eyebrow := Label.new()
	eyebrow.text = "ПЕРЕХОД"
	eyebrow.modulate = Color(0.55, 0.82, 0.62)
	eyebrow.add_theme_font_size_override("font_size", 11)
	destination_body.add_child(eyebrow)
	var route := Label.new()
	route.text = "%s  →  %s" % [target_map if not target_map.is_empty() else "эта карта", target_region if not target_region.is_empty() else "старт"]
	route.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	destination_body.add_child(route)
	var trigger := str(values.get("Trigger", ""))
	if not trigger.is_empty():
		var trigger_label := Label.new()
		trigger_label.text = "Триггер: %s" % trigger
		trigger_label.modulate = Color(0.72, 0.72, 0.75)
		destination_body.add_child(trigger_label)
	return destination


func _reference_value(value: String) -> String:
	return value.replace(" · resolved", "").replace(" · MISSING", "")


func _existing_interact_actions() -> Control:
	var wrapper := VBoxContainer.new()
	wrapper.name = "InteractAuthoring"
	var buttons := HFlowContainer.new()
	buttons.name = "InteractActions"
	buttons.add_theme_constant_override("h_separation", 4)
	buttons.add_theme_constant_override("v_separation", 4)
	wrapper.add_child(buttons)
	var edit := Button.new()
	edit.text = "Настройки"
	edit.tooltip_text = "Редактирует scene-owned Interact через Undo/Redo."
	buttons.add_child(edit)
	var remove := Button.new()
	remove.text = "Удалить"
	remove.tooltip_text = "Удаляет Interact из текущей сцены. Ctrl+Z восстанавливает."
	remove.modulate = Color(1.0, 0.65, 0.62)
	remove.pressed.connect(_request_remove_interact)
	buttons.add_child(remove)
	var interact := _authoring_interact()
	var chain_holder := VBoxContainer.new()
	chain_holder.name = "ActionChainEditorHolder"
	var chain_button: Button = null
	var chain_id := ""
	if interact != null and interact.kind in ["talk", "shop", "trigger", "custom", "quest_marker"]:
		chain_id = interact.script_id
		if interact.kind == "quest_marker" and interact.quest_id.is_empty():
			# The legacy value is the status flag, not an action document.
			chain_id = ""
		var chain := Button.new()
		chain_button = chain
		chain.name = "EditActionChainButton"
		chain.text = "Действия"
		chain.tooltip_text = "Редактирует цепочку объекта. У quest-marker она отделена от состояния задания."
		chain.pressed.connect(_toggle_action_chain_editor.bind(
			chain_holder,
			chain,
			chain_id,
			interact.effective_quest_id() if interact.kind == "quest_marker" else "",
		))
		buttons.add_child(chain)
	var quest_holder := VBoxContainer.new()
	quest_holder.name = "QuestEditorHolder"
	if interact != null and interact.kind == "quest_marker":
		var quest := Button.new()
		quest.name = "EditQuestButton"
		quest.text = "Описание задания"
		quest.tooltip_text = "Описание и цели задания; состояние остаётся в typed flags."
		quest.pressed.connect(_toggle_quest_editor.bind(quest_holder, quest, interact))
		buttons.add_child(quest)
		var quest_event := Button.new()
		quest_event.name = "BindQuestEventButton"
		quest_event.text = "+ Событие задания"
		quest_event.tooltip_text = "Создаёт или открывает цепочку объекта и сразу предлагает начать задание, выполнить цель или завершить его."
		quest_event.pressed.connect(
			_open_quest_event_for_interact.bind(
				chain_holder,
				chain_button,
				chain_id,
				interact.effective_quest_id(),
			)
		)
		buttons.add_child(quest_event)
	if _standalone != null:
		var bounds := Button.new()
		bounds.name = "EditStandaloneBoundsButton"
		bounds.text = "Размер зоны"
		bounds.tooltip_text = "Редактирует BoxShape3D этой scene-owned зоны одной Undo/Redo operation."
		buttons.add_child(bounds)
	var holder := VBoxContainer.new()
	holder.name = "InteractEditorHolder"
	wrapper.add_child(holder)
	edit.pressed.connect(_toggle_existing_interact_editor.bind(holder, edit))
	wrapper.add_child(chain_holder)
	wrapper.add_child(quest_holder)
	if _standalone != null:
		var bounds_holder := VBoxContainer.new()
		bounds_holder.name = "StandaloneBoundsEditorHolder"
		wrapper.add_child(bounds_holder)
		var bounds_button := buttons.get_node_or_null("EditStandaloneBoundsButton") as Button
		if bounds_button != null:
			bounds_button.pressed.connect(_toggle_standalone_bounds_editor.bind(bounds_holder, bounds_button))
	return wrapper


func _add_interact_card() -> Control:
	var panel := PanelContainer.new()
	panel.name = "AddInteract"
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.12, 0.15, 0.125), Color(0.30, 0.52, 0.34)))
	var body := VBoxContainer.new()
	panel.add_child(body)
	var add := Button.new()
	add.name = "AddInteractButton"
	add.text = "+ Добавить взаимодействие"
	add.alignment = HORIZONTAL_ALIGNMENT_LEFT
	add.tooltip_text = "Создаёт scene-owned EmberInteract; исходный JOI JSON не меняется."
	body.add_child(add)
	var holder := VBoxContainer.new()
	holder.name = "InteractEditorHolder"
	body.add_child(holder)
	add.pressed.connect(_toggle_new_interact_editor.bind(holder, add))
	var quick := Button.new()
	quick.name = "QuickTriggerChainButton"
	quick.text = "+ Триггер с цепочкой"
	quick.alignment = HORIZONTAL_ALIGNMENT_LEFT
	quick.tooltip_text = "Одной Undo-операцией создаёт scene-owned Interact + Shape и canonical документ цепочки."
	body.add_child(quick)
	var chain_holder := VBoxContainer.new()
	chain_holder.name = "ActionChainEditorHolder"
	body.add_child(chain_holder)
	quick.pressed.connect(_toggle_action_chain_editor.bind(chain_holder, quick, ""))
	return panel


func _toggle_existing_interact_editor(holder: VBoxContainer, button: Button) -> void:
	if holder.get_child_count() == 0:
		var interact := _authoring_interact()
		holder.add_child(_make_interact_editor(EmberSceneAuthoring.interact_values(interact), false))
		holder.visible = true
	else:
		holder.visible = not holder.visible
	button.text = "Скрыть настройки" if holder.visible else "Настройки"


func _toggle_new_interact_editor(holder: VBoxContainer, button: Button) -> void:
	if holder.get_child_count() == 0:
		holder.add_child(_make_interact_editor(EmberSceneAuthoring.normalized_interact_values({}), true))
		holder.visible = true
	else:
		holder.visible = not holder.visible
	button.text = "Скрыть форму" if holder.visible else "+ Добавить взаимодействие"


func _make_interact_editor(values: Dictionary, is_new: bool) -> Control:
	var editor := InteractEditor.new() as Control
	var object_id := (
		_prop.placement_id
		if _prop != null
		else str(_snapshot.get("name", "trigger"))
	)
	var completion_flag := EmberSceneAuthoring.suggested_completion_flag(
		str(_snapshot.get("mapId", "")),
		object_id,
	)
	editor.call("setup", values, is_new, str(_snapshot.get("mapId", "")), completion_flag)
	editor.connect("save_requested", _on_interact_editor_save)
	return editor


func _toggle_action_chain_editor(
	holder: VBoxContainer,
	button: Button,
	script_id: String,
	quest_binding_id := "",
) -> void:
	if holder.get_child_count() == 0:
		var editable_id := script_id if ActionScriptStore.exists(script_id) else ""
		var suggested := ActionScriptStore.suggested_id(
			_prop.placement_id if _prop != null else str(_snapshot.get("name", "trigger")),
		)
		var editor := ActionChainEditor.new() as Control
		editor.call("setup", editable_id, suggested, {}, quest_binding_id)
		editor.connect("save_requested", _on_action_chain_save)
		editor.connect("cancel_requested", _dismiss_action_chain_editor.bind(holder, button))
		editor.connect("delete_requested", _on_action_chain_delete.bind(holder, button))
		editor.connect("dialogue_save_requested", _on_dialogue_save)
		editor.connect("shop_save_requested", _on_shop_save)
		editor.connect("shop_migrate_requested", _on_shop_migrate)
		editor.connect("item_save_requested", _on_item_save)
		editor.connect("item_migrate_requested", _on_item_migrate)
		holder.add_child(editor)
		holder.visible = true
	else:
		holder.visible = not holder.visible
	button.text = "Скрыть действия" if holder.visible else "Действия"


func _open_quest_event_for_interact(
	holder: VBoxContainer,
	button: Button,
	script_id: String,
	quest_id: String,
) -> void:
	if holder.get_child_count() == 0:
		_toggle_action_chain_editor(holder, button, script_id, quest_id)
	else:
		holder.visible = true
		button.text = "Скрыть действия"
	var editor := holder.get_child(0) as EmberActionChainEditor if holder.get_child_count() > 0 else null
	if editor != null:
		editor.call_deferred("open_quest_event_picker", quest_id)


func _on_dialogue_save(document: Dictionary) -> void:
	dialogue_save_requested.emit(document)


func _on_shop_save(document: Dictionary) -> void:
	shop_save_requested.emit(document)


func _on_shop_migrate(shop_id: String) -> void:
	shop_migrate_requested.emit(shop_id)


func _on_item_save(document: Dictionary) -> void:
	item_save_requested.emit(document)


func _on_item_migrate(item_id: String) -> void:
	item_migrate_requested.emit(item_id)


func _toggle_quest_editor(
	holder: VBoxContainer,
	button: Button,
	interact: EmberInteract,
) -> void:
	if holder.get_child_count() == 0:
		var existing := QuestStore.document(interact.effective_quest_id())
		var current_id := str(existing.get("id", ""))
		var source_id := _prop.placement_id if _prop != null else str(_snapshot.get("name", "quest"))
		var suggested := current_id if not current_id.is_empty() else QuestStore.suggested_id(source_id)
		var effective_status_flag := interact.effective_quest_status_flag_id()
		var suggested_status := (
			effective_status_flag
			if not effective_status_flag.is_empty()
			else "%s_status" % suggested
		)
		var editor := QuestEditor.new() as EmberQuestEditor
		editor.setup(current_id, suggested, suggested_status)
		editor.save_requested.connect(func(document: Dictionary) -> void:
			quest_save_requested.emit(interact, document)
		)
		editor.cancel_requested.connect(_dismiss_quest_editor.bind(holder, button))
		holder.add_child(editor)
		holder.visible = true
	else:
		holder.visible = not holder.visible
	button.text = "Скрыть описание" if holder.visible else "Описание задания"


func _dismiss_quest_editor(holder: VBoxContainer, button: Button) -> void:
	for child in holder.get_children():
		holder.remove_child(child)
		child.queue_free()
	holder.visible = false
	button.text = "Описание задания"


func _on_action_chain_save(document: Dictionary) -> void:
	if _prop != null:
		chain_save_requested.emit(_prop, document)
	elif _standalone != null:
		standalone_chain_save_requested.emit(_standalone, document)


func _on_action_chain_delete(_script_id: String, holder: VBoxContainer, button: Button) -> void:
	if _prop != null:
		chain_remove_requested.emit(_prop)
	elif _standalone != null:
		standalone_chain_remove_requested.emit(_standalone)
	_dismiss_action_chain_editor(holder, button)


func _dismiss_action_chain_editor(holder: VBoxContainer, button: Button) -> void:
	for child in holder.get_children():
		holder.remove_child(child)
		child.queue_free()
	holder.visible = false
	button.text = "Действия"


func _on_interact_editor_save(values: Dictionary) -> void:
	if _prop != null:
		interact_save_requested.emit(_prop, values)
	elif _standalone != null:
		standalone_save_requested.emit(_standalone, values)


func _request_remove_interact() -> void:
	if _prop != null:
		interact_remove_requested.emit(_prop)
	elif _standalone != null:
		standalone_remove_requested.emit(_standalone)


func _authoring_interact() -> EmberInteract:
	if _prop != null:
		return _prop.get_node_or_null("Interact") as EmberInteract
	return _standalone


func _toggle_standalone_bounds_editor(holder: VBoxContainer, button: Button) -> void:
	if holder.get_child_count() == 0:
		holder.add_child(_make_standalone_bounds_editor())
		holder.visible = true
	else:
		holder.visible = not holder.visible
	button.text = "Скрыть размер" if holder.visible else "Размер зоны"


func _make_standalone_bounds_editor() -> Control:
	var panel := PanelContainer.new()
	panel.name = "StandaloneBoundsEditor"
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.08, 0.14, 0.16), Color(0.30, 0.70, 0.78)))
	var column := VBoxContainer.new()
	panel.add_child(column)
	var hint := Label.new()
	hint.text = "Размер BoxShape3D в мировых единицах. Голубая рамка в viewport обновится после сохранения."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(0.62, 0.82, 0.88)
	column.add_child(hint)
	var current := EmberSceneAuthoring.standalone_box_size(_standalone)
	var inputs := HBoxContainer.new()
	column.add_child(inputs)
	for data in [["X", "x", current.x], ["Высота", "y", current.y], ["Z", "z", current.z]]:
		var label := Label.new()
		label.text = data[0]
		inputs.add_child(label)
		var value := SpinBox.new()
		value.name = "Bounds_%s" % data[1]
		value.min_value = 1.0
		value.max_value = 512.0
		value.step = 1.0
		value.value = float(data[2])
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		inputs.add_child(value)
	var save := Button.new()
	save.name = "SaveStandaloneBounds"
	save.text = "Сохранить размер"
	save.pressed.connect(_save_standalone_bounds.bind(panel))
	column.add_child(save)
	return panel


func _save_standalone_bounds(panel: Control) -> void:
	if _standalone == null:
		return
	var x := panel.find_child("Bounds_x", true, false) as SpinBox
	var y := panel.find_child("Bounds_y", true, false) as SpinBox
	var z := panel.find_child("Bounds_z", true, false) as SpinBox
	if x != null and y != null and z != null:
		standalone_bounds_save_requested.emit(_standalone, Vector3(x.value, y.value, z.value))


func _apply_filter(index: int) -> void:
	if _components_box == null:
		return
	var errors_only := index == 1
	for card in _components_box.get_children():
		card.visible = not errors_only or bool(card.get_meta("has_error", false))


func _component_has_errors(component: Dictionary) -> bool:
	var rows: Array = component.get("rows", [])
	for raw_row in rows:
		if typeof(raw_row) == TYPE_DICTIONARY and str(raw_row.get("status", "")) == "error":
			return true
	return false


func _build_diagnostics() -> void:
	var title := Label.new()
	title.text = "ДИАГНОСТИКА"
	title.add_theme_font_size_override("font_size", 13)
	add_child(title)
	var diagnostics: Array = _snapshot.get("diagnostics", [])
	if diagnostics.is_empty():
		var ok := Label.new()
		ok.name = "DiagnosticsOk"
		ok.text = "Ошибок ссылок и ownership не найдено."
		ok.modulate = Color(0.62, 0.9, 0.68)
		ok.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(ok)
		return
	var list := VBoxContainer.new()
	list.name = "Diagnostics"
	for raw_diag in diagnostics:
		if typeof(raw_diag) != TYPE_DICTIONARY:
			continue
		var diag: Dictionary = raw_diag
		var label := Label.new()
		var severity := str(diag.get("severity", "info"))
		label.text = "%s · %s" % [severity.to_upper(), str(diag.get("message", ""))]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		match severity:
			"error": label.modulate = Color(1.0, 0.48, 0.42)
			"warning": label.modulate = Color(1.0, 0.72, 0.38)
			_: label.modulate = Color(0.62, 0.78, 1.0)
		list.add_child(label)
	add_child(list)


func _select_owner() -> void:
	if _prop == null:
		return
	var selection := EditorInterface.get_selection()
	if selection == null:
		return
	selection.clear()
	selection.add_node(_prop)


func _open_path(path: String) -> void:
	if FileAccess.file_exists(path):
		OS.shell_open(path)


func _request_rebuild() -> void:
	if _prop != null:
		rebuild_requested.emit(_prop)


func _source_badge(source: String, compact := false) -> Label:
	var badge := Label.new()
	badge.text = _source_title(source)
	badge.tooltip_text = _source_hint(source)
	badge.modulate = _source_color(source)
	badge.add_theme_font_size_override("font_size", 10 if compact else 12)
	var style := StyleBoxFlat.new()
	var color := _source_color(source)
	style.bg_color = Color(color.r, color.g, color.b, 0.12)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	badge.add_theme_stylebox_override("normal", style)
	return badge


func _source_title(source: String) -> String:
	match source:
		"Asset": return "Ассет"
		"Scene": return "Сцена"
		"Derived": return "Расчёт"
	return source


func _source_hint(source: String) -> String:
	match source:
		"Asset": return "Источник: JOI .vox/.json. Изменяется через source workflow."
		"Scene": return "Источник: текущий .tscn. Изменения должны проходить Undo/Redo."
		"Derived": return "Вычислено из asset/scene. Не является authoring полем."
	return source


func _source_color(source: String) -> Color:
	match source:
		"Asset": return Color(0.58, 0.78, 1.0)
		"Scene": return Color(0.72, 0.9, 0.62)
		"Derived": return Color(0.75, 0.68, 0.9)
	return Color(0.75, 0.75, 0.78)


func _display_label(label: String) -> String:
	var labels := {
		"Source": "Источник",
		"Mesh": "Сетка",
		"Surfaces": "Поверхности",
		"Metadata": "Метаданные",
		"Physical": "Физический",
		"Generated": "Сгенерирован",
		"Shape": "Форма",
		"Bounds": "Размер",
		"Activation": "Активация",
		"Emissive voxels": "Светящихся вокселей",
		"Centroid": "Центр света",
		"Casts light": "Источник света",
		"Range": "Радиус",
		"Strength": "Яркость",
		"Shadow requested": "Тени запрошены",
		"Host shadow suppressed": "Тень корпуса отключена",
		"Flicker": "Мерцание",
		"Effective Omni range": "Итоговый радиус",
		"Effective energy": "Итоговая энергия",
		"Shadow active in editor": "Тень в редакторе",
		"Map shadow budget": "Бюджет теней карты",
		"Kind": "Тип",
		"Fallback status": "Fallback (редко)",
		"Current quest icon": "Иконка сейчас",
		"Quest": "Задание",
		"Quest flag": "Save-key (авто)",
		"Script": "Цепочка / сценарий",
		"Shop": "Магазин",
		"Note": "Заметка",
	}
	return str(labels.get(label, label))


func _display_value(value: String) -> String:
	return value.replace(" · resolved", " · найдено").replace(" · MISSING", " · НЕ НАЙДЕНО")


func _panel_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 6.0
	return style
