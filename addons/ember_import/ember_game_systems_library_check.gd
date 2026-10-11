extends SceneTree
## Read-only saved-file inspection in a fresh process. Existing validators own rules.
const Store = preload("res://addons/ember_import/ember_game_systems_store.gd")
const Items = preload("res://scripts/ember_item_catalog.gd")
const Story = preload("res://scripts/ember_action_catalog.gd")
const Transition = preload("res://scripts/ember_combat_transition.gd")
var _issues: Array[Dictionary] = []
var _records: Array[Dictionary] = []
var _ids := {}
var _dependency_cache := {}
var _source_hashes := {}
var _report_path := ""

func _init() -> void:
	var paths := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(Transition.LIBRARY_CHECK_PREFIX): paths.append(ProjectSettings.globalize_path(arg.trim_prefix(Transition.LIBRARY_CHECK_PREFIX)).replace("\\", "/"))
	var folder := ProjectSettings.globalize_path("user://ember-library-check").replace("\\", "/")
	if paths.size() != 1 or paths[0].replace("\\", "/").get_base_dir() != folder or paths[0].get_extension() != "json":
		printerr("Library check: invalid output request")
		quit.call_deferred(2)
		return
	_report_path = paths[0]
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		quit.call_deferred(2)
		return
	_run.call_deferred()

func _run() -> void:
	var start := Time.get_ticks_msec()
	var specs := Store.SPECS.duplicate()
	specs["icon"] = [Items.ICON_DIR, "icon_id", Items.IconResource]
	specs["story_action"] = [Story.NATIVE_DIR, "action_id", Story.ActionResource]
	for module in specs:
		_ids[module] = {}
		var spec: Array = specs[module]
		var directory := DirAccess.open(spec[0])
		if directory == null:
			continue
		var files := directory.get_files()
		files.sort()
		for filename in files:
			if filename.get_extension() != "tres": continue
			var record := {"module": str(module), "path": str(spec[0]).path_join(filename), "id": "", "name": filename, "loadable": false, "resource": null}
			_records.append(record)
			var problems := _dependencies(record.path, {})
			if not problems.is_empty():
				for problem in problems: _issue(record, "missing_dependency", problem)
				continue
			var resource := ResourceLoader.load(record.path, "", ResourceLoader.CACHE_MODE_IGNORE)
			if resource == null:
				_issue(record, "unreadable", "Не удалось прочитать Resource; откройте файл и журнал проверки.")
				continue
			if resource.get_script() != spec[2]:
				_issue(record, "wrong_type", "Тип Resource не соответствует разделу.")
				continue
			record.resource = resource
			record.loadable = true
			record.id = str(resource.get(spec[1])).strip_edges()
			record.name = str(resource.definition.get("nameRu", record.id)) if module in ["item", "icon"] else str(resource.document.get("nameRu", record.id)) if module == "story_action" else str(resource.get("display_name"))
			if not Store.valid_id(str(resource.get(spec[1]))): _issue(record, "invalid_id", "Некорректный или пустой ID; пробелы по краям также недопустимы.")
			if filename.get_basename() != record.id: _issue(record, "filename_id", "Имя файла %s не совпадает с ID %s; публикация ожидает файл %s.tres." % [filename, record.id, record.id])
			if not _ids[module].has(record.id): _ids[module][record.id] = []
			_ids[module][record.id].append(record)
	for module in _ids:
		for id in _ids[module]:
			var records: Array = _ids[module][id]
			if records.size() > 1:
				var paths := PackedStringArray()
				for record in records: paths.append(record.path)
				for record in records: _issue(record, "duplicate_id", "ID %s повторяется в разделе: %s." % [id, ", ".join(paths)])
	var known_actions := PackedStringArray(_ids.get("action", {}).keys())
	for record in _records:
		if record.resource == null: continue
		_links(record)
		var resource: Resource = record.resource
		_metadata(record, resource)
		if record.module == "item" and str(resource.definition.get("id", "")) != record.id: _issue(record, "envelope_id", "ID предмета и его данных различаются.")
		if record.module in ["icon", "story_action"]:
			var data: Dictionary = resource.definition if record.module == "icon" else resource.document
			if str(data.get("id", record.id)) != record.id: _issue(record, "envelope_id", "ID Resource и его данных различаются.")
			continue
		if not _safe_nested(record): continue
		var errors: Array = Store.ItemStore.validation_errors(resource.definition) if record.module == "item" else resource.call("validation_errors", known_actions) if record.module == "unit" else resource.call("validation_errors")
		for error in errors: _issue(record, "validation", str(error))
	for record in _records:
		if str(_source_hashes.get(record.path, "")) != FileAccess.get_sha256(record.path): _issue(record, "changed_during_check", "Файл изменился во время проверки. Повторите её.")
	var report := {"version": 1, "request": _report_path, "ok": true, "recordCount": _records.size(), "issueCount": _issues.size(), "issues": _issues, "elapsedMs": Time.get_ticks_msec() - start, "sources": _source_hashes, "scope": "saved native game systems; linked icon/story identities and resource dependencies"}
	var output := FileAccess.open(_report_path, FileAccess.WRITE)
	if output == null:
		printerr("Library check: cannot write report")
		quit(2)
		return
	output.store_string(JSON.stringify(report))
	output.close()
	print("LIBRARY_CHECK_COMPLETE records=%d issues=%d elapsed_ms=%d" % [report.recordCount, report.issueCount, report.elapsedMs])
	quit(0)

func _issue(record: Dictionary, code: String, message: String) -> void:
	var issue := {"module": record.module, "path": record.path, "id": record.id, "name": record.name, "loadable": record.loadable, "code": code, "message": message}
	if issue not in _issues: _issues.append(issue)

func _dependencies(path: String, visiting: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	if visiting.has(path): return ["Циклическая Resource-ссылка: " + path]
	if _dependency_cache.has(path):
		problems.assign(_dependency_cache[path])
		return problems
	_source_hashes[path] = FileAccess.get_sha256(path)
	var next := visiting.duplicate()
	next[path] = true
	for raw in ResourceLoader.get_dependencies(path):
		var parts := str(raw).split("::")
		var dependency := str(parts[-1])
		if dependency.begins_with("uid://"):
			var uid := ResourceUID.text_to_id(dependency)
			dependency = ResourceUID.get_id_path(uid) if ResourceUID.has_id(uid) else ""
		if dependency.is_empty() or not ResourceLoader.exists(dependency):
			problems.append("Потеряна файловая ссылка: %s → %s." % [path, str(raw)])
		elif dependency.get_extension() in ["tres", "res", "tscn"]:
			for problem in _dependencies(dependency, next):
				if problem not in problems: problems.append(problem)
	_dependency_cache[path] = problems.duplicate()
	return problems

func _reference(record: Dictionary, module: String, id: String) -> void:
	if id.is_empty(): return
	var targets: Array = _ids.get(module, {}).get(id, [])
	if targets.is_empty(): _issue(record, "missing_id", "Не найдена ссылка %s → %s." % [module, id])
	elif targets.size() > 1: _issue(record, "ambiguous_id", "Ссылка %s → %s неоднозначна: несколько записей с этим ID." % [module, id])

func _links(record: Dictionary) -> void:
	var resource: Resource = record.resource
	match record.module:
		"item": _reference(record, "icon", str(resource.definition.get("iconId", "")))
		"action":
			if str(resource.call("effect_id")) in ["duo_pulse", "steam_breach"]: _reference(record, "unit", str(resource.get("partner_unit_id")))
		"effect":
			match str(resource.call("operation_id")):
				"apply_status": _reference(record, "status", str(resource.get("status_id")))
				"remove_status":
					for id in resource.get("remove_status_ids"): _reference(record, "status", str(id))
				"spread":
					for id in resource.get("spread_status_ids"): _reference(record, "status", str(id))
		"unit":
			for id in resource.get("action_ids"): _reference(record, "action", str(id))
			_reference(record, "ai", str(resource.get("ai_profile_id")))
		"loot":
			for entry in resource.get("entries"):
				if entry != null: _reference(record, "item", str(entry.get("item_id")))
		"encounter":
			for key in ["party_unit_ids", "enemy_unit_ids"]:
				for id in resource.get(key): _reference(record, "unit", str(id))
			for key in ["victory_action_script_id", "defeat_action_script_id"]: _reference(record, "story_action", str(resource.get(key)))

func _safe_nested(record: Dictionary) -> bool:
	if record.module != "action": return true
	var safe := true
	for step in record.resource.get("effect_steps"):
		if step != null and step.get_script() != Store.SPECS.effect[2]:
			record.loadable = false
			_issue(record, "wrong_effect_type", "В последовательности находится Resource другого типа вместо эффекта.")
			safe = false
		elif step != null: _metadata(record, step)
	return safe

func _metadata(record: Dictionary, resource: Resource) -> void:
	for property in resource.get_property_list():
		if not (int(property.usage) & PROPERTY_USAGE_STORAGE) or not (int(property.usage) & PROPERTY_USAGE_EDITOR): continue
		var value: Variant = resource.get(property.name)
		if int(property.type) == TYPE_INT and int(property.hint) == PROPERTY_HINT_ENUM:
			var allowed: Array[int] = []
			for option in str(property.hint_string).split(","):
				var parts := option.split(":")
				allowed.append(int(parts[1]) if parts.size() > 1 else allowed.size())
			if int(value) not in allowed: _issue(record, "enum_value", "Поле %s: значение %s не входит в варианты, объявленные Resource." % [property.name, value])
