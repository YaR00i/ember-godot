extends SceneTree
## Wave 3 smoke: scene-owned move/rotate/duplicate survives save/reopen without
## touching the authored scene or JOI pack. The test writes only to user://.

const MAP_PATH := "res://scenes/fan_town.tscn"
const MAP_ID := "fan_town"
const SOURCE_PLACEMENT_ID := "ft_inn_door"
const TEMP_PATH := "user://ember_wave3_scene_roundtrip.tscn"
const TILE_SIZE := 16.0
const SceneAuthoring = preload("res://scripts/ember_scene_authoring.gd")


func _init() -> void:
	quit(_run())


func _run() -> int:
	var errors: Array[String] = []
	var scene_hash_before := FileAccess.get_sha256(MAP_PATH)
	var pack_hash_before := FileAccess.get_sha256(EmberPack.map_path(MAP_ID))
	var source_packed := ResourceLoader.load(MAP_PATH, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	var root := source_packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) if source_packed else null
	if root == null:
		printerr("FAIL scene edit roundtrip: source scene unavailable")
		return 1
	var source := _find_prop(root, SOURCE_PLACEMENT_ID)
	if source == null:
		errors.append("контрольная дверь не найдена")
	var prop_count_before := _prop_count(root)
	var duplicate: EmberVoxelProp = null
	var expected_transform := Transform3D.IDENTITY
	var expected_id := ""
	var expected_model_id := ""
	if source:
		expected_model_id = source.model_id
		duplicate = SceneAuthoring.make_duplicate(root, source, Vector3(TILE_SIZE, 0.0, 0.0))
		if duplicate == null:
			errors.append("safe duplicate не создан")
		else:
			expected_id = duplicate.placement_id
			duplicate.rotation.y += PI * 0.5
			expected_transform = duplicate.transform
			SceneAuthoring.attach_duplicate(root, source, source.get_parent(), duplicate)
			if source.get_node_or_null("Interact") != null and duplicate.get_node_or_null("Interact") == null:
				errors.append("duplicate потерял вложенный Interact до save")

	var staged := PackedScene.new()
	var pack_err := staged.pack(root)
	if pack_err != OK:
		errors.append("не удалось pack временной сцены (%s)" % pack_err)
	elif ResourceSaver.save(staged, TEMP_PATH) != OK:
		errors.append("не удалось сохранить временную сцену")
	root.free()

	var reopened_packed := ResourceLoader.load(TEMP_PATH, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	var reopened := reopened_packed.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED) if reopened_packed else null
	if reopened == null:
		errors.append("временная сцена не открылась повторно")
	else:
		var saved_duplicate := _find_prop(reopened, expected_id)
		if saved_duplicate == null:
			errors.append("duplicate не пережил save/reopen")
		else:
			if saved_duplicate.model_id != expected_model_id:
				errors.append("duplicate потерял model_id")
			if not saved_duplicate.transform.is_equal_approx(expected_transform):
				errors.append("move/rotate не пережили save/reopen")
			if saved_duplicate.get_node_or_null("Interact") == null:
				errors.append("вложенный Interact не пережил save/reopen")
		if _prop_count(reopened) != prop_count_before + 1:
			errors.append("save/reopen изменил число props не на один")
		if SceneAuthoring.placement_ids(reopened).size() != _prop_count(reopened):
			errors.append("после duplicate есть пустые или повторяющиеся placement_id")
		reopened.free()

	if FileAccess.get_sha256(MAP_PATH) != scene_hash_before:
		errors.append("roundtrip изменил исходный .tscn")
	if FileAccess.get_sha256(EmberPack.map_path(MAP_ID)) != pack_hash_before:
		errors.append("roundtrip изменил JOI map JSON")
	var temp_absolute := ProjectSettings.globalize_path(TEMP_PATH)
	if FileAccess.file_exists(temp_absolute):
		DirAccess.remove_absolute(temp_absolute)

	if not errors.is_empty():
		printerr("FAIL scene edit roundtrip")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS scene edit roundtrip")
	print("  duplicate placement: ", expected_id)
	print("  move + rotate + Interact survived save/reopen")
	print("  source .tscn and JOI map JSON preserved")
	return 0


func _find_prop(node: Node, placement_id: String) -> EmberVoxelProp:
	if node == null:
		return null
	if node is EmberVoxelProp and (node as EmberVoxelProp).placement_id == placement_id:
		return node as EmberVoxelProp
	for child in node.get_children():
		var found := _find_prop(child, placement_id)
		if found:
			return found
	return null


func _prop_count(node: Node) -> int:
	if node == null:
		return 0
	var count := 1 if node is EmberVoxelProp else 0
	for child in node.get_children():
		count += _prop_count(child)
	return count
