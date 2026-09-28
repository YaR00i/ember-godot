extends SceneTree

const Creation = preload("res://addons/ember_import/ember_compact_map_creation.gd")
const Dialog = preload("res://addons/ember_import/ember_compact_map_dialog.gd")
const TerrainResource = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Brush = preload("res://addons/ember_import/ember_compact_terrain_brush.gd")
const DIRECTORY := "user://compact_map_coast_test"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var creation := _creation()
	assert(not creation.prepare_coast_sections("invalid_coast", 2, 2, 16, 16, 16, 371))
	assert(creation.prepare_coast_sections("coast_fixture", 2, 2, 32, 16, 16, 371), creation.error)
	var terrain: TerrainResource = creation.source
	assert(terrain.width == 768 and terrain.depth == 768)
	assert(terrain.validation_errors().is_empty())
	var land := 0
	var sand := 0
	var water := 0
	var max_seam_delta := 0
	for z in range(0, terrain.depth, 8):
		for x in range(0, terrain.width, 8):
			var index := x + z * terrain.width
			var ground := terrain.heights[index]
			assert(ground % 4 == 0)
			assert(terrain.heights[index + 7 + 7 * terrain.width] == ground)
			if terrain.water_levels[index] > ground:
				water += 1
				assert(terrain.water_materials[index] == 5)
			elif terrain.top_materials[index] == 3:
				sand += 1
			else:
				land += 1
		max_seam_delta = maxi(max_seam_delta, absi(terrain.heights[383 + z * terrain.width] - terrain.heights[384 + z * terrain.width]))
	for x in range(0, terrain.width, 8):
		max_seam_delta = maxi(max_seam_delta, absi(terrain.heights[x + 383 * terrain.width] - terrain.heights[x + 384 * terrain.width]))
	assert(land > 0 and sand > 0 and water > 0)
	assert(max_seam_delta <= 8)
	var repeated := _creation()
	assert(repeated.prepare_coast_sections("coast_repeat", 2, 2, 32, 16, 16, 371), repeated.error)
	assert(repeated.source.heights == terrain.heights and repeated.source.top_materials == terrain.top_materials and repeated.source.water_levels == terrain.water_levels)
	var other_seed := _creation()
	assert(other_seed.prepare_coast_sections("coast_other", 2, 2, 32, 16, 16, 372), other_seed.error)
	assert(other_seed.source.heights != terrain.heights)
	var large := _creation()
	var large_started := Time.get_ticks_msec()
	assert(large.prepare_coast_sections("coast_large", 4, 4, 32, 16, 16, 371), large.error)
	var large_prepare_ms := Time.get_ticks_msec() - large_started
	assert(large.source.width == 1536 and large.source.depth == 1536 and large.source.validation_errors().is_empty())
	large.source = null
	var path := creation.commit()
	assert(not path.is_empty(), creation.error)
	var saved := ResourceLoader.load(creation.terrain_path(), "", ResourceLoader.CACHE_MODE_IGNORE) as TerrainResource
	assert(saved != null and saved.validation_errors().is_empty() and saved.heights == terrain.heights)
	var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	assert(packed != null)
	var scene := packed.instantiate()
	var map := scene.get_node("Map") as EmberMapLoader
	assert(map != null and map.compact_terrain != null)
	root.add_child(scene)
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	while projection.pending_tile_count() > 0:
		await process_frame
	var undo := UndoRedo.new()
	var brush := Brush.new()
	var editable := saved.working_copy()
	brush.configure({"target": weakref(map), "resource": editable}, undo, map)
	var center := Vector2i(terrain.width / 2, terrain.depth * 3 / 4)
	var sample_index := center.x + center.y * terrain.width
	var initial_height := editable.heights[sample_index]
	var floor_sample := map.surface_floor_sample(Vector3(center.x + 0.5, 0, center.y + 0.5))
	assert(floor_sample.solid and is_equal_approx(floor_sample.position.y, float(initial_height)))
	var sea_sample := projection.water_surface_sample(Vector3(terrain.width * 0.5, 0, terrain.depth * 0.1))
	assert(sea_sample.wet)
	assert(brush.begin("raise", 0.5, 4, 2, 0, 16, 0, 371, 0, -99999, "coarse", "square", 4))
	brush.stamp(center)
	brush.end()
	assert(editable.heights[sample_index] > initial_height)
	undo.undo()
	assert(editable.heights[sample_index] == initial_height)
	undo.clear_history()
	undo.free()
	var dialog := Dialog.new()
	root.add_child(dialog)
	dialog.creation.scene_directory = DIRECTORY.path_join("dialog_scenes")
	dialog.creation.terrain_directory = DIRECTORY.path_join("dialog_terrains")
	dialog._id_field.text = "coast_dialog"
	dialog._preset.select(1)
	dialog._preset_changed(1)
	dialog._prepare()
	assert(not dialog.get_ok_button().disabled and dialog._texture.visible and dialog._texture.texture != null)
	dialog._seed.value = 372
	await process_frame
	assert(dialog.get_ok_button().disabled)
	dialog.free()
	scene.queue_free()
	await process_frame
	for file in [path, creation.terrain_path()]:
		assert(DirAccess.remove_absolute(ProjectSettings.globalize_path(file)) == OK)
	print("COMPACT_MAP_COAST coast=ok sections=2x2 seam_delta=", max_seam_delta, " sand=", sand, " water=", water, " land=", land, " deterministic=ok save_reopen=ok brush_undo=ok dialog=ok large_prepare_ms=", large_prepare_ms)
	quit()


func _creation() -> Creation:
	var result := Creation.new()
	result.scene_directory = DIRECTORY.path_join("scenes")
	result.terrain_directory = DIRECTORY.path_join("terrains")
	return result
