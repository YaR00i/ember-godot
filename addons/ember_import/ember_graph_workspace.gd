@tool
class_name EmberGraphWorkspace
extends Control
## Full-size native GraphEdit workspace. It projects canonical action, dialogue,
## and quest documents while reusing their existing stores and safe editors.

const ActionStore = preload("res://addons/ember_import/ember_action_script_store.gd")
const DialogueStore = preload("res://addons/ember_import/ember_dialogue_store.gd")
const DialogueGraphModel = preload("res://addons/ember_import/ember_dialogue_graph_model.gd")
const ActionEditor = preload("res://addons/ember_import/ember_action_chain_editor.gd")
const DialogueEditor = preload("res://addons/ember_import/ember_dialogue_editor.gd")
const QuestStore = preload("res://addons/ember_import/ember_quest_store.gd")
const QuestUsageIndex = preload("res://addons/ember_import/ember_quest_usage_index.gd")
const QuestEditor = preload("res://addons/ember_import/ember_quest_editor.gd")
const CombatResult = preload("res://scripts/prototypes/ember_combat_result.gd")
const TypedValueEditor = preload("res://addons/ember_import/ember_typed_value_editor.gd")
const VnPreview = preload("res://addons/ember_import/ember_vn_preview.gd")
const VnAssets = preload("res://scripts/ember_vn_assets.gd")
const VnVisuals = preload("res://scripts/ember_vn_visuals.gd")
const VisualLibraryPicker = preload("res://addons/ember_import/ember_visual_library_picker.gd")
const LootTableCatalog = preload("res://scripts/prototypes/ember_combat_loot_table_catalog.gd")
const LootLibraryWorkspace = preload("res://addons/ember_import/ember_combat_loot_library_workspace.gd")
const CombatContentWorkspace = preload("res://addons/ember_import/ember_combat_content_library_workspace.gd")
const VoxelSculptWorkspace = preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")
const CLIPBOARD_COPY := 0
const CLIPBOARD_CUT := 1
const CLIPBOARD_PASTE := 2
const DEFAULT_GRAPH_SPLIT_RATIO := 0.68
const MIN_GRAPH_SPLIT_RATIO := 0.52
const MAX_GRAPH_SPLIT_RATIO := 0.78

signal action_save_requested(document: Dictionary)
signal action_migrate_requested(action_id: String)
signal dialogue_save_requested(document: Dictionary)
signal dialogue_migrate_requested(dialogue_id: String)
signal quest_save_requested(document: Dictionary)
signal shop_save_requested(document: Dictionary)
signal shop_migrate_requested(shop_id: String)
signal item_save_requested(document: Dictionary)
signal item_migrate_requested(item_id: String)
signal scene_node_requested(node_path: NodePath)
signal quest_event_bind_requested(
	scene_path: NodePath,
	event_token: String,
	quest_document: Dictionary,
)
signal quest_event_unbind_requested(scene_path: NodePath, event_entry: Dictionary)
signal quest_event_remove_requested(event_entry: Dictionary)

var _kind: OptionButton
var _resource: OptionButton
var _editor_interface: EditorInterface
var _editor_undo_redo: Object
var _graph_split: HSplitContainer
var _graph_split_ratio := DEFAULT_GRAPH_SPLIT_RATIO
var _secondary_tools_button: Button
var _secondary_tools_popup: PopupPanel
var _loot_workspace: EmberCombatLootLibraryWorkspace
var _combat_content_workspace: Control
var _voxel_sculpt_workspace: EmberVoxelSculptWorkspace
var _graph: GraphEdit
var _editor_holder: VBoxContainer
var _status: Label
var _diagnostic_focus_button: Button
var _selection_label: Label
var _graph_add_type: OptionButton
var _graph_add_button: Button
var _arrange_button: Button
var _dialogue_add_type: OptionButton
var _dialogue_add_button: Button
var _quest_new_button: Button
var _quest_add_objective_button: Button
var _quest_overview_button: Button
var _quest_all_links_button: Button
var _quest_focus_label: Label
var _quest_event_button: Button
var _duplicate_button: Button
var _clipboard_menu: MenuButton
var _graph_delete_button: Button
var _set_start_button: Button
var _group_name: LineEdit
var _group_button: Button
var _ungroup_button: Button
var _node_palette: PopupPanel
var _node_palette_search: LineEdit
var _node_palette_list: ItemList
var _discard_draft_dialog: ConfirmationDialog
var _draft_undo_button: Button
var _draft_redo_button: Button
var _graph_save_button: Button
var _vn_preview_button: Button
var _vn_preview_window: Window
var _vn_preview: EmberVnPreview
var _vn_assets: EmberVnAssets
var _background_import_dialog: FileDialog
var _background_import_picker: OptionButton
var _background_import_preview: TextureRect
var _background_import_callback: Callable
var _visual_library_popup: PopupPanel
var _visual_library_picker: EmberVisualLibraryPicker
var _visual_library_callback := Callable()
var _action_editor: EmberActionChainEditor
var _dialogue_editor: EmberDialogueEditor
var _quest_editor: EmberQuestEditor
var _action_draft: Dictionary = {}
var _draft_history: Array[Dictionary] = []
var _draft_cursor := -1
var _dialogue_draft: Dictionary = {}
var _dialogue_history: Array[Dictionary] = []
var _dialogue_cursor := -1
var _quest_draft: Dictionary = {}
var _quest_history: Array[Dictionary] = []
var _quest_cursor := -1
var _quest_inline_before: Dictionary = {}
var _quest_is_new := false
var _quest_focus_target := ""
var _current_kind := "action"
var _current_id := ""
var _selected_editor_index := -1
var _selected_step_id := ""
var _selected_group_id := ""
var _view_states := {}
var _inline_edit_before: Dictionary = {}
var _palette_graph_position := Vector2.ZERO
var _pending_connection: Dictionary = {}
var _node_clipboard: Dictionary = {}
var _clipboard_paste_serial := 0
var _pending_navigation: Dictionary = {}
var _suppress_navigation := false
var _scene_root_ref: WeakRef
var _selected_scene_path := NodePath("")
var _selected_scene_label := ""
var _voxel_surface_sources: Dictionary = {}


func configure(editor_interface: EditorInterface, undo_redo: Object = null) -> void:
	_editor_interface = editor_interface
	_editor_undo_redo = undo_redo


func export_editor_layout() -> Dictionary:
	if _graph_split != null and _graph_split.size.x > 1.0:
		_on_graph_split_dragged(_graph_split.split_offset)
	return {"split_ratio": _graph_split_ratio}


func import_editor_layout(data: Dictionary) -> void:
	_graph_split_ratio = clampf(
		float(data.get("split_ratio", DEFAULT_GRAPH_SPLIT_RATIO)),
		MIN_GRAPH_SPLIT_RATIO,
		MAX_GRAPH_SPLIT_RATIO,
	)
	if _graph_split != null:
		_apply_graph_split_ratio.call_deferred()


func _ready() -> void:
	if get_child_count() == 0:
		_build()
	_refresh_resource_list()
	_open_selected()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey:
		return
	if _current_kind in ["loot", "combat_content", "voxel_sculpt"]:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo or not (key.ctrl_pressed or key.meta_pressed):
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	if key.keycode == KEY_Z:
		if key.shift_pressed:
			_redo_action_draft()
		else:
			_undo_action_draft()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_Y:
		_redo_action_draft()
		get_viewport().set_input_as_handled()


func open_resource(kind: String, resource_id: String) -> void:
	if get_child_count() == 0:
		_build()
	var target_kind := _normalized_kind(kind)
	if not Engine.is_editor_hint():
		_apply_navigation(target_kind, resource_id)
		return
	_request_navigation(target_kind, resource_id, false)


func open_voxel_surface(
	surface: EmberVoxelModelResource,
	resource_path: String,
	initial_region_blocks := Rect2i(),
) -> void:
	if surface == null:
		return
	if get_child_count() == 0:
		_build()
	var surface_id := surface.model_id.strip_edges()
	if surface_id.is_empty():
		surface_id = resource_path.get_file().get_basename()
	_voxel_surface_sources[surface_id] = {
		"resource": surface,
		"path": resource_path,
		"label": "%s · %d×%d" % [surface.display_name, surface.size_blocks.x, surface.size_blocks.z],
		"region": initial_region_blocks,
	}
	_request_navigation("voxel_sculpt", surface_id, true)


func set_scene_root(scene_root: Node) -> void:
	_scene_root_ref = weakref(scene_root) if scene_root != null else null
	if scene_root == null or (
		not _selected_scene_path.is_empty()
		and scene_root.get_node_or_null(_selected_scene_path) == null
	):
		_selected_scene_path = NodePath("")
		_selected_scene_label = ""
	if (
		is_node_ready()
		and visible
		and _current_kind == "quest"
		and not _quest_draft.is_empty()
	):
		_render_document(_quest_draft)


func _scene_root() -> Node:
	return _scene_root_ref.get_ref() as Node if _scene_root_ref != null else null


func set_scene_selection(target: Node) -> void:
	var root := _scene_root()
	var next_path := NodePath("")
	var next_label := ""
	if root != null and is_instance_valid(target) and (target == root or root.is_ancestor_of(target)):
		next_path = root.get_path_to(target)
		next_label = str(target.name)
	if next_path == _selected_scene_path and next_label == _selected_scene_label:
		return
	_selected_scene_path = next_path
	_selected_scene_label = next_label
	if (
		is_node_ready()
		and visible
		and _current_kind == "quest"
		and not _quest_draft.is_empty()
	):
		_render_document(_quest_draft)


func refresh_quest_scene_projection(message := "") -> void:
	if _current_kind != "quest" or _quest_draft.is_empty():
		return
	_render_document(_quest_draft)
	if not message.is_empty():
		_status.text = message


func accept_quest_binding_save(message := "") -> void:
	if _current_kind != "quest" or _quest_draft.is_empty():
		return
	_current_id = str(_quest_draft.get("id", _current_id))
	_quest_is_new = false
	_refresh_resource_list(_current_id)
	_open_selected()
	if not message.is_empty():
		_status.text = message


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var root_box := VBoxContainer.new()
	root_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_theme_constant_override("separation", 5)
	add_child(root_box)
	var document_toolbar := HBoxContainer.new()
	document_toolbar.name = "GraphDocumentToolbar"
	document_toolbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	document_toolbar.add_theme_constant_override("separation", 6)
	root_box.add_child(document_toolbar)
	var title := Label.new()
	title.text = "EMBER GRAPH"
	title.modulate = Color(0.96, 0.72, 0.32)
	title.add_theme_font_size_override("font_size", 14)
	document_toolbar.add_child(title)
	_kind = OptionButton.new()
	_kind.name = "GraphKind"
	_kind.add_item("Цепочки действий")
	_kind.set_item_metadata(0, "action")
	_kind.add_item("Диалоги")
	_kind.set_item_metadata(1, "dialogue")
	_kind.add_item("Задания")
	_kind.set_item_metadata(2, "quest")
	_kind.add_item("Лут врагов")
	_kind.set_item_metadata(3, "loot")
	_kind.add_item("Бойцы и приёмы")
	_kind.set_item_metadata(4, "combat_content")
	_kind.item_selected.connect(_on_kind_selected)
	document_toolbar.add_child(_kind)
	_resource = OptionButton.new()
	_resource.name = "GraphResource"
	_resource.custom_minimum_size.x = 220.0
	_resource.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resource.item_selected.connect(_on_resource_selected)
	document_toolbar.add_child(_resource)
	var reload := Button.new()
	reload.text = "Обновить"
	reload.pressed.connect(_request_reload)
	document_toolbar.add_child(reload)
	_graph_save_button = Button.new()
	_graph_save_button.name = "SaveDialogueGraph"
	_graph_save_button.text = "Сохранить"
	_graph_save_button.tooltip_text = "Проверяет текущий документ и сохраняет canonical owner одной Undo/Redo operation."
	_graph_save_button.pressed.connect(_save_current_graph)
	document_toolbar.add_child(_graph_save_button)
	var tool_row := HBoxContainer.new()
	tool_row.name = "GraphToolRow"
	tool_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tool_row.add_theme_constant_override("separation", 4)
	root_box.add_child(tool_row)
	_secondary_tools_button = Button.new()
	_secondary_tools_button.name = "GraphSecondaryTools"
	_secondary_tools_button.text = "Ещё…"
	_secondary_tools_button.tooltip_text = "Раскладка, буфер обмена, дублирование, группы и диагностические режимы."
	_secondary_tools_button.pressed.connect(_show_secondary_tools)
	_secondary_tools_popup = PopupPanel.new()
	_secondary_tools_popup.name = "GraphSecondaryToolsPopup"
	add_child(_secondary_tools_popup)
	var secondary_margin := MarginContainer.new()
	secondary_margin.add_theme_constant_override("margin_left", 8)
	secondary_margin.add_theme_constant_override("margin_top", 8)
	secondary_margin.add_theme_constant_override("margin_right", 8)
	secondary_margin.add_theme_constant_override("margin_bottom", 8)
	_secondary_tools_popup.add_child(secondary_margin)
	var secondary_box := VBoxContainer.new()
	secondary_box.name = "GraphSecondaryToolsContent"
	secondary_box.custom_minimum_size.x = 260.0
	secondary_box.add_theme_constant_override("separation", 4)
	secondary_margin.add_child(secondary_box)
	_arrange_button = Button.new()
	_arrange_button.text = "Упорядочить"
	_arrange_button.tooltip_text = "Штатная автоматическая раскладка GraphEdit. Позиции являются editor view и не меняют gameplay."
	_arrange_button.pressed.connect(_arrange_all)
	_arrange_button.pressed.connect(_hide_secondary_tools)
	secondary_box.add_child(_arrange_button)
	_graph_add_type = OptionButton.new()
	_graph_add_type.name = "GraphAddActionType"
	for data in [
		["Диалог", "talk"],
		["Выдать предмет", "give_item"],
		["Изменить флаг", "set_flag"],
		["Пауза", "wait"],
		["Открыть магазин", "open_shop"],
		["Сменить карту", "change_map"],
		["Начать бой", "start_battle"],
		["Запустить цепочку", "run_script"],
	]:
		_graph_add_type.add_item(data[0])
		_graph_add_type.set_item_metadata(_graph_add_type.item_count - 1, data[1])
	tool_row.add_child(_graph_add_type)
	_graph_add_button = Button.new()
	_graph_add_button.name = "GraphAddActionNode"
	_graph_add_button.text = "+ Нода"
	_graph_add_button.tooltip_text = "Добавляет action-ноду в конец черновика. Документ меняется только после Сохранить цепочку."
	_graph_add_button.pressed.connect(_add_action_node)
	tool_row.add_child(_graph_add_button)
	_dialogue_add_type = OptionButton.new()
	_dialogue_add_type.name = "GraphAddDialogueType"
	for data in [
		["Реплика", "dialogue"],
		["Выбор", "choice"],
		["Заставка", "splash"],
		["Изменить флаг", "set_flag"],
		["Конец", "end"],
	]:
		_dialogue_add_type.add_item(data[0])
		_dialogue_add_type.set_item_metadata(_dialogue_add_type.item_count - 1, data[1])
	tool_row.add_child(_dialogue_add_type)
	_dialogue_add_button = Button.new()
	_dialogue_add_button.name = "GraphAddDialogueNode"
	_dialogue_add_button.text = "+ Нода"
	_dialogue_add_button.tooltip_text = "Добавляет dialogue-ноду в центр текущего viewport. Подключите её перед сохранением."
	_dialogue_add_button.pressed.connect(_add_dialogue_node)
	tool_row.add_child(_dialogue_add_button)
	_quest_new_button = Button.new()
	_quest_new_button.name = "GraphNewQuest"
	_quest_new_button.text = "+ Задание"
	_quest_new_button.tooltip_text = "Создаёт локальный черновик нового EmberQuestResource. На диск он попадёт только после «Сохранить задание»."
	_quest_new_button.pressed.connect(_create_quest_draft)
	tool_row.add_child(_quest_new_button)
	_quest_add_objective_button = Button.new()
	_quest_add_objective_button.name = "GraphAddQuestObjective"
	_quest_add_objective_button.text = "+ Цель"
	_quest_add_objective_button.tooltip_text = "Добавляет цель в локальный quest-черновик. ↶ отменяет до сохранения."
	_quest_add_objective_button.pressed.connect(_add_quest_objective)
	tool_row.add_child(_quest_add_objective_button)
	_quest_overview_button = Button.new()
	_quest_overview_button.name = "GraphQuestOverview"
	_quest_overview_button.text = "Задание"
	_quest_overview_button.tooltip_text = "Хлебная крошка: вернуться к компактному обзору задания."
	_quest_overview_button.pressed.connect(_open_quest_overview)
	tool_row.add_child(_quest_overview_button)
	_quest_all_links_button = Button.new()
	_quest_all_links_button.name = "GraphQuestAllLinks"
	_quest_all_links_button.text = "Все связи"
	_quest_all_links_button.tooltip_text = "Диагностический полный граф: все объекты, цепочки и диалоги одновременно."
	_quest_all_links_button.pressed.connect(_open_all_quest_links)
	_quest_all_links_button.pressed.connect(_hide_secondary_tools)
	secondary_box.add_child(_quest_all_links_button)
	_quest_focus_label = Label.new()
	_quest_focus_label.name = "GraphQuestFocusLabel"
	_quest_focus_label.custom_minimum_size.x = 150.0
	_quest_focus_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quest_focus_label.clip_text = true
	_quest_focus_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_quest_focus_label.modulate = Color(0.62, 0.78, 0.96)
	tool_row.add_child(_quest_focus_label)
	_quest_event_button = Button.new()
	_quest_event_button.name = "GraphAddQuestEvent"
	_quest_event_button.text = "+ Событие задания"
	_quest_event_button.tooltip_text = "Добавляет start/objective/done как обычный set_flag. В диалоге подключите ноду к нужной ветке."
	_quest_event_button.pressed.connect(_open_quest_event_library)
	tool_row.add_child(_quest_event_button)
	_duplicate_button = Button.new()
	_duplicate_button.name = "GraphDuplicateNodes"
	_duplicate_button.text = "Дубликат"
	_duplicate_button.tooltip_text = "Ctrl+D · Копирует выбранные ноды и их внутренние связи в локальный черновик."
	_duplicate_button.pressed.connect(_duplicate_selected_nodes)
	_duplicate_button.pressed.connect(_hide_secondary_tools)
	secondary_box.add_child(_duplicate_button)
	_clipboard_menu = MenuButton.new()
	_clipboard_menu.name = "GraphClipboardMenu"
	_clipboard_menu.text = "Буфер"
	_clipboard_menu.tooltip_text = "Ctrl+C / Ctrl+X / Ctrl+V · Копирование между графами одного типа."
	var clipboard_popup := _clipboard_menu.get_popup()
	clipboard_popup.add_item("Копировать · Ctrl+C", CLIPBOARD_COPY)
	clipboard_popup.add_item("Вырезать · Ctrl+X", CLIPBOARD_CUT)
	clipboard_popup.add_item("Вставить · Ctrl+V", CLIPBOARD_PASTE)
	clipboard_popup.id_pressed.connect(_on_clipboard_menu_item)
	secondary_box.add_child(_clipboard_menu)
	_graph_delete_button = Button.new()
	_graph_delete_button.name = "GraphDeleteActionNodes"
	_graph_delete_button.text = "Удалить"
	_graph_delete_button.tooltip_text = "Удаляет выбранные ноды из черновика. Входящие переходы очищаются и требуют переподключения."
	_graph_delete_button.pressed.connect(_delete_selected_action_nodes)
	tool_row.add_child(_graph_delete_button)
	_set_start_button = Button.new()
	_set_start_button.name = "GraphSetDialogueStart"
	_set_start_button.text = "Сделать стартом"
	_set_start_button.tooltip_text = "Записывает выбранную ноду в canonical startStepId текущего dialogue-черновика."
	_set_start_button.pressed.connect(_set_selected_dialogue_start)
	tool_row.add_child(_set_start_button)
	_group_name = LineEdit.new()
	_group_name.name = "GraphGroupName"
	_group_name.placeholder_text = "Название группы"
	_group_name.custom_minimum_size.x = 150.0
	_group_name.text_submitted.connect(_rename_selected_group)
	secondary_box.add_child(_group_name)
	_group_button = Button.new()
	_group_button.name = "GraphCreateGroup"
	_group_button.text = "Группа"
	_group_button.tooltip_text = "Создаёт visual GraphFrame вокруг выбранных dialogue-нод. Shift+клик выбирает несколько."
	_group_button.pressed.connect(_create_group_from_selection)
	_group_button.pressed.connect(_hide_secondary_tools)
	secondary_box.add_child(_group_button)
	_ungroup_button = Button.new()
	_ungroup_button.name = "GraphRemoveGroup"
	_ungroup_button.text = "Убрать из группы"
	_ungroup_button.tooltip_text = "У выбранных нод снимает membership; у выбранного frame удаляет только рамку. Ноды не удаляются."
	_ungroup_button.pressed.connect(_remove_selected_groups)
	_ungroup_button.pressed.connect(_hide_secondary_tools)
	secondary_box.add_child(_ungroup_button)
	_draft_undo_button = Button.new()
	_draft_undo_button.name = "GraphDraftUndo"
	_draft_undo_button.text = "↶"
	_draft_undo_button.tooltip_text = "Отменить последнее структурное изменение черновика."
	_draft_undo_button.pressed.connect(_undo_action_draft)
	tool_row.add_child(_draft_undo_button)
	_draft_redo_button = Button.new()
	_draft_redo_button.name = "GraphDraftRedo"
	_draft_redo_button.text = "↷"
	_draft_redo_button.tooltip_text = "Вернуть структурное изменение черновика."
	_draft_redo_button.pressed.connect(_redo_action_draft)
	tool_row.add_child(_draft_redo_button)
	_vn_preview_button = Button.new()
	_vn_preview_button.name = "OpenVnPreview"
	_vn_preview_button.text = "▶ Превью сцены"
	_vn_preview_button.tooltip_text = "Открывает live preview текущего несохранённого dialogue/VN draft."
	_vn_preview_button.pressed.connect(_open_vn_preview)
	tool_row.add_child(_vn_preview_button)
	tool_row.add_child(_secondary_tools_button)
	var status_row := HBoxContainer.new()
	status_row.name = "GraphStatusRow"
	status_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_box.add_child(status_row)
	_status = Label.new()
	_status.name = "GraphStatus"
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.custom_minimum_size.y = 26.0
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.clip_text = true
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.modulate = Color(0.66, 0.74, 0.84)
	_status.mouse_entered.connect(_sync_status_tooltip)
	status_row.add_child(_status)
	_diagnostic_focus_button = Button.new()
	_diagnostic_focus_button.name = "GraphFocusDiagnostic"
	_diagnostic_focus_button.text = "К первой ошибке"
	_diagnostic_focus_button.visible = false
	_diagnostic_focus_button.pressed.connect(_focus_first_diagnostic)
	status_row.add_child(_diagnostic_focus_button)
	_graph_split = HSplitContainer.new()
	_graph_split.name = "GraphSplit"
	_graph_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graph_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph_split.split_offset = 780
	_graph_split.dragged.connect(_on_graph_split_dragged)
	root_box.add_child(_graph_split)
	_graph = GraphEdit.new()
	_graph.name = "EmberGraphEdit"
	_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph.custom_minimum_size = Vector2(520.0, 420.0)
	_graph.size_flags_stretch_ratio = 3.0
	_graph.minimap_enabled = true
	_graph.show_arrange_button = true
	_graph.show_grid = true
	_graph.show_zoom_label = true
	_graph.snapping_enabled = true
	_graph.right_disconnects = true
	_graph.connection_lines_curvature = 0.45
	_graph.connection_lines_thickness = 3.0
	_graph.node_selected.connect(_on_node_selected)
	_graph.connection_request.connect(_on_connection_request)
	_graph.disconnection_request.connect(_on_disconnection_request)
	_graph.delete_nodes_request.connect(_on_delete_nodes_request)
	_graph.duplicate_nodes_request.connect(_duplicate_selected_nodes)
	_graph.copy_nodes_request.connect(_copy_selected_nodes)
	_graph.cut_nodes_request.connect(_cut_selected_nodes)
	_graph.paste_nodes_request.connect(_paste_nodes)
	_graph.graph_elements_linked_to_frame_request.connect(_on_graph_elements_linked_to_frame_request)
	_graph.popup_request.connect(_on_graph_popup_request)
	_graph.connection_to_empty.connect(_on_connection_to_empty)
	_graph.connection_from_empty.connect(_on_connection_from_empty)
	_graph.begin_node_move.connect(_on_begin_node_move)
	_graph.end_node_move.connect(_on_end_node_move)
	_graph_split.add_child(_graph)
	var scroll := ScrollContainer.new()
	scroll.name = "GraphEditorScroll"
	scroll.custom_minimum_size = Vector2(340.0, 420.0)
	# Keep the property column stable. Long node/resource names must be clipped
	# inside it instead of renegotiating the HSplitContainer on every selection.
	scroll.size_flags_horizontal = Control.SIZE_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 0.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.clip_contents = true
	_graph_split.add_child(scroll)
	_editor_holder = VBoxContainer.new()
	_editor_holder.name = "GraphPropertyEditor"
	_editor_holder.custom_minimum_size.x = 0.0
	_editor_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor_holder.add_theme_constant_override("separation", 6)
	scroll.add_child(_editor_holder)
	_loot_workspace = LootLibraryWorkspace.new() as EmberCombatLootLibraryWorkspace
	_loot_workspace.visible = false
	_loot_workspace.setup(_editor_interface, _editor_undo_redo)
	_loot_workspace.table_selected.connect(_on_loot_table_selected)
	_apply_graph_split_ratio.call_deferred()
	root_box.add_child(_loot_workspace)
	_combat_content_workspace = CombatContentWorkspace.new() as Control
	_combat_content_workspace.visible = false
	_combat_content_workspace.call("setup", _editor_interface, _editor_undo_redo)
	root_box.add_child(_combat_content_workspace)
	_voxel_sculpt_workspace = VoxelSculptWorkspace.new() as EmberVoxelSculptWorkspace
	_voxel_sculpt_workspace.name = "VoxelSurfaceSculptWorkspace"
	_voxel_sculpt_workspace.visible = false
	_voxel_sculpt_workspace.setup(_editor_interface, _editor_undo_redo)
	_voxel_sculpt_workspace.status_changed.connect(_on_voxel_sculpt_status)
	root_box.add_child(_voxel_sculpt_workspace)
	_build_node_palette()
	_build_discard_draft_dialog()


func _show_secondary_tools() -> void:
	if _secondary_tools_popup == null or _secondary_tools_button == null:
		return
	var popup_position := Vector2i(
		roundi(_secondary_tools_button.global_position.x),
		roundi(_secondary_tools_button.global_position.y + _secondary_tools_button.size.y),
	)
	var content := _secondary_tools_popup.find_child("GraphSecondaryToolsContent", true, false) as Control
	var content_height := 220
	if content != null:
		content_height = clampi(roundi(content.get_combined_minimum_size().y) + 16, 72, 320)
	_secondary_tools_popup.popup(Rect2i(popup_position, Vector2i(300, content_height)))


func _hide_secondary_tools() -> void:
	if _secondary_tools_popup != null:
		_secondary_tools_popup.hide()


func _on_graph_split_dragged(offset: int) -> void:
	if _graph_split == null or _graph_split.size.x <= 1.0:
		return
	_graph_split_ratio = clampf(
		float(offset) / _graph_split.size.x,
		MIN_GRAPH_SPLIT_RATIO,
		MAX_GRAPH_SPLIT_RATIO,
	)


func _apply_graph_split_ratio() -> void:
	if _graph_split == null or _graph_split.size.x <= 1.0:
		return
	var editor_scroll := _graph_split.get_node_or_null("GraphEditorScroll") as ScrollContainer
	var minimum_left := int(_graph.custom_minimum_size.x) if _graph != null else 520
	var minimum_right := int(editor_scroll.custom_minimum_size.x) if editor_scroll != null else 340
	var maximum_offset := maxi(minimum_left, int(_graph_split.size.x) - minimum_right)
	_graph_split.split_offset = clampi(
		roundi(_graph_split.size.x * _graph_split_ratio),
		minimum_left,
		maximum_offset,
	)


func _sync_status_tooltip() -> void:
	if _status != null:
		_status.tooltip_text = _status.text


func _build_discard_draft_dialog() -> void:
	_discard_draft_dialog = ConfirmationDialog.new()
	_discard_draft_dialog.name = "DiscardGraphDraftDialog"
	_discard_draft_dialog.title = "Несохранённый Ember Graph"
	_discard_draft_dialog.ok_button_text = "Отбросить и перейти"
	_discard_draft_dialog.cancel_button_text = "Остаться"
	_discard_draft_dialog.confirmed.connect(_confirm_discard_navigation)
	_discard_draft_dialog.canceled.connect(_cancel_discard_navigation)
	add_child(_discard_draft_dialog)


func _build_node_palette() -> void:
	_node_palette = PopupPanel.new()
	_node_palette.name = "GraphNodePalette"
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(340.0, 320.0)
	box.add_theme_constant_override("separation", 6)
	_node_palette.add_child(box)
	var title := Label.new()
	title.text = "Добавить ноду"
	title.modulate = Color(0.96, 0.72, 0.32)
	box.add_child(title)
	_node_palette_search = LineEdit.new()
	_node_palette_search.name = "GraphNodePaletteSearch"
	_node_palette_search.placeholder_text = "Поиск типа…"
	_node_palette_search.text_changed.connect(func(_text: String) -> void: _refresh_node_palette())
	_node_palette_search.text_submitted.connect(func(_text: String) -> void:
		if _node_palette_list.item_count > 0:
			_activate_node_palette_item(0)
	)
	box.add_child(_node_palette_search)
	_node_palette_list = ItemList.new()
	_node_palette_list.name = "GraphNodePaletteList"
	_node_palette_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_node_palette_list.select_mode = ItemList.SELECT_SINGLE
	_node_palette_list.item_activated.connect(_activate_node_palette_item)
	box.add_child(_node_palette_list)
	add_child(_node_palette)


func _on_graph_popup_request(at_position: Vector2) -> void:
	if _current_kind == "quest":
		_add_quest_objective()
		return
	_open_node_palette(at_position, {})


func _on_connection_to_empty(
	from_node: StringName,
	from_port: int,
	release_position: Vector2,
) -> void:
	if _current_kind == "quest":
		return
	_open_node_palette(release_position, {
		"direction": "from",
		"node": from_node,
		"port": from_port,
	})


func _on_connection_from_empty(
	to_node: StringName,
	to_port: int,
	release_position: Vector2,
) -> void:
	if _current_kind == "quest":
		return
	_open_node_palette(release_position, {
		"direction": "to",
		"node": to_node,
		"port": to_port,
	})


func _open_node_palette(at_position: Vector2, pending: Dictionary) -> void:
	if _node_palette == null:
		return
	_palette_graph_position = _graph.scroll_offset + at_position / maxf(_graph.zoom, 0.01)
	var distance := maxf(float(_graph.snapping_distance), 1.0)
	_palette_graph_position = Vector2(
		snappedf(_palette_graph_position.x, distance),
		snappedf(_palette_graph_position.y, distance),
	)
	_pending_connection = pending.duplicate(true)
	_node_palette_search.text = ""
	_refresh_node_palette()
	var screen_position := _graph.get_screen_position() + at_position
	_node_palette.popup(Rect2i(Vector2i(screen_position), Vector2i(360, 360)))
	_node_palette_search.call_deferred("grab_focus")


func _palette_options() -> Array[Dictionary]:
	if _current_kind == "action":
		return [
			{"label": "Диалог", "type": "talk"},
			{"label": "Выдать предмет", "type": "give_item"},
			{"label": "Изменить флаг", "type": "set_flag"},
			{"label": "Пауза", "type": "wait"},
			{"label": "Открыть магазин", "type": "open_shop"},
			{"label": "Сменить карту", "type": "change_map"},
			{"label": "Начать бой", "type": "start_battle"},
			{"label": "Запустить цепочку", "type": "run_script"},
		]
	if _current_kind == "quest":
		return [{"label": "Цель задания", "type": "objective"}]
	var result: Array[Dictionary] = [
		{"label": "Реплика", "type": "dialogue"},
		{"label": "Выбор", "type": "choice"},
		{"label": "Заставка", "type": "splash"},
		{"label": "Изменить флаг", "type": "set_flag"},
		{"label": "Конец", "type": "end"},
	]
	if str(_pending_connection.get("direction", "")) == "to":
		result = result.filter(func(option: Dictionary) -> bool: return option["type"] != "end")
	return result


func _refresh_node_palette() -> void:
	if _node_palette_list == null:
		return
	var query := _node_palette_search.text.strip_edges().to_lower()
	_node_palette_list.clear()
	for option in _palette_options():
		var haystack := "%s %s" % [option.get("label", ""), option.get("type", "")]
		if not query.is_empty() and not query in haystack.to_lower():
			continue
		_node_palette_list.add_item("%s  ·  %s" % [option.get("label", ""), option.get("type", "")])
		_node_palette_list.set_item_metadata(_node_palette_list.item_count - 1, option.get("type", ""))
	if _node_palette_list.item_count > 0:
		_node_palette_list.select(0)


func _activate_node_palette_item(index: int) -> void:
	if index < 0 or index >= _node_palette_list.item_count:
		return
	var step_type := str(_node_palette_list.get_item_metadata(index))
	var pending := _pending_connection.duplicate(true)
	_node_palette.hide()
	_pending_connection = {}
	if _current_kind == "dialogue":
		_create_dialogue_node_at(step_type, _palette_graph_position, pending)
	elif _current_kind == "quest":
		_add_quest_objective()
	else:
		_create_action_node_near(step_type, pending)


func _on_kind_selected(_index: int) -> void:
	if _suppress_navigation or _kind.selected < 0:
		return
	_request_navigation(str(_kind.get_item_metadata(_kind.selected)), "", false)


func _on_resource_selected(_index: int) -> void:
	if _suppress_navigation or _resource.selected < 0:
		return
	_request_navigation(
		_current_kind, str(_resource.get_item_metadata(_resource.selected)), false
	)


func _on_loot_table_selected(table_id: String) -> void:
	if _suppress_navigation or table_id.is_empty() or table_id == _current_id:
		return
	_request_navigation("loot", table_id, false)


func _on_voxel_sculpt_status(message: String, color: Color) -> void:
	if _current_kind != "voxel_sculpt" or _status == null:
		return
	_status.text = message
	_status.modulate = color


func _request_reload() -> void:
	_vn_catalog().reload()
	if is_instance_valid(_vn_preview):
		_vn_preview.reload_assets()
	_request_navigation(_current_kind, _current_id, true)


func _request_navigation(kind: String, resource_id: String, force_reload: bool) -> void:
	var target_kind := _normalized_kind(kind)
	var target_id := resource_id
	if target_kind == _current_kind and target_id.is_empty():
		target_id = _current_id
	if not force_reload and target_kind == _current_kind and target_id == _current_id:
		_restore_navigation_controls()
		return
	if _has_unsaved_draft():
		_pending_navigation = {
			"kind": target_kind,
			"id": target_id,
			"reload": force_reload,
		}
		_restore_navigation_controls()
		_discard_draft_dialog.dialog_text = (
			"В %s есть несохранённый черновик.\n"
			+ "Переход к %s отбросит локальные изменения."
		) % [_current_id, target_id if not target_id.is_empty() else target_kind]
		_discard_draft_dialog.popup_centered(Vector2i(520, 170))
		_status.text = "НЕ СОХРАНЕНО · переход приостановлен до вашего решения."
		_status.modulate = Color(1.0, 0.72, 0.30)
		return
	_apply_navigation(target_kind, target_id)


func _confirm_discard_navigation() -> void:
	if _pending_navigation.is_empty():
		return
	var pending := _pending_navigation.duplicate(true)
	_pending_navigation = {}
	if _current_kind == "voxel_sculpt" and _voxel_sculpt_workspace != null:
		_voxel_sculpt_workspace.discard_changes()
	_apply_navigation(str(pending.get("kind", "action")), str(pending.get("id", "")))


func _cancel_discard_navigation() -> void:
	_pending_navigation = {}
	_restore_navigation_controls()
	if _current_kind == "voxel_sculpt" and _voxel_sculpt_workspace != null:
		_voxel_sculpt_workspace.show_current_status()
	elif _current_kind == "dialogue":
		_update_dialogue_draft_status()
	elif _current_kind == "quest":
		_update_quest_draft_status()
	else:
		_update_action_draft_status()


func _apply_navigation(kind: String, resource_id: String) -> void:
	_capture_view_state()
	var next_kind := _normalized_kind(kind)
	if next_kind != _current_kind or resource_id != _current_id:
		_quest_focus_target = ""
	_suppress_navigation = true
	_current_kind = next_kind
	_select_metadata(_kind, _current_kind)
	_current_id = resource_id
	_refresh_resource_list(resource_id)
	if not resource_id.is_empty():
		_select_metadata(_resource, resource_id)
	_suppress_navigation = false
	_open_selected()


func _normalized_kind(kind: String) -> String:
	return kind if kind in ["action", "dialogue", "quest", "loot", "combat_content", "voxel_sculpt"] else "action"


func _restore_navigation_controls() -> void:
	_suppress_navigation = true
	_select_metadata(_kind, _current_kind)
	_refresh_resource_list(_current_id)
	if not _current_id.is_empty():
		_select_metadata(_resource, _current_id)
	_suppress_navigation = false


func _has_unsaved_draft() -> bool:
	if _current_kind == "voxel_sculpt":
		return _voxel_sculpt_workspace != null and _voxel_sculpt_workspace.has_unsaved_changes()
	if _current_kind == "loot":
		return false
	if _current_kind == "combat_content":
		return false
	if _current_kind == "dialogue":
		if _dialogue_history.is_empty() or _dialogue_draft.is_empty():
			return false
		return _current_dialogue_document() != _dialogue_history[0]
	if _current_kind == "quest":
		if _quest_is_new and not _quest_draft.is_empty():
			return true
		if _quest_history.is_empty() or _quest_draft.is_empty():
			return false
		return _current_quest_document() != _quest_history[0]
	if _draft_history.is_empty() or _action_draft.is_empty():
		return false
	return _current_action_document() != _draft_history[0]


func _arrange_all() -> void:
	for graph_node in _graph_nodes():
		graph_node.selected = true
	_graph.arrange_nodes()
	_on_end_node_move.call_deferred()


func _view_key() -> String:
	if _current_kind == "quest":
		var mode := (
			"overview"
			if _quest_focus_target.is_empty()
			else "all"
			if _quest_focus_target == "__all__"
			else "focus:%s" % _quest_focus_target
		)
		return "%s:%s:%s" % [_current_kind, _current_id, mode]
	return "%s:%s" % [_current_kind, _current_id]


func _capture_view_state() -> void:
	if _graph == null or _current_id.is_empty():
		return
	var positions := {}
	for graph_node in _graph_nodes():
		var step_id := str(graph_node.get_meta("step_id", ""))
		if not step_id.is_empty():
			positions[step_id] = graph_node.position_offset
	_view_states[_view_key()] = {
		"scroll": _graph.scroll_offset,
		"zoom": _graph.zoom,
		"positions": positions,
	}


func _restore_view_state() -> void:
	if _graph == null:
		return
	var state: Dictionary = _view_states.get(_view_key(), {})
	if state.is_empty():
		_graph.scroll_offset = Vector2.ZERO
		_graph.zoom = 1.0
		return
	var positions: Dictionary = state.get("positions", {})
	for graph_node in _graph_nodes():
		var step_id := str(graph_node.get_meta("step_id", ""))
		if positions.has(step_id) and typeof(positions[step_id]) == TYPE_VECTOR2:
			graph_node.position_offset = positions[step_id]
	_graph.zoom = float(state.get("zoom", 1.0))
	_graph.scroll_offset = state.get("scroll", Vector2.ZERO)


func _apply_cached_dialogue_layout(document: Dictionary) -> Dictionary:
	var result := document.duplicate(true)
	var state: Dictionary = _view_states.get(_view_key(), {})
	var positions: Dictionary = state.get("positions", {})
	if positions.is_empty():
		return result
	var known_steps := DialogueGraphModel.steps_by_id(result)
	var layout: Dictionary = (
		result.get("editorLayout", {}).duplicate(true)
		if typeof(result.get("editorLayout", {})) == TYPE_DICTIONARY
		else {}
	)
	for step_id in positions:
		if known_steps.has(step_id) and typeof(positions[step_id]) == TYPE_VECTOR2:
			var position: Vector2 = positions[step_id]
			layout[step_id] = {"x": position.x, "y": position.y}
	result["editorLayout"] = layout
	return result


func _apply_cached_quest_layout(document: Dictionary) -> Dictionary:
	var result := document.duplicate(true)
	var state: Dictionary = _view_states.get(_view_key(), {})
	var positions: Dictionary = state.get("positions", {})
	if positions.is_empty():
		return result
	var layout: Dictionary = result.get("editorLayout", {}).duplicate(true)
	for step_id in positions:
		if step_id != "quest_root" and not str(step_id).begins_with("objective:"):
			continue
		if typeof(positions[step_id]) != TYPE_VECTOR2:
			continue
		var position: Vector2 = positions[step_id]
		layout[step_id] = {"x": position.x, "y": position.y}
	result["editorLayout"] = layout
	return result


func _on_begin_node_move() -> void:
	_capture_view_state()


func _on_end_node_move() -> void:
	_capture_view_state()
	if _current_kind == "dialogue" and not _dialogue_draft.is_empty():
		_push_dialogue_draft(_apply_collapsed_frame_moves(_current_dialogue_document()))
	elif (
		_current_kind == "quest"
		and not _quest_draft.is_empty()
		and _quest_focus_target.is_empty()
	):
		_push_quest_draft(_apply_cached_quest_layout(_quest_draft))


func _apply_collapsed_frame_moves(document: Dictionary) -> Dictionary:
	var result := document.duplicate(true)
	var layout: Dictionary = result.get("editorLayout", {}).duplicate(true)
	for element in _graph_elements():
		if not bool(element.get_meta("collapsed", false)):
			continue
		var source_origin: Vector2 = element.get_meta("layout_origin", element.position_offset)
		var delta := element.position_offset - source_origin
		if delta.is_zero_approx():
			continue
		for raw_member in element.get_meta("members", []):
			var member := str(raw_member)
			var source: Dictionary = (
				layout.get(member, {}).duplicate(true)
				if typeof(layout.get(member, {})) == TYPE_DICTIONARY
				else {}
			)
			source["x"] = float(source.get("x", 0.0)) + delta.x
			source["y"] = float(source.get("y", 0.0)) + delta.y
			layout[member] = source
	result["editorLayout"] = layout
	return result


func _reset_action_draft(document: Dictionary) -> void:
	_action_draft = ActionStore.normalized_document(document)
	_draft_history = [_action_draft.duplicate(true)]
	_draft_cursor = 0


func _reset_dialogue_draft(document: Dictionary) -> void:
	_dialogue_draft = DialogueGraphModel.normalized_document(document)
	_dialogue_history = [_dialogue_draft.duplicate(true)]
	_dialogue_cursor = 0


func _reset_quest_draft(document: Dictionary, is_new := false) -> void:
	_quest_draft = QuestStore.normalized_document(document)
	_quest_history = [_quest_draft.duplicate(true)]
	_quest_cursor = 0
	_quest_inline_before = {}
	_quest_is_new = is_new


func _current_action_document() -> Dictionary:
	if is_instance_valid(_action_editor):
		return ActionStore.normalized_document(_action_editor.call("_document"))
	return _action_draft.duplicate(true)


func _current_dialogue_document() -> Dictionary:
	_capture_view_state()
	return _apply_cached_dialogue_layout(_dialogue_draft)


func _current_quest_document() -> Dictionary:
	return QuestStore.normalized_document(_quest_draft)


func _push_action_draft(document: Dictionary) -> void:
	var normalized := ActionStore.normalized_document(document)
	if _draft_cursor + 1 < _draft_history.size():
		_draft_history.resize(_draft_cursor + 1)
	_draft_history.append(normalized.duplicate(true))
	_draft_cursor = _draft_history.size() - 1
	_apply_action_draft(normalized)


func _push_dialogue_draft(document: Dictionary) -> void:
	var normalized := DialogueGraphModel.normalized_document(document)
	if normalized == _dialogue_draft:
		return
	if _dialogue_cursor + 1 < _dialogue_history.size():
		_dialogue_history.resize(_dialogue_cursor + 1)
	_dialogue_history.append(normalized.duplicate(true))
	_dialogue_cursor = _dialogue_history.size() - 1
	_apply_dialogue_draft(normalized)


func _push_quest_draft(document: Dictionary) -> void:
	var normalized := QuestStore.normalized_document(document)
	if normalized == _quest_draft:
		return
	if _quest_cursor + 1 < _quest_history.size():
		_quest_history.resize(_quest_cursor + 1)
	_quest_history.append(normalized.duplicate(true))
	_quest_cursor = _quest_history.size() - 1
	_apply_quest_draft(normalized)


func _apply_action_draft(document: Dictionary) -> void:
	_capture_view_state()
	_action_draft = ActionStore.normalized_document(document)
	_selected_editor_index = -1
	_selected_step_id = ""
	_selected_group_id = ""
	_render_document(_action_draft)
	_build_property_editor()
	_update_mutation_controls()
	_update_action_draft_status()


func _apply_dialogue_draft(document: Dictionary) -> void:
	_capture_view_state()
	_inline_edit_before = {}
	_dialogue_draft = DialogueGraphModel.normalized_document(document)
	_selected_editor_index = -1
	_selected_step_id = ""
	_selected_group_id = ""
	_render_document(_dialogue_draft)
	_build_property_editor()
	_update_mutation_controls()
	_update_dialogue_draft_status()
	_refresh_vn_preview()


func _apply_quest_draft(document: Dictionary) -> void:
	_capture_view_state()
	_quest_inline_before = {}
	_quest_draft = QuestStore.normalized_document(document)
	_selected_editor_index = -1
	_selected_step_id = ""
	_selected_group_id = ""
	_render_document(_quest_draft)
	_build_property_editor()
	_update_mutation_controls()
	_update_quest_draft_status()


func _add_action_node() -> void:
	if _current_kind != "action" or _graph_add_type.selected < 0:
		return
	_create_action_node_near(str(_graph_add_type.get_item_metadata(_graph_add_type.selected)), {})


func _create_action_node_near(step_type: String, pending: Dictionary) -> void:
	var document := _current_action_document()
	var steps: Array = document.get("steps", []).duplicate(true)
	var insert_at := steps.size()
	if not pending.is_empty():
		var graph_node := _graph.get_node_or_null(NodePath(str(pending.get("node", "")))) as GraphNode
		var anchor_index := int(graph_node.get_meta("editor_index", -1)) if graph_node != null else -1
		if anchor_index >= 0:
			insert_at = anchor_index + 1 if str(pending.get("direction", "")) == "from" else anchor_index
	steps.insert(insert_at, ActionStore.default_step(step_type))
	document["steps"] = steps
	_push_action_draft(document)
	_select_action_index(insert_at)


func _add_dialogue_node() -> void:
	if _current_kind != "dialogue" or _dialogue_add_type.selected < 0:
		return
	var step_type := str(_dialogue_add_type.get_item_metadata(_dialogue_add_type.selected))
	var center := _graph.scroll_offset + _graph.size / maxf(_graph.zoom * 2.0, 0.01)
	var distance := maxf(float(_graph.snapping_distance), 1.0)
	center = Vector2(snappedf(center.x, distance), snappedf(center.y, distance))
	_create_dialogue_node_at(step_type, center, {})


func _create_quest_draft() -> void:
	if _current_kind != "quest":
		return
	if _has_unsaved_draft():
		_status.text = "Сначала сохраните текущий quest-черновик или переключитесь и подтвердите его сброс."
		_status.modulate = Color(1.0, 0.72, 0.30)
		return
	var base := QuestStore.suggested_id("new")
	var quest_id := base
	var suffix := 2
	var known := QuestStore.ids()
	while quest_id in known:
		quest_id = "%s_%d" % [base, suffix]
		suffix += 1
	_current_id = quest_id
	_suppress_navigation = true
	_resource.clear()
	_resource.add_item("Новое задание · %s" % quest_id)
	_resource.set_item_metadata(0, quest_id)
	_resource.select(0)
	_suppress_navigation = false
	_quest_focus_target = ""
	_reset_quest_draft({
		"id": quest_id,
		"statusFlagId": "%s_status" % quest_id,
		"titleRu": "Новое задание",
		"summaryRu": "",
		"showWhenAvailable": false,
		"objectives": [{
			"id": "main",
			"textRu": "Выполнить цель",
			"flagId": "%s_goal" % quest_id,
			"progressMode": "flag",
			"counterEventId": "",
			"requiredCount": 1,
			"optional": false,
		}],
	}, true)
	_render_document(_quest_draft)
	_build_property_editor()
	_update_mutation_controls()
	_update_quest_draft_status()


func _add_quest_objective() -> void:
	if _current_kind != "quest" or _quest_draft.is_empty():
		return
	var document := _current_quest_document()
	var objectives: Array = document.get("objectives", []).duplicate(true)
	var known := {}
	for raw_objective in objectives:
		if typeof(raw_objective) == TYPE_DICTIONARY:
			known[str((raw_objective as Dictionary).get("id", ""))] = true
	var objective_id := "objective_%d" % (objectives.size() + 1)
	var serial := objectives.size() + 2
	while known.has(objective_id):
		objective_id = "objective_%d" % serial
		serial += 1
	objectives.append({
		"id": objective_id,
		"textRu": "Новая цель",
		"flagId": "%s_%s" % [str(document.get("id", "quest")), objective_id],
		"progressMode": "flag",
		"counterEventId": "",
		"requiredCount": 1,
		"optional": false,
	})
	document["objectives"] = objectives
	_push_quest_draft(document)
	_select_quest_objective(objectives.size() - 1)


func _open_quest_event_library() -> void:
	if _current_kind == "quest":
		return
	_open_visual_library(
		"СОБЫТИЯ ЗАДАНИЙ",
		QuestStore.event_reference_entries(),
		"",
		_apply_quest_event,
		Vector2i(0, 0),
		240,
		3,
	)


func _apply_quest_event(token: String) -> void:
	var preset := QuestStore.action_for_event(token)
	if preset.is_empty():
		return
	if _current_kind == "action":
		var document := _current_action_document()
		var steps: Array = document.get("steps", []).duplicate(true)
		var insert_at := steps.size()
		for node in _graph_nodes():
			if node.selected:
				insert_at = int(node.get_meta("editor_index", steps.size())) + 1
				break
		steps.insert(clampi(insert_at, 0, steps.size()), preset)
		document["steps"] = steps
		_push_action_draft(document)
		_select_action_index(insert_at)
		return
	if _current_kind != "dialogue":
		return
	var document := _current_dialogue_document()
	var center := _graph.scroll_offset + _graph.size / maxf(_graph.zoom * 2.0, 0.01)
	var distance := maxf(float(_graph.snapping_distance), 1.0)
	center = Vector2(snappedf(center.x, distance), snappedf(center.y, distance))
	var changed := DialogueGraphModel.add_step(document, "set_flag", center)
	var steps: Array = changed.get("steps", [])
	var step_id := str((steps[-1] as Dictionary).get("id", "")) if not steps.is_empty() else ""
	changed = DialogueGraphModel.set_step_field(changed, step_id, "flag", preset.get("flag", ""))
	changed = DialogueGraphModel.set_step_field(changed, step_id, "value", preset.get("value", true))
	_push_dialogue_draft(changed)
	_select_dialogue_step(step_id)


func _create_dialogue_node_at(step_type: String, position: Vector2, pending: Dictionary) -> void:
	var document := _current_dialogue_document()
	var changed := DialogueGraphModel.add_step(document, step_type, position)
	var steps: Array = changed.get("steps", [])
	var step_id := str((steps[-1] as Dictionary).get("id", "")) if not steps.is_empty() else ""
	if not pending.is_empty():
		var graph_node := _graph.get_node_or_null(NodePath(str(pending.get("node", "")))) as GraphNode
		var anchor_id := str(graph_node.get_meta("step_id", "")) if graph_node != null else ""
		var direction := str(pending.get("direction", ""))
		if not anchor_id.is_empty() and direction == "from":
			changed = DialogueGraphModel.replace_edge(
				changed, anchor_id, int(pending.get("port", 0)), step_id
			)
		elif not anchor_id.is_empty() and direction == "to" and step_type != "end":
			changed = DialogueGraphModel.replace_edge(changed, step_id, 0, anchor_id)
	_push_dialogue_draft(changed)
	_select_dialogue_step(step_id)


func _delete_selected_action_nodes() -> void:
	var names: Array[StringName] = []
	for element in _graph_elements():
		if element.selected:
			names.append(element.name)
	_on_delete_nodes_request(names)


func _duplicate_selected_nodes() -> void:
	if _current_kind == "quest":
		_status.text = "Для новой цели используйте «+ Цель»; связи задания вычисляются автоматически."
		return
	if _current_kind == "dialogue":
		var step_ids := _selected_step_ids()
		if step_ids.is_empty():
			_status.text = "Выберите dialogue-ноды для дублирования."
			return
		var duplicated := DialogueGraphModel.duplicate_steps(
			_current_dialogue_document(), step_ids, Vector2(60.0, 60.0)
		)
		var new_ids: Array[String] = []
		for raw_id in duplicated.get("newIds", []):
			new_ids.append(str(raw_id))
		_push_dialogue_draft(duplicated.get("document", {}))
		_select_dialogue_steps(new_ids)
		return
	var indices := _selected_action_indices()
	if indices.is_empty():
		return
	indices.sort()
	var document := _current_action_document()
	var steps: Array = document.get("steps", []).duplicate(true)
	var clones: Array = []
	for index in indices:
		if index < steps.size():
			clones.append((steps[index] as Dictionary).duplicate(true))
	var insert_at := indices[-1] + 1
	for offset in clones.size():
		steps.insert(insert_at + offset, clones[offset])
	document["steps"] = steps
	_push_action_draft(document)
	_select_action_indices(insert_at, clones.size())


func _on_clipboard_menu_item(item_id: int) -> void:
	_hide_secondary_tools()
	match item_id:
		CLIPBOARD_COPY:
			_copy_selected_nodes()
		CLIPBOARD_CUT:
			_cut_selected_nodes()
		CLIPBOARD_PASTE:
			_paste_nodes()


func _copy_selected_nodes() -> void:
	if _current_kind == "quest":
		return
	if _current_kind == "dialogue":
		var step_ids := _selected_step_ids()
		if step_ids.is_empty():
			_status.text = "Выберите dialogue-ноды для копирования."
			return
		_node_clipboard = DialogueGraphModel.copy_steps(_current_dialogue_document(), step_ids)
	else:
		var indices := _selected_action_indices()
		if indices.is_empty():
			_status.text = "Выберите action-ноды для копирования."
			return
		var steps: Array = _current_action_document().get("steps", [])
		var copied_steps: Array = []
		for index in indices:
			if index < steps.size():
				copied_steps.append((steps[index] as Dictionary).duplicate(true))
		_node_clipboard = {"kind": "action", "steps": copied_steps}
	_clipboard_paste_serial = 0
	_status.text = "Скопировано нод: %d · вставка доступна в графе того же типа." % int(
		_node_clipboard.get("steps", []).size()
	)
	_update_mutation_controls()


func _cut_selected_nodes() -> void:
	if _current_kind == "quest":
		return
	var selected_count: int = (
		_selected_step_ids().size()
		if _current_kind == "dialogue"
		else _selected_action_indices().size()
	)
	var total_count: int = (
		_current_dialogue_document().get("steps", []).size()
		if _current_kind == "dialogue"
		else _current_action_document().get("steps", []).size()
	)
	if selected_count <= 0:
		_status.text = "Выберите ноды для вырезания."
		return
	if total_count - selected_count < 1:
		_status.text = "Нельзя вырезать все ноды: граф должен содержать хотя бы одну."
		return
	_copy_selected_nodes()
	_delete_selected_action_nodes()
	_status.text = "Вырезано нод: %d · ↶ вернёт их, Ctrl+V вставит копию." % selected_count


func _paste_nodes() -> void:
	if _current_kind == "quest":
		return
	if _node_clipboard.is_empty():
		_status.text = "Буфер нод пуст. Сначала нажмите Ctrl+C или Ctrl+X."
		return
	if str(_node_clipboard.get("kind", "")) != _current_kind:
		_status.text = "Буфер содержит другой тип графа; переключитесь обратно или скопируйте новые ноды."
		return
	var copied_steps: Array = _node_clipboard.get("steps", [])
	if copied_steps.is_empty():
		return
	if _current_kind == "dialogue":
		var pasted := DialogueGraphModel.paste_steps(
			_current_dialogue_document(), _node_clipboard, _clipboard_graph_position()
		)
		var new_ids: Array[String] = []
		for raw_id in pasted.get("newIds", []):
			new_ids.append(str(raw_id))
		if new_ids.is_empty():
			_status.text = "В буфере нет совместимых dialogue-нод."
			return
		_clipboard_paste_serial += 1
		_push_dialogue_draft(pasted.get("document", {}))
		_select_dialogue_steps(new_ids)
		return
	var document := _current_action_document()
	var steps: Array = document.get("steps", []).duplicate(true)
	var selected := _selected_action_indices()
	var insert_at := selected[-1] + 1 if not selected.is_empty() else steps.size()
	for offset in copied_steps.size():
		steps.insert(insert_at + offset, (copied_steps[offset] as Dictionary).duplicate(true))
	document["steps"] = steps
	_push_action_draft(document)
	_select_action_indices(insert_at, copied_steps.size())


func _clipboard_graph_position() -> Vector2:
	var local := _graph.get_local_mouse_position()
	if not Rect2(Vector2.ZERO, _graph.size).has_point(local):
		local = _graph.size * 0.5
	var position := _graph.scroll_offset + local / maxf(_graph.zoom, 0.01)
	position += Vector2.ONE * 30.0 * float(_clipboard_paste_serial)
	var distance := maxf(float(_graph.snapping_distance), 1.0)
	return Vector2(snappedf(position.x, distance), snappedf(position.y, distance))


func _on_delete_nodes_request(nodes: Array[StringName]) -> void:
	if nodes.is_empty():
		return
	if _current_kind == "quest":
		var objective_indices: Array[int] = []
		for node_name in nodes:
			var quest_node := _graph.get_node_or_null(NodePath(str(node_name))) as GraphNode
			if quest_node == null or str(quest_node.get_meta("quest_role", "")) != "objective":
				continue
			var objective_index := int(quest_node.get_meta("editor_index", -1))
			if objective_index >= 0 and objective_index not in objective_indices:
				objective_indices.append(objective_index)
		var quest_document := _current_quest_document()
		var quest_objectives: Array = quest_document.get("objectives", []).duplicate(true)
		if objective_indices.is_empty():
			_status.text = "Центральную ноду задания удалить нельзя; выберите цель."
			return
		if quest_objectives.size() - objective_indices.size() < 1:
			_status.text = "У задания должна остаться хотя бы одна цель."
			return
		objective_indices.sort()
		objective_indices.reverse()
		var removed_ids: Array[String] = []
		for objective_index in objective_indices:
			if objective_index < quest_objectives.size():
				removed_ids.append(str((quest_objectives[objective_index] as Dictionary).get("id", "")))
				quest_objectives.remove_at(objective_index)
		for index in quest_objectives.size():
			var objective: Dictionary = (quest_objectives[index] as Dictionary).duplicate(true)
			var dependencies: Array = objective.get("requiresObjectiveIds", []).duplicate()
			for removed_id in removed_ids:
				dependencies.erase(removed_id)
			objective["requiresObjectiveIds"] = dependencies
			quest_objectives[index] = objective
		quest_document["objectives"] = quest_objectives
		var layout: Dictionary = quest_document.get("editorLayout", {}).duplicate(true)
		for removed_id in removed_ids:
			layout.erase("objective:%s" % removed_id)
		quest_document["editorLayout"] = layout
		_push_quest_draft(quest_document)
		return
	if _current_kind == "dialogue":
		var step_ids: Array[String] = []
		var group_ids: Array[String] = []
		for node_name in nodes:
			var element := _graph.get_node_or_null(NodePath(str(node_name))) as GraphElement
			var element_group_id := str(element.get_meta("group_id", "")) if element != null else ""
			if not element_group_id.is_empty():
				if element_group_id not in group_ids:
					group_ids.append(element_group_id)
			elif element is GraphNode:
				var graph_node := element as GraphNode
				var step_id := str(graph_node.get_meta("step_id", ""))
				if not step_id.is_empty() and step_id not in step_ids:
					step_ids.append(step_id)
		var document := _current_dialogue_document()
		if not group_ids.is_empty():
			document = DialogueGraphModel.remove_groups(document, group_ids)
		if step_ids.is_empty():
			_push_dialogue_draft(document)
			return
		if document.get("steps", []).size() - step_ids.size() < 1:
			_status.text = "Dialogue graph должен содержать хотя бы одну ноду."
			return
		_push_dialogue_draft(DialogueGraphModel.remove_steps(document, step_ids))
		return
	var indices: Array[int] = []
	for node_name in nodes:
		var graph_node := _graph.get_node_or_null(NodePath(str(node_name))) as GraphNode
		if graph_node != null:
			var index := int(graph_node.get_meta("editor_index", -1))
			if index >= 0 and index not in indices:
				indices.append(index)
	var document := _current_action_document()
	var steps: Array = document.get("steps", []).duplicate(true)
	if indices.is_empty():
		return
	if steps.size() - indices.size() < 1:
		_status.text = "Цепочка должна содержать хотя бы одну ноду."
		return
	indices.sort()
	indices.reverse()
	for index in indices:
		if index < steps.size():
			steps.remove_at(index)
	document["steps"] = steps
	_push_action_draft(document)


func _set_selected_dialogue_start() -> void:
	if _current_kind != "dialogue" or _selected_step_id.is_empty():
		return
	var document := DialogueGraphModel.set_start(_current_dialogue_document(), _selected_step_id)
	_push_dialogue_draft(document)
	_select_dialogue_step(_selected_step_id)


func _create_group_from_selection() -> void:
	if _current_kind != "dialogue":
		return
	var members: Array[String] = []
	for graph_node in _graph_nodes():
		if graph_node.selected:
			members.append(str(graph_node.get_meta("step_id", "")))
	if members.is_empty():
		_status.text = "Выберите одну или несколько dialogue-нод. Shift+клик добавляет к выбору."
		return
	var changed := DialogueGraphModel.add_group(_current_dialogue_document(), _group_name.text, members)
	var groups: Array = changed.get("editorGroups", [])
	var group_id := str((groups[-1] as Dictionary).get("id", "")) if not groups.is_empty() else ""
	_push_dialogue_draft(changed)
	_select_group(group_id)


func _remove_selected_groups() -> void:
	if _current_kind != "dialogue":
		return
	if not _selected_group_id.is_empty():
		_push_dialogue_draft(DialogueGraphModel.remove_groups(
			_current_dialogue_document(), [_selected_group_id]
		))
		return
	var selected_steps: Array[String] = []
	for graph_node in _graph_nodes():
		if graph_node.selected:
			selected_steps.append(str(graph_node.get_meta("step_id", "")))
	if selected_steps.is_empty() or not _selection_has_group_member():
		_status.text = "Выберите frame или ноду внутри группы."
		return
	_push_dialogue_draft(DialogueGraphModel.remove_members_from_groups(
		_current_dialogue_document(), selected_steps
	))


func _toggle_group_collapsed(group_id: String) -> void:
	if _current_kind != "dialogue":
		return
	var collapsed := false
	for raw_group in _dialogue_draft.get("editorGroups", []):
		if typeof(raw_group) == TYPE_DICTIONARY and str(raw_group.get("id", "")) == group_id:
			collapsed = bool((raw_group as Dictionary).get("collapsed", false))
			break
	_push_dialogue_draft(DialogueGraphModel.set_group_collapsed(
		_current_dialogue_document(), group_id, not collapsed
	))
	_select_group(group_id)


func _on_graph_elements_linked_to_frame_request(elements: Array, frame_name: StringName) -> void:
	if _current_kind == "quest":
		return
	if _current_kind != "dialogue":
		return
	var frame := _graph.get_node_or_null(NodePath(str(frame_name))) as GraphFrame
	if frame == null:
		return
	var members: Array[String] = []
	for raw_element in elements:
		var graph_node := raw_element as GraphNode
		if graph_node != null:
			var step_id := str(graph_node.get_meta("step_id", ""))
			if not step_id.is_empty() and step_id not in members:
				members.append(step_id)
	if members.is_empty():
		return
	var group_id := str(frame.get_meta("group_id", ""))
	_push_dialogue_draft(DialogueGraphModel.add_members_to_group(
		_current_dialogue_document(), group_id, members
	))
	_select_group(group_id)


func _rename_selected_group(title: String) -> void:
	if _current_kind != "dialogue" or _selected_group_id.is_empty():
		return
	var group_id := _selected_group_id
	_push_dialogue_draft(DialogueGraphModel.rename_group(
		_current_dialogue_document(), group_id, title
	))
	_select_group(group_id)


func _quest_dependency_input_port() -> int:
	# GraphNode ports are indexed by enabled inputs, not by their slot number.
	# Compact overview hides the membership input, so dependency becomes port 0;
	# focus/all-links keep membership enabled, so dependency remains port 1.
	return 0 if _quest_focus_target.is_empty() else 1


func _on_connection_request(
	from_node: StringName,
	from_port: int,
	to_node: StringName,
	to_port: int,
) -> void:
	var source := _graph.get_node_or_null(NodePath(str(from_node))) as GraphNode
	var target := _graph.get_node_or_null(NodePath(str(to_node))) as GraphNode
	if source == null or target == null or source == target:
		return
	if _current_kind == "quest":
		var source_role := str(source.get_meta("quest_role", ""))
		var target_role := str(target.get_meta("quest_role", ""))
		if source_role in ["scene", "scene_candidate"] and from_port == 0:
			var event_token := ""
			if target_role == "objective" and to_port == 3:
				event_token = QuestStore.event_token(
					str(_quest_draft.get("id", "")),
					"objective",
					str(target.get_meta("objective_id", "")),
				)
			elif target_role == "root" and to_port in [1, 2]:
				event_token = QuestStore.event_token(
					str(_quest_draft.get("id", "")),
					"start" if to_port == 1 else "complete",
				)
			if event_token.is_empty():
				_status.text = "Тяните зелёный порт объекта к зелёному входу старта, завершения или цели."
				return
			_request_quest_event_binding_for(
				NodePath(str(source.get_meta("owner_path", ""))), event_token
			)
			return
		var dependency_input_port := _quest_dependency_input_port()
		if (
			source_role != "objective"
			or target_role != "objective"
			or from_port != 0
			or to_port != dependency_input_port
		):
			_status.text = "Соединяйте выход цели с синим входом следующей цели."
			return
		var source_id := str(source.get_meta("objective_id", ""))
		var target_id := str(target.get_meta("objective_id", ""))
		var changed := QuestStore.set_dependency(
			_current_quest_document(), source_id, target_id, true
		)
		if changed == _quest_draft:
			_status.text = "Эту зависимость нельзя добавить: она уже есть или создаёт цикл."
			_status.modulate = Color(1.0, 0.48, 0.42)
			return
		_push_quest_draft(changed)
		_select_quest_objective(int(target.get_meta("editor_index", -1)))
		return
	if _current_kind == "dialogue":
		var source_id := str(source.get_meta("step_id", ""))
		var target_id := str(target.get_meta("step_id", ""))
		var changed := DialogueGraphModel.replace_edge(
			_current_dialogue_document(), source_id, from_port, target_id
		)
		if changed == _dialogue_draft:
			_status.text = "Этот выход нельзя переподключить."
			return
		_push_dialogue_draft(changed)
		_select_dialogue_step(source_id)
		return
	var source_index := int(source.get_meta("editor_index", -1))
	var target_index := int(target.get_meta("editor_index", -1))
	if source_index < 0 or target_index < 0 or target_index == source_index + 1:
		return
	var document := _current_action_document()
	var steps: Array = document.get("steps", []).duplicate(true)
	if source_index >= steps.size() or target_index >= steps.size():
		return
	var target_step: Variant = steps[target_index]
	steps.remove_at(target_index)
	if target_index < source_index:
		source_index -= 1
	var insert_index := mini(source_index + 1, steps.size())
	steps.insert(insert_index, target_step)
	document["steps"] = steps
	_push_action_draft(document)
	_select_action_index(insert_index)


func _on_disconnection_request(
	from_node: StringName,
	from_port: int,
	to_node: StringName,
	to_port: int,
) -> void:
	if _current_kind == "quest":
		var source := _graph.get_node_or_null(NodePath(str(from_node))) as GraphNode
		var target := _graph.get_node_or_null(NodePath(str(to_node))) as GraphNode
		if (
			source != null
			and target != null
			and str(source.get_meta("quest_role", "")) == "scene"
			and str(target.get_meta("quest_role", "")) == "usage"
			and from_port == 0
			and to_port == 0
		):
			_request_quest_event_unbinding_for(
				NodePath(str(source.get_meta("owner_path", ""))),
				target.get_meta("quest_event", {}) as Dictionary,
			)
			return
		var dependency_input_port := _quest_dependency_input_port()
		if (
			source != null
			and target != null
			and str(source.get_meta("quest_role", "")) == "objective"
			and str(target.get_meta("quest_role", "")) == "objective"
			and from_port == 0
			and to_port == dependency_input_port
		):
			_push_quest_draft(QuestStore.set_dependency(
				_current_quest_document(),
				str(source.get_meta("objective_id", "")),
				str(target.get_meta("objective_id", "")),
				false,
			))
		else:
			_status.text = "Золотая связь показывает принадлежность цели и не удаляется."
		return
	if _current_kind == "dialogue":
		var source := _graph.get_node_or_null(NodePath(str(from_node))) as GraphNode
		if source == null:
			return
		var source_id := str(source.get_meta("step_id", ""))
		_push_dialogue_draft(DialogueGraphModel.replace_edge(
			_current_dialogue_document(), source_id, from_port, ""
		))
		_status.text = "Выход отключён · исправьте красную диагностику перед сохранением."
		return
	_status.text = "Action-chain всегда связная: перетащите новый провод, чтобы изменить порядок."


func _undo_action_draft() -> void:
	if _current_kind == "dialogue":
		if _dialogue_cursor <= 0:
			return
		_dialogue_cursor -= 1
		_apply_dialogue_draft(_dialogue_history[_dialogue_cursor])
	elif _current_kind == "quest":
		if _quest_cursor <= 0:
			return
		_quest_cursor -= 1
		_apply_quest_draft(_quest_history[_quest_cursor])
	else:
		if _draft_cursor <= 0:
			return
		_draft_cursor -= 1
		_apply_action_draft(_draft_history[_draft_cursor])


func _redo_action_draft() -> void:
	if _current_kind == "dialogue":
		if _dialogue_cursor + 1 >= _dialogue_history.size():
			return
		_dialogue_cursor += 1
		_apply_dialogue_draft(_dialogue_history[_dialogue_cursor])
	elif _current_kind == "quest":
		if _quest_cursor + 1 >= _quest_history.size():
			return
		_quest_cursor += 1
		_apply_quest_draft(_quest_history[_quest_cursor])
	else:
		if _draft_cursor + 1 >= _draft_history.size():
			return
		_draft_cursor += 1
		_apply_action_draft(_draft_history[_draft_cursor])


func _select_action_index(index: int) -> void:
	for graph_node in _graph_nodes():
		if int(graph_node.get_meta("editor_index", -1)) == index:
			_graph.set_selected(graph_node)
			_on_node_selected(graph_node)
			return


func _select_dialogue_step(step_id: String) -> void:
	for graph_node in _graph_nodes():
		if str(graph_node.get_meta("step_id", "")) == step_id:
			_graph.set_selected(graph_node)
			_on_node_selected(graph_node)
			return


func _select_dialogue_steps(step_ids: Array[String]) -> void:
	var last: GraphNode
	for graph_node in _graph_nodes():
		graph_node.selected = str(graph_node.get_meta("step_id", "")) in step_ids
		if graph_node.selected:
			last = graph_node
	if last != null:
		_on_node_selected(last)


func _select_action_indices(first: int, count: int) -> void:
	var last: GraphNode
	for graph_node in _graph_nodes():
		var index := int(graph_node.get_meta("editor_index", -1))
		graph_node.selected = index >= first and index < first + count
		if graph_node.selected:
			last = graph_node
	if last != null:
		_on_node_selected(last)


func _select_quest_objective(index: int) -> void:
	for graph_node in _graph_nodes():
		if (
			str(graph_node.get_meta("quest_role", "")) == "objective"
			and int(graph_node.get_meta("editor_index", -1)) == index
		):
			_graph.set_selected(graph_node)
			_on_node_selected(graph_node)
			return


func _select_group(group_id: String) -> void:
	for element in _graph_elements():
		if str(element.get_meta("group_id", "")) == group_id:
			_graph.set_selected(element)
			_on_node_selected(element)
			return


func _update_mutation_controls() -> void:
	var action_mode := _current_kind == "action"
	var dialogue_mode := _current_kind == "dialogue"
	var quest_mode := _current_kind == "quest"
	var loot_mode := _current_kind == "loot"
	var sculpt_mode := _current_kind == "voxel_sculpt"
	if _resource != null:
		_resource.visible = not loot_mode
	if _arrange_button != null:
		_arrange_button.visible = not loot_mode and not sculpt_mode
	if _secondary_tools_button != null:
		_secondary_tools_button.visible = not loot_mode and not sculpt_mode
	for control in [_graph_add_type, _graph_add_button]:
		if control != null:
			control.visible = action_mode
	for control in [_dialogue_add_type, _dialogue_add_button, _set_start_button]:
		if control != null:
			control.visible = dialogue_mode
	for control in [_quest_new_button, _quest_add_objective_button]:
		if control != null:
			control.visible = quest_mode
	if _quest_overview_button != null:
		_quest_overview_button.visible = quest_mode
		_quest_overview_button.disabled = _quest_focus_target.is_empty()
	if _quest_all_links_button != null:
		_quest_all_links_button.visible = quest_mode
		_quest_all_links_button.disabled = not quest_mode or _quest_focus_target == "__all__"
	if _quest_focus_label != null:
		_quest_focus_label.visible = quest_mode
		_quest_focus_label.text = _quest_focus_title()
		_quest_focus_label.tooltip_text = _quest_focus_label.text
	if _quest_event_button != null:
		_quest_event_button.visible = not quest_mode and not loot_mode and not sculpt_mode
		_quest_event_button.disabled = (
			(action_mode and _action_draft.is_empty())
			or (dialogue_mode and _dialogue_draft.is_empty())
		)
	if _quest_add_objective_button != null:
		_quest_add_objective_button.disabled = not quest_mode or _quest_draft.is_empty()
	if _graph_delete_button != null:
		_graph_delete_button.visible = not loot_mode and not sculpt_mode
		_graph_delete_button.disabled = (
			not _has_selected_quest_objective()
			if quest_mode
			else not _has_selected_graph_node()
		)
	if _duplicate_button != null:
		_duplicate_button.visible = not quest_mode and not loot_mode and not sculpt_mode
		_duplicate_button.disabled = quest_mode or not _has_selected_step_node()
	if _clipboard_menu != null:
		_clipboard_menu.visible = not quest_mode and not loot_mode and not sculpt_mode
		var popup := _clipboard_menu.get_popup()
		popup.set_item_disabled(CLIPBOARD_COPY, not _has_selected_step_node())
		popup.set_item_disabled(CLIPBOARD_CUT, not _has_selected_step_node())
		popup.set_item_disabled(
			CLIPBOARD_PASTE,
			_node_clipboard.is_empty() or str(_node_clipboard.get("kind", "")) != _current_kind,
		)
	if _set_start_button != null:
		_set_start_button.disabled = (
			not dialogue_mode
			or _selected_step_id.is_empty()
			or _selected_step_id == str(_dialogue_draft.get("startStepId", ""))
		)
	for control in [_group_name, _group_button, _ungroup_button]:
		if control != null:
			control.visible = dialogue_mode
	if _group_button != null:
		_group_button.disabled = not dialogue_mode or not _has_selected_step_node()
	if _ungroup_button != null:
		_ungroup_button.disabled = not dialogue_mode or (_selected_group_id.is_empty() and not _selection_has_group_member())
		_ungroup_button.text = "Удалить группу" if not _selected_group_id.is_empty() else "Убрать из группы"
	if _draft_undo_button != null:
		_draft_undo_button.visible = not loot_mode and not sculpt_mode
		_draft_undo_button.disabled = (
			_quest_cursor <= 0
			if quest_mode
			else _draft_cursor <= 0
			if action_mode
			else _dialogue_cursor <= 0
		)
	if _draft_redo_button != null:
		_draft_redo_button.visible = not loot_mode and not sculpt_mode
		_draft_redo_button.disabled = (
			_quest_cursor + 1 >= _quest_history.size()
			if quest_mode
			else _draft_cursor + 1 >= _draft_history.size()
			if action_mode
			else _dialogue_cursor + 1 >= _dialogue_history.size()
		)
	if _graph_save_button != null:
		_graph_save_button.visible = not loot_mode and not sculpt_mode
		_graph_save_button.text = (
			"Сохранить цепочку"
			if action_mode
			else "Сохранить задание"
			if quest_mode
			else "Сохранить диалог"
		)
		_graph_save_button.disabled = (
			not QuestStore.validation_errors(_quest_draft).is_empty()
			if quest_mode
			else not ActionStore.validation_errors(_current_action_document()).is_empty()
			if action_mode
			else not DialogueStore.graph_validation_errors(_dialogue_draft).is_empty()
		)
	if _vn_preview_button != null:
		_vn_preview_button.visible = dialogue_mode
		_vn_preview_button.disabled = not dialogue_mode or _dialogue_draft.is_empty()


func _quest_focus_title() -> String:
	if _quest_focus_target.is_empty():
		return "› Обзор"
	if _quest_focus_target == "__all__":
		return "› Все связи"
	if _quest_focus_target == "quest_root":
		return "› Старт и завершение"
	for raw_objective in _quest_draft.get("objectives", []):
		if typeof(raw_objective) != TYPE_DICTIONARY:
			continue
		var objective: Dictionary = raw_objective
		if str(objective.get("id", "")) == _quest_focus_target:
			return "› %s" % str(objective.get("textRu", _quest_focus_target))
	return "› %s" % _quest_focus_target


func _open_quest_overview() -> void:
	_set_quest_focus("")


func _open_all_quest_links() -> void:
	_set_quest_focus("__all__")


func _open_quest_event_focus(target_id: String) -> void:
	_set_quest_focus(target_id)


func _set_quest_focus(target_id: String) -> void:
	if _current_kind != "quest" or _quest_draft.is_empty() or target_id == _quest_focus_target:
		return
	_capture_view_state()
	_quest_focus_target = target_id
	_selected_editor_index = -1
	_render_document(_quest_draft)
	_build_property_editor()
	_update_mutation_controls()


func _update_action_draft_status() -> void:
	if _current_kind != "action":
		return
	_status.modulate = Color(0.66, 0.74, 0.84)
	var diagnostics := ActionStore.validation_diagnostics(_action_draft)
	var errors := _diagnostic_messages(diagnostics)
	var dirty := _draft_cursor > 0
	_status.text = "%s · %d нод%s%s" % [
		_current_id,
		_action_draft.get("steps", []).size(),
		" · ЧЕРНОВИК" if dirty else "",
		" · ⚠ %s" % errors[0] if not errors.is_empty() else "",
	]
	_update_diagnostic_focus_button(diagnostics)


func _update_dialogue_draft_status() -> void:
	if _current_kind != "dialogue":
		return
	var diagnostics := DialogueGraphModel.validation_diagnostics(_dialogue_draft)
	var errors := _diagnostic_messages(diagnostics)
	_status.text = "%s · %d нод%s%s" % [
		_current_id,
		_dialogue_draft.get("steps", []).size(),
		" · ЧЕРНОВИК" if _dialogue_cursor > 0 or not _inline_edit_before.is_empty() else "",
		" · ⚠ %s" % errors[0] if not errors.is_empty() else " · связи корректны",
	]
	_status.modulate = Color(1.0, 0.48, 0.42) if not errors.is_empty() else Color(0.66, 0.82, 0.70)
	_update_diagnostic_focus_button(diagnostics)


func _update_quest_draft_status() -> void:
	if _current_kind != "quest":
		return
	var errors := QuestStore.validation_errors(_quest_draft)
	var objective_count: int = _quest_draft.get("objectives", []).size()
	var dependency_count := QuestStore.dependency_edges(_quest_draft).size()
	_status.text = "%s · 1 задание + %d целей · %d переходов%s%s" % [
		str(_quest_draft.get("id", _current_id)),
		objective_count,
		dependency_count,
		" · НОВЫЙ" if _quest_is_new else " · ЧЕРНОВИК" if _quest_cursor > 0 or not _quest_inline_before.is_empty() else "",
		" · ⚠ %s" % errors[0] if not errors.is_empty() else " · готово к сохранению",
	]
	_status.modulate = Color(1.0, 0.48, 0.42) if not errors.is_empty() else Color(0.72, 0.84, 0.48)
	if _diagnostic_focus_button != null:
		_diagnostic_focus_button.visible = false


func _save_current_graph() -> void:
	if _current_kind == "quest":
		_save_quest_graph()
		return
	if _current_kind == "dialogue":
		_save_dialogue_graph()
		return
	if _current_kind != "action":
		return
	var document := _current_action_document()
	var errors := ActionStore.validation_errors(document)
	if not errors.is_empty():
		_status.text = "Сохранение остановлено · %s" % errors[0]
		_status.modulate = Color(1.0, 0.48, 0.42)
		return
	action_save_requested.emit(document)
	_current_id = str(document.get("id", _current_id))
	_refresh_resource_list(_current_id)
	_open_selected()


func _save_dialogue_graph() -> void:
	if _current_kind == "quest":
		_save_quest_graph()
		return
	if _current_kind != "dialogue":
		return
	var document := _current_dialogue_document()
	var errors := DialogueStore.graph_validation_errors(document)
	if not errors.is_empty():
		_status.text = "Сохранение остановлено · %s" % errors[0]
		_status.modulate = Color(1.0, 0.48, 0.42)
		return
	dialogue_save_requested.emit(document)
	_current_id = str(document.get("id", _current_id))
	_refresh_resource_list(_current_id)
	_open_selected()


func _save_quest_graph() -> void:
	var document := _current_quest_document()
	var errors := QuestStore.validation_errors(document)
	if not errors.is_empty():
		_status.text = "Сохранение остановлено · %s" % errors[0]
		_status.modulate = Color(1.0, 0.48, 0.42)
		return
	quest_save_requested.emit(document)
	_current_id = str(document.get("id", _current_id))
	_quest_is_new = false
	_refresh_resource_list(_current_id)
	_open_selected()


func _refresh_resource_list(preferred: String = "") -> void:
	if _resource == null:
		return
	var ids: Array[String] = []
	if _current_kind == "voxel_sculpt":
		ids = [EmberVoxelSculptModel.PILOT_ID]
		for registered_id in _voxel_surface_sources:
			if str(registered_id) not in ids:
				ids.append(str(registered_id))
	elif _current_kind == "dialogue":
		ids = EmberInteractionContent.dialogue_ids()
	elif _current_kind == "quest":
		ids = QuestStore.ids()
	elif _current_kind == "loot":
		ids = LootTableCatalog.ids()
	elif _current_kind == "combat_content":
		ids = ["combat_library"]
	else:
		ids = EmberInteractionContent.action_script_ids()
	_resource.clear()
	for resource_id in ids:
		var label := resource_id
		if _current_kind == "voxel_sculpt":
			if _voxel_surface_sources.has(resource_id):
				label = str((_voxel_surface_sources[resource_id] as Dictionary).get("label", resource_id))
			else:
				label = "Surface Canvas 4×4 · %s" % resource_id
		elif _current_kind == "quest":
			var quest := QuestStore.document(resource_id)
			label = "%s · %s" % [str(quest.get("titleRu", resource_id)), resource_id]
		elif _current_kind == "loot":
			var table := LootTableCatalog.resource(resource_id)
			label = "%s · %s" % [table.display_name if table != null else resource_id, resource_id]
		elif _current_kind == "combat_content":
			label = "Эффекты · умения · герои и существа"
		_resource.add_item(label)
		_resource.set_item_metadata(_resource.item_count - 1, resource_id)
		if resource_id == preferred:
			_resource.select(_resource.item_count - 1)
	if _resource.item_count == 0:
		_current_id = ""
	elif preferred.is_empty() or not preferred in ids:
		_resource.select(0)
		_current_id = str(_resource.get_item_metadata(0))


func _open_selected() -> void:
	_capture_view_state()
	if _resource == null or _resource.item_count == 0 or _resource.selected < 0:
		_current_id = ""
		_clear_graph()
		_clear_editor()
		if _diagnostic_focus_button != null:
			_diagnostic_focus_button.visible = false
		_status.text = "Контент не найден"
		return
	_current_id = str(_resource.get_item_metadata(_resource.selected))
	_selected_editor_index = -1
	_selected_step_id = ""
	_selected_group_id = ""
	if _current_kind == "voxel_sculpt":
		_action_draft = {}
		_draft_history.clear()
		_draft_cursor = -1
		_dialogue_draft = {}
		_dialogue_history.clear()
		_dialogue_cursor = -1
		_quest_draft = {}
		_quest_history.clear()
		_quest_cursor = -1
		_quest_is_new = false
		_clear_graph()
		_clear_editor()
		if _graph_split != null:
			_graph_split.visible = false
		if _loot_workspace != null:
			_loot_workspace.visible = false
		if _combat_content_workspace != null:
			_combat_content_workspace.visible = false
		if _voxel_sculpt_workspace != null:
			_voxel_sculpt_workspace.visible = true
			if _voxel_surface_sources.has(_current_id):
				var source := _voxel_surface_sources[_current_id] as Dictionary
				_voxel_sculpt_workspace.open_surface(
					source.get("resource") as EmberVoxelModelResource,
					str(source.get("path", "")),
					source.get("region", Rect2i()),
				)
			else:
				_voxel_sculpt_workspace.open_pilot()
		_update_mutation_controls()
		return
	if _current_kind == "loot":
		_action_draft = {}
		_draft_history.clear()
		_draft_cursor = -1
		_dialogue_draft = {}
		_dialogue_history.clear()
		_dialogue_cursor = -1
		_quest_draft = {}
		_quest_history.clear()
		_quest_cursor = -1
		_quest_is_new = false
		_clear_graph()
		_clear_editor()
		if _graph_split != null:
			_graph_split.visible = false
		if _loot_workspace != null:
			_loot_workspace.visible = true
			_loot_workspace.refresh(_current_id)
		if _voxel_sculpt_workspace != null:
			_voxel_sculpt_workspace.visible = false
		if _combat_content_workspace != null:
			_combat_content_workspace.visible = false
		_update_mutation_controls()
		_status.text = "%s · центральная библиотека · item icons, шанс и количество · Ctrl+Z через Godot" % _current_id
		_status.modulate = Color(0.66, 0.74, 0.84)
		return
	if _current_kind == "combat_content":
		_action_draft = {}
		_draft_history.clear()
		_draft_cursor = -1
		_dialogue_draft = {}
		_dialogue_history.clear()
		_dialogue_cursor = -1
		_quest_draft = {}
		_quest_history.clear()
		_quest_cursor = -1
		_quest_is_new = false
		_clear_graph()
		_clear_editor()
		if _graph_split != null:
			_graph_split.visible = false
		if _loot_workspace != null:
			_loot_workspace.visible = false
		if _voxel_sculpt_workspace != null:
			_voxel_sculpt_workspace.visible = false
		if _combat_content_workspace != null:
			_combat_content_workspace.visible = true
			_combat_content_workspace.call("refresh")
		_update_mutation_controls()
		_status.text = "Единая библиотека боя · reusable effects → actions → units · canonical .tres"
		_status.modulate = Color(0.66, 0.74, 0.84)
		return
	if _graph_split != null:
		_graph_split.visible = true
	if _loot_workspace != null:
		_loot_workspace.visible = false
	if _combat_content_workspace != null:
		_combat_content_workspace.visible = false
	if _voxel_sculpt_workspace != null:
		_voxel_sculpt_workspace.visible = false
	var document: Dictionary
	if _current_kind == "dialogue":
		document = DialogueStore.document(_current_id)
	elif _current_kind == "quest":
		document = QuestStore.document(_current_id)
	else:
		document = ActionStore.document(_current_id)
	if _current_kind == "action":
		_reset_action_draft(document)
		document = _action_draft
		_dialogue_draft = {}
		_dialogue_history.clear()
		_dialogue_cursor = -1
		_quest_draft = {}
		_quest_history.clear()
		_quest_cursor = -1
		_quest_is_new = false
	elif _current_kind == "dialogue":
		_action_draft = {}
		_draft_history.clear()
		_draft_cursor = -1
		_reset_dialogue_draft(document)
		document = _dialogue_draft
		_quest_draft = {}
		_quest_history.clear()
		_quest_cursor = -1
		_quest_is_new = false
	else:
		_action_draft = {}
		_draft_history.clear()
		_draft_cursor = -1
		_dialogue_draft = {}
		_dialogue_history.clear()
		_dialogue_cursor = -1
		_reset_quest_draft(document)
		document = _quest_draft
	_render_document(document)
	_build_property_editor()
	_update_mutation_controls()
	if _current_kind == "action":
		_update_action_draft_status()
		if is_instance_valid(_vn_preview_window):
			_vn_preview_window.hide()
	elif _current_kind == "dialogue":
		_update_dialogue_draft_status()
		_refresh_vn_preview()
	else:
		_update_quest_draft_status()
		if is_instance_valid(_vn_preview_window):
			_vn_preview_window.hide()


func _render_document(document: Dictionary) -> void:
	_clear_graph()
	if document.is_empty():
		if _diagnostic_focus_button != null:
			_diagnostic_focus_button.visible = false
		_status.text = "Документ не найден"
		return
	if _current_kind == "dialogue":
		_render_dialogue(document)
	elif _current_kind == "quest":
		_render_quest(document)
	else:
		_render_action(document)
	if _current_kind == "quest":
		var usage_count := 0
		var scene_count := 0
		for graph_node in _graph_nodes():
			if str(graph_node.get_meta("quest_role", "")) == "usage":
				usage_count += 1
			elif str(graph_node.get_meta("quest_role", "")) == "scene":
				scene_count += 1
		if _quest_focus_target.is_empty():
			_status.text = "%s · компактный обзор · %d целей · откройте события внутри нужной ноды" % [
				_current_id,
				(_quest_draft.get("objectives", []) as Array).size(),
			]
		elif _quest_focus_target == "__all__":
			_status.text = "%s · все связи · %d событий · %d объектов" % [
				_current_id, usage_count, scene_count,
			]
		else:
			_status.text = "%s · %s · %d событий · %d объектов" % [
				_current_id, _quest_focus_title(), usage_count, scene_count,
			]
	else:
		_status.text = "%s · %d нод · view не меняет документ" % [
			_current_id,
			_graph_nodes().size(),
		]
	_restore_view_state()
	_graph.queue_redraw()


func _render_quest(document: Dictionary) -> void:
	var color := Color(0.96, 0.70, 0.26)
	var dependency_color := Color(0.34, 0.72, 1.0)
	var usage_color := Color(0.72, 0.42, 0.92)
	var layout: Dictionary = document.get("editorLayout", {})
	var usage_entries := QuestUsageIndex.entries(document)
	var scene_root := _scene_root()
	var scene_entries: Array[Dictionary] = []
	if scene_root != null:
		scene_entries = QuestUsageIndex.scene_entries(scene_root, document, usage_entries)
	var objective_ids := {}
	for raw_objective in document.get("objectives", []):
		if typeof(raw_objective) == TYPE_DICTIONARY:
			objective_ids[str((raw_objective as Dictionary).get("id", ""))] = true
	if (
		not _quest_focus_target.is_empty()
		and _quest_focus_target not in ["__all__", "quest_root"]
		and not objective_ids.has(_quest_focus_target)
	):
		_quest_focus_target = ""
	var overview_mode := _quest_focus_target.is_empty()
	var all_links_mode := _quest_focus_target == "__all__"
	var focused_mode := not overview_mode and not all_links_mode
	var root_visible := not focused_mode or _quest_focus_target == "quest_root"
	var root_node := GraphNode.new()
	root_node.name = "quest_root"
	root_node.title = "Задание · %s" % str(document.get("id", ""))
	var root_layout: Dictionary = layout.get("quest_root", {})
	root_node.position_offset = Vector2(
		float(root_layout.get("x", 60.0)),
		float(root_layout.get("y", 150.0)),
	)
	root_node.custom_minimum_size = Vector2(360.0, 270.0)
	root_node.resizable = false
	root_node.set_meta("step_id", "quest_root")
	root_node.set_meta("quest_role", "root")
	root_node.set_meta("editor_index", -1)
	var root_body := VBoxContainer.new()
	root_body.name = "InlineQuestFields"
	root_body.custom_minimum_size.x = 325.0
	root_body.add_theme_constant_override("separation", 4)
	root_node.add_child(root_body)
	_add_quest_inline_line(
		root_body, "ID", "id", str(document.get("id", "")), _quest_is_new,
		"Имя Resource. После первого сохранения не переименовывается."
	)
	_add_quest_inline_line(
		root_body, "Статус", "statusFlagId", str(document.get("statusFlagId", "")), true,
		"Save-ключ общего состояния: active / done / true."
	)
	_add_quest_inline_line(
		root_body, "Название", "titleRu", str(document.get("titleRu", "")), true,
		"Название, которое увидит игрок в журнале."
	)
	_add_quest_inline_multiline(root_body, "Описание", "summaryRu", str(document.get("summaryRu", "")))
	_add_quest_inline_toggle(
		root_body,
		"Показывать до принятия",
		"showWhenAvailable",
		bool(document.get("showWhenAvailable", false)),
	)
	_add_quest_binding_controls(root_body, [
		{
			"name": "BindQuestStartToSelection",
			"text": "▶ Старт → объект",
			"token": QuestStore.event_token(str(document.get("id", "")), "start"),
		},
		{
			"name": "BindQuestCompleteToSelection",
			"text": "✓ Завершение → объект",
			"token": QuestStore.event_token(str(document.get("id", "")), "complete"),
		},
	])
	if overview_mode:
		_add_quest_event_summary(
			root_body, "quest_root", usage_entries, scene_entries, "OpenQuestRootEvents"
		)
	if not overview_mode:
		var root_usage_hint := Label.new()
		root_usage_hint.text = "События запуска / завершения"
		root_usage_hint.tooltip_text = "Фиолетовый вход показывает существующие action/dialogue события. Связь вычисляется и не хранится в задании."
		root_usage_hint.modulate = usage_color
		root_node.add_child(root_usage_hint)
		var root_start_bind := Label.new()
		root_start_bind.text = "Перетащить объект → начать задание"
		root_start_bind.tooltip_text = "Зелёный вход создаёт/дополняет цепочку выбранного объекта событием старта."
		root_start_bind.modulate = Color(0.46, 0.86, 0.62)
		root_node.add_child(root_start_bind)
		var root_complete_bind := Label.new()
		root_complete_bind.text = "Перетащить объект → завершить задание"
		root_complete_bind.tooltip_text = "Зелёный вход создаёт/дополняет цепочку выбранного объекта событием завершения."
		root_complete_bind.modulate = Color(0.58, 0.92, 0.72)
		root_node.add_child(root_complete_bind)
		root_node.set_slot(1, true, 2, usage_color, false, 0, usage_color)
		root_node.set_slot(2, true, 3, Color(0.46, 0.86, 0.62), false, 0, color)
		root_node.set_slot(3, true, 3, Color(0.58, 0.92, 0.72), false, 0, color)
	if not overview_mode:
		root_node.set_slot(0, false, 0, color, true, 0, color)
	if focused_mode:
		root_node.position_offset = Vector2(520.0, 220.0)
	if root_visible:
		_graph.add_child(root_node)
	var objectives: Array = document.get("objectives", [])
	var objective_nodes := {}
	for index in objectives.size():
		if typeof(objectives[index]) != TYPE_DICTIONARY:
			continue
		var objective: Dictionary = objectives[index]
		var objective_id := str(objective.get("id", "objective_%d" % (index + 1)))
		if focused_mode and _quest_focus_target != objective_id:
			continue
		var node := GraphNode.new()
		node.name = "quest_objective_%d" % index
		node.title = "Цель %d · %s" % [index + 1, objective_id]
		var layout_key := "objective:%s" % objective_id
		var objective_layout: Dictionary = layout.get(layout_key, {})
		node.position_offset = Vector2(
			float(objective_layout.get("x", 520.0)),
			float(objective_layout.get("y", 60.0 + index * 245.0)),
		)
		node.custom_minimum_size = Vector2(350.0, 215.0)
		node.resizable = false
		node.set_meta("step_id", "objective:%s" % objective_id)
		node.set_meta("quest_role", "objective")
		node.set_meta("objective_id", objective_id)
		node.set_meta("editor_index", index)
		var body := VBoxContainer.new()
		body.name = "InlineQuestObjectiveFields"
		body.custom_minimum_size.x = 315.0
		body.add_theme_constant_override("separation", 4)
		node.add_child(body)
		_add_quest_objective_line(body, index, "Внутренний ID", "id", objective_id)
		_add_quest_objective_line(
			body, index, "Текст", "textRu", str(objective.get("textRu", ""))
		)
		_add_quest_objective_line(
			body, index, "Прогресс цели (save key)", "flagId", str(objective.get("flagId", ""))
		)
		_add_quest_objective_progress(body, index, objective)
		_add_quest_objective_toggle(
			body, index, "Необязательная", bool(objective.get("optional", false))
		)
		var counter_mode := str(objective.get("progressMode", "flag")) == "counter"
		if not counter_mode:
			_add_quest_binding_controls(body, [{
			"name": "BindQuestObjective_%d_ToSelection" % index,
			"text": "□ Выполнение → объект",
			"token": QuestStore.event_token(
				str(document.get("id", "")), "objective", objective_id
			),
			}])
		if overview_mode and not counter_mode:
			_add_quest_event_summary(
				body,
				objective_id,
				usage_entries,
				scene_entries,
				"OpenQuestObjectiveEvents_%d" % index,
			)
		var dependency_ports := HBoxContainer.new()
		dependency_ports.name = "QuestDependencyPorts_%d" % index
		var dependency_hint := Label.new()
		dependency_hint.text = "После: %s" % (
			", ".join(objective.get("requiresObjectiveIds", []))
			if not (objective.get("requiresObjectiveIds", []) as Array).is_empty()
			else "без условий"
		)
		dependency_hint.tooltip_text = "Синий вход — предыдущие цели. Синий выход — следующая цель."
		dependency_hint.modulate = Color(0.54, 0.76, 0.96)
		dependency_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dependency_ports.add_child(dependency_hint)
		node.add_child(dependency_ports)
		if not overview_mode and not counter_mode:
			var usage_hint := Label.new()
			usage_hint.text = "События выполнения цели"
			usage_hint.tooltip_text = "Фиолетовый вход показывает, где существующий диалог или action chain меняет флаг этой цели."
			usage_hint.modulate = usage_color
			node.add_child(usage_hint)
			var bind_hint := Label.new()
			bind_hint.text = "Перетащить объект → выполнить цель"
			bind_hint.tooltip_text = "Зелёный вход создаёт/дополняет цепочку объекта обычным set_flag этой цели."
			bind_hint.modulate = Color(0.46, 0.86, 0.62)
			node.add_child(bind_hint)
			node.set_slot(2, true, 2, usage_color, false, 0, usage_color)
			node.set_slot(3, true, 3, Color(0.46, 0.86, 0.62), false, 0, color)
		if not overview_mode:
			node.set_slot(0, true, 0, color, false, 0, color)
		node.set_slot(1, true, 1, dependency_color, true, 1, dependency_color)
		if focused_mode:
			node.position_offset = Vector2(520.0, 220.0)
		_graph.add_child(node)
		objective_nodes[objective_id] = node.name
		if root_visible and all_links_mode:
			_graph.connect_node(root_node.name, 0, node.name, 0)
	for edge in QuestStore.dependency_edges(document):
		var prerequisite_id := str(edge.get("from", ""))
		var dependent_id := str(edge.get("to", ""))
		if objective_nodes.has(prerequisite_id) and objective_nodes.has(dependent_id):
			_graph.connect_node(
				objective_nodes[prerequisite_id], 0,
				objective_nodes[dependent_id], _quest_dependency_input_port(),
			)
	if overview_mode:
		return
	var visible_usage_entries: Array[Dictionary] = []
	for raw_entry in usage_entries:
		var entry: Dictionary = raw_entry
		if all_links_mode or str(entry.get("targetId", "")) == _quest_focus_target:
			visible_usage_entries.append(entry)
	var selected_event_ids := {}
	var scene_event_counts := {}
	for raw_scene_entry in scene_entries:
		var scene_entry: Dictionary = raw_scene_entry
		for raw_event_id in scene_entry.get("eventIds", []):
			var event_id := str(raw_event_id)
			scene_event_counts[event_id] = int(scene_event_counts.get(event_id, 0)) + 1
		if str(scene_entry.get("ownerPath", "")) != str(_selected_scene_path):
			continue
		for raw_event_id in scene_entry.get("eventIds", []):
			selected_event_ids[str(raw_event_id)] = true
	var usage_nodes := _render_quest_usages(
		document,
		visible_usage_entries,
		root_node.name,
		objective_nodes,
		usage_color,
		selected_event_ids,
		scene_event_counts,
	)
	var scene_owner_paths := _render_quest_scene_backlinks(
		scene_entries, usage_nodes
	)
	var candidate_anchor := root_node
	if focused_mode and _quest_focus_target != "quest_root":
		candidate_anchor = _graph.get_node_or_null(NodePath(str(
			objective_nodes.get(_quest_focus_target, "")
		))) as GraphNode
	if candidate_anchor != null:
		_render_selected_scene_candidate(document, candidate_anchor, scene_owner_paths)
	# In objective focus the root card is only a temporary source for its name;
	# it was never parented, so freeing the workspace cannot reclaim it.
	if not root_visible:
		root_node.free()


func _add_quest_event_summary(
	parent: Container,
	target_id: String,
	usage_entries: Array[Dictionary],
	scene_entries: Array[Dictionary],
	button_name: String,
) -> void:
	var event_ids := {}
	var action_documents := {}
	var dialogue_documents := {}
	for raw_entry in usage_entries:
		var entry: Dictionary = raw_entry
		if str(entry.get("targetId", "")) != target_id:
			continue
		event_ids[str(entry.get("id", ""))] = true
		var document_id := str(entry.get("documentId", ""))
		if str(entry.get("documentKind", "")) == "dialogue":
			dialogue_documents[document_id] = true
		else:
			action_documents[document_id] = true
	var scene_owners := {}
	for raw_scene_entry in scene_entries:
		var scene_entry: Dictionary = raw_scene_entry
		for raw_event_id in scene_entry.get("eventIds", []):
			if event_ids.has(str(raw_event_id)):
				scene_owners[str(scene_entry.get("ownerPath", ""))] = true
				break
	var card := VBoxContainer.new()
	card.name = "%sSummary" % button_name
	card.add_theme_constant_override("separation", 3)
	var counts := Label.new()
	counts.text = "Цепочки: %d · Диалоги: %d · Объекты: %d" % [
		action_documents.size(), dialogue_documents.size(), scene_owners.size(),
	]
	counts.tooltip_text = (
		"Сводка вычисляется из action/dialogue Resources и открытой сцены; "
		+ "в Quest Resource эти ссылки не копируются."
	)
	counts.modulate = Color(0.72, 0.66, 0.88)
	card.add_child(counts)
	var button := Button.new()
	button.name = button_name
	button.text = "Открыть события и объекты →"
	button.tooltip_text = "Сфокусировать граф только на этом событии и убрать паутину остальных целей."
	button.pressed.connect(_open_quest_event_focus.bind(target_id))
	card.add_child(button)
	parent.add_child(card)


func _render_quest_usages(
	document: Dictionary,
	usage_entries: Array[Dictionary],
	root_node_name: StringName,
	objective_nodes: Dictionary,
	color: Color,
	selected_event_ids: Dictionary,
	scene_event_counts: Dictionary,
) -> Dictionary:
	var target_counts := {}
	var usage_serial := 0
	var nodes_by_event_id := {}
	for raw_entry in usage_entries:
		var entry: Dictionary = raw_entry
		var target_id := str(entry.get("targetId", ""))
		var target_name := root_node_name if target_id == "quest_root" else StringName(
			str(objective_nodes.get(target_id, ""))
		)
		if str(target_name).is_empty():
			continue
		var target := _graph.get_node_or_null(NodePath(str(target_name))) as GraphNode
		if target == null:
			continue
		var target_index := int(target_counts.get(target_id, 0))
		target_counts[target_id] = target_index + 1
		usage_serial += 1
		var graph_node := GraphNode.new()
		graph_node.name = "quest_usage_%d" % usage_serial
		var source_title := str(entry.get("documentTitle", entry.get("documentId", "")))
		var compact_title := (
			source_title.left(27) + "…"
			if source_title.length() > 28
			else source_title
		)
		graph_node.title = "%s · %s" % [
			"Цепочка" if str(entry.get("documentKind", "")) == "action" else "Диалог",
			compact_title,
		]
		graph_node.tooltip_text = "%s · %s" % [
			str(entry.get("documentKind", "")), source_title,
		]
		graph_node.position_offset = target.position_offset + Vector2(
			-390.0,
			float(target_index) * 150.0,
		)
		graph_node.custom_minimum_size = Vector2(290.0, 104.0)
		graph_node.resizable = false
		graph_node.set_meta("step_id", str(entry.get("id", "")))
		graph_node.set_meta("quest_role", "usage")
		graph_node.set_meta("document_kind", str(entry.get("documentKind", "")))
		graph_node.set_meta("document_id", str(entry.get("documentId", "")))
		graph_node.set_meta("target_id", target_id)
		graph_node.set_meta("quest_event", entry.duplicate(true))
		graph_node.set_meta("editor_index", -1)
		var body := VBoxContainer.new()
		body.custom_minimum_size.x = 260.0
		var operation := Label.new()
		operation.text = str(entry.get("operationLabel", "Событие задания"))
		operation.modulate = color
		body.add_child(operation)
		var detail := Label.new()
		detail.text = "%s · %s = %s" % [
			str(entry.get("location", "")),
			str(entry.get("flag", "")),
			str(entry.get("value", "")),
		]
		detail.custom_minimum_size = Vector2(260.0, 24.0)
		detail.tooltip_text = detail.text
		detail.clip_text = true
		detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		detail.modulate = Color(0.72, 0.74, 0.80)
		body.add_child(detail)
		graph_node.add_child(body)
		graph_node.set_slot(0, false, 0, color, true, 2, color)
		var scene_hint := Label.new()
		scene_hint.text = "Объекты открытой сцены"
		scene_hint.tooltip_text = "Зелёный вход показывает scene-owned Interact, который запускает этот документ."
		scene_hint.modulate = Color(0.46, 0.86, 0.62)
		graph_node.add_child(scene_hint)
		graph_node.set_slot(1, true, 3, Color(0.46, 0.86, 0.62), false, 0, color)
		var action_row := HBoxContainer.new()
		action_row.name = "QuestUsageActions"
		action_row.add_theme_constant_override("separation", 4)
		graph_node.add_child(action_row)
		_add_link_button(
			action_row,
			str(entry.get("documentKind", "")),
			str(entry.get("documentId", "")),
			true,
		)
		if (
			str(entry.get("documentKind", "")) == "action"
			and selected_event_ids.has(str(entry.get("id", "")))
		):
			var unbind_button := Button.new()
			unbind_button.name = "UnbindSelectedQuestEvent_%d" % usage_serial
			unbind_button.text = "Отвязать"
			unbind_button.tooltip_text = (
				"Удалить только это событие из цепочки выбранного объекта. "
				+ "Общие цепочки защищены копированием. Ctrl+Z отменяет."
			)
			unbind_button.modulate = Color(1.0, 0.55, 0.50)
			unbind_button.pressed.connect(_request_quest_event_unbinding_for.bind(
				_selected_scene_path, entry.duplicate(true)
			))
			action_row.add_child(unbind_button)
		elif (
			str(entry.get("documentKind", "")) == "action"
			and int(scene_event_counts.get(str(entry.get("id", "")), 0)) == 0
		):
			var remove_button := Button.new()
			remove_button.name = "RemoveOrphanedQuestEvent_%d" % usage_serial
			remove_button.text = "Удалить лишнее"
			remove_button.tooltip_text = (
				"Ни один объект открытой сцены не запускает это событие. "
				+ "Удаляется только данный set_flag; пустая цепочка удалится целиком. "
				+ "Изменение действует на canonical Resource и отменяется Ctrl+Z."
			)
			remove_button.modulate = Color(1.0, 0.55, 0.50)
			remove_button.pressed.connect(_request_orphaned_quest_event_removal.bind(
				entry.duplicate(true)
			))
			action_row.add_child(remove_button)
		_graph.add_child(graph_node)
		_graph.connect_node(
			graph_node.name,
			0,
			target_name,
			0 if target_id == "quest_root" else 2,
		)
		nodes_by_event_id[str(entry.get("id", ""))] = graph_node.name
	return nodes_by_event_id


func _render_quest_scene_backlinks(
	scene_entries: Array[Dictionary],
	usage_nodes: Dictionary,
) -> Dictionary:
	var owner_paths := {}
	var color := Color(0.46, 0.86, 0.62)
	var scene_serial := 0
	for raw_entry in scene_entries:
		var entry: Dictionary = raw_entry
		var linked_names: Array[StringName] = []
		for raw_event_id in entry.get("eventIds", []):
			var event_id := str(raw_event_id)
			if usage_nodes.has(event_id):
				linked_names.append(StringName(str(usage_nodes[event_id])))
		if linked_names.is_empty():
			continue
		var anchor := _graph.get_node_or_null(NodePath(str(linked_names[0]))) as GraphNode
		if anchor == null:
			continue
		scene_serial += 1
		var graph_node := GraphNode.new()
		graph_node.name = "quest_scene_%d" % scene_serial
		var owner_name := str(entry.get("ownerName", "Объект"))
		var compact_name := owner_name.left(25) + "…" if owner_name.length() > 26 else owner_name
		graph_node.title = "Объект · %s" % compact_name
		graph_node.tooltip_text = str(entry.get("ownerPath", entry.get("nodePath", "")))
		graph_node.position_offset = anchor.position_offset + Vector2(
			-350.0,
			float(scene_serial - 1) * 125.0,
		)
		graph_node.custom_minimum_size = Vector2(270.0, 112.0)
		graph_node.resizable = false
		graph_node.set_meta("step_id", str(entry.get("id", "")))
		graph_node.set_meta("quest_role", "scene")
		graph_node.set_meta("node_path", str(entry.get("nodePath", "")))
		graph_node.set_meta("owner_path", str(entry.get("ownerPath", "")))
		owner_paths[str(entry.get("ownerPath", ""))] = true
		graph_node.set_meta("editor_index", -1)
		var body := VBoxContainer.new()
		body.custom_minimum_size.x = 240.0
		var kind := Label.new()
		kind.text = "%s · %s" % [
			str(entry.get("activation", "")),
			str(entry.get("kind", "")),
		]
		kind.modulate = color
		body.add_child(kind)
		var script := Label.new()
		script.text = "Цепочка: %s" % str(entry.get("scriptId", ""))
		script.custom_minimum_size = Vector2(240.0, 24.0)
		script.clip_text = true
		script.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		script.tooltip_text = script.text
		body.add_child(script)
		graph_node.add_child(body)
		graph_node.set_slot(0, false, 0, color, true, 3, color)
		var select_button := Button.new()
		select_button.name = "SelectQuestSceneNode"
		select_button.text = "Выбрать в сцене ↗"
		select_button.tooltip_text = "Перейти к authoring owner этого Interact в открытой сцене."
		select_button.pressed.connect(_request_scene_node.bind(
			NodePath(str(entry.get("nodePath", "")))
		))
		graph_node.add_child(select_button)
		_graph.add_child(graph_node)
		for linked_name in linked_names:
			_graph.connect_node(graph_node.name, 0, linked_name, 0)
	return owner_paths


func _render_selected_scene_candidate(
	_document: Dictionary,
	root_node: GraphNode,
	existing_owner_paths: Dictionary,
) -> void:
	if _selected_scene_path.is_empty() or existing_owner_paths.has(str(_selected_scene_path)):
		return
	var scene_root := _scene_root()
	var target := scene_root.get_node_or_null(_selected_scene_path) if scene_root != null else null
	if target == null:
		return
	var color := Color(0.46, 0.86, 0.62)
	var graph_node := GraphNode.new()
	graph_node.name = "quest_scene_candidate"
	var compact_name := (
		_selected_scene_label.left(25) + "…"
		if _selected_scene_label.length() > 26
		else _selected_scene_label
	)
	graph_node.title = "Выбранный объект · %s" % compact_name
	graph_node.tooltip_text = str(_selected_scene_path)
	graph_node.position_offset = root_node.position_offset + Vector2(-760.0, -80.0)
	graph_node.custom_minimum_size = Vector2(290.0, 116.0)
	graph_node.resizable = false
	graph_node.set_meta("step_id", "scene_candidate:%s" % str(_selected_scene_path))
	graph_node.set_meta("quest_role", "scene_candidate")
	graph_node.set_meta("owner_path", str(_selected_scene_path))
	graph_node.set_meta("node_path", str(_selected_scene_path))
	graph_node.set_meta("editor_index", -1)
	var body := VBoxContainer.new()
	body.custom_minimum_size.x = 260.0
	var selected := Label.new()
	selected.text = "Готов к привязке"
	selected.modulate = color
	body.add_child(selected)
	var hint := Label.new()
	hint.text = "Тяните зелёный порт к зелёному входу"
	hint.tooltip_text = "Цель выполнится через canonical set_flag; кнопки в quest/objective нодах делают то же самое."
	hint.custom_minimum_size = Vector2(260.0, 24.0)
	hint.clip_text = true
	hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	body.add_child(hint)
	graph_node.add_child(body)
	graph_node.set_slot(0, false, 0, color, true, 3, color)
	var select_button := Button.new()
	select_button.name = "SelectQuestSceneCandidate"
	select_button.text = "Показать в 3D ↗"
	select_button.pressed.connect(_request_scene_node.bind(_selected_scene_path))
	graph_node.add_child(select_button)
	_graph.add_child(graph_node)


func _request_scene_node(node_path: NodePath) -> void:
	scene_node_requested.emit(node_path)


func _add_quest_binding_controls(parent: Container, choices: Array) -> void:
	var selection := Label.new()
	selection.name = "QuestSceneSelection"
	selection.text = (
		"Объект: %s" % _selected_scene_label
		if not _selected_scene_path.is_empty()
		else "Объект: сначала выберите в 3D/Scene"
	)
	selection.tooltip_text = (
		str(_selected_scene_path)
		if not _selected_scene_path.is_empty()
		else "Выберите voxel-prop или самостоятельный Interact в дереве сцены."
	)
	selection.modulate = (
		Color(0.46, 0.86, 0.62)
		if not _selected_scene_path.is_empty()
		else Color(0.62, 0.64, 0.70)
	)
	selection.custom_minimum_size = Vector2(0.0, 22.0)
	selection.clip_text = true
	selection.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	parent.add_child(selection)
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 4)
	buttons.add_theme_constant_override("v_separation", 4)
	parent.add_child(buttons)
	for raw_choice in choices:
		var choice: Dictionary = raw_choice
		var button := Button.new()
		button.name = str(choice.get("name", "BindQuestEventToSelection"))
		button.text = str(choice.get("text", "Привязать событие"))
		button.disabled = _selected_scene_path.is_empty()
		button.tooltip_text = (
			"Добавит обычный set_flag в цепочку выбранного объекта. "
			+ "Resource и scene binding входят в одно Undo/Redo."
		)
		button.pressed.connect(_request_quest_event_binding.bind(
			str(choice.get("token", ""))
		))
		buttons.add_child(button)


func _request_quest_event_binding(event_token: String) -> void:
	_request_quest_event_binding_for(_selected_scene_path, event_token)


func _request_quest_event_binding_for(
	scene_path: NodePath,
	event_token: String,
) -> void:
	if scene_path.is_empty() or event_token.is_empty():
		return
	var document := _current_quest_document()
	var errors := QuestStore.validation_errors(document)
	if not errors.is_empty():
		_status.text = "Привязка остановлена · %s" % errors[0]
		_status.modulate = Color(1.0, 0.48, 0.42)
		return
	quest_event_bind_requested.emit(scene_path, event_token, document)


func _request_quest_event_unbinding_for(
	scene_path: NodePath,
	event_entry: Dictionary,
) -> void:
	if scene_path.is_empty() or event_entry.is_empty():
		return
	if str(event_entry.get("documentKind", "")) != "action":
		_status.text = "События внутри диалога отвязываются в Dialogue Graph."
		_status.modulate = Color(1.0, 0.72, 0.36)
		return
	quest_event_unbind_requested.emit(scene_path, event_entry.duplicate(true))


func _request_orphaned_quest_event_removal(event_entry: Dictionary) -> void:
	if str(event_entry.get("documentKind", "")) != "action":
		return
	quest_event_remove_requested.emit(event_entry.duplicate(true))


func _add_quest_inline_line(
	parent: Container,
	label_text: String,
	field: String,
	value: String,
	editable: bool,
	tooltip: String,
) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 82.0
	label.modulate = Color(0.72, 0.74, 0.80)
	row.add_child(label)
	var input := LineEdit.new()
	input.name = "InlineQuest_%s" % field
	input.text = value
	input.editable = editable
	input.tooltip_text = tooltip
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if editable:
		input.focus_entered.connect(_begin_quest_inline_edit)
		input.focus_exited.connect(_commit_quest_inline_edit)
		input.text_changed.connect(_set_quest_document_field.bind(field))
	row.add_child(input)
	parent.add_child(row)


func _add_quest_inline_multiline(
	parent: Container,
	label_text: String,
	field: String,
	value: String,
) -> void:
	var label := Label.new()
	label.text = label_text
	label.modulate = Color(0.72, 0.74, 0.80)
	parent.add_child(label)
	var input := TextEdit.new()
	input.name = "InlineQuest_%s" % field
	input.text = value
	input.custom_minimum_size.y = 62.0
	input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	input.focus_entered.connect(_begin_quest_inline_edit)
	input.focus_exited.connect(_commit_quest_inline_edit)
	input.text_changed.connect(func() -> void: _set_quest_document_field(input.text, field))
	parent.add_child(input)


func _add_quest_inline_toggle(
	parent: Container,
	label_text: String,
	field: String,
	value: bool,
) -> void:
	var toggle := CheckBox.new()
	toggle.name = "InlineQuest_%s" % field
	toggle.text = label_text
	toggle.button_pressed = value
	toggle.toggled.connect(func(enabled: bool) -> void:
		_begin_quest_inline_edit()
		_set_quest_document_field(enabled, field)
		_commit_quest_inline_edit()
	)
	parent.add_child(toggle)


func _add_quest_objective_line(
	parent: Container,
	index: int,
	label_text: String,
	field: String,
	value: String,
) -> void:
	var label := Label.new()
	label.text = label_text
	label.modulate = Color(0.64, 0.67, 0.74)
	label.add_theme_font_size_override("font_size", 11)
	parent.add_child(label)
	var input := LineEdit.new()
	input.name = "InlineQuestObjective_%d_%s" % [index, field]
	input.text = value
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.focus_entered.connect(_begin_quest_inline_edit)
	input.focus_exited.connect(_commit_quest_inline_edit)
	input.text_changed.connect(_set_quest_objective_field.bind(index, field))
	parent.add_child(input)


func _add_quest_objective_toggle(
	parent: Container,
	index: int,
	label_text: String,
	value: bool,
) -> void:
	var toggle := CheckBox.new()
	toggle.name = "InlineQuestObjective_%d_optional" % index
	toggle.text = label_text
	toggle.button_pressed = value
	toggle.tooltip_text = "Не нужна для автоматического завершения задания."
	toggle.toggled.connect(func(enabled: bool) -> void:
		_begin_quest_inline_edit()
		_set_quest_objective_field(enabled, index, "optional")
		_commit_quest_inline_edit()
	)
	parent.add_child(toggle)


func _add_quest_objective_progress(
	parent: Container,
	index: int,
	objective: Dictionary,
) -> void:
	var mode := OptionButton.new()
	mode.name = "InlineQuestObjective_%d_progressMode" % index
	mode.add_item("Событие / флаг")
	mode.set_item_metadata(0, "flag")
	mode.add_item("Боевой счётчик")
	mode.set_item_metadata(1, "counter")
	mode.select(1 if str(objective.get("progressMode", "flag")) == "counter" else 0)
	mode.tooltip_text = "Боевой счётчик обновляет итог встречи; объект и set_flag для него не нужны."
	parent.add_child(mode)
	var counter := OptionButton.new()
	counter.name = "InlineQuestObjective_%d_combatCounter" % index
	var selected_counter := str(objective.get("counterEventId", ""))
	var matched := false
	for option in CombatResult.counter_options():
		counter.add_item(str(option.get("label", option.get("id", ""))))
		counter.set_item_metadata(counter.item_count - 1, str(option.get("id", "")))
		if str(option.get("id", "")) == selected_counter:
			counter.select(counter.item_count - 1)
			matched = true
	if str(objective.get("progressMode", "flag")) == "counter" and not selected_counter.is_empty() and not matched:
		counter.add_item("Сохранённый · %s" % selected_counter)
		counter.set_item_metadata(counter.item_count - 1, selected_counter)
		counter.select(counter.item_count - 1)
	parent.add_child(counter)
	var required := SpinBox.new()
	required.name = "InlineQuestObjective_%d_requiredCount" % index
	required.min_value = 1
	required.max_value = 9999
	required.value = maxi(1, int(objective.get("requiredCount", 1)))
	required.prefix = "Нужно: "
	parent.add_child(required)
	var update_visibility := func() -> void:
		var enabled := str(mode.get_selected_metadata()) == "counter"
		counter.visible = enabled
		required.visible = enabled
	mode.item_selected.connect(func(_selected: int) -> void:
		_begin_quest_inline_edit()
		_set_quest_objective_field(str(mode.get_selected_metadata()), index, "progressMode")
		if str(mode.get_selected_metadata()) == "counter" and counter.item_count > 0:
			_set_quest_objective_field(str(counter.get_selected_metadata()), index, "counterEventId")
		_commit_quest_inline_edit()
		update_visibility.call()
		call_deferred("_render_document", _quest_draft.duplicate(true))
	)
	counter.item_selected.connect(func(_selected: int) -> void:
		_begin_quest_inline_edit()
		_set_quest_objective_field(str(counter.get_selected_metadata()), index, "counterEventId")
		_commit_quest_inline_edit()
	)
	required.value_changed.connect(func(value: float) -> void:
		_begin_quest_inline_edit()
		_set_quest_objective_field(int(value), index, "requiredCount")
		_commit_quest_inline_edit()
	)
	update_visibility.call()


func _begin_quest_inline_edit() -> void:
	if _quest_inline_before.is_empty():
		_quest_inline_before = _current_quest_document()


func _commit_quest_inline_edit() -> void:
	if _quest_inline_before.is_empty():
		return
	var normalized := _current_quest_document()
	normalized = _remap_quest_objective_ids(normalized, _quest_inline_before)
	if normalized != _quest_inline_before:
		if _quest_cursor + 1 < _quest_history.size():
			_quest_history.resize(_quest_cursor + 1)
		_quest_history.append(normalized.duplicate(true))
		_quest_cursor = _quest_history.size() - 1
		_quest_draft = normalized
	_quest_inline_before = {}
	_build_property_editor()
	_update_mutation_controls()
	_update_quest_draft_status()


func _remap_quest_objective_ids(document: Dictionary, before: Dictionary) -> Dictionary:
	var result := document.duplicate(true)
	var objectives: Array = result.get("objectives", []).duplicate(true)
	var old_objectives: Array = before.get("objectives", [])
	var remap := {}
	for index in mini(objectives.size(), old_objectives.size()):
		var old_id := str((old_objectives[index] as Dictionary).get("id", ""))
		var new_id := str((objectives[index] as Dictionary).get("id", ""))
		if not old_id.is_empty() and not new_id.is_empty() and old_id != new_id:
			remap[old_id] = new_id
	if remap.is_empty():
		return result
	for index in objectives.size():
		var objective: Dictionary = (objectives[index] as Dictionary).duplicate(true)
		var dependencies: Array = objective.get("requiresObjectiveIds", []).duplicate()
		for dependency_index in dependencies.size():
			var dependency_id := str(dependencies[dependency_index])
			if remap.has(dependency_id):
				dependencies[dependency_index] = remap[dependency_id]
		objective["requiresObjectiveIds"] = dependencies
		objectives[index] = objective
	result["objectives"] = objectives
	var layout: Dictionary = result.get("editorLayout", {}).duplicate(true)
	for old_id in remap:
		var old_key := "objective:%s" % old_id
		var new_key := "objective:%s" % str(remap[old_id])
		if layout.has(old_key):
			layout[new_key] = layout[old_key]
			layout.erase(old_key)
	result["editorLayout"] = layout
	return QuestStore.normalized_document(result)


func _set_quest_document_field(value: Variant, field: String) -> void:
	_quest_draft[field] = value
	_update_mutation_controls()
	_update_quest_draft_status()


func _set_quest_objective_field(value: Variant, index: int, field: String) -> void:
	var objectives: Array = _quest_draft.get("objectives", []).duplicate(true)
	if index < 0 or index >= objectives.size() or typeof(objectives[index]) != TYPE_DICTIONARY:
		return
	var objective: Dictionary = (objectives[index] as Dictionary).duplicate(true)
	objective[field] = value
	objectives[index] = objective
	_quest_draft["objectives"] = objectives
	_update_mutation_controls()
	_update_quest_draft_status()


func _render_action(document: Dictionary) -> void:
	var steps: Array = document.get("steps", [])
	var diagnostics := ActionStore.validation_diagnostics(document)
	var node_names: Array[StringName] = []
	for index in steps.size():
		var step: Dictionary = steps[index]
		var node_name := StringName("action_%d" % index)
		var graph_node := _make_node(
			node_name,
			"%d · %s" % [index + 1, _action_title(str(step.get("type", "")))],
			_action_summary(step),
			Vector2(60.0 + index * 300.0, 120.0),
			index > 0,
			index + 1 < steps.size(),
			Color(0.38, 0.67, 1.0),
		)
		graph_node.set_meta("editor_index", index)
		graph_node.set_meta("step_id", "step_%d" % (index + 1))
		_attach_node_diagnostics(
			graph_node, _diagnostics_for_step(diagnostics, "step_%d" % (index + 1))
		)
		match str(step.get("type", "")):
			"talk":
				_add_link_button(graph_node, "dialogue", str(step.get("dialogueId", "")))
			"run_script":
				_add_link_button(graph_node, "action", str(step.get("scriptId", "")))
		_graph.add_child(graph_node)
		node_names.append(node_name)
	for index in node_names.size() - 1:
		_graph.connect_node(node_names[index], 0, node_names[index + 1], 0)


func _render_dialogue(document: Dictionary) -> void:
	var steps: Array = document.get("steps", [])
	var layout: Dictionary = document.get("editorLayout", {}) if typeof(document.get("editorLayout", {})) == TYPE_DICTIONARY else {}
	var editor_indices := _dialogue_editor_indices(document)
	var edges := DialogueGraphModel.edges(document)
	var diagnostics := DialogueGraphModel.validation_diagnostics(document)
	var node_names := {}
	var frame_names := {}
	var group_element_names := {}
	var collapsed_owner := {}
	var groups: Array = document.get("editorGroups", []) if typeof(document.get("editorGroups", [])) == TYPE_ARRAY else []
	for raw_group in groups:
		if typeof(raw_group) != TYPE_DICTIONARY or not bool((raw_group as Dictionary).get("collapsed", false)):
			continue
		var collapsed_group: Dictionary = raw_group
		var collapsed_group_id := str(collapsed_group.get("id", ""))
		for raw_member in collapsed_group.get("members", []):
			collapsed_owner[str(raw_member)] = collapsed_group_id
	for index in groups.size():
		if typeof(groups[index]) != TYPE_DICTIONARY:
			continue
		var group: Dictionary = groups[index]
		var group_id := str(group.get("id", "group_%d" % index))
		var collapsed := bool(group.get("collapsed", false))
		if collapsed:
			var boundary := _group_boundary_counts(edges, group.get("members", []))
			var proxy := _make_collapsed_group_node(group, boundary, _group_origin(group, layout))
			proxy.name = StringName("dialogue_group_%d" % index)
			var group_diagnostics: Array[Dictionary] = []
			for raw_member in group.get("members", []):
				group_diagnostics.append_array(_diagnostics_for_step(diagnostics, str(raw_member)))
			_attach_node_diagnostics(proxy, group_diagnostics)
			_graph.add_child(proxy)
			group_element_names[group_id] = proxy.name
		else:
			var frame := GraphFrame.new()
			frame.name = StringName("dialogue_frame_%d" % index)
			frame.title = str(group.get("title", group_id))
			frame.autoshrink_enabled = true
			frame.autoshrink_margin = 36
			frame.tint_color_enabled = true
			frame.tint_color = Color(0.17, 0.24, 0.34, 0.44)
			frame.set_meta("group_id", group_id)
			frame.set_meta("members", group.get("members", []).duplicate())
			_graph.add_child(frame)
			_add_group_titlebar_controls(frame, group, false)
			frame_names[group_id] = frame.name
			group_element_names[group_id] = frame.name
	for index in steps.size():
		var step: Dictionary = steps[index]
		var step_id := str(step.get("id", "step_%d" % index))
		if collapsed_owner.has(step_id):
			continue
		var safe_name := StringName("dialogue_%d" % index)
		var source_position: Dictionary = layout.get(step_id, {}) if typeof(layout.get(step_id, {})) == TYPE_DICTIONARY else {}
		var position := Vector2(
			float(source_position.get("x", 60 + (index % 5) * 300)),
			float(source_position.get("y", 80 + (index / 5) * 190)),
		)
		var kind := str(step.get("type", ""))
		var graph_node := _make_dialogue_node(
			safe_name,
			("▶ " if step_id == str(document.get("startStepId", "")) else "") + "%s · %s" % [step_id, kind],
			step,
			position,
			_dialogue_color(kind),
		)
		graph_node.set_meta("editor_index", int(editor_indices.get(step_id, -1)))
		graph_node.set_meta("step_id", step_id)
		_attach_node_diagnostics(graph_node, _diagnostics_for_step(diagnostics, step_id))
		_graph.add_child(graph_node)
		node_names[step_id] = safe_name
	var rendered_connections := {}
	for edge in edges:
		var source_id := str(edge.get("from", ""))
		var target_id := str(edge.get("to", ""))
		var source_group := str(collapsed_owner.get(source_id, ""))
		var target_group := str(collapsed_owner.get(target_id, ""))
		if not source_group.is_empty() and source_group == target_group:
			continue
		var from_name: StringName
		var from_port := 0
		if not source_group.is_empty() and group_element_names.has(source_group):
			from_name = group_element_names[source_group]
		elif node_names.has(source_id):
			from_name = node_names[source_id]
			from_port = int(edge.get("port", 0))
		else:
			continue
		var to_name: StringName
		if not target_group.is_empty() and group_element_names.has(target_group):
			to_name = group_element_names[target_group]
		elif node_names.has(target_id):
			to_name = node_names[target_id]
		else:
			continue
		if from_name == to_name:
			continue
		var connection_key := "%s:%d>%s" % [from_name, from_port, to_name]
		if rendered_connections.has(connection_key):
			continue
		rendered_connections[connection_key] = true
		_graph.connect_node(from_name, from_port, to_name, 0)
	for raw_group in groups:
		if typeof(raw_group) != TYPE_DICTIONARY:
			continue
		var group: Dictionary = raw_group
		var group_id := str(group.get("id", ""))
		if not frame_names.has(group_id) or bool(group.get("collapsed", false)):
			continue
		for raw_member in group.get("members", []):
			var member := str(raw_member)
			if node_names.has(member):
				_graph.attach_graph_element_to_frame(node_names[member], frame_names[group_id])


func _group_boundary_counts(edges: Array[Dictionary], members: Array) -> Dictionary:
	var member_ids := {}
	for raw_member in members:
		member_ids[str(raw_member)] = true
	var incoming := 0
	var outgoing := 0
	for edge in edges:
		var source_inside := member_ids.has(str(edge.get("from", "")))
		var target_inside := member_ids.has(str(edge.get("to", "")))
		if not source_inside and target_inside:
			incoming += 1
		elif source_inside and not target_inside:
			outgoing += 1
	return {"incoming": incoming, "outgoing": outgoing}


func _make_collapsed_group_node(group: Dictionary, boundary: Dictionary, position: Vector2) -> GraphNode:
	var proxy := GraphNode.new()
	var group_id := str(group.get("id", "group"))
	proxy.title = str(group.get("title", group_id))
	proxy.position_offset = position
	proxy.custom_minimum_size = Vector2(300.0, 72.0)
	proxy.resizable = false
	proxy.set_meta("group_id", group_id)
	proxy.set_meta("collapsed", true)
	proxy.set_meta("members", group.get("members", []).duplicate())
	proxy.set_meta("layout_origin", position)
	var summary := Label.new()
	summary.text = "%d нод · %d вход · %d выход" % [
		(group.get("members", []) as Array).size(),
		int(boundary.get("incoming", 0)),
		int(boundary.get("outgoing", 0)),
	]
	summary.custom_minimum_size = Vector2(260.0, 28.0)
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary.modulate = Color(0.68, 0.78, 0.90)
	proxy.add_child(summary)
	var port_color := Color(0.48, 0.76, 1.0)
	proxy.set_slot(
		0,
		int(boundary.get("incoming", 0)) > 0,
		0,
		port_color,
		int(boundary.get("outgoing", 0)) > 0,
		0,
		port_color,
	)
	_add_group_titlebar_controls(proxy, group, true)
	return proxy


func _add_group_titlebar_controls(element: GraphElement, group: Dictionary, collapsed: bool) -> void:
	var titlebar: HBoxContainer = element.call("get_titlebar_hbox")
	var member_count := Label.new()
	member_count.text = "%d нод" % (group.get("members", []) as Array).size()
	member_count.modulate = Color(0.66, 0.74, 0.84)
	titlebar.add_child(member_count)
	var group_id := str(group.get("id", "group"))
	var toggle := Button.new()
	toggle.name = StringName("ToggleGraphGroup_%s" % group_id)
	toggle.text = "Развернуть" if collapsed else "Свернуть"
	toggle.flat = true
	toggle.pressed.connect(_toggle_group_collapsed.bind(group_id))
	titlebar.add_child(toggle)


func _group_origin(group: Dictionary, layout: Dictionary) -> Vector2:
	var origin := Vector2(INF, INF)
	for raw_member in group.get("members", []):
		var member := str(raw_member)
		if typeof(layout.get(member, {})) != TYPE_DICTIONARY:
			continue
		var source: Dictionary = layout[member]
		origin.x = minf(origin.x, float(source.get("x", 0.0)))
		origin.y = minf(origin.y, float(source.get("y", 0.0)))
	return Vector2.ZERO if is_inf(origin.x) else origin - Vector2(36.0, 56.0)


func _make_dialogue_node(
	node_name: StringName,
	title: String,
	step: Dictionary,
	position: Vector2,
	color: Color,
) -> GraphNode:
	var kind := str(step.get("type", ""))
	var graph_node := GraphNode.new()
	graph_node.name = node_name
	graph_node.title = title
	graph_node.position_offset = position
	graph_node.custom_minimum_size = Vector2(310.0, 130.0)
	graph_node.resizable = false
	var step_id := str(step.get("id", ""))
	var body := VBoxContainer.new()
	body.name = "InlineNodeFields"
	body.custom_minimum_size.x = 275.0
	body.add_theme_constant_override("separation", 3)
	graph_node.add_child(body)
	match kind:
		"dialogue":
			_add_inline_identity_selectors(body, step_id, step, false)
			_add_inline_text(body, "Имя", step_id, "nameRu", str(step.get("nameRu", "")))
			_add_inline_select(
				body, "Сторона", step_id, "portraitSide", ["left", "right"],
				str(step.get("portraitSide", "left"))
			)
			_add_inline_art_select(body, "Фон", "Inline_%s_bgArtId" % step_id, str(step.get("bgArtId", "")), func(value: String) -> void:
				_set_inline_step_value(step_id, "bgArtId", value)
			)
			_add_inline_multiline(body, "Реплика", step_id, "textRu", str(step.get("textRu", "")))
			_add_inline_actor_editor(body, step_id, step)
		"choice":
			_add_inline_multiline(body, "Вопрос", step_id, "promptRu", str(step.get("promptRu", "")), 52.0)
			_add_inline_art_select(body, "Фон", "Inline_%s_bgArtId" % step_id, str(step.get("bgArtId", "")), func(value: String) -> void:
				_set_inline_step_value(step_id, "bgArtId", value)
			)
			_add_inline_actor_editor(body, step_id, step)
		"splash":
			_add_inline_multiline(body, "Подпись", step_id, "captionRu", str(step.get("captionRu", "")), 52.0)
			_add_inline_art_select(body, "Арт", "Inline_%s_artId" % step_id, str(step.get("artId", "")), func(value: String) -> void:
				_set_inline_step_value(step_id, "artId", value)
			)
		"set_flag":
			_add_inline_quest_flag(body, step_id, str(step.get("flag", step.get("flagId", ""))))
			var typed := TypedValueEditor.new() as EmberTypedValueEditor
			typed.name = "InlineTypedValue"
			typed.setup(step.get("value", true), "InlineFlagValue")
			typed.value_changed.connect(func(value: Variant) -> void:
				_begin_inline_edit()
				_set_inline_step_value(step_id, "value", value)
			)
			body.add_child(typed)
			_bind_inline_focus_tree(typed)
		"grant_cinders":
			_add_inline_number(body, "Количество", step_id, "amount", float(step.get("amount", 0)))
		"end":
			var end_label := Label.new()
			end_label.text = "Завершает текущий диалог."
			end_label.modulate = Color(0.68, 0.72, 0.80)
			body.add_child(end_label)
		_:
			var summary := Label.new()
			summary.text = _dialogue_summary(step)
			summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			body.add_child(summary)
	graph_node.set_slot(0, true, 0, color, kind != "choice" and step.has("next"), 0, color)
	if kind == "choice":
		var options: Variant = step.get("options", [])
		if typeof(options) == TYPE_ARRAY:
			for index in options.size():
				var option: Dictionary = options[index] if typeof(options[index]) == TYPE_DICTIONARY else {}
				var row := HBoxContainer.new()
				row.name = "ChoicePort_%d" % index
				var number := Label.new()
				number.text = "%d." % (index + 1)
				row.add_child(number)
				var input := LineEdit.new()
				input.name = "InlineChoiceLabel_%d" % index
				input.text = str(option.get("labelRu", ""))
				input.tooltip_text = "Ответ %s → %s" % [option.get("id", index + 1), option.get("next", "не подключён")]
				input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				input.focus_entered.connect(_begin_inline_edit)
				input.focus_exited.connect(_commit_inline_edit)
				input.text_changed.connect(func(value: String) -> void:
					_set_inline_option_value(step_id, index, "labelRu", value)
				)
				row.add_child(input)
				graph_node.add_child(row)
				var port_color := Color.from_hsv(fmod(0.08 + index * 0.17, 1.0), 0.62, 1.0)
				graph_node.set_slot(index + 1, false, 0, color, true, 0, port_color)
	return graph_node


func _add_inline_text(parent: Container, label_text: String, step_id: String, field: String, value: String) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 68.0
	label.modulate = Color(0.72, 0.74, 0.80)
	row.add_child(label)
	var input := LineEdit.new()
	input.name = "Inline_%s_%s" % [step_id, field]
	input.text = value
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.focus_entered.connect(_begin_inline_edit)
	input.focus_exited.connect(_commit_inline_edit)
	input.text_changed.connect(func(text: String) -> void: _set_inline_step_value(step_id, field, text))
	row.add_child(input)
	parent.add_child(row)


func _add_inline_quest_flag(parent: Container, step_id: String, value: String) -> void:
	var event := Button.new()
	event.name = "Inline_%s_quest_event" % step_id
	event.text = "Событие задания…"
	event.tooltip_text = "Выбрать понятную операцию; нода останется canonical set_flag."
	event.pressed.connect(_open_inline_quest_event_library.bind(step_id))
	parent.add_child(event)
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Флаг"
	label.custom_minimum_size.x = 68.0
	label.modulate = Color(0.72, 0.74, 0.80)
	row.add_child(label)
	var input := LineEdit.new()
	input.name = "Inline_%s_flag" % step_id
	input.text = value
	input.placeholder_text = "save-ключ"
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.focus_entered.connect(_begin_inline_edit)
	input.focus_exited.connect(_commit_inline_edit)
	input.text_changed.connect(func(text: String) -> void: _set_inline_step_value(step_id, "flag", text))
	row.add_child(input)
	var library := Button.new()
	library.name = "Inline_%s_flag_library" % step_id
	library.text = "▦"
	library.tooltip_text = "Выбрать общий статус задания или флаг выполнения цели"
	library.pressed.connect(_open_inline_quest_flag_library.bind(step_id, input))
	row.add_child(library)
	parent.add_child(row)


func _open_inline_quest_event_library(step_id: String) -> void:
	_open_visual_library(
		"СОБЫТИЯ ЗАДАНИЙ",
		QuestStore.event_reference_entries(),
		"",
		_apply_inline_quest_event.bind(step_id),
		Vector2i(0, 0),
		240,
		3,
	)


func _apply_inline_quest_event(token: String, step_id: String) -> void:
	var preset := QuestStore.action_for_event(token)
	if preset.is_empty():
		return
	var changed := DialogueGraphModel.set_step_field(
		_current_dialogue_document(), step_id, "flag", preset.get("flag", "")
	)
	changed = DialogueGraphModel.set_step_field(
		changed, step_id, "value", preset.get("value", true)
	)
	_push_dialogue_draft(changed)
	_select_dialogue_step(step_id)


func _open_inline_quest_flag_library(step_id: String, input: LineEdit) -> void:
	_open_visual_library(
		"ФЛАГИ ЗАДАНИЙ",
		QuestStore.flag_reference_entries(),
		input.text.strip_edges(),
		_apply_inline_quest_flag.bind(step_id, input),
		Vector2i(0, 0),
		210,
		3,
	)


func _apply_inline_quest_flag(value: String, step_id: String, input: LineEdit) -> void:
	if input == null or not is_instance_valid(input):
		return
	_begin_inline_edit()
	input.text = value
	_set_inline_step_value(step_id, "flag", value)
	_commit_inline_edit()


func _add_inline_select(
	parent: Container,
	label_text: String,
	step_id: String,
	field: String,
	values: Array[String],
	value: String,
) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 68.0
	label.modulate = Color(0.72, 0.74, 0.80)
	row.add_child(label)
	var input := OptionButton.new()
	input.name = "Inline_%s_%s" % [step_id, field]
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item in values:
		input.add_item(item)
		input.set_item_metadata(input.item_count - 1, item)
		if item == value:
			input.select(input.item_count - 1)
	input.focus_entered.connect(_begin_inline_edit)
	input.focus_exited.connect(_commit_inline_edit)
	input.item_selected.connect(func(index: int) -> void:
		_begin_inline_edit()
		_set_inline_step_value(step_id, field, input.get_item_metadata(index))
	)
	row.add_child(input)
	parent.add_child(row)


func _add_inline_art_select(
	parent: Container,
	label_text: String,
	control_name: String,
	current_id: String,
	selected_callback: Callable,
) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 68.0
	label.modulate = Color(0.72, 0.74, 0.80)
	row.add_child(label)
	var picker := OptionButton.new()
	picker.name = control_name
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.fit_to_longest_item = false
	picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	picker.custom_minimum_size.x = 120.0
	_populate_art_picker(picker, current_id)
	var preview := _make_picker_preview(
		"%s_preview" % control_name,
		_vn_catalog().art_thumbnail(_effective_art_id(control_name, current_id)),
	)
	row.add_child(preview)
	var library_button := Button.new()
	library_button.name = "%s_library" % control_name
	library_button.text = "▦"
	library_button.custom_minimum_size.x = 34.0
	library_button.tooltip_text = "Открыть визуальную библиотеку фонов"
	library_button.pressed.connect(func() -> void:
		var current := str(picker.get_item_metadata(picker.selected))
		_open_visual_library(
			"БИБЛИОТЕКА ФОНОВ",
			VnVisuals.background_entries(
				_vn_catalog(),
				_empty_art_label(control_name),
				_empty_art_tooltip(control_name),
				_vn_catalog().art_thumbnail(_effective_art_id(control_name, ""), 56),
				current,
			),
			current,
			_apply_art_library_selection.bind(control_name, picker, preview, selected_callback),
		)
	)
	var import_button := Button.new()
	import_button.name = "%s_import" % control_name
	import_button.text = "+ Фон"
	import_button.custom_minimum_size.x = 54.0
	import_button.tooltip_text = (
		"Добавить фон в проект…\n"
		+ "Изображение → res://assets/vn_backgrounds/\n"
		+ "Описание → res://content/vn_backgrounds/*.tres"
	)
	import_button.pressed.connect(
		_open_background_import.bind(picker, preview, selected_callback)
	)
	picker.item_selected.connect(func(index: int) -> void:
		_begin_inline_edit()
		var next_id := str(picker.get_item_metadata(index))
		_update_art_picker_tooltip(picker)
		preview.texture = _vn_catalog().art_thumbnail(
			_effective_art_id(control_name, next_id)
		)
		selected_callback.call(next_id)
		_commit_inline_edit()
	)
	row.add_child(picker)
	row.add_child(library_button)
	row.add_child(import_button)
	parent.add_child(row)


func _apply_art_library_selection(
	value: String,
	control_name: String,
	picker: OptionButton,
	preview: TextureRect,
	selected_callback: Callable,
) -> void:
	_populate_art_picker(picker, value)
	preview.texture = _vn_catalog().art_thumbnail(_effective_art_id(control_name, value))
	_begin_inline_edit()
	selected_callback.call(value)
	_commit_inline_edit()


func _populate_art_picker(picker: OptionButton, current_id: String) -> void:
	picker.clear()
	picker.add_item(_empty_art_label(picker.name))
	picker.set_item_metadata(0, "")
	picker.set_item_tooltip(0, _empty_art_tooltip(picker.name))
	var found := current_id.is_empty()
	for entry in _vn_catalog().art_entries():
		if str(entry.get("kind", "")) == "portrait":
			continue
		var art_id := str(entry.get("id", ""))
		var caption := str(entry.get("captionRu", art_id)).strip_edges()
		if caption.is_empty():
			caption = art_id
		var exists := bool(entry.get("exists", false))
		var compact_caption := _ellipsize(caption, 30)
		var text := "%s %s" % ["✓" if exists else "⚠", compact_caption]
		# Keep images out of PopupMenu. Godot 4.7.2 can crash natively while an
		# icon-backed OptionButton is rebuilt by an editor plugin. The selected
		# asset is rendered in the adjacent TextureRect instead.
		picker.add_item(text)
		picker.set_item_metadata(picker.item_count - 1, art_id)
		picker.set_item_tooltip(
			picker.item_count - 1,
			"%s\nID: %s\n%s\n%s" % [
				caption,
				art_id,
				entry.get("path", ""),
				(
					"Godot Resource · редактируемый"
					if bool(entry.get("native", false))
					else "Legacy JSON · только чтение"
				) if exists else "ФАЙЛ ОТСУТСТВУЕТ",
			],
		)
		if art_id == current_id:
			picker.select(picker.item_count - 1)
			found = true
	if not found:
		picker.add_item("⚠ Неизвестный · %s" % _ellipsize(current_id, 18))
		picker.set_item_metadata(picker.item_count - 1, current_id)
		picker.set_item_tooltip(picker.item_count - 1, "Неизвестный art ID: %s" % current_id)
		picker.select(picker.item_count - 1)
	_update_art_picker_tooltip(picker)


func _ellipsize(value: String, maximum: int) -> String:
	var clean := value.strip_edges()
	return clean if clean.length() <= maximum else "%s…" % clean.left(maximum - 1)


func _update_art_picker_tooltip(picker: OptionButton) -> void:
	if picker.selected >= 0:
		picker.tooltip_text = picker.get_item_tooltip(picker.selected)


func _effective_art_id(control_name: String, selected_id: String) -> String:
	var clean := selected_id.strip_edges()
	if not clean.is_empty():
		return clean
	if control_name.ends_with("_bgArtId"):
		return str(_dialogue_draft.get("defaultBgArtId", "")).strip_edges()
	return ""


func _empty_art_label(control_name: String) -> String:
	if not control_name.ends_with("_bgArtId"):
		return "— Без фона"
	var inherited_id := str(_dialogue_draft.get("defaultBgArtId", "")).strip_edges()
	if inherited_id.is_empty():
		return "↳ Фон сцены не задан"
	return "↳ Фон сцены · %s" % _ellipsize(_art_caption(inherited_id), 20)


func _empty_art_tooltip(control_name: String) -> String:
	if not control_name.ends_with("_bgArtId"):
		return "Не показывать фон"
	var inherited_id := str(_dialogue_draft.get("defaultBgArtId", "")).strip_edges()
	if inherited_id.is_empty():
		return "Нода наследует фон сцены, но он пока не задан."
	return "Наследовать фон сцены\n%s\nID: %s" % [_art_caption(inherited_id), inherited_id]


func _art_caption(art_id: String) -> String:
	for entry in _vn_catalog().art_entries():
		if str(entry.get("id", "")) == art_id:
			return str(entry.get("captionRu", art_id))
	return art_id


func _refresh_inherited_background_controls() -> void:
	for raw_picker in find_children("Inline_*_bgArtId", "OptionButton", true, false):
		var picker := raw_picker as OptionButton
		if picker == null or picker.item_count == 0:
			continue
		picker.set_item_text(0, _empty_art_label(picker.name))
		picker.set_item_tooltip(0, _empty_art_tooltip(picker.name))
		_update_art_picker_tooltip(picker)
		if str(picker.get_item_metadata(picker.selected)).is_empty():
			var preview := find_child("%s_preview" % picker.name, true, false) as TextureRect
			if preview != null:
				preview.texture = _vn_catalog().art_thumbnail(
					str(_dialogue_draft.get("defaultBgArtId", ""))
				)


func _open_background_import(
	picker: OptionButton,
	preview: TextureRect,
	selected_callback: Callable,
) -> void:
	_ensure_background_import_dialog()
	_background_import_picker = picker
	_background_import_preview = preview
	_background_import_callback = selected_callback
	var pictures := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if not pictures.is_empty() and DirAccess.dir_exists_absolute(pictures):
		_background_import_dialog.current_dir = pictures
	_background_import_dialog.popup_centered_ratio(0.72)


func _ensure_background_import_dialog() -> void:
	if is_instance_valid(_background_import_dialog):
		return
	_background_import_dialog = FileDialog.new()
	_background_import_dialog.name = "VnBackgroundImportDialog"
	_background_import_dialog.title = "Добавить фон в Ember"
	_background_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_background_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_background_import_dialog.use_native_dialog = true
	_background_import_dialog.filters = PackedStringArray([
		"*.png, *.jpg, *.jpeg, *.webp, *.svg ; Изображения фона",
	])
	_background_import_dialog.file_selected.connect(_on_background_file_selected)
	_background_import_dialog.canceled.connect(_clear_background_import_target)
	add_child(_background_import_dialog)


func _on_background_file_selected(source_path: String) -> void:
	var picker := _background_import_picker
	var preview := _background_import_preview
	var callback := _background_import_callback
	_clear_background_import_target()
	var result := _vn_catalog().import_background(source_path)
	if not bool(result.get("ok", false)):
		_status.text = "⚠ Фон не добавлен · %s" % result.get("error", "неизвестная ошибка")
		_status.modulate = Color(1.0, 0.48, 0.42)
		return
	var art_id := str(result.get("id", ""))
	if not is_instance_valid(picker) or not is_instance_valid(preview) or not callback.is_valid():
		_status.text = "Фон добавлен: %s" % art_id
		return
	_populate_art_picker(picker, art_id)
	preview.texture = _vn_catalog().art_thumbnail(art_id)
	_begin_inline_edit()
	callback.call(art_id)
	_commit_inline_edit()
	_status.text = "Фон добавлен · %s · сохранён как Godot Resource" % art_id
	_status.modulate = Color(0.54, 0.86, 0.62)


func _clear_background_import_target() -> void:
	_background_import_picker = null
	_background_import_preview = null
	_background_import_callback = Callable()


func _open_native_background_folder() -> void:
	var directory := _vn_catalog().native_background_directory()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	OS.shell_show_in_file_manager(ProjectSettings.globalize_path(directory))


func _add_inline_identity_selectors(
	parent: Container,
	step_id: String,
	source: Dictionary,
	actor_mode: bool,
	sync_step := false,
) -> void:
	var prefix := "InlineActor_%s" % step_id if actor_mode else "Inline_%s" % step_id
	var speaker := str(source.get("speaker", ""))
	var portrait := str(source.get("portraitKey", "neutral"))
	var speaker_row := HBoxContainer.new()
	var speaker_label := Label.new()
	speaker_label.text = "Персонаж"
	speaker_label.custom_minimum_size.x = 68.0
	speaker_row.add_child(speaker_label)
	var speaker_picker := OptionButton.new()
	speaker_picker.name = "%s_speaker" % prefix
	speaker_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speaker_picker.fit_to_longest_item = false
	speaker_picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_populate_speaker_picker(speaker_picker, speaker)
	var speaker_preview := _make_picker_preview(
		"%s_speaker_preview" % prefix, _speaker_thumbnail(speaker)
	)
	speaker_row.add_child(speaker_preview)
	speaker_row.add_child(speaker_picker)
	parent.add_child(speaker_row)
	var portrait_row := HBoxContainer.new()
	var portrait_label := Label.new()
	portrait_label.text = "Эмоция"
	portrait_label.custom_minimum_size.x = 68.0
	portrait_row.add_child(portrait_label)
	var portrait_picker := OptionButton.new()
	portrait_picker.name = "%s_portraitKey" % prefix
	portrait_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	portrait_picker.fit_to_longest_item = false
	portrait_picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_populate_portrait_picker(portrait_picker, speaker, portrait)
	var portrait_preview := _make_picker_preview(
		"%s_portraitKey_preview" % prefix,
		_vn_catalog().portrait_thumbnail(speaker, portrait),
	)
	var speaker_library := Button.new()
	speaker_library.name = "%s_speaker_library" % prefix
	speaker_library.text = "▦"
	speaker_library.custom_minimum_size.x = 34.0
	speaker_library.tooltip_text = "Открыть визуальную библиотеку персонажей"
	speaker_library.pressed.connect(func() -> void:
		var current := str(speaker_picker.get_item_metadata(speaker_picker.selected))
		_open_visual_library(
			"БИБЛИОТЕКА ПЕРСОНАЖЕЙ",
			VnVisuals.speaker_entries(_vn_catalog(), current),
			current,
			_apply_speaker_library_selection.bind(
				step_id,
				actor_mode,
				sync_step,
				speaker_picker,
				portrait_picker,
				speaker_preview,
				portrait_preview,
			),
		)
	)
	speaker_row.add_child(speaker_library)
	portrait_row.add_child(portrait_preview)
	portrait_row.add_child(portrait_picker)
	var portrait_library := Button.new()
	portrait_library.name = "%s_portraitKey_library" % prefix
	portrait_library.text = "▦"
	portrait_library.custom_minimum_size.x = 34.0
	portrait_library.tooltip_text = "Открыть визуальную библиотеку эмоций выбранного персонажа"
	portrait_library.pressed.connect(func() -> void:
		var current_speaker := str(speaker_picker.get_item_metadata(speaker_picker.selected))
		var current_portrait := str(portrait_picker.get_item_metadata(portrait_picker.selected))
		_open_visual_library(
			"ЭМОЦИИ · %s" % current_speaker,
			VnVisuals.portrait_entries(_vn_catalog(), current_speaker, current_portrait),
			current_portrait,
			_apply_portrait_library_selection.bind(
				step_id,
				actor_mode,
				sync_step,
				speaker_picker,
				portrait_picker,
				speaker_preview,
				portrait_preview,
			),
		)
	)
	portrait_row.add_child(portrait_library)
	var import_portrait := Button.new()
	import_portrait.name = "%s_portraitKey_import" % prefix
	import_portrait.text = "+ Арт"
	import_portrait.tooltip_text = (
		"Добавить изображение для выбранного персонажа…\n"
		+ "Изображение → res://assets/vn_portraits/<speaker>/\n"
		+ "Описание → res://content/vn_portraits/*.tres"
	)
	import_portrait.pressed.connect(func() -> void:
		_open_portrait_import(
			step_id,
			actor_mode,
			sync_step,
			speaker_picker,
			portrait_picker,
			speaker_preview,
			portrait_preview,
		)
	)
	portrait_row.add_child(import_portrait)
	parent.add_child(portrait_row)
	speaker_picker.item_selected.connect(func(index: int) -> void:
		var next_speaker := str(speaker_picker.get_item_metadata(index))
		var next_portrait := str(portrait_picker.get_item_metadata(portrait_picker.selected))
		if not _vn_catalog().has_portrait(next_speaker, next_portrait):
			next_portrait = _vn_catalog().first_portrait_key(next_speaker)
		speaker_preview.texture = _speaker_thumbnail(next_speaker)
		portrait_preview.texture = _vn_catalog().portrait_thumbnail(next_speaker, next_portrait)
		_apply_identity_selection(step_id, next_speaker, next_portrait, actor_mode, sync_step)
	)
	portrait_picker.item_selected.connect(func(index: int) -> void:
		portrait_preview.texture = _vn_catalog().portrait_thumbnail(
			str(speaker_picker.get_item_metadata(speaker_picker.selected)),
			str(portrait_picker.get_item_metadata(index)),
		)
		_apply_identity_selection(
			step_id,
			str(speaker_picker.get_item_metadata(speaker_picker.selected)),
			str(portrait_picker.get_item_metadata(index)),
			actor_mode,
			sync_step,
		)
	)


func _apply_speaker_library_selection(
	speaker: String,
	step_id: String,
	actor_mode: bool,
	sync_step: bool,
	speaker_picker: OptionButton,
	portrait_picker: OptionButton,
	speaker_preview: TextureRect,
	portrait_preview: TextureRect,
) -> void:
	var portrait := str(portrait_picker.get_item_metadata(portrait_picker.selected))
	if not _vn_catalog().has_portrait(speaker, portrait):
		portrait = _vn_catalog().first_portrait_key(speaker)
	_populate_speaker_picker(speaker_picker, speaker)
	_populate_portrait_picker(portrait_picker, speaker, portrait)
	speaker_preview.texture = _speaker_thumbnail(speaker)
	portrait_preview.texture = _vn_catalog().portrait_thumbnail(speaker, portrait)
	_apply_identity_selection(step_id, speaker, portrait, actor_mode, sync_step)


func _apply_portrait_library_selection(
	portrait: String,
	step_id: String,
	actor_mode: bool,
	sync_step: bool,
	speaker_picker: OptionButton,
	portrait_picker: OptionButton,
	speaker_preview: TextureRect,
	portrait_preview: TextureRect,
) -> void:
	var speaker := str(speaker_picker.get_item_metadata(speaker_picker.selected))
	_populate_portrait_picker(portrait_picker, speaker, portrait)
	speaker_preview.texture = _speaker_thumbnail(speaker)
	portrait_preview.texture = _vn_catalog().portrait_thumbnail(speaker, portrait)
	_apply_identity_selection(step_id, speaker, portrait, actor_mode, sync_step)


func _open_visual_library(
	title: String,
	entries: Array[Dictionary],
	current_id: String,
	callback: Callable,
	icon_size := Vector2i(56, 56),
	column_width := 116,
	text_lines := 2,
) -> void:
	_visual_library_callback = callback
	if _visual_library_popup == null or not is_instance_valid(_visual_library_popup):
		_visual_library_popup = PopupPanel.new()
		_visual_library_popup.name = "VnVisualLibraryPopup"
		add_child(_visual_library_popup)
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 12)
		margin.add_theme_constant_override("margin_top", 12)
		margin.add_theme_constant_override("margin_right", 12)
		margin.add_theme_constant_override("margin_bottom", 12)
		_visual_library_popup.add_child(margin)
		_visual_library_picker = VisualLibraryPicker.new() as EmberVisualLibraryPicker
		margin.add_child(_visual_library_picker)
		_visual_library_picker.value_chosen.connect(_accept_visual_library_value)
	_visual_library_picker.setup(title, entries, current_id)
	_visual_library_picker.set_tile_layout(icon_size, column_width, text_lines)
	_visual_library_popup.popup_centered(Vector2i(660, 530))


func _accept_visual_library_value(value: String) -> void:
	var callback := _visual_library_callback
	_visual_library_popup.hide()
	_visual_library_callback = Callable()
	if callback.is_valid():
		callback.call(value)


func _open_portrait_import(
	step_id: String,
	actor_mode: bool,
	sync_step: bool,
	speaker_picker: OptionButton,
	portrait_picker: OptionButton,
	speaker_preview: TextureRect,
	portrait_preview: TextureRect,
) -> void:
	var speaker := str(speaker_picker.get_item_metadata(speaker_picker.selected)).strip_edges()
	if speaker.is_empty():
		_status.text = "⚠ Сначала выберите персонажа"
		_status.modulate = Color(1.0, 0.48, 0.42)
		return
	var dialog := FileDialog.new()
	dialog.name = "VnPortraitImportDialog"
	dialog.title = "Добавить эмоцию · %s" % speaker
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true
	dialog.filters = PackedStringArray([
		"*.png, *.jpg, *.jpeg, *.webp, *.svg ; Изображение персонажа",
	])
	dialog.file_selected.connect(func(source_path: String) -> void:
		var result := _vn_catalog().import_portrait(source_path, speaker)
		if not bool(result.get("ok", false)):
			_status.text = "⚠ Портрет не добавлен · %s" % result.get("error", "неизвестная ошибка")
			_status.modulate = Color(1.0, 0.48, 0.42)
			dialog.queue_free()
			return
		var next_speaker := str(result.get("speakerId", speaker))
		var next_portrait := str(result.get("portraitKey", "neutral"))
		_populate_speaker_picker(speaker_picker, next_speaker)
		_populate_portrait_picker(portrait_picker, next_speaker, next_portrait)
		speaker_preview.texture = _speaker_thumbnail(next_speaker)
		portrait_preview.texture = _vn_catalog().portrait_thumbnail(next_speaker, next_portrait)
		_apply_identity_selection(step_id, next_speaker, next_portrait, actor_mode, sync_step)
		_status.text = "Эмоция добавлена · %s/%s · Godot Resource" % [next_speaker, next_portrait]
		_status.modulate = Color(0.54, 0.86, 0.62)
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	var pictures := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if not pictures.is_empty() and DirAccess.dir_exists_absolute(pictures):
		dialog.current_dir = pictures
	dialog.popup_centered_ratio(0.72)


func _populate_speaker_picker(picker: OptionButton, current: String) -> void:
	picker.clear()
	var found := false
	for speaker in _vn_catalog().speaker_ids():
		picker.add_item(speaker)
		picker.set_item_metadata(picker.item_count - 1, speaker)
		if speaker == current:
			picker.select(picker.item_count - 1)
			found = true
	if not found:
		picker.add_item("⚠ %s · нет portrait registry" % (current if not current.is_empty() else "не выбран"))
		picker.set_item_metadata(picker.item_count - 1, current)
		picker.select(picker.item_count - 1)


func _populate_portrait_picker(picker: OptionButton, speaker: String, current: String) -> void:
	picker.clear()
	var found := false
	for entry in _vn_catalog().portrait_entries(speaker):
		var key := str(entry.get("key", ""))
		var label := str(entry.get("labelRu", key))
		var exists := bool(entry.get("exists", false))
		var text := "%s %s · %s" % ["✓" if exists else "⚠", label, key]
		picker.add_item(text)
		picker.set_item_metadata(picker.item_count - 1, key)
		picker.set_item_tooltip(picker.item_count - 1, str(entry.get("path", "")))
		if key == current:
			picker.select(picker.item_count - 1)
			found = true
	if not found:
		picker.add_item("⚠ %s · нет у %s" % [current, speaker])
		picker.set_item_metadata(picker.item_count - 1, current)
		picker.select(picker.item_count - 1)


func _apply_identity_selection(
	step_id: String,
	speaker: String,
	portrait: String,
	actor_mode: bool,
	sync_step: bool,
) -> void:
	_begin_inline_edit()
	var changed := _dialogue_draft
	if not actor_mode or sync_step:
		changed = DialogueGraphModel.set_step_field(changed, step_id, "speaker", speaker)
		changed = DialogueGraphModel.set_step_field(changed, step_id, "portraitKey", portrait)
	var step: Dictionary = DialogueGraphModel.steps_by_id(changed).get(step_id, {})
	var actors: Variant = step.get("actors", [])
	if actor_mode or (typeof(actors) == TYPE_ARRAY and not (actors as Array).is_empty()):
		changed = DialogueGraphModel.set_primary_actor_field(changed, step_id, "speaker", speaker)
		changed = DialogueGraphModel.set_primary_actor_field(changed, step_id, "portraitKey", portrait)
	_dialogue_draft = changed
	_sync_identity_controls(step_id, speaker, portrait, not actor_mode or sync_step)
	_update_mutation_controls()
	_update_dialogue_draft_status()
	_commit_inline_edit()
	_refresh_vn_preview(step_id)


func _sync_identity_controls(
	step_id: String, speaker: String, portrait: String, include_step: bool
) -> void:
	var prefixes: Array[String] = ["InlineActor_%s" % step_id]
	if include_step:
		prefixes.append("Inline_%s" % step_id)
	for prefix in prefixes:
		var speaker_picker := find_child("%s_speaker" % prefix, true, false) as OptionButton
		var portrait_picker := find_child("%s_portraitKey" % prefix, true, false) as OptionButton
		if speaker_picker != null:
			_select_metadata(speaker_picker, speaker)
		if portrait_picker != null:
			_populate_portrait_picker(portrait_picker, speaker, portrait)
		var speaker_preview := find_child("%s_speaker_preview" % prefix, true, false) as TextureRect
		var portrait_preview := find_child("%s_portraitKey_preview" % prefix, true, false) as TextureRect
		if speaker_preview != null:
			speaker_preview.texture = _speaker_thumbnail(speaker)
		if portrait_preview != null:
			portrait_preview.texture = _vn_catalog().portrait_thumbnail(speaker, portrait)


func _make_picker_preview(control_name: String, texture: Texture2D) -> TextureRect:
	var preview := TextureRect.new()
	preview.name = control_name
	preview.custom_minimum_size = Vector2(40.0, 40.0)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.texture = texture
	return preview


func _speaker_thumbnail(speaker: String) -> Texture2D:
	if speaker.is_empty():
		return null
	var representative := (
		"neutral" if _vn_catalog().has_portrait(speaker, "neutral")
		else _vn_catalog().first_portrait_key(speaker)
	)
	return _vn_catalog().portrait_thumbnail(speaker, representative)


func _vn_catalog() -> EmberVnAssets:
	if _vn_assets == null:
		_vn_assets = VnAssets.new() as EmberVnAssets
	return _vn_assets


func _add_inline_actor_editor(parent: Container, step_id: String, step: Dictionary) -> void:
	var actors: Array = step.get("actors", []) if typeof(step.get("actors", [])) == TYPE_ARRAY else []
	var toggle := Button.new()
	toggle.name = "InlineActorToggle_%s" % step_id
	toggle.toggle_mode = true
	toggle.text = "Постановка · %s ▸" % ("нет персонажа" if actors.is_empty() else "главный персонаж")
	parent.add_child(toggle)
	var details := VBoxContainer.new()
	details.name = "InlineActorFields_%s" % step_id
	details.visible = false
	details.add_theme_constant_override("separation", 3)
	parent.add_child(details)
	toggle.toggled.connect(func(open: bool) -> void:
		details.visible = open
		toggle.text = "Постановка · %s %s" % [
			"нет персонажа" if actors.is_empty() else "главный персонаж",
			"▾" if open else "▸",
		]
	)
	if actors.is_empty() or typeof(actors[0]) != TYPE_DICTIONARY:
		var add := Button.new()
		add.name = "InlineActorAdd_%s" % step_id
		add.text = "+ Добавить персонажа"
		add.tooltip_text = "Создаёт actors[0] из speaker/emotion этой ноды."
		add.pressed.connect(func() -> void:
			_push_dialogue_draft(DialogueGraphModel.add_primary_actor(_dialogue_draft, step_id))
		)
		details.add_child(add)
		return
	var actor: Dictionary = actors[0]
	_add_inline_actor_text(details, "ID", step_id, "id", str(actor.get("id", "main")))
	_add_inline_identity_selectors(details, step_id, actor, true, str(step.get("type", "")) == "dialogue")
	_add_inline_actor_number(details, "X", step_id, "x", float(actor.get("x", 50.0)), -1000.0, 1000.0, 0.1)
	_add_inline_actor_number(details, "Y", step_id, "y", float(actor.get("y", 100.0)), -1000.0, 1000.0, 0.1)
	_add_inline_actor_number(details, "Scale", step_id, "scale", float(actor.get("scale", 1.0)), 0.01, 20.0, 0.01)
	var flip := CheckBox.new()
	flip.name = "InlineActor_%s_flipX" % step_id
	flip.text = "Отразить по X"
	flip.button_pressed = bool(actor.get("flipX", false))
	flip.focus_entered.connect(_begin_inline_edit)
	flip.focus_exited.connect(_commit_inline_edit)
	flip.toggled.connect(func(enabled: bool) -> void:
		_begin_inline_edit()
		_set_inline_actor_value(step_id, "flipX", enabled)
	)
	details.add_child(flip)
	var remove := Button.new()
	remove.name = "InlineActorRemove_%s" % step_id
	remove.text = "Убрать главного персонажа"
	remove.tooltip_text = "Удаляет только actors[0]; остальные actors сохраняются."
	remove.pressed.connect(func() -> void:
		_push_dialogue_draft(DialogueGraphModel.remove_primary_actor(_dialogue_draft, step_id))
	)
	details.add_child(remove)


func _add_inline_actor_text(
	parent: Container, label_text: String, step_id: String, field: String, value: String
) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 68.0
	row.add_child(label)
	var input := LineEdit.new()
	input.name = "InlineActor_%s_%s" % [step_id, field]
	input.text = value
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.focus_entered.connect(_begin_inline_edit)
	input.focus_exited.connect(_commit_inline_edit)
	input.text_changed.connect(func(text: String) -> void: _set_inline_actor_value(step_id, field, text))
	row.add_child(input)
	parent.add_child(row)


func _add_inline_actor_number(
	parent: Container,
	label_text: String,
	step_id: String,
	field: String,
	value: float,
	minimum: float,
	maximum: float,
	increment: float,
) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 68.0
	row.add_child(label)
	var input := SpinBox.new()
	input.name = "InlineActor_%s_%s" % [step_id, field]
	input.min_value = minimum
	input.max_value = maximum
	input.step = increment
	input.value = value
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.value_changed.connect(func(number: float) -> void:
		_begin_inline_edit()
		_set_inline_actor_value(step_id, field, number)
	)
	input.get_line_edit().focus_exited.connect(_commit_inline_edit)
	row.add_child(input)
	parent.add_child(row)


func _add_inline_multiline(
	parent: Container,
	label_text: String,
	step_id: String,
	field: String,
	value: String,
	height := 72.0,
) -> void:
	var label := Label.new()
	label.text = label_text
	label.modulate = Color(0.72, 0.74, 0.80)
	parent.add_child(label)
	var input := TextEdit.new()
	input.name = "Inline_%s_%s" % [step_id, field]
	input.text = value
	input.custom_minimum_size.y = height
	input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	input.focus_entered.connect(_begin_inline_edit)
	input.focus_exited.connect(_commit_inline_edit)
	input.text_changed.connect(func() -> void: _set_inline_step_value(step_id, field, input.text))
	parent.add_child(input)


func _add_inline_number(parent: Container, label_text: String, step_id: String, field: String, value: float) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 90.0
	row.add_child(label)
	var input := SpinBox.new()
	input.name = "Inline_%s_%s" % [step_id, field]
	input.min_value = 0.0
	input.max_value = 999999.0
	input.step = 1.0
	input.value = value
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.value_changed.connect(func(number: float) -> void:
		_begin_inline_edit()
		_set_inline_step_value(step_id, field, int(number))
	)
	input.get_line_edit().focus_exited.connect(_commit_inline_edit)
	row.add_child(input)
	parent.add_child(row)


func _bind_inline_focus_tree(root: Node) -> void:
	for child in root.find_children("*", "Control", true, false):
		var control := child as Control
		if not control.focus_entered.is_connected(_begin_inline_edit):
			control.focus_entered.connect(_begin_inline_edit)
		if not control.focus_exited.is_connected(_commit_inline_edit):
			control.focus_exited.connect(_commit_inline_edit)


func _begin_inline_edit() -> void:
	if _inline_edit_before.is_empty():
		_inline_edit_before = _dialogue_draft.duplicate(true)


func _commit_inline_edit() -> void:
	if _inline_edit_before.is_empty():
		return
	if _inline_edit_before != _dialogue_draft:
		if _dialogue_cursor + 1 < _dialogue_history.size():
			_dialogue_history.resize(_dialogue_cursor + 1)
		_dialogue_history.append(_dialogue_draft.duplicate(true))
		_dialogue_cursor = _dialogue_history.size() - 1
	_inline_edit_before = {}
	_update_mutation_controls()
	_update_dialogue_draft_status()


func _set_inline_step_value(step_id: String, field: String, value: Variant) -> void:
	_dialogue_draft = DialogueGraphModel.set_step_field(_dialogue_draft, step_id, field, value)
	_update_mutation_controls()
	_update_dialogue_draft_status()
	_refresh_vn_preview(step_id)


func _set_inline_actor_value(step_id: String, field: String, value: Variant) -> void:
	_dialogue_draft = DialogueGraphModel.set_primary_actor_field(
		_dialogue_draft, step_id, field, value
	)
	_update_mutation_controls()
	_update_dialogue_draft_status()
	_refresh_vn_preview(step_id)


func _set_inline_option_value(step_id: String, option_index: int, field: String, value: Variant) -> void:
	_dialogue_draft = DialogueGraphModel.set_choice_option_field(
		_dialogue_draft, step_id, option_index, field, value
	)
	_update_mutation_controls()
	_update_dialogue_draft_status()
	_refresh_vn_preview(step_id)


func _make_node(
	node_name: StringName,
	title: String,
	body: String,
	position: Vector2,
	has_input: bool,
	has_output: bool,
	color: Color,
) -> GraphNode:
	var graph_node := GraphNode.new()
	graph_node.name = node_name
	graph_node.title = title
	graph_node.position_offset = position
	graph_node.custom_minimum_size = Vector2(240.0, 96.0)
	graph_node.resizable = false
	var label := Label.new()
	label.text = body
	label.custom_minimum_size = Vector2(210.0, 54.0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.tooltip_text = body
	graph_node.add_child(label)
	graph_node.set_slot(0, has_input, 0, color, has_output, 0, color)
	return graph_node


func _add_link_button(
	parent: Container,
	kind: String,
	resource_id: String,
	compact := false,
) -> void:
	if resource_id.is_empty():
		return
	var open := Button.new()
	open.name = "OpenLinkedGraph"
	open.text = "Открыть ↗" if compact else "Открыть %s ↗" % resource_id
	open.custom_minimum_size.x = 0.0
	open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open.clip_text = true
	open.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	open.tooltip_text = "Перейти к связанному %s в этой же graph-вкладке." % (
		"диалогу" if kind == "dialogue" else "сценарию"
	)
	open.pressed.connect(open_resource.bind(kind, resource_id))
	parent.add_child(open)


func _build_property_editor() -> void:
	_clear_editor()
	var selection_row := HBoxContainer.new()
	selection_row.name = "GraphSelectionRow"
	_editor_holder.add_child(selection_row)
	_selection_label = Label.new()
	_selection_label.name = "GraphSelectionLabel"
	_selection_label.text = "Все карточки"
	_selection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selection_label.custom_minimum_size.x = 0.0
	_selection_label.clip_text = true
	_selection_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_selection_label.modulate = Color(0.96, 0.72, 0.32)
	selection_row.add_child(_selection_label)
	var show_all := Button.new()
	show_all.name = "ShowAllGraphCards"
	show_all.text = "Показать все"
	show_all.tooltip_text = "Снимает выбор ноды и возвращает полный список карточек справа."
	show_all.pressed.connect(_show_all_cards)
	selection_row.add_child(show_all)
	var note := Label.new()
	note.text = (
		"Поля внутри quest-нод — основной редактор. Золотая линия означает принадлежность; синяя A → B — B откроется после A. Фиолетовые события и зелёные объекты открытой сцены вычисляются и редактируются только через их кнопки перехода."
		if _current_kind == "quest"
		else "Поля внутри dialogue-нод — основной редактор. Правая карточка служит обзором. Shift+клик выбирает несколько нод для visual Group/Frame; runtime группы не видит."
	)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.68, 0.76, 0.88)
	_editor_holder.add_child(note)
	if _current_kind == "quest":
		_add_quest_resource_properties()
		_action_editor = null
		_dialogue_editor = null
		_quest_editor = QuestEditor.new() as EmberQuestEditor
		_quest_editor.setup(
			str(_quest_draft.get("id", _current_id)),
			str(_quest_draft.get("id", _current_id)),
			str(_quest_draft.get("statusFlagId", "")),
			_quest_draft,
		)
		for control_name in ["SaveQuest", "CancelQuest", "AddQuestObjective", "RemoveQuestObjective"]:
			for control in _quest_editor.find_children(control_name, "Control", true, false):
				(control as Control).visible = false
		_set_editor_read_only(_quest_editor)
		_editor_holder.add_child(_quest_editor)
	elif _current_kind == "dialogue":
		_add_dialogue_scene_properties()
		_action_editor = null
		_quest_editor = null
		_dialogue_editor = DialogueEditor.new() as EmberDialogueEditor
		_dialogue_editor.setup(_current_id, DialogueStore.suggested_id(_current_id), _dialogue_draft)
		for control_name in [
			"SaveDialogue",
			"AddDialogueCard",
			"DialogueCardMove",
			"DialogueCardRemove",
			"AddChoiceOption",
			"DialogueOptionRemove",
		]:
			for control in _dialogue_editor.find_children(control_name, "Control", true, false):
				(control as Control).visible = false
		_set_editor_read_only(_dialogue_editor)
		_editor_holder.add_child(_dialogue_editor)
	else:
		_dialogue_editor = null
		_quest_editor = null
		_add_action_script_properties()
		_action_editor = ActionEditor.new() as EmberActionChainEditor
		_action_editor.setup(_current_id, ActionStore.suggested_id(_current_id), _action_draft)
		_action_editor.save_requested.connect(_on_action_save)
		_action_editor.dialogue_save_requested.connect(_on_dialogue_save)
		_action_editor.shop_save_requested.connect(_on_shop_save)
		_action_editor.shop_migrate_requested.connect(_on_shop_migrate)
		_action_editor.item_save_requested.connect(_on_item_save)
		_action_editor.item_migrate_requested.connect(_on_item_migrate)
		var remove := _action_editor.find_child("DeleteActionChain", true, false) as Button
		if remove != null:
			remove.visible = false
		var add_step := _action_editor.find_child("AddActionStep", true, false) as Control
		if add_step != null:
			add_step.visible = false
		for control_name in ["StepMoveUp", "StepMoveDown", "StepRemove"]:
			for control in _action_editor.find_children(control_name, "Button", true, false):
				(control as Button).visible = false
		_editor_holder.add_child(_action_editor)
	_apply_selection_to_editor()


func _add_quest_resource_properties() -> void:
	var section := VBoxContainer.new()
	section.name = "QuestResourceProperties"
	section.add_theme_constant_override("separation", 4)
	var title := Label.new()
	title.text = "ЗАДАНИЕ"
	title.modulate = Color(0.96, 0.72, 0.32)
	section.add_child(title)
	var source := Label.new()
	source.name = "QuestStorageOwner"
	source.text = (
		"Источник: новый локальный черновик"
		if _quest_is_new
		else "Источник: Godot Resource"
	)
	source.tooltip_text = (
		"Файл ещё не создан"
		if _quest_is_new
		else QuestStore.source_path(str(_quest_draft.get("id", _current_id)))
	)
	source.modulate = Color(0.90, 0.68, 0.36) if _quest_is_new else Color(0.50, 0.82, 0.60)
	section.add_child(source)
	var legend := Label.new()
	legend.text = "◆ status flag задаёт active/done · золото = принадлежность · синяя A → B = последовательность · несколько входов означают «выполнить все»."
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend.modulate = Color(0.62, 0.72, 0.84)
	section.add_child(legend)
	_editor_holder.add_child(section)
	_editor_holder.add_child(HSeparator.new())


func _add_action_script_properties() -> void:
	var section := VBoxContainer.new()
	section.name = "ActionScriptProperties"
	section.add_theme_constant_override("separation", 4)
	var title := Label.new()
	title.text = "ЦЕПОЧКА ДЕЙСТВИЙ"
	title.modulate = Color(0.78, 0.84, 1.0)
	section.add_child(title)
	var owner := ActionStore.owner(_current_id)
	var source_row := HBoxContainer.new()
	var source := Label.new()
	source.name = "ActionStorageOwner"
	source.text = (
		"Источник: Godot Resource"
		if owner == "native"
		else "Источник: Legacy JSON"
	)
	source.tooltip_text = ActionStore.source_path(_current_id)
	source.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source.modulate = Color(0.50, 0.82, 0.60) if owner == "native" else Color(0.90, 0.68, 0.36)
	source_row.add_child(source)
	var migrate := Button.new()
	migrate.name = "MigrateActionResource"
	migrate.text = "Уже .tres" if owner == "native" else "Перенести в .tres"
	migrate.disabled = owner != "legacy"
	migrate.tooltip_text = (
		"Создаёт res://content/action_scripts/%s.tres.\n"
		+ "Legacy JSON остаётся резервным read-only источником.\n"
		+ "Ctrl+Z отменяет миграцию."
	) % _current_id
	migrate.pressed.connect(_migrate_current_action)
	source_row.add_child(migrate)
	section.add_child(source_row)
	_editor_holder.add_child(section)
	_editor_holder.add_child(HSeparator.new())


func _migrate_current_action() -> void:
	if _current_kind != "action" or ActionStore.owner(_current_id) != "legacy":
		return
	action_migrate_requested.emit(_current_id)
	call_deferred("_finish_action_migration_ui")


func _finish_action_migration_ui() -> void:
	if ActionStore.owner(_current_id) != "native":
		_status.text = "⚠ Не удалось перенести цепочку в Godot Resource"
		_status.modulate = Color(1.0, 0.48, 0.42)
		return
	_build_property_editor()
	_status.text = "Цепочка перенесена в res://content/action_scripts/%s.tres · Ctrl+Z отменит" % _current_id
	_status.modulate = Color(0.54, 0.86, 0.62)


func _add_dialogue_scene_properties() -> void:
	var section := VBoxContainer.new()
	section.name = "DialogueSceneProperties"
	section.add_theme_constant_override("separation", 4)
	var title := Label.new()
	title.text = "VN СЦЕНА"
	title.modulate = Color(0.96, 0.72, 0.32)
	section.add_child(title)
	var owner := DialogueStore.owner(_current_id)
	var source_row := HBoxContainer.new()
	var source := Label.new()
	source.name = "DialogueStorageOwner"
	source.text = (
		"Источник: Godot Resource"
		if owner == "native"
		else "Источник: Legacy JSON"
	)
	source.tooltip_text = DialogueStore.source_path(_current_id)
	source.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source.modulate = Color(0.50, 0.82, 0.60) if owner == "native" else Color(0.90, 0.68, 0.36)
	source_row.add_child(source)
	var migrate := Button.new()
	migrate.name = "MigrateDialogueResource"
	migrate.text = "Уже .tres" if owner == "native" else "Перенести в .tres"
	migrate.disabled = owner != "legacy"
	migrate.tooltip_text = (
		"Создаёт res://content/dialogues/%s.tres.\nLegacy JSON остаётся резервным read-only источником.\nCtrl+Z отменяет миграцию."
		% _current_id
	)
	migrate.pressed.connect(_migrate_current_dialogue)
	source_row.add_child(migrate)
	section.add_child(source_row)
	var hint := Label.new()
	hint.text = "Фон сцены задаётся один раз и автоматически наследуется нодами. В ноде выбирайте другой фон только как исключение."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(0.64, 0.70, 0.80)
	section.add_child(hint)
	var library_row := HBoxContainer.new()
	var library_path := Label.new()
	library_path.text = "Фоны: res://assets/vn_backgrounds/"
	library_path.tooltip_text = (
		"Файлы изображений: res://assets/vn_backgrounds/\n"
		+ "Метаданные: res://content/vn_backgrounds/*.tres\n"
		+ "Старый JOI arts/registry.json подключён только для чтения."
	)
	library_path.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	library_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library_path.modulate = Color(0.58, 0.68, 0.82)
	library_row.add_child(library_path)
	var open_folder := Button.new()
	open_folder.name = "OpenVnBackgroundFolder"
	open_folder.text = "Папка"
	open_folder.tooltip_text = "Открыть папку фоновых изображений проекта"
	open_folder.pressed.connect(_open_native_background_folder)
	library_row.add_child(open_folder)
	section.add_child(library_row)
	_add_inline_art_select(
		section,
		"Фон сцены",
		"DialogueDefaultBgArtId",
		str(_dialogue_draft.get("defaultBgArtId", "")),
		func(value: String) -> void:
			_dialogue_draft = DialogueGraphModel.set_document_field(
				_dialogue_draft, "defaultBgArtId", value
			)
			_update_mutation_controls()
			_update_dialogue_draft_status()
			_refresh_inherited_background_controls()
			_refresh_vn_preview()
	)
	var override_count := DialogueGraphModel.background_override_count(_dialogue_draft)
	var inherit_all := Button.new()
	inherit_all.name = "InheritSceneBackgroundAll"
	inherit_all.text = (
		"Сделать общим для всей сцены · убрать overrides: %d" % override_count
		if override_count > 0
		else "Все ноды уже наследуют фон сцены"
	)
	inherit_all.tooltip_text = (
		"Удаляет только индивидуальные bgArtId у dialogue/choice нод.\n"
		+ "Фон сцены, splash-арты, связи и постановка персонажей не меняются.\n"
		+ "Операция отменяется одной кнопкой ↶."
	)
	inherit_all.disabled = override_count == 0
	inherit_all.pressed.connect(_inherit_scene_background_all)
	section.add_child(inherit_all)
	_editor_holder.add_child(section)
	var divider := HSeparator.new()
	_editor_holder.add_child(divider)


func _inherit_scene_background_all() -> void:
	var changed := DialogueGraphModel.inherit_scene_background(_dialogue_draft)
	if changed == _dialogue_draft:
		return
	_push_dialogue_draft(changed)
	_status.text = "Ноды наследуют единый фон сцены · ↶ вернёт индивидуальные фоны"
	_status.modulate = Color(0.54, 0.86, 0.62)


func _migrate_current_dialogue() -> void:
	if _current_kind != "dialogue" or DialogueStore.owner(_current_id) != "legacy":
		return
	dialogue_migrate_requested.emit(_current_id)
	call_deferred("_finish_dialogue_migration_ui")


func _finish_dialogue_migration_ui() -> void:
	if DialogueStore.owner(_current_id) != "native":
		_status.text = "⚠ Не удалось перенести диалог в Godot Resource"
		_status.modulate = Color(1.0, 0.48, 0.42)
		return
	_build_property_editor()
	_status.text = "Диалог перенесён в res://content/dialogues/%s.tres · Ctrl+Z отменит" % _current_id
	_status.modulate = Color(0.54, 0.86, 0.62)


func _open_vn_preview() -> void:
	if _current_kind != "dialogue" or _dialogue_draft.is_empty():
		return
	_ensure_vn_preview()
	_vn_preview.set_document(_current_dialogue_document(), _selected_step_id)
	if is_instance_valid(_vn_preview_window):
		_vn_preview_window.title = "Ember VN Preview · %s" % _current_id
		_vn_preview_window.popup_centered(Vector2i(1080, 760))


func _ensure_vn_preview() -> void:
	if is_instance_valid(_vn_preview):
		return
	if DisplayServer.get_name() == "headless":
		_vn_preview = VnPreview.new() as EmberVnPreview
		_vn_preview.name = "EmberVnPreview"
		_vn_preview.visible = false
		add_child(_vn_preview)
		_vn_preview.set_asset_resolver(_vn_catalog())
		return
	_vn_preview_window = Window.new()
	_vn_preview_window.name = "EmberVnPreviewWindow"
	_vn_preview_window.min_size = Vector2i(820, 620)
	_vn_preview_window.size = Vector2i(1080, 760)
	_vn_preview_window.transient = true
	_vn_preview_window.exclusive = false
	_vn_preview_window.close_requested.connect(_vn_preview_window.hide)
	add_child(_vn_preview_window)
	_vn_preview = VnPreview.new() as EmberVnPreview
	_vn_preview.name = "EmberVnPreview"
	_vn_preview_window.add_child(_vn_preview)
	_vn_preview.set_asset_resolver(_vn_catalog())


func _refresh_vn_preview(preferred_step_id := "") -> void:
	if not is_instance_valid(_vn_preview) or _current_kind != "dialogue":
		return
	_vn_preview.set_document(_current_dialogue_document(), preferred_step_id)
	if is_instance_valid(_vn_preview_window):
		_vn_preview_window.title = "Ember VN Preview · %s%s" % [
			_current_id,
			" · LIVE DRAFT" if _has_unsaved_draft() else "",
		]


func _set_editor_read_only(root: Node) -> void:
	for child in root.find_children("*", "Control", true, false):
		if child is LineEdit:
			(child as LineEdit).editable = false
		elif child is TextEdit:
			(child as TextEdit).editable = false
		elif child is BaseButton:
			(child as BaseButton).disabled = true
		elif child is SpinBox:
			(child as SpinBox).editable = false


func _on_node_selected(node: Node) -> void:
	var element := node as GraphElement
	if element == null:
		return
	element.selected = true
	if not str(element.get_meta("group_id", "")).is_empty():
		_selected_group_id = str(element.get_meta("group_id", ""))
		_selected_step_id = ""
		_selected_editor_index = -1
		if _group_name != null:
			_group_name.text = str(element.get("title"))
		_apply_selection_to_editor()
		_update_mutation_controls()
		return
	var graph_node := element as GraphNode
	_selected_group_id = ""
	_selected_editor_index = int(graph_node.get_meta("editor_index", -1))
	_selected_step_id = str(graph_node.get_meta("step_id", graph_node.title))
	_apply_selection_to_editor()
	_update_mutation_controls()
	_refresh_vn_preview(_selected_step_id)


func _show_all_cards() -> void:
	_selected_editor_index = -1
	_selected_step_id = ""
	_selected_group_id = ""
	for element in _graph_elements():
		element.selected = false
	_apply_selection_to_editor()
	_update_mutation_controls()


func _apply_selection_to_editor() -> void:
	if _selection_label != null:
		_selection_label.text = (
			"Все карточки"
			if _selected_step_id.is_empty() and _selected_group_id.is_empty()
			else "Группа: %s" % _selected_group_id
			if not _selected_group_id.is_empty()
			else "Нода: %s%s" % [
				_selected_step_id,
				" · только просмотр" if _selected_editor_index < 0 else "",
			]
		)
		_selection_label.tooltip_text = _selection_label.text
	var action_steps := _editor_holder.find_child("ActionSteps", true, false) as VBoxContainer
	if action_steps != null:
		_set_only_child_visible(action_steps, _selected_editor_index)
	var dialogue_cards := _editor_holder.find_child("DialogueCards", true, false) as VBoxContainer
	if dialogue_cards != null:
		_set_only_child_visible(dialogue_cards, _selected_editor_index)
	var quest_objectives := _editor_holder.find_child("QuestObjectives", true, false) as VBoxContainer
	if quest_objectives != null:
		_set_only_child_visible(quest_objectives, _selected_editor_index)
	var scroll := _editor_holder.get_parent() as ScrollContainer
	if scroll != null:
		scroll.scroll_vertical = 0


func _set_only_child_visible(container: Container, selected_index: int) -> void:
	for index in container.get_child_count():
		container.get_child(index).visible = selected_index < 0 or index == selected_index


func _on_action_save(document: Dictionary) -> void:
	action_save_requested.emit(document)
	_current_id = str(document.get("id", _current_id))
	_refresh_resource_list(_current_id)
	_open_selected()


func _on_dialogue_save(document: Dictionary) -> void:
	dialogue_save_requested.emit(document)
	if _current_kind == "dialogue":
		_current_id = str(document.get("id", _current_id))
		_refresh_resource_list(_current_id)
		_open_selected()


func _on_shop_save(document: Dictionary) -> void:
	shop_save_requested.emit(document)


func _on_shop_migrate(shop_id: String) -> void:
	shop_migrate_requested.emit(shop_id)


func _on_item_save(document: Dictionary) -> void:
	item_save_requested.emit(document)


func _on_item_migrate(item_id: String) -> void:
	item_migrate_requested.emit(item_id)


func _dialogue_targets(step: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if str(step.get("type", "")) == "choice":
		var options: Variant = step.get("options", [])
		if typeof(options) == TYPE_ARRAY:
			for option in options:
				if typeof(option) == TYPE_DICTIONARY:
					var target := str(option.get("next", "")).strip_edges()
					if not target.is_empty() and target not in result:
						result.append(target)
	else:
		var target := str(step.get("next", "")).strip_edges()
		if not target.is_empty():
			result.append(target)
	return result


func _dialogue_editor_indices(document: Dictionary) -> Dictionary:
	var projected := DialogueStore.projection(document)
	if not bool(projected.get("ok", false)):
		return {}
	var steps := {}
	for raw_step in document.get("steps", []):
		if typeof(raw_step) == TYPE_DICTIONARY:
			steps[str(raw_step.get("id", ""))] = raw_step
	var result := {}
	var current := str(document.get("startStepId", ""))
	var card_index := 0
	for _guard in range(DialogueStore.MAX_STEPS):
		if not steps.has(current):
			break
		var step: Dictionary = steps[current]
		var kind := str(step.get("type", ""))
		if kind == "end":
			break
		result[current] = card_index
		if kind == "choice":
			var common_next := ""
			for raw_option in step.get("options", []):
				if typeof(raw_option) != TYPE_DICTIONARY:
					continue
				var reply_id := str(raw_option.get("next", ""))
				result[reply_id] = card_index
				if steps.has(reply_id):
					common_next = str((steps[reply_id] as Dictionary).get("next", ""))
			current = common_next
		else:
			current = str(step.get("next", ""))
		card_index += 1
	return result


func _action_title(step_type: String) -> String:
	match step_type:
		"talk": return "Диалог"
		"give_item": return "Предмет"
		"set_flag": return "Флаг"
		"wait": return "Пауза"
		"open_shop": return "Магазин"
		"change_map": return "Карта"
		"start_battle": return "Бой"
		"run_script": return "Цепочка"
	return step_type


func _action_summary(step: Dictionary) -> String:
	match str(step.get("type", "")):
		"talk": return "dialogue: %s" % step.get("dialogueId", "—")
		"give_item": return "%s × %s" % [step.get("itemId", "—"), step.get("count", 1)]
		"set_flag": return "%s = %s" % [step.get("flag", "—"), step.get("value", true)]
		"wait": return "%s сек." % step.get("sec", 0)
		"open_shop": return "shop: %s" % step.get("shopId", "—")
		"change_map": return "%s → %s" % [step.get("targetMapId", "—"), step.get("targetRegionId", "start")]
		"start_battle": return "encounter: %s" % step.get("encounterId", "—")
		"run_script": return "script: %s" % step.get("scriptId", "—")
	return ""


func _dialogue_summary(step: Dictionary) -> String:
	match str(step.get("type", "")):
		"dialogue": return "%s\n%s" % [step.get("nameRu", step.get("speaker", "")), step.get("textRu", "")]
		"choice":
			var options: Array = step.get("options", [])
			return "%s\n%d вариантов" % [step.get("promptRu", ""), options.size()]
		"splash": return str(step.get("captionRu", "splash"))
		"set_flag": return "%s = %s" % [step.get("flag", step.get("flagId", "—")), step.get("value", true)]
		"grant_cinders": return "+%s cinders" % step.get("amount", 0)
		"end": return "Конец сцены"
	return JSON.stringify(step)


func _dialogue_color(kind: String) -> Color:
	match kind:
		"choice": return Color(0.96, 0.67, 0.22)
		"end": return Color(0.55, 0.58, 0.66)
		"set_flag", "grant_cinders": return Color(0.55, 0.84, 0.48)
		"splash": return Color(0.76, 0.48, 0.92)
	return Color(0.35, 0.72, 1.0)


func _diagnostic_messages(diagnostics: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for diagnostic in diagnostics:
		result.append(str(diagnostic.get("message", "")))
	return result


func _diagnostics_for_step(diagnostics: Array[Dictionary], step_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for diagnostic in diagnostics:
		if str(diagnostic.get("stepId", "")) == step_id:
			result.append(diagnostic.duplicate(true))
	return result


func _attach_node_diagnostics(graph_node: GraphNode, diagnostics: Array[Dictionary]) -> void:
	if diagnostics.is_empty():
		return
	graph_node.set_meta("diagnostics", diagnostics.duplicate(true))
	var messages := _diagnostic_messages(diagnostics)
	var tooltip := "\n".join(messages)
	var badge := Button.new()
	badge.name = "NodeDiagnosticBadge"
	badge.text = "⚠ %d" % diagnostics.size()
	badge.flat = true
	badge.modulate = Color(1.0, 0.40, 0.34)
	badge.tooltip_text = tooltip
	var first := diagnostics[0]
	badge.pressed.connect(_focus_diagnostic.bind(
		str(first.get("stepId", "")), str(first.get("message", ""))
	))
	var titlebar: HBoxContainer = graph_node.get_titlebar_hbox()
	titlebar.add_child(badge)
	var warning := Label.new()
	warning.name = "NodeDiagnosticMessage"
	warning.text = "⚠ %s%s" % [
		messages[0],
		"  (+%d)" % (messages.size() - 1) if messages.size() > 1 else "",
	]
	warning.tooltip_text = tooltip
	warning.modulate = Color(1.0, 0.48, 0.42)
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.custom_minimum_size = Vector2(275.0, 32.0)
	graph_node.add_child(warning)


func _current_diagnostics() -> Array[Dictionary]:
	return (
		DialogueGraphModel.validation_diagnostics(_dialogue_draft)
		if _current_kind == "dialogue"
		else ActionStore.validation_diagnostics(_action_draft)
	)


func _update_diagnostic_focus_button(diagnostics: Array[Dictionary]) -> void:
	if _diagnostic_focus_button == null:
		return
	var target: Dictionary = {}
	for diagnostic in diagnostics:
		if not str(diagnostic.get("stepId", "")).is_empty():
			target = diagnostic
			break
	_diagnostic_focus_button.visible = not target.is_empty()
	_diagnostic_focus_button.tooltip_text = str(target.get("message", ""))


func _focus_first_diagnostic() -> void:
	for diagnostic in _current_diagnostics():
		var step_id := str(diagnostic.get("stepId", ""))
		if not step_id.is_empty():
			_focus_diagnostic(step_id, str(diagnostic.get("message", "")))
			return


func _focus_diagnostic(step_id: String, message: String) -> void:
	var target: GraphElement
	for graph_node in _graph_nodes():
		if str(graph_node.get_meta("step_id", "")) == step_id:
			target = graph_node
			break
	if target == null and _current_kind == "dialogue":
		for raw_group in _dialogue_draft.get("editorGroups", []):
			if typeof(raw_group) != TYPE_DICTIONARY or step_id not in raw_group.get("members", []):
				continue
			var group_id := str((raw_group as Dictionary).get("id", ""))
			for element in _graph_elements():
				if str(element.get_meta("group_id", "")) == group_id:
					target = element
					break
			break
	if target != null:
		_graph.set_selected(target)
		_on_node_selected(target)
		_graph.scroll_offset = target.position_offset - _graph.size / maxf(_graph.zoom * 2.0, 0.01)
	_status.text = "⚠ %s" % message
	_status.modulate = Color(1.0, 0.48, 0.42)


func _clear_graph() -> void:
	if _graph == null:
		return
	_graph.clear_connections()
	# GraphEdit queues native move_child calls for frames. Removing a frame
	# synchronously leaves those calls targeting a node with no parent. Detach
	# its members while their original names still exist, then retire the hidden
	# frame in place until SceneTree has drained its deferred calls.
	for frame in _graph_elements():
		if frame is GraphFrame:
			for member in _graph.get_attached_nodes_of_frame(frame.name):
				_graph.detach_graph_element_from_frame(member)
	for child in _graph.get_children():
		if not child is GraphElement or child.is_queued_for_deletion():
			continue
		if child is GraphFrame:
			child.set_block_signals(true)
			child.hide()
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
			child.name = "RetiredFrame_%d" % child.get_instance_id()
		else:
			_graph.remove_child(child)
		child.queue_free()


func _clear_editor() -> void:
	if _editor_holder == null:
		return
	_action_editor = null
	_dialogue_editor = null
	_quest_editor = null
	for child in _editor_holder.get_children():
		_editor_holder.remove_child(child)
		child.queue_free()


func _graph_nodes() -> Array[GraphNode]:
	var result: Array[GraphNode] = []
	for child in _graph.get_children():
		if child is GraphNode:
			result.append(child)
	return result


func _graph_elements() -> Array[GraphElement]:
	var result: Array[GraphElement] = []
	for child in _graph.get_children():
		if child is GraphElement and not child.is_queued_for_deletion():
			result.append(child)
	return result


func _has_selected_graph_node() -> bool:
	for graph_node in _graph_nodes():
		if graph_node.selected:
			return true
	return false


func _has_selected_quest_objective() -> bool:
	for graph_node in _graph_nodes():
		if graph_node.selected and str(graph_node.get_meta("quest_role", "")) == "objective":
			return true
	return false


func _has_selected_step_node() -> bool:
	for graph_node in _graph_nodes():
		if graph_node.selected and not str(graph_node.get_meta("step_id", "")).is_empty():
			return true
	return false


func _selected_action_indices() -> Array[int]:
	var indices: Array[int] = []
	for graph_node in _graph_nodes():
		if not graph_node.selected:
			continue
		var index := int(graph_node.get_meta("editor_index", -1))
		if index >= 0 and index not in indices:
			indices.append(index)
	indices.sort()
	return indices


func _selected_step_ids() -> Array[String]:
	var result: Array[String] = []
	for graph_node in _graph_nodes():
		if not graph_node.selected:
			continue
		var step_id := str(graph_node.get_meta("step_id", ""))
		if not step_id.is_empty() and step_id not in result:
			result.append(step_id)
	return result


func _selection_has_group_member() -> bool:
	var selected_steps := {}
	for graph_node in _graph_nodes():
		if graph_node.selected:
			selected_steps[str(graph_node.get_meta("step_id", ""))] = true
	if selected_steps.is_empty():
		return false
	for raw_group in _dialogue_draft.get("editorGroups", []):
		if typeof(raw_group) != TYPE_DICTIONARY:
			continue
		for member in raw_group.get("members", []):
			if selected_steps.has(str(member)):
				return true
	return false


func _select_metadata(option: OptionButton, value: String) -> void:
	for index in option.item_count:
		if str(option.get_item_metadata(index)) == value:
			option.select(index)
			return
