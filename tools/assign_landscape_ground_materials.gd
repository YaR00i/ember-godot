extends SceneTree
## One-time authoring step (22 Oct 2026): give the palette of landscape_compact the accepted painted materials.
## Roles and material ids follow the palette order the map creation tool writes; the grey-green slot 4 is grass
## (author decision), so every column that used it moves to slot 2. Heights, water and flow are not touched.
## Idempotent. Run: godot --headless --path . --script res://tools/assign_landscape_ground_materials.gd
const PATH := "res://content/world_terrains/landscape_compact.res"
const ROLES := ["", "soil", "grass", "sand", "grass", ""]
const IDS := ["", "soil_grain", "cartoon_grass", "cartoon_sand", "cartoon_grass", ""]

func _initialize() -> void:
	var terrain = load(PATH)
	if terrain == null or terrain.palette.size() != ROLES.size():
		printerr("ASSIGN FAIL: terrain missing or palette is not the expected 6 slots")
		quit(1); return
	var heights_before: PackedInt32Array = terrain.heights.duplicate()
	var water_before: PackedInt32Array = terrain.water_levels.duplicate()
	terrain.palette_surface_roles = PackedStringArray(ROLES)
	terrain.palette_material_ids = PackedStringArray(IDS)
	var moved := 0
	for index in terrain.top_materials.size():
		if terrain.top_materials[index] == 4:
			terrain.top_materials[index] = 2; moved += 1
	for index in terrain.base_materials.size():
		if terrain.base_materials[index] == 4:
			terrain.base_materials[index] = 2
	var errors: Array = terrain.validation_errors()
	if not errors.is_empty() or terrain.heights != heights_before or terrain.water_levels != water_before:
		printerr("ASSIGN FAIL: ", errors)
		quit(1); return
	var result := ResourceSaver.save(terrain, PATH)
	print("ASSIGN ", "OK" if result == OK else "SAVE FAILED %d" % result, " columns moved to grass: ", moved)
	quit(0 if result == OK else 1)
