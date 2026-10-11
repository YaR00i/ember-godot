@tool
extends RefCounted
## Editor process adapter. It passes one saved native path to the existing Lab.
const Transition = preload("res://scripts/ember_combat_transition.gd")
static var _pid := -1

static func arguments(path: String, log_path := "") -> PackedStringArray:
	var result := PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "--scene", Transition.COMBAT_SCENE, "--windowed", "--resolution", "1600x900", "--max-fps", "30"])
	if not log_path.is_empty(): result.append_array(["--log-file", log_path])
	result.append_array(["--", Transition.LIBRARY_TEST_PREFIX + path])
	return result

static func start(path: String) -> Dictionary:
	var request := Transition.library_test_content(path)
	if not request.get("ok", false): return request
	if _pid > 0 and OS.is_process_running(_pid): return {"ok": false, "error": "Тест уже открыт. Завершите его перед новым запуском."}
	var folder := "user://ember-library-lab/logs"
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)) != OK: return {"ok": false, "error": "Не удалось создать журнал тестового запуска."}
	var log_path := ProjectSettings.globalize_path(folder.path_join("lab-%d-%d.log" % [OS.get_process_id(), Time.get_ticks_usec()]))
	_pid = OS.create_process(OS.get_executable_path(), arguments(path, log_path), false)
	if _pid < 0: return {"ok": false, "error": "Не удалось открыть тестовое окно Godot."}
	return {"ok": true, "pid": _pid, "log": log_path}
