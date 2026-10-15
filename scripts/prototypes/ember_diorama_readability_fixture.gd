extends RefCounted
## Small saved fixture through the existing Source. Author maps remain untouched.
const STEP_AREA := Rect2i(55,99,19,7)
const STEP_VOXELS := 3

static func source() -> EmberTerrainPilotResource:
	var result: EmberTerrainPilotResource=load("res://content/world_terrains/grass_field_study.res").working_copy()
	result.palette.append(Color("796047"))
	result.palette_surface_roles.append("soil")
	result.palette_material_ids.append("soil_grain")
	for z in range(STEP_AREA.position.y,STEP_AREA.end.y):
		for x in range(STEP_AREA.position.x,STEP_AREA.end.x):
			result.heights[result.column_index(x,z)]+=STEP_VOXELS
	for z in range(100,116):
		for x in range(99,113):
			var i:=result.column_index(x,z)
			result.top_materials[i]=4;result.base_materials[i]=4
	return result
