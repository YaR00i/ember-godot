@tool
extends RefCounted
## Editor publication adapter. Existing typed Resources and ItemStore remain canonical.
const Catalog = preload("res://addons/ember_import/ember_game_systems_catalog.gd")
const ItemStore = preload("res://addons/ember_import/ember_item_store.gd")
const SPECS := {
	"item": ["res://content/items", "item_id", preload("res://scripts/ember_item_resource.gd")],
	"status": ["res://content/combat/statuses", "status_id", preload("res://scripts/prototypes/ember_combat_status_resource.gd")],
	"effect": ["res://content/combat/effects", "effect_id", preload("res://scripts/prototypes/ember_combat_effect_resource.gd")],
	"action": ["res://content/combat/actions", "action_id", preload("res://scripts/prototypes/ember_combat_action_resource.gd")],
	"unit": ["res://content/combat/units", "unit_id", preload("res://scripts/prototypes/ember_combat_unit_resource.gd")],
	"ai": ["res://content/combat/ai_profiles", "profile_id", preload("res://scripts/prototypes/ember_combat_ai_profile_resource.gd")],
	"loot": ["res://content/combat/loot_tables", "table_id", preload("res://scripts/prototypes/ember_combat_loot_table_resource.gd")],
	"field": ["res://content/combat/battlefields", "field_id", preload("res://scripts/prototypes/ember_battlefield_resource.gd")],
	"encounter": ["res://content/combat/encounters", "encounter_id", preload("res://scripts/prototypes/ember_encounter_resource.gd")],
}

static func kind(module: String) -> String:
	return "item" if module == "equipment" else module

static func path_for(module: String, id: String) -> String:
	var spec: Array = SPECS.get(kind(module), [])
	return str(spec[0]).path_join(id + ".tres") if not spec.is_empty() and valid_id(id) else ""

static func valid_id(id: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^[a-z0-9][a-z0-9_-]*$")
	return regex.search(id) != null

static func id_for(module: String, resource: Resource) -> String:
	return str(resource.get(SPECS[kind(module)][1]))

static func clone(resource: Resource) -> Resource:
	# Built-in rows/arrays are isolated; external effect/loot/field links stay shared.
	return resource.duplicate_deep(Resource.DEEP_DUPLICATE_INTERNAL)

static func blank(module: String, id: String, name: String) -> Resource:
	var key := kind(module)
	if not SPECS.has(key): return null
	var resource: Resource = SPECS[key][2].new()
	resource.set(SPECS[key][1], id)
	if key == "item":
		resource.set("definition", ItemStore.normalized_document({"id": id, "nameRu": name, "kind": "armor" if module == "equipment" else "material", "slot": "armor" if module == "equipment" else "none"}))
	else:
		resource.set("display_name", name)
	if key == "field":
		for property in ["terrain_kinds", "elevations", "blocked", "groups"]:
			var cells: Variant = resource.get(property)
			cells.resize(resource.cell_count())
			cells.fill("" if property == "groups" else 0)
			resource.set(property, cells)
		resource.party_deployment_cells = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3)]
		resource.enemy_deployment_cells = [Vector2i(6, 0), Vector2i(6, 1), Vector2i(6, 2)]
	return resource

static func validation(module: String, resource: Resource) -> Array[String]:
	var errors: Array[String] = []
	var key := kind(module)
	if resource == null or not SPECS.has(key) or resource.get_script() != SPECS[key][2]:
		errors.append("Тип записи не соответствует разделу.")
		return errors
	var id := id_for(module, resource)
	if not valid_id(id): errors.append("ID: только a-z, 0-9, _ и -, первый символ — буква или цифра.")
	if key == "item":
		if str(resource.get("definition").get("id", "")) != id: errors.append("ID предмета и его данных различаются.")
		errors.append_array(ItemStore.validation_errors(resource.get("definition")))
	elif resource.has_method("validation_errors"):
		errors.append_array(resource.call("validation_errors", Catalog.Actions.ids()) if key == "unit" else resource.call("validation_errors"))
	return errors

static func snapshot(path: String) -> Dictionary:
	return {"path": path, "exists": FileAccess.file_exists(path), "bytes": FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()}

static func signature(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""

static func write(module: String, resource: Resource, path: String) -> int:
	if not validation(module, resource).is_empty() or path != path_for(module, id_for(module, resource)): return ERR_INVALID_DATA
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if error != OK and error != ERR_ALREADY_EXISTS: return error
	var before := snapshot(path)
	var uid := ResourceLoader.get_resource_uid(path) if before.exists else ResourceUID.INVALID_ID
	# ItemStore owns item normalization/write; combat uses the established native saver.
	error = ItemStore.write_document(resource.get("definition")) if kind(module) == "item" else ResourceSaver.save(resource, path)
	if error == OK and uid != ResourceUID.INVALID_ID: error = ResourceSaver.set_uid(path, uid)
	if error != OK:
		restore(before)
		return error
	_sync(path)
	return OK

static func restore(value: Dictionary) -> int:
	var path := str(value.get("path", ""))
	if not _allowed_path(path): return ERR_INVALID_PARAMETER
	var error := OK
	if value.get("exists", false):
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null: return FileAccess.get_open_error()
		file.store_buffer(value.bytes)
		error = file.get_error()
		file.close()
	else:
		error = DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) if FileAccess.file_exists(path) else OK
	if error == OK: _sync(path)
	return error

static func remove_with_backup(path: String) -> int:
	if not _allowed_path(path) or not FileAccess.file_exists(path): return ERR_INVALID_PARAMETER
	var backup_dir := "user://ember-editor-resource-backups"
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(backup_dir))
	if error != OK and error != ERR_ALREADY_EXISTS: return error
	var digest := signature(path)
	var backup := backup_dir.path_join(path.get_file().get_basename() + "-" + digest + ".tres")
	if not FileAccess.file_exists(backup):
		var file := FileAccess.open(backup, FileAccess.WRITE)
		if file == null: return FileAccess.get_open_error()
		file.store_buffer(FileAccess.get_file_as_bytes(path))
		file.close()
	if signature(backup) != digest: return ERR_FILE_CORRUPT
	return restore({"path": path, "exists": false})

static func _allowed_path(path: String) -> bool:
	for key in SPECS:
		if path == path_for(key, path.get_file().get_basename()): return true
	return false

static func _sync(path: String) -> void:
	if FileAccess.file_exists(path): ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	Catalog.refresh()
