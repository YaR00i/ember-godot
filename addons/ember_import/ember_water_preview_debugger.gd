@tool
extends EditorDebuggerPlugin
## Transport only. Scene values and Undo remain owned by the world look panel.

var apply_settings: Callable


func _has_capture(prefix: String) -> bool:
	return prefix == "ember_water"


func _capture(message: String, data: Array, session_id: int) -> bool:
	if message != "ember_water:apply": return false
	var result := {"ok": false, "message": "Откройте исходную сцену воды в редакторе."}
	if data.size() in [3, 4] and data[0] is String and data[1] is NodePath and data[2] is Dictionary and apply_settings.is_valid():
		if data.size() == 3: result = apply_settings.call(data[0], data[1], data[2])
		elif data[3] is Dictionary: result = apply_settings.call(data[0], data[1], data[2], data[3])
	get_session(session_id).send_message("ember_water:result", [result])
	return true
