extends SceneTree
## G1 ownership gate: legacy is imported once; save/reopen, catalog and prefab
## then work exclusively from the Godot Resource.

const MODEL_ID := "vox_fan_anvil"
const TEMP_PATH := "user://vox_fan_anvil_native_test.tres"


func _init() -> void:
	quit(_run())


func _run() -> int:
	var errors: Array[String] = []
	var absolute := ProjectSettings.globalize_path(TEMP_PATH)
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)
	var report := EmberVoxelLegacyImporter.import_model(MODEL_ID, TEMP_PATH, true)
	if not bool(report.get("ok", false)):
		errors.append(str(report.get("error", "import failed")))
	else:
		var loaded := ResourceLoader.load(TEMP_PATH, "", ResourceLoader.CACHE_MODE_REPLACE) as EmberVoxelModelResource
		if loaded == null:
			errors.append("saved resource did not reopen")
		else:
			errors.append_array(loaded.validation_errors())
			var definition := loaded.to_definition()
			if not bool(definition.get("_nativeGodotVoxel", false)):
				errors.append("native owner marker is missing")
			var model: Dictionary = definition.get("model", {})
			var mesh := VoxMesher.build_from_ember_model(model, VoxMesher.normalized_voxel_size(model))
			if mesh.get_surface_count() == 0:
				errors.append("reopened resource did not build a mesh")
			else:
				var bounds := mesh.get_aabb().size
				if bounds.x > 1.001 or bounds.y > 1.001 or bounds.z > 1.001:
					errors.append("native model exceeds its normalized one-block footprint: %s" % bounds)
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)
	_validate_native_catalog_and_prefab(errors)
	if not errors.is_empty():
		printerr("FAIL native voxel resource")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS native voxel resource")
	print("  legacy pair -> Godot Resource -> save/reopen -> normalized mesh")
	print("  no reverse write to JOI")
	return 0


func _validate_native_catalog_and_prefab(errors: Array[String]) -> void:
	var definition := EmberVoxelCatalog.definition(MODEL_ID)
	if str(definition.get("_owner", "")) != "godot":
		errors.append("native model did not take ownership in the catalog")
	var sources := EmberVoxelPrefab.source_paths(MODEL_ID)
	if str(sources.get("owner", "")) != "godot" or not str(sources.get("vox", "")).is_empty():
		errors.append("prefab builder still resolves the JOI pair for a migrated model")
	EmberVoxelPrefab.begin_import()
	var packed := EmberVoxelPrefab.ensure_saved(MODEL_ID, 16.0, {})
	var prefab_report := EmberVoxelPrefab.validate_packed(MODEL_ID, packed)
	if not bool(prefab_report.get("ok", false)):
		errors.append_array(prefab_report.get("errors", []))
	var previous_pack: Variant = ProjectSettings.get_setting("ember/pack_path", "")
	ProjectSettings.set_setting("ember/pack_path", "C:/definitely-missing-ember-pack")
	EmberVoxelPrefab.begin_import()
	var detached_definition := EmberVoxelCatalog.definition(MODEL_ID)
	var detached_preview := EmberVoxelPrefab.make_preview_instance(MODEL_ID, 16.0)
	if str(detached_definition.get("_owner", "")) != "godot" or detached_preview == null:
		errors.append("migrated model still depends on the JOI pack path")
	if detached_preview:
		detached_preview.free()
	ProjectSettings.set_setting("ember/pack_path", previous_pack)
	EmberVoxelPrefab.begin_import()
