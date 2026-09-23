extends RefCounted
## Initial authored content, not a second terrain generator or brush owner.
## Runtime and all later editing use the ordinary native Surface Resource.
const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const MAP_ID := "world_canvas"
const SOURCE_PATH := "res://content/world_surfaces/world_canvas_surface.tres"
const FOOTPRINT := Vector2i(24, 25)
const ORIGIN := Vector3(0, -32, 0)
const SEA_LEVEL := 0.0

static func shoreline(z: float) -> float:
	return 170.0 + 22.0*sin(z*TAU/400.0+0.45) + 10.0*sin(z*TAU/200.0-0.8)

static func make_surface() -> EmberVoxelModelResource:
	var surface := Model.make_native_world_surface(MAP_ID, FOOTPRINT)
	surface.display_name = "Холст мира · берег и вода"
	surface.material["artDirection"] = "open_coastal_canvas"
	surface.palette = PackedColorArray([
		Color.TRANSPARENT,
		Color("#7d6950"), # earth, only exposed at the cut boundary
		Color("#7fa36a"), # calm grass
		Color("#d6bd85"), # broad sandy beach
		Color("#b3b990"), # pale submerged floor
		Color("#50aaa3"), # water tint, interpreted by the existing water material
	])
	var size := surface.grid_size()
	var values := surface.voxels
	var levels := PackedInt32Array()
	var materials := PackedByteArray()
	var colors := PackedByteArray()
	levels.resize(size.x*size.z)
	materials.resize(size.x*size.z)
	colors.resize(size.x*size.z)
	for z in size.z:
		var coast := shoreline(z+0.5)
		for x in size.x:
			var distance := x+0.5-coast
			var height := 6.0*(1.0-smoothstep(-36.0,0.0,distance)) if distance < 0 else -20.0*smoothstep(0.0,132.0,distance)
			var count := roundi(height-ORIGIN.y)
			var cap := 2 if distance < -44.0 else 3 if distance < 20.0 else 4
			var column := x+z*size.x
			for y in count:
				values[column+y*size.x*size.z] = cap if y >= count-4 else 1
			if count < int(SEA_LEVEL-ORIGIN.y):
				levels[column] = int(SEA_LEVEL-ORIGIN.y)
				materials[column] = Model.SURFACE_FILL_WATER
				colors[column] = 5
	surface.voxels = values
	surface.surface_fill_levels = levels
	surface.surface_fill_materials = materials
	surface.surface_fill_palette = colors
	return surface
