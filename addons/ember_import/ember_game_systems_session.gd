@tool
extends RefCounted
## One editor draft; no gameplay state. Draft Undo is local, publication is global.
const Store = preload("res://addons/ember_import/ember_game_systems_store.gd")
signal changed
signal published
var module := ""
var draft: Resource
var path := ""
var is_new := false
var _baseline: Resource
var _live_source: Resource
var _live_values := {}
var _signature := ""
var _undo := UndoRedo.new()
var _editor_undo: Object
var _publication_context := RefCounted.new()
var last_error := ""
var _publish_ok := false

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_undo): _undo.free()

func configure(undo: Object) -> void:
	_editor_undo = undo

func publish_current(module_id: String, resource: Resource) -> bool:
	# Explicit Save from the existing Inspector approves its current edited values.
	module = module_id
	path = resource.resource_path
	draft = Store.clone(resource)
	_baseline = Store.clone(resource)
	_live_source = resource
	_live_values = _values(resource)
	_signature = Store.signature(path)
	is_new = false
	return save()

func open(module_id: String, record: Dictionary) -> bool:
	if not FileAccess.file_exists(str(record.path)):
		last_error = "Файл записи больше не существует. Обновите библиотеку."
		return false
	module = module_id
	path = str(record.path)
	var source := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	_live_source = record.get("resource") as Resource
	if Engine.is_editor_hint():
		var inspected := EditorInterface.get_inspector().get_edited_object()
		if inspected is Resource and inspected.resource_path == path: _live_source = inspected
	if _live_source == null: _live_source = ResourceLoader.load(path)
	_live_values = _values(_live_source)
	draft = Store.clone(source)
	_baseline = Store.clone(source)
	is_new = false
	_signature = Store.signature(path)
	_undo.clear_history(false)
	last_error = ""
	changed.emit()
	return true

func create(module_id: String, id: String, name: String, source: Resource = null) -> bool:
	var target := Store.path_for(module_id, id)
	if target.is_empty() or FileAccess.file_exists(target) or Store.Catalog.entries(module_id).any(func(record: Dictionary) -> bool: return record.id == id):
		last_error = "Нужен свободный ID; существующая запись не перезаписана."
		return false
	module = module_id
	path = target
	draft = Store.clone(source) if source != null else Store.blank(module, id, name)
	if draft == null: return false
	draft.set(Store.SPECS[Store.kind(module)][1], id)
	if Store.kind(module) == "item":
		var data: Dictionary = draft.get("definition").duplicate(true)
		data["id"] = id
		data["nameRu"] = name
		draft.set("definition", data)
	else: draft.set("display_name", name)
	_baseline = Store.clone(draft)
	_signature = ""
	is_new = true
	_live_source = null
	_live_values = {}
	_undo.clear_history(false)
	last_error = ""
	changed.emit()
	return true

func has_changes() -> bool:
	return draft != null and (is_new or _values(draft) != _values(_baseline))

func set_value(property: String, value: Variant, field_key := "") -> void:
	if draft == null: return
	var before: Variant = draft.get(property)
	if before == value: return
	var merge := UndoRedo.MERGE_ENDS if typeof(value) in [TYPE_STRING, TYPE_INT, TYPE_FLOAT, TYPE_COLOR] or not field_key.is_empty() else UndoRedo.MERGE_DISABLE
	_undo.create_action("Изменить " + property + field_key, merge)
	_undo.add_do_method(_assign.bind(property, value))
	_undo.add_undo_method(_assign.bind(property, before))
	_undo.commit_action()

func _assign(property: String, value: Variant) -> void:
	draft.set(property, value)
	changed.emit()

func undo() -> void:
	if _undo.has_undo(): _undo.undo()

func redo() -> void:
	if _undo.has_redo(): _undo.redo()

func can_undo() -> bool: return _undo.has_undo()
func can_redo() -> bool: return _undo.has_redo()

func discard() -> void:
	draft = null
	_baseline = null
	_undo.clear_history(false)
	changed.emit()

func save() -> bool:
	last_error = ""
	var errors := Store.validation(module, draft)
	if not errors.is_empty():
		last_error = "\n".join(errors)
		return false
	if Store.path_for(module, Store.id_for(module, draft)) != path:
		last_error = "ID существующей записи нельзя менять. Для нового ID создайте копию."
		return false
	if Store.signature(path) != _signature:
		last_error = "Файл изменён другим редактором. Сохранение остановлено; черновик сохранён в окне."
		return false
	if _live_source != null and (_values(_live_source) != _live_values or _live_values != _values(_baseline)):
		last_error = "В исходной записи есть несохранённые изменения другого редактора. Сохранение остановлено."
		return false
	if _editor_undo == null:
		last_error = "История редактора недоступна. Запись не сохранена."
		return false
	var before := Store.snapshot(path)
	_publish_ok = Store.write(module, draft, path) == OK
	if not _publish_ok:
		last_error = "Не удалось записать файл. Черновик оставлен для повторного сохранения."
		return false
	var after := Store.snapshot(path)
	_record_publication(before, after, "Сохранить игровую запись")
	draft = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	_baseline = Store.clone(draft)
	_signature = Store.signature(path)
	is_new = false
	_live_source = ResourceLoader.load(path)
	_live_values = _values(_live_source)
	_undo.clear_history(false)
	changed.emit()
	published.emit()
	return true

func remove(module_id: String, record: Dictionary, expected_signature: String) -> bool:
	last_error = ""
	if _editor_undo == null or Store.signature(str(record.path)) != expected_signature:
		last_error = "Файл изменился или история редактора недоступна. Удаление остановлено."
		return false
	if not Store.Catalog.incoming(module_id, record).is_empty():
		last_error = "На запись есть прямые ссылки. Сначала измените их у потребителей."
		return false
	if Engine.is_editor_hint():
		var inspected := EditorInterface.get_inspector().get_edited_object()
		if inspected is Resource and inspected.resource_path == record.path and _values(inspected) != _values(ResourceLoader.load(str(record.path), "", ResourceLoader.CACHE_MODE_IGNORE)):
			last_error = "В Inspector есть несохранённые изменения этой записи. Удаление остановлено."
			return false
	var before := Store.snapshot(str(record.path))
	if Store.remove_with_backup(str(record.path)) != OK:
		last_error = "Не удалось сохранить резервную копию; запись не удалена."
		return false
	_record_publication(before, {"path": record.path, "exists": false, "bytes": PackedByteArray()}, "Удалить игровую запись")
	published.emit()
	return true

func _record_publication(before: Dictionary, after: Dictionary, title: String) -> void:
	if _editor_undo is EditorUndoRedoManager:
		(_editor_undo as EditorUndoRedoManager).create_action(title, UndoRedo.MERGE_DISABLE, _publication_context)
		Callable(_editor_undo, "add_do_method").call(self, "_restore_publication", after)
		Callable(_editor_undo, "add_undo_method").call(self, "_restore_publication", before)
		(_editor_undo as EditorUndoRedoManager).commit_action(false)
	else:
		(_editor_undo as UndoRedo).create_action(title)
		(_editor_undo as UndoRedo).add_do_method(_restore_publication.bind(after))
		(_editor_undo as UndoRedo).add_undo_method(_restore_publication.bind(before))
		(_editor_undo as UndoRedo).commit_action(false)

func _restore_publication(snapshot: Dictionary) -> void:
	if Store.restore(snapshot) != OK:
		last_error = "Не удалось восстановить запись через Undo/Redo."
		push_error(last_error)
	published.emit()

func _values(resource: Resource) -> Dictionary:
	var result := {}
	for property in resource.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_STORAGE and str(property.name) != "script": result[property.name] = _value(resource.get(property.name))
	return result

func _value(value: Variant) -> Variant:
	if value is Resource:
		return {"external": value.resource_path} if not value.is_built_in() else _values(value)
	if value is Array:
		var result: Array = []
		for element in value: result.append(_value(element))
		return result
	if value is Dictionary:
		var result := {}
		for key in value: result[key] = _value(value[key])
		return result
	return value
