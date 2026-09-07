@tool
class_name EmberContentMigrationReport
extends RefCounted
## Read-only G1/G2 inventory. It measures canonical ownership and derived-data
## health without creating Resources, rebuilding prefabs or touching JOI files.

const VoxelCatalog = preload("res://scripts/ember_voxel_catalog.gd")
const VoxelPrefab = preload("res://scripts/ember_voxel_prefab.gd")
const ActionCatalog = preload("res://scripts/ember_action_catalog.gd")
const ActionStore = preload("res://addons/ember_import/ember_action_script_store.gd")
const DialogueCatalog = preload("res://scripts/ember_dialogue_catalog.gd")
const DialogueStore = preload("res://addons/ember_import/ember_dialogue_store.gd")
const ItemCatalog = preload("res://scripts/ember_item_catalog.gd")
const ItemStore = preload("res://addons/ember_import/ember_item_store.gd")
const ShopCatalog = preload("res://scripts/ember_shop_catalog.gd")
const ShopStore = preload("res://addons/ember_import/ember_shop_store.gd")
const VnAssets = preload("res://scripts/ember_vn_assets.gd")
const VoxelBatches = preload("res://addons/ember_import/ember_voxel_migration_batches.gd")
const DOMAIN_ORDER := ["voxel", "action", "dialogue", "item", "shop", "vn"]


static func build() -> Dictionary:
	var started := Time.get_ticks_msec()
	var domains := {
		"voxel": _voxel_domain(),
		"action": _document_domain(
			ActionCatalog.ids(), ActionCatalog.owner, ActionStore.document,
			ActionStore.validation_errors,
		),
		"dialogue": _document_domain(
			DialogueCatalog.ids(), DialogueCatalog.owner, DialogueStore.document,
			DialogueStore.graph_validation_errors,
		),
		"item": _document_domain(
			ItemCatalog.ids(), ItemCatalog.owner, ItemStore.document,
			ItemStore.validation_errors,
		),
		"shop": _document_domain(
			ShopCatalog.ids(), ShopCatalog.owner, ShopStore.document,
			ShopStore.validation_errors,
		),
		"vn": _vn_domain(),
	}
	var totals := _empty_counts()
	for raw_domain in domains.values():
		var domain: Dictionary = raw_domain
		_add_counts(totals, domain.get("counts", {}))
	return {
		"schema": 1,
		"generated_unix": int(Time.get_unix_time_from_system()),
		"duration_ms": Time.get_ticks_msec() - started,
		"totals": totals,
		"domains": domains,
	}


static func filtered_entries(
	report: Dictionary,
	domain_filter := "all",
	state_filter := "all",
	query := "",
) -> Array[Dictionary]:
	## Read-only projection for editor dashboards. Filters never mutate the
	## inventory or its source catalogs.
	var result: Array[Dictionary] = []
	var domains: Dictionary = report.get("domains", {})
	var normalized_query := query.strip_edges().to_lower()
	for domain_name in DOMAIN_ORDER:
		if domain_filter != "all" and domain_filter != domain_name:
			continue
		var domain: Dictionary = domains.get(domain_name, {})
		for raw_entry in domain.get("entries", []):
			var entry: Dictionary = (raw_entry as Dictionary).duplicate(true)
			entry["domain"] = domain_name
			if not _matches_state_filter(entry, state_filter):
				continue
			if not normalized_query.is_empty() and not _entry_search_text(entry).contains(normalized_query):
				continue
			result.append(entry)
	return result


static func _matches_state_filter(entry: Dictionary, state_filter: String) -> bool:
	match state_filter:
		"native", "legacy":
			return str(entry.get("owner", "")) == state_filter
		"attention":
			return entry_needs_attention(entry)
		"scene_used":
			return int(entry.get("reference_count", 0)) > 0
		"sandbox_batch":
			return VoxelBatches.entry_matches(entry, "sandbox")
		"sandbox_pending":
			return (
				str(entry.get("owner", "")) == "legacy"
				and _matches_state_filter(entry, "sandbox_batch")
			)
		"fan_town_ready_batch":
			return VoxelBatches.entry_matches(entry, "fan_town_ready")
		"fan_town_ready_pending":
			return (
				str(entry.get("owner", "")) == "legacy"
				and _matches_state_filter(entry, "fan_town_ready_batch")
			)
		_:
			return true


static func entry_needs_attention(entry: Dictionary) -> bool:
	return (
		str(entry.get("status", "")) in ["missing", "invalid"]
		or str(entry.get("derived_status", "")) in ["missing", "stale", "invalid"]
		or not (entry.get("errors", []) as Array).is_empty()
		or not (entry.get("derived_errors", []) as Array).is_empty()
	)


static func _entry_search_text(entry: Dictionary) -> String:
	var fragments := PackedStringArray([
		str(entry.get("domain", "")),
		str(entry.get("id", "")),
		str(entry.get("owner", "")),
		str(entry.get("status", "")),
		str(entry.get("kind", "")),
		str(entry.get("derived_status", "")),
		str(entry.get("prefab_path", "")),
	])
	for key in ["errors", "derived_errors", "referenced_in"]:
		for value in entry.get(key, []):
			fragments.append(str(value))
	return " ".join(fragments).to_lower()


static func _document_domain(
	ids: Array[String],
	owner_callable: Callable,
	document_callable: Callable,
	validation_callable: Callable,
) -> Dictionary:
	var entries: Array[Dictionary] = []
	var counts := _empty_counts()
	for content_id in ids:
		var owner := _normalized_owner(str(owner_callable.call(content_id)))
		var document: Dictionary = document_callable.call(content_id)
		var errors: Array[String] = []
		for error in validation_callable.call(document):
			errors.append(str(error))
		var entry := {
			"id": content_id,
			"owner": owner,
			"status": _entry_status(owner, errors),
			"errors": errors,
		}
		entries.append(entry)
		_count_entry(counts, owner, errors)
	return {"counts": counts, "entries": entries}


static func _voxel_domain() -> Dictionary:
	var entries: Array[Dictionary] = []
	var counts := _empty_counts()
	counts["derived_ready"] = 0
	counts["derived_missing"] = 0
	counts["derived_stale"] = 0
	counts["derived_invalid"] = 0
	counts["reference_missing"] = 0
	var definitions := VoxelCatalog.definitions()
	var references := _voxel_references()
	var ids: Array[String] = []
	for raw_id in definitions:
		ids.append(str(raw_id))
	ids.sort()
	for model_id in ids:
		var definition: Dictionary = definitions.get(model_id, {})
		var owner := _normalized_owner(str(definition.get("_owner", "")))
		var errors: Array[String] = []
		var resource := VoxelCatalog.native_resource(model_id) if owner == "native" else null
		if owner == "native":
			if resource == null:
				errors.append("Native Resource не загружается")
			else:
				errors.append_array(resource.validation_errors())
		var tags := _string_array(definition.get("tags", []))
		var is_surface := "surface" in tags
		var prefab_path := VoxelPrefab.prefab_path(model_id)
		var derived_status := "not_required" if is_surface else "missing"
		var derived_errors: Array[String] = []
		var referenced_in: Array = references.get(model_id, [])
		if not is_surface and ResourceLoader.exists(prefab_path):
			var packed := ResourceLoader.load(
				prefab_path, "", ResourceLoader.CACHE_MODE_REPLACE
			) as PackedScene
			var validation: Dictionary = VoxelPrefab.validate_packed(model_id, packed)
			for error in validation.get("errors", []):
				derived_errors.append(str(error))
			if bool(validation.get("ok", false)):
				derived_status = "ready"
				counts["derived_ready"] += 1
			elif _has_stale_error(derived_errors):
				derived_status = "stale"
				counts["derived_stale"] += 1
			else:
				derived_status = "invalid"
				counts["derived_invalid"] += 1
		else:
			if not is_surface:
				counts["derived_missing"] += 1
		var entry := {
			"id": model_id,
			"owner": owner,
			"kind": "surface" if is_surface else "model",
			"status": _entry_status(owner, errors),
			"errors": errors,
			"prefab_path": prefab_path if not is_surface else "",
			"derived_status": derived_status,
			"derived_errors": derived_errors,
			"reference_count": referenced_in.size(),
			"referenced_in": referenced_in.duplicate(),
		}
		entries.append(entry)
		_count_entry(counts, owner, errors)
	var missing_references: Array[String] = []
	for model_id in references:
		if not definitions.has(model_id):
			missing_references.append(str(model_id))
	missing_references.sort()
	counts["reference_missing"] = missing_references.size()
	return {
		"counts": counts,
		"entries": entries,
		"missing_references": missing_references,
	}


static func _vn_domain() -> Dictionary:
	var assets := VnAssets.new() as EmberVnAssets
	var entries: Array[Dictionary] = []
	var counts := _empty_counts()
	for raw_entry in assets.art_entries():
		var entry: Dictionary = raw_entry
		_append_vn_entry(entries, counts, "background", str(entry.get("id", "")), entry)
	for speaker in assets.speaker_ids():
		for raw_entry in assets.portrait_entries(speaker):
			var entry: Dictionary = raw_entry
			_append_vn_entry(
				entries, counts, "portrait", "%s/%s" % [speaker, entry.get("key", "")], entry,
			)
	return {"counts": counts, "entries": entries}


static func _append_vn_entry(
	entries: Array[Dictionary],
	counts: Dictionary,
	kind: String,
	content_id: String,
	entry: Dictionary,
) -> void:
	var owner := "native" if bool(entry.get("native", false)) else "legacy"
	var errors: Array[String] = []
	if content_id.strip_edges().is_empty():
		errors.append("Пустой ID")
	if not bool(entry.get("exists", false)):
		errors.append("Файл изображения не найден")
	entries.append({
		"id": content_id,
		"kind": kind,
		"owner": owner,
		"status": _entry_status(owner, errors),
		"errors": errors,
	})
	_count_entry(counts, owner, errors)


static func _empty_counts() -> Dictionary:
	return {
		"total": 0,
		"native": 0,
		"legacy_remaining": 0,
		"missing": 0,
		"invalid": 0,
		"native_invalid": 0,
	}


static func _count_entry(counts: Dictionary, owner: String, errors: Array[String]) -> void:
	counts["total"] = int(counts.get("total", 0)) + 1
	if owner == "native":
		counts["native"] = int(counts.get("native", 0)) + 1
	elif owner == "legacy":
		counts["legacy_remaining"] = int(counts.get("legacy_remaining", 0)) + 1
	else:
		counts["missing"] = int(counts.get("missing", 0)) + 1
	if not errors.is_empty():
		counts["invalid"] = int(counts.get("invalid", 0)) + 1
		if owner == "native":
			counts["native_invalid"] = int(counts.get("native_invalid", 0)) + 1


static func _add_counts(target: Dictionary, source: Dictionary) -> void:
	for key in target:
		target[key] = int(target.get(key, 0)) + int(source.get(key, 0))


static func _normalized_owner(raw: String) -> String:
	if raw in ["native", "godot"]:
		return "native"
	if raw in ["legacy", "legacy_import"]:
		return "legacy"
	return "missing"


static func _entry_status(owner: String, errors: Array[String]) -> String:
	if owner == "missing":
		return "missing"
	if not errors.is_empty():
		return "invalid"
	return owner


static func _string_array(raw: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(raw) == TYPE_ARRAY or typeof(raw) == TYPE_PACKED_STRING_ARRAY:
		for value in raw:
			result.append(str(value))
	return result


static func _has_stale_error(errors: Array[String]) -> bool:
	for error in errors:
		if error.contains("текущих исходников"):
			return true
	return false


static func _voxel_references() -> Dictionary:
	var found := {}
	_scan_scene_references("res://scenes", found)
	return found


static func _scan_scene_references(directory: String, found: Dictionary) -> void:
	var absolute := ProjectSettings.globalize_path(directory)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	for child_directory in DirAccess.get_directories_at(absolute):
		_scan_scene_references(directory.path_join(child_directory), found)
	for filename in DirAccess.get_files_at(absolute):
		if filename.get_extension().to_lower() != "tscn":
			continue
		var scene_path := directory.path_join(filename)
		var text := FileAccess.get_file_as_string(scene_path)
		_collect_regex_values(text, "model_id\\s*=\\s*\"([^\"]+)\"", scene_path, found)
		_collect_regex_values(text, "prefabs/voxels/([^\".]+)\\.tscn", scene_path, found)


static func _collect_regex_values(
	text: String,
	pattern: String,
	source_path: String,
	found: Dictionary,
) -> void:
	var expression := RegEx.new()
	if expression.compile(pattern) != OK:
		return
	for match_value in expression.search_all(text):
		var value := match_value.get_string(1).strip_edges()
		if not value.is_empty():
			if not found.has(value):
				found[value] = []
			var paths: Array = found[value]
			if source_path not in paths:
				paths.append(source_path)
