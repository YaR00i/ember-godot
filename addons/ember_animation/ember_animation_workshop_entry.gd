@tool
extends RefCounted

const SCENE := "res://assets/local_characters/hoshi/mira_animation_workshop.scn"
const LIBRARY := "res://assets/local_characters/hoshi/mira_motion_editable.tres"
const BUILD_SCRIPT := "res://tools/build_mira_animation_workshop.gd"

var _opening := false

func open(host: Node, selection_path: String, show_3d := true) -> bool:
	if _opening:
		return false
	_opening = true
	if not FileAccess.file_exists(SCENE) or not FileAccess.file_exists(LIBRARY):
		print("Ember: подготавливаем мастерскую анимаций Миры…")
		var log := ProjectSettings.globalize_path("user://mira-animation-workshop-build.log")
		var pid := OS.create_process(OS.get_executable_path(), PackedStringArray([
			"--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--log-file", log, "--script", BUILD_SCRIPT,
		]))
		if pid > 0:
			var deadline := Time.get_ticks_msec() + 30000
			while OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
				await host.get_tree().create_timer(0.15).timeout
			if OS.is_process_running(pid):
				OS.kill(pid)
				_opening = false
				push_error("Ember: истекло время подготовки мастерской. Журнал: " + log)
				return false
		if not FileAccess.file_exists(SCENE) or not FileAccess.file_exists(LIBRARY):
			_opening = false
			push_error("Ember: мастерская Миры не подготовилась. Журнал: " + log)
			return false
	EditorInterface.open_scene_from_path(SCENE)
	if show_3d:
		EditorInterface.set_main_screen_editor("3D")
	for frame in 8:
		await host.get_tree().process_frame
		var root := EditorInterface.get_edited_scene_root()
		if root == null or root.scene_file_path != SCENE:
			continue
		var node := root if selection_path.is_empty() else root.get_node_or_null(root.get(selection_path) as NodePath)
		if node == null:
			break
		var selection := EditorInterface.get_selection()
		selection.clear()
		selection.add_node(node)
		EditorInterface.edit_node(node)
		_opening = false
		return true
	_opening = false
	push_error("Ember: не удалось открыть элементы мастерской Миры.")
	return false
