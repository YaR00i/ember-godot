@tool
extends RefCounted
## Nonblocking process adapter; never refreshes the live editor's Resource caches.
const Transition = preload("res://scripts/ember_combat_transition.gd")
const SCRIPT := "res://addons/ember_import/ember_game_systems_library_check.gd"
var _pid := -1
var _path := ""
var _start := 0

func running() -> bool:
	return _pid > 0

func start() -> Dictionary:
	if running(): return {"ok": false, "error": "Проверка уже выполняется."}
	var folder := "user://ember-library-check"
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)) != OK: return {"ok": false, "error": "Не удалось создать каталог отчёта."}
	_path = ProjectSettings.globalize_path(folder.path_join("report-%d-%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]))
	_start = Time.get_ticks_msec()
	_pid = OS.create_process(OS.get_executable_path(), PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", SCRIPT, "--log-file", _path + ".log", "--", Transition.LIBRARY_CHECK_PREFIX + _path]), false)
	if _pid < 0: return {"ok": false, "error": "Не удалось запустить проверку Godot."}
	return {"ok": true, "pid": _pid}

func poll() -> Dictionary:
	if not running(): return {}
	if OS.is_process_running(_pid):
		if Time.get_ticks_msec() - _start > 120000:
			OS.kill(_pid)
			_pid = -1
			return {"ok": false, "error": "Проверка превысила две минуты. Отчёт не готов; журнал: " + _path + ".log"}
		return {}
	_pid = -1
	if not FileAccess.file_exists(_path): return {"ok": false, "error": "Проверка завершилась без отчёта. Журнал: " + _path + ".log"}
	if FileAccess.file_exists(_path + ".log") and "SCRIPT ERROR:" in FileAccess.get_file_as_string(_path + ".log"):
		return {"ok": false, "error": "Правило проверки завершилось с ошибкой; отчёт не считается полным. Журнал: " + _path + ".log"}
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path))
	if typeof(report) != TYPE_DICTIONARY or int(report.get("version", 0)) != 1 or str(report.get("request", "")) != _path or not report.get("ok", false) or typeof(report.get("issues")) != TYPE_ARRAY:
		return {"ok": false, "error": "Отчёт повреждён или проверка не завершена. Журнал: " + _path + ".log"}
	report["reportPath"] = _path
	return report

func cancel() -> void:
	if _pid > 0 and OS.is_process_running(_pid): OS.kill(_pid)
	_pid = -1
