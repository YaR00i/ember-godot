@tool
extends EditorPlugin

const Catalog = preload("res://addons/ember_animation/ember_animation_catalog.gd")
const WorkshopEntry = preload("res://addons/ember_animation/ember_animation_workshop_entry.gd")
const SocketInspector = preload("res://addons/ember_animation/ember_animation_socket_inspector.gd")
const SCREEN := "Анимации"

var _entry := WorkshopEntry.new()
var _catalog: Catalog
var _menu: MenuButton
var _socket_inspector: EditorInspectorPlugin
var _opening := false

func _enter_tree() -> void:
	_catalog = Catalog.new()
	_catalog.undo_history = get_undo_redo()
	_catalog.hide()
	EditorInterface.get_editor_main_screen().add_child(_catalog)
	_catalog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_catalog.timeline_requested.connect(_open_timeline)
	_catalog.workshop_requested.connect(_open_workshop)
	_socket_inspector = SocketInspector.new()
	add_inspector_plugin(_socket_inspector)
	_menu = MenuButton.new()
	_menu.text = SCREEN
	_menu.get_popup().add_item("Открыть мастерскую", 0)
	_menu.get_popup().add_item("Из выбранного AnimationPlayer", 1)
	_menu.get_popup().add_item("Мира · крепление посоха", 2)
	_menu.get_popup().add_item("Мира · позы посоха", 3)
	_menu.get_popup().id_pressed.connect(_menu_selected)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _menu)
	add_tool_menu_item("Ember: Анимации", _show_screen)

func _exit_tree() -> void:
	remove_tool_menu_item("Ember: Анимации")
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _menu)
	_menu.queue_free()
	remove_inspector_plugin(_socket_inspector)
	_catalog.queue_free()

func _has_main_screen() -> bool:
	return true

func _get_plugin_name() -> String:
	return SCREEN

func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon("AnimationPlayer", "EditorIcons")

func _make_visible(visible: bool) -> void:
	if not is_instance_valid(_catalog):
		return
	_catalog.visible = visible
	if visible and not _catalog.has_source():
		_open_workshop.call_deferred()

func _show_screen() -> void:
	EditorInterface.set_main_screen_editor(SCREEN)

func _menu_selected(id: int) -> void:
	match id:
		0:
			_show_screen()
			_open_workshop()
		1:
			for node in EditorInterface.get_selection().get_selected_nodes():
				if node is AnimationPlayer:
					_catalog.show_library(node)
					_show_screen()
					return
			push_warning("Выбери AnimationPlayer в дереве сцены.")
		2: _entry.open(self, "socket_path")
		3: _entry.open(self, "")

func _open_workshop() -> void:
	if _opening:
		return
	_opening = true
	var opened := await _entry.open(self, "", false)
	_opening = false
	if not opened:
		return
	var root := EditorInterface.get_edited_scene_root()
	_catalog.show_library(root.get_node_or_null(root.get("player_path")) as AnimationPlayer)

func _open_timeline(motion: AnimationPlayer) -> void:
	EditorInterface.set_main_screen_editor("3D")
	EditorInterface.edit_node(motion)
