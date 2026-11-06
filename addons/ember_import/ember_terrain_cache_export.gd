@tool
extends EditorExportPlugin
const Bundle = preload("res://scripts/prototypes/ember_terrain_prepared_bundle.gd")
const Plan = preload("res://scripts/ember_terrain_plan_resource.gd")
const TreeSpecies = preload("res://scripts/ember_tree_species.gd")

func _get_name() -> String: return "EmberPreparedTerrain"

func _begin_customize_scenes(_platform: EditorExportPlatform, _features: PackedStringArray) -> bool: return true

func _get_customization_configuration_hash() -> int: return 4 # Omit regenerated solid surface materials too.

func _customize_scene(scene: Node, _path: String) -> Node:
	var changed := strip_authoring_plan(scene)
	changed = strip_derived_material_overrides(scene) or changed
	return scene if changed else null

static func strip_derived_material_overrides(node: Node) -> bool:
	var changed := false
	if node is MeshInstance3D and node.material_override!=null and node.material_override.get_meta("ember_derived_solid_material",false):
		# Prop.refresh_solid_material rebuilds this disposable override before
		# play. Serializing its GPU lookup banks loses Image layers on export.
		node.material_override=null
		changed=true
	if node is MeshInstance3D and node.mesh is ArrayMesh and node.mesh.has_meta("solid_surface_material_ids"):
		var copy:ArrayMesh
		for surface in node.mesh.get_surface_count():
			var material:Material=node.mesh.surface_get_material(surface)
			if material!=null and material.get_meta("ember_derived_solid_material",false):
				if copy==null:copy=node.mesh.duplicate() as ArrayMesh
				copy.surface_set_material(surface,null)
		if copy!=null:node.mesh=copy;changed=true
	for child in node.get_children():changed=strip_derived_material_overrides(child) or changed
	return changed

static func strip_authoring_plan(node: Node) -> bool:
	var changed := node.has_meta(Plan.META)
	if changed: node.remove_meta(Plan.META)
	for key in [Plan.GROVE_MEMBER_META,Plan.GROVE_GROUP_META]:
		if node.has_meta(key): node.remove_meta(key); changed = true
	for child in node.get_children(): changed = strip_authoring_plan(child) or changed
	return changed

func _export_begin(_features: PackedStringArray, _debug: bool, _path: String, _flags: int) -> void:
	_export_main_object_meshes()
	if not FileAccess.file_exists(Bundle.ROOT.path_join("manifest.json")): return
	var prepared := Bundle.inspect(Bundle.ROOT)
	if not prepared.error.is_empty():
		push_warning("Prepared terrain was skipped; ordinary runtime build remains available: " + prepared.error)
		return
	for file: Dictionary in prepared.files:
		add_file(file.target, FileAccess.get_file_as_bytes(file.source), false)
	# Tree cache keys include the original artwork bytes. Imported .ctex data
	# alone cannot satisfy FileAccess.get_sha256 on these PNG source paths.
	var artwork := {}
	for path in TreeSpecies.LEAF_ART + TreeSpecies.BARK_ART:artwork[path]=true
	for path in artwork:
		if FileAccess.file_exists(path):add_file(path,FileAccess.get_file_as_bytes(path),false)
	print("TERRAIN_EXPORT_READY files=", prepared.files.size(), " bytes=", prepared.manifest.total_bytes)

func _export_main_object_meshes() -> void:
	var source_path := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	if source_path.is_empty(): return
	var source := ResourceLoader.load(source_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	if source == null: return
	var scene := source.instantiate()
	var map := scene.get_node_or_null("Map") as EmberMapLoader
	if map != null:
		var catalog := {}
		var published := {}
		var temp := "user://ember-export-mesh-%s-%s.res" % [OS.get_process_id(), Time.get_ticks_usec()]
		for node in map.find_children("*", "Node3D", true, false):
			var prop := node as EmberVoxelProp
			if prop == null: continue
			var mesh := prop.bake_packed_detail_mesh()
			if mesh == null: continue
			if ResourceSaver.save(mesh, temp, ResourceSaver.FLAG_BUNDLE_RESOURCES) != OK:
				push_warning("Cannot pack detailed mesh for " + str(map.get_path_to(prop)))
				continue
			var bytes := FileAccess.get_file_as_bytes(temp)
			var key := Bundle.Storage.checksum(bytes).hex_encode()
			var path := "res://ember-prepared/objects/" + key + ".res"
			if not published.has(path):
				add_file(path, bytes, false)
				published[path] = bytes.size()
			catalog[str(map.get_path_to(prop))] = [prop.model_id, path]
		if FileAccess.file_exists(temp): DirAccess.remove_absolute(temp)
		add_file(EmberMapLoader.PACKED_OBJECT_INDEX, JSON.stringify({"scene":source.resource_path,"props":catalog}).to_utf8_buffer(), false)
		print("OBJECT_MESH_EXPORT_READY instances=", catalog.size(), " meshes=", published.size())
	scene.free()
