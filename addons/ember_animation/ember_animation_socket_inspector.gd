@tool
extends EditorInspectorPlugin

const WorkshopEntry = preload("res://addons/ember_animation/ember_animation_workshop_entry.gd")

func _can_handle(object: Object) -> bool:
	var workshop := EditorInterface.get_edited_scene_root()
	return object is Marker3D and workshop != null and workshop.scene_file_path == WorkshopEntry.SCENE \
		and workshop.get_node_or_null(workshop.get("socket_path")) == object

func _parse_begin(_object: Object) -> void:
	var workshop := EditorInterface.get_edited_scene_root()
	var panel := VBoxContainer.new()
	var save := Button.new()
	save.text = "Сохранить крепление в игре"
	panel.add_child(save)
	var restore := Button.new()
	restore.text = "Вернуть сохранённое крепление"
	panel.add_child(restore)
	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(status)
	save.pressed.connect(func() -> void:
		status.text = "Крепление сохранено." if workshop.save_socket() else "Сохранение не удалось. Подробности в выводе Godot."
	)
	restore.pressed.connect(func() -> void:
		status.text = "Крепление восстановлено." if workshop.reload_socket() else "Не удалось загрузить крепление."
	)
	add_custom_control(panel)
