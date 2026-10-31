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
