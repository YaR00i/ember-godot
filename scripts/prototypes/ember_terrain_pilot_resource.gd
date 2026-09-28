@tool
class_name EmberTerrainPilotResource
extends Resource
## Disposable architecture pilot. One column owns its ground and water intent;
## meshes and collision are rebuilt from these arrays in editor and play.

const SCHEMA_VERSION := 1
const CELLS_PER_BLOCK := 16
const Heightfield = preload("res://scripts/ember_voxel_heightfield.gd")

@export var schema_version := SCHEMA_VERSION
@export var source_path := ""
@export var source_sha256 := ""
@export var width := 0
@export var depth := 0
@export var height_limit := 128
@export var origin_y := 0
@export var palette := PackedColorArray()
@export var heights := PackedInt32Array()
@export var top_materials := PackedByteArray()
@export var base_materials := PackedByteArray()
@export var cap_depths := PackedByteArray()
@export var water_levels := PackedInt32Array()
@export var water_materials := PackedByteArray()
## Rare authored side-color exceptions; key=column, value={voxel_y: palette_id}.
@export var column_material_overrides: Dictionary = {}
@export var unsupported_holes := 0


func column_index(x: int, z: int) -> int:
	return x + z * width


func same_terrain_data(other: EmberTerrainPilotResource) -> bool:
	if other == null:
		return false
	for field in ["schema_version", "width", "depth", "height_limit", "origin_y", "palette", "heights", "top_materials", "base_materials", "cap_depths", "water_levels", "water_materials", "column_material_overrides", "unsupported_holes"]:
		if get(field) != other.get(field):
			return false
	return true


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	var count := width * depth
	if schema_version != SCHEMA_VERSION:
		errors.append("unsupported terrain pilot schema")
	if width < 1 or depth < 1:
		errors.append("terrain pilot extent must be positive")
	for channel in [heights, top_materials, base_materials, cap_depths, water_levels, water_materials]:
		if channel.size() != count:
			errors.append("terrain pilot column channel has wrong size")
			break
	if palette.size() < 2:
		errors.append("terrain pilot palette is missing")
	if unsupported_holes > 0:
		errors.append("terrain pilot cannot represent internal holes")
	if errors.is_empty():
		for column in count:
			if heights[column] < 0 or heights[column] > height_limit or water_levels[column] < 0 or water_levels[column] > height_limit:
				errors.append("terrain pilot height is out of range")
				break
			if top_materials[column] >= palette.size() or base_materials[column] >= palette.size() or water_materials[column] >= palette.size():
				errors.append("terrain pilot material is out of palette")
				break
			if cap_depths[column] > heights[column]:
				errors.append("terrain pilot cap exceeds column height")
				break
	if errors.is_empty():
		for raw_column in column_material_overrides:
			var column := int(raw_column)
			if column < 0 or column >= count or typeof(column_material_overrides[raw_column]) != TYPE_DICTIONARY:
				errors.append("terrain pilot side override has invalid column")
				break
			var exceptions: Dictionary = column_material_overrides[raw_column]
			for raw_y in exceptions:
				if int(raw_y) < 0 or int(raw_y) >= height_limit or int(exceptions[raw_y]) <= 0 or int(exceptions[raw_y]) >= palette.size():
					errors.append("terrain pilot side override is out of range")
					break
			if not errors.is_empty():
				break
	return errors


func working_copy() -> EmberTerrainPilotResource:
	var copy := duplicate(true) as EmberTerrainPilotResource
	copy.heights = heights.duplicate()
	copy.top_materials = top_materials.duplicate()
	copy.base_materials = base_materials.duplicate()
	copy.cap_depths = cap_depths.duplicate()
	copy.water_levels = water_levels.duplicate()
	copy.water_materials = water_materials.duplicate()
	copy.column_material_overrides = column_material_overrides.duplicate(true)
	return copy


static func from_surface(source: EmberVoxelModelResource) -> EmberTerrainPilotResource:
	var result := new()
	var size := source.grid_size()
	var count := size.x * size.z
	result.width = size.x
	result.depth = size.z
	result.height_limit = size.y
	result.palette = source.palette.duplicate()
	result.heights = PackedInt32Array()
	result.heights.resize(count)
	result.top_materials.resize(count)
	result.base_materials.resize(count)
	result.cap_depths.resize(count)
	result.water_levels.resize(count)
	result.water_materials.resize(count)
	var tops := Heightfield.column_heights(source.voxels, size, source.palette.size() - 1)
	var layer_size := count
	for column in count:
		var top := tops[column]
		result.heights[column] = top + 1
		if top >= 0:
			var cap := int(source.voxels[column + top * layer_size])
			result.top_materials[column] = cap
			var run := 0
			while top - run >= 0 and run < 255 and source.voxels[column + (top - run) * layer_size] == cap:
				run += 1
			result.cap_depths[column] = run
			result.base_materials[column] = (
				int(source.voxels[column + (top - run) * layer_size]) if top - run >= 0 else cap
			)
			var exceptions := {}
			for y in top + 1:
				var expected := cap if y >= top + 1 - run else result.base_materials[column]
				var actual := int(source.voxels[column + y * layer_size])
				if actual == 0:
					result.unsupported_holes += 1
				elif actual != expected:
					exceptions[y] = actual
			if not exceptions.is_empty():
				result.column_material_overrides[column] = exceptions
		if column < source.surface_fill_levels.size():
			result.water_levels[column] = source.surface_fill_levels[column]
		if column < source.surface_fill_materials.size() and source.surface_fill_materials[column] == 1:
			result.water_materials[column] = (
				source.surface_fill_palette[column] if column < source.surface_fill_palette.size() else 0
			)
	return result
