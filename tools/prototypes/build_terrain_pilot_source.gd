extends SceneTree
## One-time conversion of the copied beach. Never writes the authored Surface.

const Source = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const INPUT := "res://content/world_surfaces/landscape_v2_experimental_surface.tres"
const OUTPUT := "res://content/terrain_pilot/beach_region.res"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var started := Time.get_ticks_msec()
	var old := ResourceLoader.load(INPUT, "", ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource
	if old == null:
		printerr("TERRAIN_PILOT_BUILD failed=source_load")
		quit(1)
		return
	var loaded := Time.get_ticks_msec()
	var compact := Source.from_surface(old)
	compact.origin_y = -32
	compact.source_path = INPUT
	compact.source_sha256 = FileAccess.get_sha256(INPUT)
	var parity := _ground_parity(old, compact)
	var converted := Time.get_ticks_msec()
	if not compact.validation_errors().is_empty():
		printerr("TERRAIN_PILOT_BUILD failed=validation errors=", compact.validation_errors())
		quit(1)
		return
	if FileAccess.file_exists(OUTPUT) and not OS.get_cmdline_user_args().has("--replace"):
		printerr("TERRAIN_PILOT_BUILD refused to replace existing pilot; pass --replace explicitly")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://content/terrain_pilot"))
	var error := ResourceSaver.save(compact, OUTPUT)
	var saved := Time.get_ticks_msec()
	if error != OK:
		printerr("TERRAIN_PILOT_BUILD failed=save error=", error)
		quit(1)
		return
	var file := FileAccess.open(OUTPUT, FileAccess.READ)
	print("TERRAIN_PILOT_BUILD load_ms=", loaded - started, " convert_and_parity_ms=", converted - loaded, " save_ms=", saved - converted, " columns=", compact.width * compact.depth, " exception_columns=", compact.column_material_overrides.size(), " parity=", parity, " source_bytes=", FileAccess.open(INPUT, FileAccess.READ).get_length(), " compact_bytes=", file.get_length())
	quit()


func _ground_parity(old: EmberVoxelModelResource, compact: Source) -> Dictionary:
	var count := compact.width * compact.depth
	var mismatches := 0
	var holes := 0
	var visible := 0
	for column in count:
		var height: int = compact.heights[column]
		var cap_start: int = maxi(0, height - int(compact.cap_depths[column]))
		var x := column % compact.width
		var z := column / compact.width
		for y in height:
			var expected: int = compact.top_materials[column] if y >= cap_start else compact.base_materials[column]
			if compact.column_material_overrides.has(column):
				expected = int((compact.column_material_overrides[column] as Dictionary).get(y, expected))
			var actual: int = old.voxels[column + y * count]
			if actual != expected:
				mismatches += 1
				if actual == 0:
					holes += 1
				if x == 0 or z == 0 or x == compact.width - 1 or z == compact.depth - 1 or compact.heights[column - 1] <= y or compact.heights[column + 1] <= y or compact.heights[column - compact.width] <= y or compact.heights[column + compact.width] <= y:
					visible += 1
	return {"all": mismatches, "holes": holes, "visible_by_height": visible}
