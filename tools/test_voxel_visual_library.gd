extends SceneTree
## Voxel visual-library contract: native Godot owners and the legacy import
## queue share one projection; only a chosen prefab is instantiated.

const Catalog = preload("res://scripts/ember_voxel_catalog.gd")
const Visuals = preload("res://scripts/ember_voxel_visuals.gd")
const SceneAuthoring = preload("res://scripts/ember_scene_authoring.gd")
const TEMP_PATH := "user://ember_voxel_visual_library_roundtrip.tscn"


func _init() -> void:
	quit(_run())


func _run() -> int:
	var errors: Array[String] = []
	var definitions := Catalog.definitions()
	var entries := Visuals.entries()
	if definitions.is_empty() or entries.size() != definitions.size():
		errors.append("visual projection does not cover the resolved model catalog")
	var native_entry := _entry_by_id(entries, "vox_fan_anvil")
	if str(native_entry.get("owner", "")) != "godot" or not bool(native_entry.get("migrated", false)):
		errors.append("visual library does not expose native migration ownership")
	if str(native_entry.get("title", "")).is_empty() or str(native_entry.get("scale", "")).is_empty():
		errors.append("visual library does not expose object-shelf title and scale metadata")
	if not native_entry.get("tags", []) is Array:
		errors.append("visual library does not expose searchable object tags")
	var ready_entry := _first_ready(entries)
	if ready_entry.is_empty():
		errors.append("catalog has no existing PackedScene available for visual placement")
	else:
		_test_scene_owned_roundtrip(ready_entry, errors)
	if not errors.is_empty():
		printerr("FAIL voxel visual library")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS voxel visual library")
	print("  canonical models: ", entries.size())
	print("  native preview target: ", ready_entry.get("previewPath", ""))
	print("  selected prefab survives authored scene save/reopen")
	return 0


func _first_ready(entries: Array[Dictionary]) -> Dictionary:
	for entry in entries:
		if bool(entry.get("ready", false)):
			return entry
	return {}


func _entry_by_id(entries: Array[Dictionary], model_id: String) -> Dictionary:
	for entry in entries:
		if str(entry.get("id", "")) == model_id:
			return entry
	return {}


func _test_scene_owned_roundtrip(entry: Dictionary, errors: Array[String]) -> void:
	var model_id := str(entry.get("id", ""))
	var prefab_path := str(entry.get("previewPath", ""))
	if model_id.is_empty() or not ResourceLoader.exists(prefab_path):
		errors.append("ready catalog entry has no stable ID or resource path")
		return
	var packed := ResourceLoader.load(prefab_path, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	var scene_root := Node3D.new()
	scene_root.name = "VoxelLibraryTest"
	var map := Node3D.new()
	map.name = "Map"
	scene_root.add_child(map)
	map.owner = scene_root
	var props := Node3D.new()
	props.name = "Props"
	map.add_child(props)
	props.owner = scene_root
	var expected_position := Vector3(16.0, 2.0, -8.0)
	var prop := SceneAuthoring.make_model_instance(
		scene_root,
		packed,
		model_id,
		expected_position,
	)
	if prop == null:
		errors.append("selected prefab could not be instantiated")
		scene_root.free()
		return
	var placement_id := prop.placement_id
	SceneAuthoring.attach_model_instance(scene_root, props, prop)
	if placement_id.is_empty() or prop.owner != scene_root or prop.get_parent() != props:
		errors.append("new prefab is not a scene-owned Map/Props child")
	var staged := PackedScene.new()
	if staged.pack(scene_root) != OK or ResourceSaver.save(staged, TEMP_PATH) != OK:
		errors.append("authored voxel scene could not be saved")
	scene_root.free()

	var reopened_packed := ResourceLoader.load(TEMP_PATH, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	var reopened := reopened_packed.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED) if reopened_packed else null
	var saved := _find_prop(reopened, placement_id)
	if saved == null:
		errors.append("selected prefab did not survive save/reopen")
	else:
		if saved.model_id != model_id or not saved.position.is_equal_approx(expected_position):
			errors.append("selected prefab lost model ID or authored transform")
	if reopened != null:
		reopened.free()
	var temp_absolute := ProjectSettings.globalize_path(TEMP_PATH)
	if FileAccess.file_exists(temp_absolute):
		DirAccess.remove_absolute(temp_absolute)


func _find_prop(node: Node, placement_id: String) -> EmberVoxelProp:
	if node == null:
		return null
	if node is EmberVoxelProp and (node as EmberVoxelProp).placement_id == placement_id:
		return node as EmberVoxelProp
	for child in node.get_children():
		var found := _find_prop(child, placement_id)
		if found != null:
			return found
	return null
