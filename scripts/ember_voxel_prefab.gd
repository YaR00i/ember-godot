class_name EmberVoxelPrefab
extends RefCounted
## Builds PackedScene per voxel model: mesh, optional shadow body, Omni slot, collider.

const PREFAB_DIR := "res://prefabs/voxels"
const MESH_DIR := "res://prefabs/voxels/meshes"
const MAT_PATH := "res://materials/ember_voxel_toon.tres"
const TRANSPARENT_MAT_PATH := "res://materials/ember_voxel_transparent.tres"
const SOURCE_SIGNATURE_META := "ember_source_signature"
const BUILD_CONTRACT := "normalized-block-v1"

static var _json_cache: Dictionary = {}


static func prefab_path(model_id: String) -> String:
	return "%s/%s.tscn" % [PREFAB_DIR, model_id]


static func mesh_path(model_id: String, shadow := false) -> String:
	var suffix := "_block_shadow" if shadow else "_block"
	return "%s/%s%s.res" % [MESH_DIR, model_id, suffix]


static func source_paths(model_id: String) -> Dictionary:
	var native_path := EmberVoxelCatalog.native_path(model_id)
	if FileAccess.file_exists(ProjectSettings.globalize_path(native_path)):
		return {"source": native_path, "json": native_path, "vox": "", "owner": "godot"}
	var json_path := EmberPack.model_json_path(model_id)
	var vox_path := ""
	var parsed: Variant = EmberPack.parse_json_file(json_path)
	if typeof(parsed) == TYPE_DICTIONARY:
		var mesh_raw: Variant = (parsed as Dictionary).get("mesh", {})
		if typeof(mesh_raw) == TYPE_DICTIONARY:
			var rel := str((mesh_raw as Dictionary).get("file", ""))
			if not rel.is_empty():
				var candidate := EmberPack.pack_root().path_join(rel.replace("\\", "/"))
				if FileAccess.file_exists(candidate):
					vox_path = candidate
	return {"source": json_path, "json": json_path, "vox": vox_path, "owner": "legacy_import"}


static func source_signature(model_id: String) -> String:
	var paths := source_paths(model_id)
	var json_path := str(paths["json"])
	if not FileAccess.file_exists(json_path):
		return ""
	var vox_path := str(paths["vox"])
	var vox_hash := FileAccess.get_sha256(vox_path) if not vox_path.is_empty() else "json-only"
	return (BUILD_CONTRACT + ":" + FileAccess.get_sha256(json_path) + ":" + vox_hash).sha256_text()


static func validate_packed(model_id: String, packed: PackedScene) -> Dictionary:
	var errors: Array[String] = []
	var checks: Array[String] = []
	if packed == null:
		return {"ok": false, "errors": ["PackedScene не загружен"], "checks": checks}
	var prefab := load_json(model_id)
	var model := model_of(prefab)
	if prefab.is_empty():
		errors.append("metadata .json не загружены")
	var root := packed.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
	if not root is EmberVoxelProp:
		if root:
			root.free()
		return {"ok": false, "errors": ["корень prefab не EmberVoxelProp"], "checks": checks}
	var prop := root as EmberVoxelProp
	if prop.model_id != model_id:
		errors.append("model_id prefab не совпадает")
	var expected_density := VoxMesher.voxels_per_block(model)
	if prop.voxels_per_block != expected_density:
		errors.append("плотность prefab не совпадает с metadata")
	elif not is_equal_approx(prop.block_world_size, 16.0):
		errors.append("prefab не хранит canonical world adapter 16")
	else:
		checks.append("%d vox/block" % expected_density)
	var expected_signature := source_signature(model_id)
	if expected_signature.is_empty() or str(prop.get_meta(SOURCE_SIGNATURE_META, "")) != expected_signature:
		errors.append("prefab собран не из текущих исходников")

	var visual := prop.get_node_or_null("Mesh") as MeshInstance3D
	if visual == null or visual.mesh == null:
		errors.append("нет Mesh")
	else:
		checks.append("Mesh")

	var collision := prop.get_node_or_null("Collision/Shape") as CollisionShape3D
	if bool(model.get("physical", false)):
		if collision == null or collision.shape == null:
			errors.append("physical-модель без Collision/Shape")
		else:
			checks.append("Collision")
	elif collision != null:
		errors.append("Collision создан для non-physical модели")

	var casts := bool(model.get("emissiveCastsLight", false))
	var omni := prop.get_node_or_null("Omni") as OmniLight3D
	if casts:
		if omni == null:
			errors.append("emissiveCastsLight без Omni")
		elif omni.shadow_enabled != bool(model.get("emissiveLightShadows", false)):
			errors.append("Omni shadow_enabled не совпадает с metadata")
		else:
			checks.append("Omni")
	else:
		if omni != null:
			errors.append("Omni создан для неэмиссивной модели")

	if casts and not bool(model.get("emissiveSuppressHostShadow", false)):
		var shadow_body := prop.get_node_or_null("ShadowBody") as MeshInstance3D
		var host_shadow_ok := shadow_body != null and shadow_body.mesh != null
		host_shadow_ok = host_shadow_ok or (visual != null and visual.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		if not host_shadow_ok:
			errors.append("источник света не имеет host shadow")
		else:
			checks.append("ShadowBody")
	prop.free()
	return {"ok": errors.is_empty(), "errors": errors, "checks": checks}


static func ensure_dirs() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MESH_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://materials"))


static func _save_with_stable_uid(resource: Resource, path: String) -> Error:
	var uid := resource_uid_from_header(path)
	if uid == ResourceUID.INVALID_ID:
		uid = ResourceLoader.get_resource_uid(path)
	if uid == ResourceUID.INVALID_ID:
		uid = ResourceUID.create_id()
	var err := ResourceSaver.save(resource, path)
	if err == OK:
		var uid_err := ResourceSaver.set_uid(path, uid)
		if uid_err != OK:
			push_error("ember prefab: cannot preserve uid %s (%s)" % [path, uid_err])
			return uid_err
	return err


static func resource_uid_from_header(path: String) -> int:
	if not FileAccess.file_exists(path):
		return ResourceUID.INVALID_ID
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ResourceUID.INVALID_ID
	var line := file.get_line()
	var marker := "uid=\""
	var start := line.find(marker)
	if start < 0:
		return ResourceUID.INVALID_ID
	start += marker.length()
	var finish := line.find("\"", start)
	if finish < 0:
		return ResourceUID.INVALID_ID
	return ResourceUID.text_to_id(line.substr(start, finish - start))


static func voxel_material() -> ShaderMaterial:
	if ResourceLoader.exists(MAT_PATH):
		return load(MAT_PATH) as ShaderMaterial
	ensure_dirs()
	var mat := EmberLights.voxel_material()
	ResourceSaver.save(mat, MAT_PATH)
	return load(MAT_PATH) as ShaderMaterial


static func voxel_transparent_material() -> ShaderMaterial:
	if ResourceLoader.exists(TRANSPARENT_MAT_PATH):
		return load(TRANSPARENT_MAT_PATH) as ShaderMaterial
	ensure_dirs()
	var mat := EmberLights.voxel_transparent_material()
	ResourceSaver.save(mat, TRANSPARENT_MAT_PATH)
	return load(TRANSPARENT_MAT_PATH) as ShaderMaterial


static func load_json(model_id: String) -> Dictionary:
	if _json_cache.has(model_id):
		return _json_cache[model_id]
	var prefab := EmberVoxelCatalog.definition(model_id)
	_json_cache[model_id] = prefab
	return prefab


static func model_of(prefab: Dictionary) -> Dictionary:
	var raw: Variant = prefab.get("model", {})
	return raw if typeof(raw) == TYPE_DICTIONARY else {}


static var _saved_this_pass: Dictionary = {}


static func begin_import() -> void:
	_saved_this_pass.clear()
	_json_cache.clear()


static func ensure_saved(
	model_id: String,
	tile_size: float,
	stats: Dictionary,
	force_rebuild := false,
) -> PackedScene:
	ensure_dirs()
	if not force_rebuild and _saved_this_pass.has(model_id):
		return _saved_this_pass[model_id]
	if not force_rebuild:
		var ready := _load_ready_prefab(model_id)
		if ready != null:
			_saved_this_pass[model_id] = ready
			return ready
	var packed := _write_prefab(model_id, tile_size, stats)
	_saved_this_pass[model_id] = packed
	return packed


static func _load_ready_prefab(model_id: String) -> PackedScene:
	var path := prefab_path(model_id)
	if not ResourceLoader.exists(path):
		return null
	var packed := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE) as PackedScene
	if packed == null:
		return null
	var report := validate_packed(model_id, packed)
	return packed if bool(report.get("ok", false)) else null


static func instantiate(model_id: String, tile_size: float, stats: Dictionary) -> EmberVoxelProp:
	var packed := ensure_saved(model_id, tile_size, stats)
	if packed == null:
		return null
	var edit := PackedScene.GEN_EDIT_STATE_DISABLED
	if Engine.is_editor_hint():
		edit = PackedScene.GEN_EDIT_STATE_INSTANCE
	var node := packed.instantiate(edit) as EmberVoxelProp
	if node == null:
		return null
	node.model_id = model_id
	node.configure_voxel_scale(node.voxels_per_block, tile_size)
	return node


static func make_preview_instance(model_id: String, tile_size := 16.0) -> EmberVoxelProp:
	# Uses the exact importer/mesher/material/tree contract without installing
	# mesh resources or writing a PackedScene. The caller owns the transient node.
	var prefab := load_json(model_id)
	if prefab.is_empty():
		return null
	var model := model_of(prefab)
	var vw := VoxMesher.normalized_voxel_size(model)
	var visual := _build_visual_mesh(model_id, prefab, vw, {})
	if visual == null:
		return null
	_apply_visual_materials(visual)
	var size := _ember_size(model_id, prefab, visual)
	return _make_tree(model_id, model, size, vw, tile_size, visual, null)


static func preview_source_revision(model_id: String) -> String:
	var paths := source_paths(model_id)
	var json_path := str(paths.get("json", ""))
	var vox_path := str(paths.get("vox", ""))
	return "%d:%d" % [
		FileAccess.get_modified_time(json_path) if FileAccess.file_exists(json_path) else 0,
		FileAccess.get_modified_time(vox_path) if FileAccess.file_exists(vox_path) else 0,
	]


static func _write_prefab(model_id: String, tile_size: float, stats: Dictionary) -> PackedScene:
	var prefab := load_json(model_id)
	var model := model_of(prefab)
	var density := VoxMesher.voxels_per_block(model)
	var vw := 1.0 / float(density)
	var visual := _build_visual_mesh(model_id, prefab, vw, stats)
	if visual == null:
		return null
	_apply_visual_materials(visual)
	var size := _ember_size(model_id, prefab, visual)
	visual = _install_mesh_resource(visual, mesh_path(model_id, false))
	if visual == null:
		return null
	var body := _body_mesh(model_id, prefab, model, vw, size)
	if body != null:
		body = _install_mesh_resource(body, mesh_path(model_id, true))
		if body == null:
			return null
	# PackedScene stays context-free at the legacy/world adapter. Every caller
	# can apply its own block size without rebuilding the normalized mesh.
	var root := _make_tree(model_id, model, size, vw, 16.0, visual, body)
	root.set_meta(SOURCE_SIGNATURE_META, source_signature(model_id))
	_set_pack_owner(root, root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	root.free()
	if err != OK:
		push_error("ember prefab: pack failed %s (%s)" % [model_id, err])
		return null
	var path := prefab_path(model_id)
	var save_err := _save_with_stable_uid(packed, path)
	if save_err != OK:
		push_error("ember prefab: save failed %s (%s)" % [model_id, save_err])
		return null
	var from_disk := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	return from_disk if from_disk else packed


static func _install_mesh_resource(built: ArrayMesh, path: String) -> ArrayMesh:
	var live: ArrayMesh = null
	if FileAccess.file_exists(ProjectSettings.globalize_path(path)):
		live = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE) as ArrayMesh
	if live != null:
		_copy_mesh_surfaces(live, built)
		if _save_with_stable_uid(live, path) != OK:
			return null
		live.emit_changed()
		return live
	if _save_with_stable_uid(built, path) != OK:
		return null
	# On first import Godot's ResourceLoader may not know the freshly written
	# binary .res until the editor filesystem scan. Keep the built resource as
	# the live cached identity instead of immediately reopening the same path.
	built.take_over_path(path)
	return built


static func _copy_mesh_surfaces(target: ArrayMesh, source: ArrayMesh) -> void:
	target.clear_surfaces()
	for surface in source.get_surface_count():
		target.add_surface_from_arrays(
			source.surface_get_primitive_type(surface),
			source.surface_get_arrays(surface),
		)
		target.surface_set_material(surface, source.surface_get_material(surface))
		target.surface_set_name(surface, source.surface_get_name(surface))


static func _apply_visual_materials(mesh: ArrayMesh) -> void:
	var opaque := voxel_material()
	var transparent := voxel_transparent_material()
	for surface in mesh.get_surface_count():
		mesh.surface_set_material(
			surface,
			transparent if mesh.surface_get_name(surface) == "transparent" else opaque,
		)


static func _set_pack_owner(node: Node, scene_owner: Node) -> void:
	for child in node.get_children():
		child.owner = scene_owner
		_set_pack_owner(child, scene_owner)


static func _ember_size(model_id: String, prefab: Dictionary, _visual: ArrayMesh) -> Vector3i:
	if bool(prefab.get("_nativeGodotVoxel", false)):
		return VoxMesher.ember_grid_size(model_of(prefab))
	var mesh_raw: Variant = prefab.get("mesh", {})
	var mesh_info: Dictionary = mesh_raw if typeof(mesh_raw) == TYPE_DICTIONARY else {}
	var rel := str(mesh_info.get("file", "voxels/models/%s.vox" % model_id))
	var vox_path := EmberPack.pack_root().path_join(rel.replace("\\", "/"))
	if FileAccess.file_exists(vox_path):
		var doc := VoxParser.parse_file(vox_path)
		if not doc.is_empty():
			return VoxMesher.ember_size(doc.models[0].size)
	return VoxMesher.ember_grid_size(model_of(prefab))


static func _build_visual_mesh(
	model_id: String,
	prefab: Dictionary,
	vw: float,
	stats: Dictionary,
) -> ArrayMesh:
	var model := model_of(prefab)
	var from_vox := _mesh_from_vox(model_id, prefab, model, vw)
	if from_vox != null:
		stats["vox_mesh"] = int(stats.get("vox_mesh", 0)) + 1
		return from_vox
	var from_json := _mesh_from_json(prefab, vw)
	if from_json != null:
		stats["json_mesh"] = int(stats.get("json_mesh", 0)) + 1
		return from_json
	stats["missing_mesh"] = int(stats.get("missing_mesh", 0)) + 1
	return null


static func _mesh_from_vox(
	model_id: String,
	prefab: Dictionary,
	model: Dictionary,
	vw: float,
) -> ArrayMesh:
	if bool(prefab.get("_nativeGodotVoxel", false)):
		return null
	var mesh_raw: Variant = prefab.get("mesh", {})
	var mesh_info: Dictionary = mesh_raw if typeof(mesh_raw) == TYPE_DICTIONARY else {}
	var rel := str(mesh_info.get("file", "voxels/models/%s.vox" % model_id))
	var vox_path := EmberPack.pack_root().path_join(rel.replace("\\", "/"))
	if not FileAccess.file_exists(vox_path):
		return null
	var doc := VoxParser.parse_file(vox_path)
	if doc.is_empty():
		return null
	var mesh := VoxMesher.build_mesh(doc, vw, PackedByteArray(), VoxMesher.model_channel(model, "transparency"))
	if mesh.get_surface_count() == 0:
		return null
	return mesh


static func _mesh_from_json(prefab: Dictionary, vw: float) -> ArrayMesh:
	var mesh := VoxMesher.build_from_ember_model(model_of(prefab), vw)
	if mesh.get_surface_count() == 0:
		return null
	return mesh


static func _body_mesh(
	model_id: String,
	prefab: Dictionary,
	model: Dictionary,
	vw: float,
	size: Vector3i,
) -> ArrayMesh:
	var skip := EmberVoxelLight.skip_mask(model, size)
	if skip.is_empty():
		return null
	if bool(prefab.get("_nativeGodotVoxel", false)):
		var native_body := VoxMesher.build_from_ember_model(model, vw, skip)
		return native_body if native_body.get_surface_count() > 0 else null
	var mesh_raw: Variant = prefab.get("mesh", {})
	var mesh_info: Dictionary = mesh_raw if typeof(mesh_raw) == TYPE_DICTIONARY else {}
	var rel := str(mesh_info.get("file", "voxels/models/%s.vox" % model_id))
	var vox_path := EmberPack.pack_root().path_join(rel.replace("\\", "/"))
	if FileAccess.file_exists(vox_path):
		var doc := VoxParser.parse_file(vox_path)
		if not doc.is_empty():
			var built := VoxMesher.build_mesh(doc, vw, skip)
			if built.get_surface_count() > 0:
				return built
	var from_json := VoxMesher.build_from_ember_model(model, vw, skip)
	if from_json.get_surface_count() > 0:
		return from_json
	return null


static func _make_tree(
	model_id: String,
	model: Dictionary,
	size: Vector3i,
	vw: float,
	tile_size: float,
	visual_mesh: ArrayMesh,
	shadow_mesh: ArrayMesh,
) -> EmberVoxelProp:
	var w := size.x * vw
	var d := size.z * vw
	var inner_pos := Vector3(-w * 0.5, 0.0, -d * 0.5)
	var root := EmberVoxelProp.new()
	root.name = model_id
	root.model_id = model_id
	root.voxels_per_block = VoxMesher.voxels_per_block(model)
	root.block_world_size = tile_size
	var visual := MeshInstance3D.new()
	visual.name = "Mesh"
	visual.mesh = visual_mesh
	visual.position = inner_pos
	visual.set_meta("ember_block_position", inner_pos)
	var casts := bool(model.get("emissiveCastsLight", false))
	var suppress := bool(model.get("emissiveSuppressHostShadow", false))
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if casts:
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if not suppress and shadow_mesh != null:
			var body_mi := MeshInstance3D.new()
			body_mi.name = "ShadowBody"
			body_mi.mesh = shadow_mesh
			body_mi.position = inner_pos
			body_mi.set_meta("ember_block_position", inner_pos)
			body_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			body_mi.layers = EmberLights.SHADOW_LAYER_LAMP_HOST
			root.add_child(body_mi)
		elif not suppress:
			visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(visual)
	if bool(model.get("physical", false)) and visual.mesh != null:
		var body := StaticBody3D.new()
		body.name = "Collision"
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		shape.shape = visual.mesh.create_trimesh_shape()
		shape.position = inner_pos
		shape.set_meta("ember_block_position", inner_pos)
		body.add_child(shape)
		root.add_child(body)
	if casts:
		_add_omni_slot(root, model, inner_pos, size, vw)
	root.configure_voxel_scale(root.voxels_per_block, tile_size)
	return root


static func _add_omni_slot(
	root: Node3D,
	model: Dictionary,
	inner_pos: Vector3,
	size: Vector3i,
	vw: float,
) -> void:
	var shadows := bool(model.get("emissiveLightShadows", false))
	var range_tiles := float(model.get("emissiveLightRange", 2.0))
	var strength := float(model.get("emissiveStrength", 0.75))
	var sum := EmberVoxelLight.summarize(model)
	var local := Vector3(0.0, size.y * vw * 0.72, 0.0)
	if not sum.is_empty():
		var cx := float(sum["cx"])
		var cy := float(sum["cy"])
		var cz := float(sum["cz"])
		var off_raw: Variant = model.get("emissiveLightOffset", {})
		if typeof(off_raw) == TYPE_DICTIONARY:
			var off: Dictionary = off_raw
			cx += float(off.get("x", 0))
			cy += float(off.get("y", 0))
			cz += float(off.get("z", 0))
		local = EmberVoxelLight.local_from_cell(inner_pos, cx, cy, cz, vw)
	var light := EmberLights.make_omni(
		"Omni",
		local,
		Color(1.0, 0.69, 0.34),
		range_tiles,
		strength,
		shadows,
		1.0,
	)
	light.set_meta("ember_block_position", local)
	light.set_meta("ember_range_blocks", maxf(1.0, range_tiles))
	root.add_child(light)
