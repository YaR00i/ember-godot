extends SceneTree
## Isolated contract test: never loads or saves an authored Surface.

const Macro = preload("res://tools/prototypes/ember_macro_terrain_2_5d.gd")

var failures: Array[String] = []


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _surface() -> EmberVoxelModelResource:
	var result := EmberVoxelModelResource.new()
	result.model_id = "macro_contract_fixture"
	result.display_name = "Disposable Macro contract fixture"
	result.size_blocks = Vector3i(4, 1, 4)
	result.height_voxels = 32
	result.palette = PackedColorArray([Color.TRANSPARENT, Color.BROWN, Color.GREEN, Color.SANDY_BROWN, Color.GRAY])
	result.voxels.resize(64 * 64 * 32)
	result.voxels.fill(1)
	result.surface_fill_levels.resize(64 * 64)
	result.surface_fill_levels.fill(18)
	result.surface_fill_materials.resize(64 * 64)
	result.surface_fill_materials.fill(1)
	result.surface_fill_palette.resize(64 * 64)
	return result


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var macro := Macro.new()
	macro.configure(Vector2i(4, 4), 32, 3817)
	_check(macro.width == 32 and macro.depth == 32, "Macro grid must be exactly 8 samples/block")
	var original := _surface()
	var edited := original.duplicate_model()
	macro.set_fine_override(Vector3i(29, 23, 31), 4) # manual addition
	macro.set_fine_override(Vector3i(32, 2, 31), 0) # manual deletion
	macro.apply_level_segment(Vector3i(26, 10, 27), Vector3i(36, 10, 34), 10, 12)
	var chunks: Array[Vector2i] = macro.dirty_target_chunks()
	_check(chunks.size() >= 2, "stroke should cross a Macro-region boundary")
	macro.bake_chunks(edited, chunks)
	var values := edited.voxels
	var size := edited.grid_size()
	var added := 29 + 31 * size.x + 23 * size.x * size.z
	var removed := 32 + 31 * size.x + 2 * size.x * size.z
	_check(values[added] == 4 and values[removed] == 0, "Fine additions/deletions must override generated terrain")
	var first := values.duplicate()
	macro.bake_chunks(edited, chunks)
	_check(edited.voxels == first, "rebake of unchanged state must be byte-identical")
	chunks.reverse()
	var reverse := original.duplicate_model()
	macro.bake_chunks(reverse, chunks)
	_check(reverse.voxels == first, "region order and halo must not change fine output")
	macro.bake_chunks(edited, [Vector2i(1, 0), Vector2i(0, 0)])
	_check(edited.voxels[added] == 4 and edited.voxels[removed] == 0, "neighbor rebake destroyed manual Fine overrides")
	var full := original.duplicate_model()
	macro.bake_chunks(full, macro.all_chunks())
	var partial := original.duplicate_model()
	macro.bake_chunks(partial, macro.all_chunks())
	macro.clear_dirty()
	macro.apply_level_segment(Vector3i(31, 14, 31), Vector3i(33, 14, 31), 14, 3)
	macro.bake_chunks(full, macro.all_chunks())
	macro.bake_chunks(partial, macro.dirty_target_chunks())
	_check(partial.voxels == full.voxels, "dirty bake differs from full bake across a region seam")
	_check(partial.surface_fill_levels == original.surface_fill_levels and partial.surface_fill_materials == original.surface_fill_materials and partial.surface_fill_palette == original.surface_fill_palette, "Macro bake changed the water layer")
	macro.set_semantic_control(Vector2i(15, 15), 2)
	var explicit_sand := original.duplicate_model()
	macro.bake_chunks(explicit_sand, macro.all_chunks())
	_check(explicit_sand.voxels != full.voxels, "explicit material semantic had no fine effect")
	var other_seed := Macro.new()
	other_seed.configure(Vector2i(4, 4), 32, 3818)
	other_seed.apply_level_segment(Vector3i(26, 10, 27), Vector3i(36, 10, 34), 10, 12)
	var other_result := original.duplicate_model()
	other_seed.bake_chunks(other_result, other_seed.all_chunks())
	var same_seed := Macro.new()
	same_seed.configure(Vector2i(4, 4), 32, 3817)
	same_seed.apply_level_segment(Vector3i(26, 10, 27), Vector3i(36, 10, 34), 10, 12)
	var same_result := original.duplicate_model()
	same_seed.bake_chunks(same_result, same_seed.all_chunks())
	_check(other_result.voxels != same_result.voxels, "coordinate seed does not affect slope breakup")
	if failures.is_empty():
		print("PASS Macro 2.5D: density, deterministic seed, halo, regional equality, add/delete overrides")
	else:
		for message in failures:
			printerr("FAIL Macro 2.5D: ", message)
	quit(0 if failures.is_empty() else 1)
