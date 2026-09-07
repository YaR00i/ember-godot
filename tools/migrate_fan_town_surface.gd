extends SceneTree
## Guarded one-shot G3 migration. Dry-run is the default; --apply writes only
## the canonical Surface Resource after exact legacy height/material parity.

const MAP_ID := "fan_town"
const OUTPUT_PATH := "res://content/world_surfaces/fan_town_surface.tres"
const SOURCE_PROVENANCE := "legacy-joi://content/ember/maps/fan_town.json"
const SculptModel = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const SurfacePhysics = preload("res://scripts/ember_voxel_surface_physics.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var errors: Array[String] = []
	var source_path := EmberPack.map_path(MAP_ID)
	var source_hash := FileAccess.get_sha256(source_path)
	var raw: Variant = EmberPack.parse_json_file(source_path)
	if typeof(raw) != TYPE_DICTIONARY:
		_finish(["legacy fan_town map is unavailable"], false)
		return
	var map := raw as Dictionary
	var grid := EmberTileMesher.surface_grid(map)
	var surface := SculptModel.make_world_surface(
		MAP_ID,
		"FanTown",
		grid,
		EmberTileMesher.tileset_colors(str(map.get("tilesetId", "village_16"))),
	)
	surface.physical = true
	surface.imported_from = SOURCE_PROVENANCE
	surface.imported_source_hash = source_hash
	for validation_error in surface.validation_errors():
		errors.append("generated Surface: %s" % validation_error)
	_validate_parity(surface, grid, errors)
	var apply := "--apply" in OS.get_cmdline_user_args()
	if apply and ResourceLoader.exists(OUTPUT_PATH):
		errors.append("canonical Surface already exists; refusing to overwrite it")
	if errors.is_empty() and apply:
		var save_error := ResourceSaver.save(surface, OUTPUT_PATH)
		if save_error != OK:
			errors.append("save failed: %s" % error_string(save_error))
		else:
			var reopened := ResourceLoader.load(
				OUTPUT_PATH, "", ResourceLoader.CACHE_MODE_REPLACE
			) as EmberVoxelModelResource
			if (
				reopened == null
				or reopened.voxels != surface.voxels
				or reopened.palette != surface.palette
				or reopened.imported_source_hash != source_hash
				or not reopened.physical
			):
				errors.append("saved Surface did not reopen byte-identically")
	if FileAccess.get_sha256(source_path) != source_hash:
		errors.append("migration changed the read-only legacy source")
	print(
		"fan_town Surface: %dx%dx%d, %d dense bytes, source %s"
		% [
			surface.grid_size().x,
			surface.grid_size().y,
			surface.grid_size().z,
			surface.voxels.size(),
			source_hash,
		]
	)
	_finish(errors, apply)


func _validate_parity(
	surface: EmberVoxelModelResource,
	grid: Dictionary,
	errors: Array[String],
) -> void:
	var width := int(grid.get("width", 0))
	var depth := int(grid.get("depth", 0))
	var heights: PackedInt32Array = grid.get("heights", PackedInt32Array())
	var tile_ids: PackedInt32Array = grid.get("tileIds", PackedInt32Array())
	if surface.size_blocks != Vector3i(width, 1, depth):
		errors.append("generated block bounds differ from the legacy grid")
		return
	var density := surface.normalized_density()
	for block_z in depth:
		for block_x in width:
			var block_index := block_x + block_z * width
			var expected_height := int(heights[block_index]) - 1
			var center := Vector2i(
				block_x * density + density / 2,
				block_z * density + density / 2,
			)
			var actual_height := SurfacePhysics.solid_height_at(surface, center)
			if actual_height != expected_height:
				errors.append(
					"height parity failed at %d,%d: %d != %d"
					% [block_x, block_z, actual_height, expected_height]
				)
				return
			var top_index := VoxMesher.cell_index(
				center.x, actual_height, center.y,
				surface.grid_size().x, surface.grid_size().z
			)
			var palette_index := int(surface.voxels[top_index])
			if palette_index <= 0 or palette_index >= surface.palette.size():
				errors.append("top material is missing at %d,%d" % [block_x, block_z])
				return
			# Every block with the same legacy tile id must resolve to the same exact
			# imported palette color. Geometry and collision use the checked height.
			for compare_index in block_index:
				if tile_ids[compare_index] != tile_ids[block_index]:
					continue
				var compare_x := compare_index % width
				var compare_z := floori(float(compare_index) / float(width))
				var compare_center := Vector2i(
					compare_x * density + density / 2,
					compare_z * density + density / 2,
				)
				var compare_y := int(heights[compare_index]) - 1
				var compare_voxel := VoxMesher.cell_index(
					compare_center.x, compare_y, compare_center.y,
					surface.grid_size().x, surface.grid_size().z
				)
				if surface.voxels[compare_voxel] != palette_index:
					errors.append("tile color parity drifted for tile %d" % tile_ids[block_index])
					return


func _finish(errors: Array[String], applied: bool) -> void:
	if errors.is_empty():
		print(
			"PASS fan_town Surface %s"
			% ("migration" if applied else "dry-run (use --apply to write)")
		)
		quit(0)
	else:
		printerr("FAIL fan_town Surface migration")
		for error in errors:
			printerr(" - ", error)
		quit(1)
