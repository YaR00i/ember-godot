@tool
class_name EmberCombatContentLibraryWorkspace
extends VBoxContainer
## Central browser for the same canonical status/effect/action/unit Resources used by
## Inspector and runtime. It does not introduce a parallel document format.

const StatusCatalog := preload("res://scripts/prototypes/ember_combat_status_catalog.gd")
const EffectCatalog := preload("res://scripts/prototypes/ember_combat_effect_catalog.gd")
const ActionCatalog := preload("res://scripts/prototypes/ember_combat_action_catalog.gd")
const UnitCatalog := preload("res://scripts/prototypes/ember_combat_unit_catalog.gd")
const StatusScript := preload("res://scripts/prototypes/ember_combat_status_resource.gd")
const EffectScript := preload("res://scripts/prototypes/ember_combat_effect_resource.gd")
const ActionScript := preload("res://scripts/prototypes/ember_combat_action_resource.gd")
const UnitScript := preload("res://scripts/prototypes/ember_combat_unit_resource.gd")
const StatusPanel := preload("res://addons/ember_import/ember_combat_status_inspector_panel.gd")
const EffectPanel := preload("res://addons/ember_import/ember_combat_effect_inspector_panel.gd")
const ActionPanel := preload("res://addons/ember_import/ember_combat_action_inspector_panel.gd")
const UnitPanel := preload("res://addons/ember_import/ember_combat_unit_inspector_panel.gd")

const KINDS := ["status", "effect", "action", "unit"]
const ROOTS := {
	"status": "res://content/combat/statuses",
	"effect": "res://content/combat/effects",
	"action": "res://content/combat/actions",
	"unit": "res://content/combat/units",
}

var _editor_interface: EditorInterface
var _undo_redo: Object
var _kind_tabs: TabBar
var _search: LineEdit
var _list: Tree
var _summary: Label
var _detail_header: VBoxContainer
var _editor: VBoxContainer
var _status: Label
var _create_dialog: ConfirmationDialog
var _create_id: LineEdit
var _create_name: LineEdit
var _create_team: OptionButton
var _create_team_label: Label
var _duplicate_source: Resource
var _selected_id := ""
var _kind := "status"
var _usage_counts := {}


func setup(editor_interface: EditorInterface, undo_redo: Object = null) -> void:
	_editor_interface = editor_interface
	_undo_redo = undo_redo
	name = "CombatContentLibraryWorkspace"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	if get_child_count() == 0:
		_build()
	refresh()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _create_dialog.visible or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo or not (key.ctrl_pressed or key.meta_pressed):
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit and key.keycode not in [KEY_F, KEY_S]:
		return
	if key.keycode == KEY_F:
		_search.grab_focus()
		_search.select_all()
	elif key.keycode == KEY_N:
		_open_create_dialog(false)
	elif key.keycode == KEY_D:
		_open_create_dialog(true)
	elif key.keycode == KEY_S:
		var resource := _selected_resource()
		if resource != null:
			_save_resource(resource)
	else:
		return
	get_viewport().set_input_as_handled()


func refresh(preferred_id := "") -> void:
	StatusCatalog.refresh()
	EffectCatalog.refresh()
	ActionCatalog.refresh()
	if not preferred_id.is_empty():
		_selected_id = preferred_id
	var resources := _resources()
	_rebuild_usage_counts(resources)
	if _selected_id.is_empty() and not resources.is_empty():
		_selected_id = _resource_id(resources[0])
	_refresh_list()
	_show_selected()


func _build() -> void:
	var heading_panel := PanelContainer.new()
	heading_panel.add_theme_stylebox_override(
		"panel", _panel_style(Color(0.055, 0.068, 0.088, 0.92), Color(0.20, 0.25, 0.32), 8)
	)
	add_child(heading_panel)
	var heading_margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		heading_margin.add_theme_constant_override(side, 10)
	heading_panel.add_child(heading_margin)
	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation", 2)
	heading_margin.add_child(heading)
	var title := Label.new()
	title.text = "БОЕВОЙ КОНТЕНТ"
	title.modulate = Color("ffc85a")
	title.add_theme_font_size_override("font_size", 20)
	heading.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Одна база для статусов, эффектов, приёмов, героев и противников"
	subtitle.modulate = Color(0.62, 0.70, 0.80)
	subtitle.add_theme_font_size_override("font_size", 12)
	heading.add_child(subtitle)

	_kind_tabs = TabBar.new()
	_kind_tabs.name = "CombatContentKinds"
	_kind_tabs.add_tab("Статусы")
	_kind_tabs.add_tab("Эффекты")
	_kind_tabs.add_tab("Умения и магия")
	_kind_tabs.add_tab("Герои и существа")
	_kind_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_kind_tabs.tab_changed.connect(_on_kind_changed)
	add_child(_kind_tabs)

	var split := HSplitContainer.new()
	split.name = "CombatContentSplit"
	split.split_offset = 500
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	var library_panel := PanelContainer.new()
	library_panel.custom_minimum_size.x = 430
	library_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	library_panel.add_theme_stylebox_override(
		"panel", _panel_style(Color(0.045, 0.055, 0.071, 0.72), Color(0.16, 0.20, 0.26), 6)
	)
	split.add_child(library_panel)
	var library_margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		library_margin.add_theme_constant_override(side, 10)
	library_panel.add_child(library_margin)
	var library := VBoxContainer.new()
	library.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library.size_flags_vertical = Control.SIZE_EXPAND_FILL
	library.add_theme_constant_override("separation", 7)
	library_margin.add_child(library)
	var library_toolbar := HBoxContainer.new()
	library_toolbar.add_theme_constant_override("separation", 6)
	library.add_child(library_toolbar)
	var library_title := Label.new()
	library_title.text = "КАТАЛОГ"
	library_title.modulate = Color(0.72, 0.78, 0.86)
	library_title.add_theme_font_size_override("font_size", 13)
	library_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library_toolbar.add_child(library_title)
	var create := Button.new()
	create.name = "CombatContentCreate"
	create.text = "+ Новый"
	create.tooltip_text = "Создать новый canonical .tres в выбранной категории."
	create.pressed.connect(_open_create_dialog.bind(false))
	library_toolbar.add_child(create)
	_summary = Label.new()
	_summary.name = "CombatContentSummary"
	_summary.modulate = Color(0.66, 0.74, 0.84)
	_summary.add_theme_font_size_override("font_size", 12)
	library.add_child(_summary)
	_search = LineEdit.new()
	_search.name = "CombatContentSearch"
	_search.placeholder_text = "Поиск по названию, ID, описанию или связи…"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_value: String) -> void: _refresh_list())
	library.add_child(_search)
	_list = Tree.new()
	_list.name = "CombatContentList"
	_list.hide_root = true
	_list.columns = 3
	_list.column_titles_visible = true
	_list.set_column_title(0, "НАЗВАНИЕ")
	_list.set_column_title(1, "ID")
	_list.set_column_title(2, "СВЯЗИ")
	_list.set_column_expand(0, true)
	_list.set_column_expand(1, true)
	_list.set_column_expand(2, false)
	_list.set_column_custom_minimum_width(0, 190)
	_list.set_column_custom_minimum_width(1, 130)
	_list.set_column_custom_minimum_width(2, 105)
	_list.select_mode = Tree.SELECT_ROW
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_item_selected)
	_list.item_activated.connect(_on_item_activated)
	library.add_child(_list)
	var library_hint := Label.new()
	library_hint.text = "Один клик — открыть карточку. Двойной клик — показать этот же .tres в Inspector."
	library_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	library_hint.modulate = Color(0.62, 0.68, 0.76)
	library_hint.add_theme_font_size_override("font_size", 12)
	library.add_child(library_hint)

	var detail_panel := PanelContainer.new()
	detail_panel.custom_minimum_size.x = 560
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_panel.add_theme_stylebox_override(
		"panel", _panel_style(Color(0.055, 0.064, 0.080, 0.72), Color(0.16, 0.20, 0.26), 6)
	)
	split.add_child(detail_panel)
	var detail_margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		detail_margin.add_theme_constant_override(side, 10)
	detail_panel.add_child(detail_margin)
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 8)
	detail_margin.add_child(detail)
	_detail_header = VBoxContainer.new()
	_detail_header.name = "CombatContentDetailHeader"
	_detail_header.add_theme_constant_override("separation", 7)
	detail.add_child(_detail_header)
	var divider := HSeparator.new()
	detail.add_child(divider)
	var scroll := ScrollContainer.new()
	scroll.name = "CombatContentEditorScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail.add_child(scroll)
	_editor = VBoxContainer.new()
	_editor.name = "CombatContentEditor"
	_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor.add_theme_constant_override("separation", 8)
	scroll.add_child(_editor)
	var status_panel := PanelContainer.new()
	status_panel.add_theme_stylebox_override(
		"panel", _panel_style(Color(0.045, 0.055, 0.071, 0.86), Color(0.16, 0.20, 0.26), 5)
	)
	add_child(status_panel)
	var status_margin := MarginContainer.new()
	status_margin.add_theme_constant_override("margin_left", 9)
	status_margin.add_theme_constant_override("margin_right", 9)
	status_margin.add_theme_constant_override("margin_top", 5)
	status_margin.add_theme_constant_override("margin_bottom", 5)
	status_panel.add_child(status_margin)
	_status = Label.new()
	_status.name = "CombatContentStatus"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = Color(0.62, 0.72, 0.82)
	_status.add_theme_font_size_override("font_size", 12)
	status_margin.add_child(_status)
	_build_create_dialog()


func _build_create_dialog() -> void:
	_create_dialog = ConfirmationDialog.new()
	_create_dialog.title = "Новый боевой Resource"
	_create_dialog.ok_button_text = "Создать .tres"
	_create_dialog.confirmed.connect(_create_resource)
	add_child(_create_dialog)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	_create_dialog.add_child(box)
	var hint := Label.new()
	hint.text = "ID становится именем файла и ссылкой из других библиотек. После создания его лучше не менять."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	var form := GridContainer.new()
	form.columns = 2
	form.add_theme_constant_override("h_separation", 12)
	form.add_theme_constant_override("v_separation", 8)
	box.add_child(form)
	var id_label := Label.new()
	id_label.text = "Stable ID"
	id_label.tooltip_text = "Служебное имя: только латинские буквы, цифры, _ и -."
	form.add_child(id_label)
	_create_id = LineEdit.new()
	_create_id.placeholder_text = "например earth_spike"
	_create_id.custom_minimum_size.x = 330
	form.add_child(_create_id)
	var name_label := Label.new()
	name_label.text = "Название"
	form.add_child(name_label)
	_create_name = LineEdit.new()
	_create_name.placeholder_text = "Название, которое увидит автор или игрок"
	form.add_child(_create_name)
	_create_team_label = Label.new()
	_create_team_label.text = "Сторона"
	form.add_child(_create_team_label)
	_create_team = OptionButton.new()
	_create_team.add_item("Герой")
	_create_team.set_item_metadata(0, "hero")
	_create_team.add_item("Враг")
	_create_team.set_item_metadata(1, "enemy")
	form.add_child(_create_team)


func _on_kind_changed(index: int) -> void:
	if index < 0 or index >= KINDS.size():
		return
	_kind = str(KINDS[index])
	_selected_id = ""
	_duplicate_source = null
	_create_team.visible = _kind == "unit"
	_create_team_label.visible = _kind == "unit"
	refresh()


func _resources() -> Array[Resource]:
	var result: Array[Resource] = []
	match _kind:
		"status":
			for status in StatusCatalog.resources():
				result.append(status)
		"effect":
			result.assign(EffectCatalog.resources())
		"action":
			for action in ActionCatalog.resources():
				result.append(action)
		"unit":
			for unit in UnitCatalog.resources():
				result.append(unit)
	return result


func _resource_id(resource: Resource) -> String:
	if resource == null:
		return ""
	return str(resource.get({
		"status": "status_id", "effect": "effect_id", "action": "action_id", "unit": "unit_id",
	}[_kind]))


func _resource_name(resource: Resource) -> String:
	return str(resource.get("display_name")) if resource != null else ""


func _resource_description(resource: Resource) -> String:
	if resource == null:
		return ""
	return str(resource.get("description" if _kind != "action" else "hint"))


func _refresh_list() -> void:
	if _list == null:
		return
	var all := _resources()
	var query := _search.text.strip_edges().to_lower() if _search != null else ""
	_list.clear()
	var root := _list.create_item()
	var selected_item: TreeItem
	var shown := 0
	for resource in all:
		var resource_id := _resource_id(resource)
		var usage := _usage_copy(resource)
		var searchable := "%s %s %s %s" % [
			_resource_name(resource), resource_id, _resource_description(resource), usage,
		]
		if not query.is_empty() and query not in searchable.to_lower():
			continue
		var item := _list.create_item(root)
		var errors := _resource_validation_errors(resource)
		item.set_text(0, ("⚠ " if not errors.is_empty() else "") + _resource_name(resource))
		item.set_text(1, resource_id)
		item.set_text(2, usage)
		item.set_metadata(0, resource_id)
		item.set_icon(0, _resource_icon(resource, 24))
		item.set_icon_max_width(0, 24)
		item.set_custom_color(0, Color("ff8d78") if not errors.is_empty() else _resource_accent(resource))
		item.set_custom_color(1, Color(0.58, 0.66, 0.76))
		item.set_custom_color(2, Color(0.66, 0.72, 0.80))
		var tooltip := "%s\n%s\n%s" % [
			_resource_description(resource), usage, resource.resource_path,
		]
		if not errors.is_empty():
			tooltip += "\n\nОшибки:\n• %s" % "\n• ".join(errors)
		for column in 3:
			item.set_tooltip_text(column, tooltip)
		if resource_id == _selected_id:
			selected_item = item
		shown += 1
	if selected_item != null:
		selected_item.select(0)
	elif root.get_first_child() != null:
		selected_item = root.get_first_child()
		selected_item.select(0)
		_selected_id = str(selected_item.get_metadata(0))
	_summary.text = "%d всего · %d показано" % [
		all.size(), shown,
	]


func _usage_copy(resource: Resource) -> String:
	var count := int(_usage_counts.get(_resource_id(resource), 0))
	if _kind == "status":
		return "%d эффект." % count
	return "%d бойц." % count if _kind == "action" else "%d действ." % count


func _rebuild_usage_counts(resources: Array[Resource]) -> void:
	_usage_counts.clear()
	for resource in resources:
		_usage_counts[_resource_id(resource)] = (
			(resource.get("action_ids") as PackedStringArray).size() if _kind == "unit" else 0
		)
	if _kind == "status":
		for effect in EffectCatalog.resources():
			for status_id in _effect_status_ids(effect):
				_usage_counts[status_id] = int(_usage_counts.get(status_id, 0)) + 1
	elif _kind == "effect":
		for action in ActionCatalog.resources():
			for step in action.effect_steps:
				if step == null:
					continue
				var effect_id := str(step.get("effect_id"))
				_usage_counts[effect_id] = int(_usage_counts.get(effect_id, 0)) + 1
	elif _kind == "action":
		for unit in UnitCatalog.resources():
			for action_id in unit.action_ids:
				_usage_counts[action_id] = int(_usage_counts.get(action_id, 0)) + 1


func _on_item_selected() -> void:
	var item := _list.get_selected()
	if item == null:
		return
	_selected_id = str(item.get_metadata(0))
	_show_selected()


func _on_item_activated() -> void:
	_on_item_selected()
	var resource := _selected_resource()
	if resource != null and _editor_interface != null:
		_editor_interface.edit_resource(resource)


func _selected_resource() -> Resource:
	match _kind:
		"status": return StatusCatalog.resource(_selected_id)
		"effect": return EffectCatalog.resource(_selected_id)
		"action": return ActionCatalog.resource(_selected_id)
		"unit": return UnitCatalog.resource(_selected_id)
	return null


func _show_selected() -> void:
	if _editor == null or _detail_header == null:
		return
	_clear_children(_detail_header)
	for child in _editor.get_children():
		_editor.remove_child(child)
		child.queue_free()
	var resource := _selected_resource()
	if resource == null:
		var empty := Label.new()
		empty.text = "Выберите запись в каталоге слева."
		empty.modulate = Color(0.62, 0.68, 0.76)
		_detail_header.add_child(empty)
		return
	var accent := _resource_accent(resource)
	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", 10)
	_detail_header.add_child(identity)
	var icon_frame := PanelContainer.new()
	icon_frame.custom_minimum_size = Vector2(54, 54)
	icon_frame.add_theme_stylebox_override(
		"panel", _panel_style(accent.darkened(0.68), accent.darkened(0.08), 6)
	)
	identity.add_child(icon_frame)
	var icon_margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		icon_margin.add_theme_constant_override(side, 6)
	icon_frame.add_child(icon_margin)
	var icon := TextureRect.new()
	icon.texture = _resource_icon(resource, 42)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon_margin.add_child(icon)
	var identity_copy := VBoxContainer.new()
	identity_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity_copy.add_theme_constant_override("separation", 1)
	identity.add_child(identity_copy)
	var kind_label := Label.new()
	kind_label.text = _resource_kind_label(resource).to_upper()
	kind_label.modulate = accent
	kind_label.add_theme_font_size_override("font_size", 11)
	identity_copy.add_child(kind_label)
	var title := Label.new()
	title.text = _resource_name(resource)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_size_override("font_size", 20)
	identity_copy.add_child(title)
	var resource_id := Label.new()
	resource_id.text = "%s  ·  %s" % [_resource_id(resource), _usage_long(resource)]
	resource_id.modulate = Color(0.62, 0.70, 0.80)
	resource_id.clip_text = true
	resource_id.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	identity_copy.add_child(resource_id)
	var errors := _resource_validation_errors(resource)
	var validation := Label.new()
	validation.text = "ГОТОВО" if errors.is_empty() else "%d ОШИБ." % errors.size()
	validation.modulate = Color("79d99a") if errors.is_empty() else Color("ff8d78")
	validation.tooltip_text = "Resource прошёл проверку." if errors.is_empty() else "• %s" % "\n• ".join(errors)
	validation.add_theme_font_size_override("font_size", 12)
	identity.add_child(validation)
	var path := Label.new()
	path.text = resource.resource_path
	path.tooltip_text = resource.resource_path
	path.modulate = Color(0.48, 0.56, 0.66)
	path.clip_text = true
	path.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	path.add_theme_font_size_override("font_size", 11)
	_detail_header.add_child(path)
	var toolbar := HFlowContainer.new()
	toolbar.add_theme_constant_override("h_separation", 6)
	toolbar.add_theme_constant_override("v_separation", 6)
	_detail_header.add_child(toolbar)
	var inspect := Button.new()
	inspect.name = "CombatContentOpenInspector"
	inspect.text = "Открыть в Inspector"
	inspect.tooltip_text = "Полные свойства этого же canonical .tres."
	inspect.disabled = _editor_interface == null
	inspect.pressed.connect(func() -> void:
		if _editor_interface != null:
			_editor_interface.edit_resource(resource)
	)
	toolbar.add_child(inspect)
	var save := Button.new()
	save.name = "CombatContentSave"
	save.text = "Сохранить"
	save.tooltip_text = "Записать изменения выбранного статуса, эффекта, действия или бойца."
	save.disabled = resource.resource_path.is_empty()
	save.pressed.connect(_save_resource.bind(resource))
	toolbar.add_child(save)
	var duplicate := Button.new()
	duplicate.name = "CombatContentDuplicate"
	duplicate.text = "Создать копию…"
	duplicate.tooltip_text = "Новый .tres на основе выбранного. Общие ссылки останутся общими."
	duplicate.pressed.connect(_open_create_dialog.bind(true))
	toolbar.add_child(duplicate)
	match _kind:
		"status":
			var panel := StatusPanel.new() as VBoxContainer
			panel.call("setup", resource)
			_editor.add_child(_content_card(panel, accent))
		"effect":
			var panel := EffectPanel.new() as VBoxContainer
			panel.call("setup", resource)
			_editor.add_child(_content_card(panel, accent))
		"action":
			var panel := ActionPanel.new() as EmberCombatActionInspectorPanel
			panel.setup(resource as EmberCombatActionResource, _editor_interface, _undo_redo)
			_editor.add_child(_content_card(panel, accent))
		"unit":
			var panel := UnitPanel.new() as EmberCombatUnitInspectorPanel
			panel.setup(resource as EmberCombatUnitResource, _editor_interface, _undo_redo)
			_editor.add_child(_content_card(panel, accent))
	_editor.add_child(_relations_card(resource, accent))
	_status.text = "Ctrl+F — поиск · Ctrl+N — новый · Ctrl+D — копия · Ctrl+S — сохранить · Ctrl+Z — отменить назначение"
	_status.modulate = Color(0.62, 0.72, 0.82)


func _resource_validation_errors(resource: Resource) -> Array:
	if resource == null:
		return ["Ресурс не найден."]
	return (
		resource.call("validation_errors", ActionCatalog.ids())
		if _kind == "unit"
		else resource.call("validation_errors")
	)


func _resource_accent(resource: Resource) -> Color:
	if resource == null:
		return Color("8793a6")
	if _kind == "unit":
		return resource.get("battle_color") as Color
	if _kind == "status":
		return resource.get("ui_color") as Color
	return resource.get("ui_color") as Color


func _resource_icon(resource: Resource, size: int) -> Texture2D:
	if resource == null:
		return null
	var texture := resource.get("portrait" if _kind == "unit" else "icon") as Texture2D
	if texture != null:
		return texture
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	image.fill(_resource_accent(resource))
	return ImageTexture.create_from_image(image)


func _resource_kind_label(resource: Resource) -> String:
	match _kind:
		"status":
			return "Статус · %s" % str(resource.call("kind_label"))
		"effect":
			return "Эффект · %s" % str(resource.call("operation_label"))
		"action":
			return "%s · %s" % [
				str(resource.call("menu_group_label")), str(resource.call("element_label")),
			]
		"unit":
			return "%s · уровень %d" % [
				"Герой" if str(resource.call("team_id")) == "hero" else "Существо",
				int(resource.get("combat_level")),
			]
	return "Боевой Resource"


func _usage_long(resource: Resource) -> String:
	var count := int(_usage_counts.get(_resource_id(resource), 0))
	if _kind == "status":
		return "Используется в эффектах: %d" % count
	if _kind == "effect":
		return "Используется в действиях: %d" % count
	if _kind == "action":
		return "Назначено бойцам: %d" % count
	return "Действий: %d" % count


func _content_card(content: Control, accent: Color) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override(
		"panel", _panel_style(Color(0.045, 0.055, 0.071, 0.72), accent.darkened(0.45), 6)
	)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	card.add_child(margin)
	margin.add_child(content)
	return card


func _relations_card(resource: Resource, accent: Color) -> Control:
	var card := PanelContainer.new()
	card.name = "CombatContentRelations"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override(
		"panel", _panel_style(Color(0.045, 0.055, 0.071, 0.72), Color(0.16, 0.20, 0.26), 6)
	)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	card.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	margin.add_child(box)
	var heading := Label.new()
	heading.text = "СВЯЗИ"
	heading.modulate = accent
	heading.add_theme_font_size_override("font_size", 12)
	box.add_child(heading)
	var relations := _related_resources(resource)
	if relations.is_empty():
		var empty := Label.new()
		empty.text = (
			"Этот статус пока не используется."
			if _kind == "status"
			else (
				"Этот эффект пока не используется."
				if _kind == "effect"
				else ("Действие пока никому не назначено." if _kind == "action" else "Бойцу пока не назначены действия.")
			)
		)
		empty.modulate = Color(0.62, 0.68, 0.76)
		box.add_child(empty)
		return card
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	box.add_child(flow)
	for relation in relations:
		var button := Button.new()
		button.text = str(relation.get("label", relation.get("id", "")))
		button.tooltip_text = "Перейти к %s" % str(relation.get("id", ""))
		button.pressed.connect(_open_related.bind(
			str(relation.get("kind", "")), str(relation.get("id", ""))
		))
		flow.add_child(button)
	return card


func _related_resources(resource: Resource) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _kind == "status":
		var status_id := _resource_id(resource)
		for effect in EffectCatalog.resources():
			if status_id in _effect_status_ids(effect):
				result.append({
					"kind": "effect", "id": str(effect.get("effect_id")),
					"label": str(effect.get("display_name")),
				})
	elif _kind == "effect":
		var effect_id := _resource_id(resource)
		for action in ActionCatalog.resources():
			for step in action.effect_steps:
				if step != null and str(step.get("effect_id")) == effect_id:
					result.append({"kind": "action", "id": action.action_id, "label": action.display_name})
					break
	elif _kind == "action":
		var action_id := _resource_id(resource)
		for unit in UnitCatalog.resources():
			if action_id in unit.action_ids:
				result.append({"kind": "unit", "id": unit.unit_id, "label": unit.display_name})
	else:
		for action_id in resource.get("action_ids") as PackedStringArray:
			var action := ActionCatalog.resource(action_id)
			result.append({
				"kind": "action",
				"id": action_id,
				"label": action.display_name if action != null else "⚠ %s" % action_id,
			})
	return result


func _effect_status_ids(effect: Resource) -> Array[String]:
	var result: Array[String] = []
	if effect == null:
		return result
	var candidates: Array = []
	candidates.append(str(effect.get("status_id")))
	candidates.append_array(Array(effect.get("remove_status_ids")))
	candidates.append_array(Array(effect.get("spread_status_ids")))
	for raw_id in candidates:
		var status_id := str(raw_id).strip_edges()
		if not status_id.is_empty() and status_id not in result:
			result.append(status_id)
	return result


func _open_related(kind: String, resource_id: String) -> void:
	var index := KINDS.find(kind)
	if index < 0 or resource_id.is_empty():
		return
	_kind_tabs.set_block_signals(true)
	_kind_tabs.current_tab = index
	_kind_tabs.set_block_signals(false)
	_kind = kind
	_selected_id = resource_id
	_duplicate_source = null
	_create_team.visible = _kind == "unit"
	_create_team_label.visible = _kind == "unit"
	refresh(resource_id)


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _panel_style(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	return style


func _save_resource(resource: Resource) -> void:
	if resource == null or resource.resource_path.is_empty():
		_status.text = "Не сохранено: у Resource ещё нет пути."
		_status.modulate = Color("ff8d78")
		return
	var errors: Array = (
		resource.call("validation_errors", ActionCatalog.ids())
		if _kind == "unit"
		else resource.call("validation_errors")
	)
	if not errors.is_empty():
		_status.text = "Не сохранено: исправьте ошибки проверки.\n• %s" % "\n• ".join(errors)
		_status.modulate = Color("ff8d78")
		return
	var error := ResourceSaver.save(resource, resource.resource_path)
	if error != OK:
		_status.text = "Не удалось сохранить %s: %s" % [resource.resource_path, error_string(error)]
		_status.modulate = Color("ff8d78")
		return
	StatusCatalog.refresh()
	EffectCatalog.refresh()
	ActionCatalog.refresh()
	var saved_id := _resource_id(resource)
	refresh(saved_id)
	_status.text = "Сохранено: %s" % resource.resource_path
	_status.modulate = Color("79d99a")


func _open_create_dialog(duplicate_selected: bool) -> void:
	_duplicate_source = _selected_resource() if duplicate_selected else null
	_create_dialog.title = "Дублировать боевой Resource" if _duplicate_source != null else "Новый боевой Resource"
	_create_dialog.ok_button_text = "Создать копию" if _duplicate_source != null else "Создать .tres"
	_create_id.text = ""
	_create_name.text = (
		"%s — вариант" % _resource_name(_duplicate_source)
		if _duplicate_source != null
		else ""
	)
	_create_team.visible = _kind == "unit"
	_create_team_label.visible = _kind == "unit"
	if _duplicate_source != null and _kind == "unit":
		_create_team.select(0 if str(_duplicate_source.call("team_id")) == "hero" else 1)
	_create_dialog.popup_centered(Vector2i(580, 300))
	_create_id.call_deferred("grab_focus")


func _create_resource() -> void:
	var resource_id := _create_id.text.strip_edges().to_lower()
	var display_name := _create_name.text.strip_edges()
	if not _valid_id(resource_id) or display_name.is_empty():
		_status.text = "Не создано: нужен уникальный stable ID (a-z, 0-9, _ или -) и понятное название."
		_status.modulate = Color("ff8d78")
		return
	var path := str(ROOTS[_kind]).path_join("%s.tres" % resource_id)
	if ResourceLoader.exists(path) or FileAccess.file_exists(path):
		_status.text = "Не создано: файл %s уже существует." % path
		_status.modulate = Color("ff8d78")
		return
	var resource := _duplicate_source.duplicate(false) as Resource if _duplicate_source != null else _blank_resource()
	if resource == null:
		_status.text = "Не удалось создать Resource."
		_status.modulate = Color("ff8d78")
		return
	resource.set({
		"status": "status_id", "effect": "effect_id", "action": "action_id", "unit": "unit_id",
	}[_kind], resource_id)
	resource.set("display_name", display_name)
	if _kind == "unit" and _duplicate_source == null:
		resource.set("team", _create_team.selected)
	var error := ResourceSaver.save(resource, path, ResourceSaver.FLAG_CHANGE_PATH)
	if error != OK:
		_status.text = "Не удалось сохранить %s: %s" % [path, error_string(error)]
		_status.modulate = Color("ff8d78")
		return
	_selected_id = resource_id
	_duplicate_source = null
	if _editor_interface != null:
		_editor_interface.get_resource_filesystem().scan()
	refresh(resource_id)
	_status.text = "Создан %s. Заполните поля в Inspector и сохраните ресурс." % path
	_status.modulate = Color("79d99a")
	if _editor_interface != null:
		_editor_interface.edit_resource(_selected_resource())


func _blank_resource() -> Resource:
	match _kind:
		"status":
			var status := StatusScript.new() as Resource
			status.set("description", "Опишите состояние для автора боевого контента.")
			return status
		"effect":
			var effect := EffectScript.new() as Resource
			effect.set("description", "Опишите переиспользуемый результат эффекта.")
			return effect
		"action":
			var action := ActionScript.new() as Resource
			action.set("hint", "Опишите результат приёма для игрока.")
			action.set("requirements_text", "Опишите условия применения.")
			action.set("power", 1)
			action.set("range_cells", 1)
			return action
		"unit":
			var unit := UnitScript.new() as Resource
			unit.set("description", "Опишите роль бойца и его особенности.")
			return unit
	return null


func _valid_id(value: String) -> bool:
	var expression := RegEx.new()
	return expression.compile("^[a-z0-9][a-z0-9_-]*$") == OK and expression.search(value) != null
