@tool
extends EditorExportPlugin
const Bundle = preload("res://scripts/prototypes/ember_terrain_prepared_bundle.gd")
const Plan = preload("res://scripts/ember_terrain_plan_resource.gd")

func _get_name() -> String: return "EmberPreparedTerrain"

func _begin_customize_scenes(_platform: EditorExportPlatform, _features: PackedStringArray) -> bool: return true

func _get_customization_configuration_hash() -> int: return 2 # Scene plan plus grove member provenance.

func _customize_scene(scene: Node, _path: String) -> Node:
	return scene if strip_authoring_plan(scene) else null

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
	print("TERRAIN_EXPORT_READY files=", prepared.files.size(), " bytes=", prepared.manifest.total_bytes)
