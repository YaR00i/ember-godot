extends SceneTree
const Fixture = preload("res://tools/fixtures/ember_mixed_editor_test_fixture.gd")

func _init() -> void:
	if not Fixture.prepare_profile(self):
		quit(2)
		return
	var source := ResourceLoader.load("res://content/world_surfaces/editor_profile_surface.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource
	var errors: Array[String] = source.validation_errors()
	if source.grid_size() != Vector3i(384, 32, 384): errors.append("performance footprint changed")
	for x in range(20, 60):
		if EmberVoxelSurfaceMesher.water_height_at(source, Vector2i(x, 32)) >= 0: errors.append("dry stroke line is wet")
		if EmberVoxelSurfaceMesher.water_height_at(source, Vector2i(x, 256)) < 0: errors.append("wet stroke line is dry")
	for path in ["res://tools/qa_voxel_editor_edit_cost.gd", "res://tools/qa_voxel_editor_performance_ab.gd"]:
		if ResourceLoader.load(path) == null: errors.append("performance diagnostic could not parse " + path)
	var packed := ResourceLoader.load("res://scenes/editor_context_fixture.tscn") as PackedScene
	var context := packed.instantiate()
	var map := context.get_node("Map") as EmberMapLoader
	if map.visual_surface == null or map.authored_size_blocks != Vector2i(4, 4) or context.get_node_or_null("Map/Props/plain_prop") == null: errors.append("object context fixture lost surface/prop owner")
	context.free()
	Fixture.verify_sources(errors)
	if not errors.is_empty():
		printerr("FAIL native performance fixture: ", "; ".join(errors))
		quit(1)
		return
	print("PASS native performance fixtures; 24x24/16/32, dry+wet 40-cell lines, saved object context, diagnostics parse")
	quit(0)
