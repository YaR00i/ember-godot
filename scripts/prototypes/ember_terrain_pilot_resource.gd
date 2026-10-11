@tool
class_name EmberTerrainPilotResource
extends Resource
## Scene-owned compact terrain. One column owns its ground and water intent;
## meshes and collision are rebuilt from these arrays in editor and play.

const SCHEMA_VERSION := 1
const SECTION_SCHEMA_VERSION := 2
const Sections = preload("res://scripts/prototypes/ember_terrain_sections.gd")
const CELLS_PER_BLOCK := 16
const SURFACE_ROLE_IDS := ["soil", "grass", "sand", "stone"]
const SURFACE_ROLE_NAMES := {"soil": "Грунт", "grass": "Трава", "sand": "Песок", "stone": "Камень"}
const Heightfield = preload("res://scripts/ember_voxel_heightfield.gd")

@export var schema_version := SCHEMA_VERSION
@export var source_path := ""
@export var source_sha256 := ""
@export var width := 0
@export var depth := 0
@export var height_limit := 128
@export var origin_y := 0
@export var palette := PackedColorArray()
## Optional semantic roles for palette slots. Empty keeps legacy colors unclassified.
@export var palette_surface_roles := PackedStringArray()
## Optional named artwork per palette slot. Empty entry uses its role's default.
@export var palette_material_ids := PackedStringArray()
@export var heights := PackedInt32Array()
@export var top_materials := PackedByteArray()
@export var base_materials := PackedByteArray()
@export var cap_depths := PackedByteArray()
@export var water_levels := PackedInt32Array()
@export var water_materials := PackedByteArray()
## Optional flow in world X/Z, one vector per 16x16-cell block. Length is local speed.
## Empty means still water; a flow vector does not create water in a dry column.
@export var water_flow := PackedVector2Array()
## Rare authored side-color exceptions; key=column, value={voxel_y: palette_id}.
@export var column_material_overrides: Dictionary = {}
@export var unsupported_holes := 0
## Schema 2: address -> payload of this same Resource. Dense root channels stay
## empty; schema 1 remains readable and is never rewritten just by opening.
@export_storage var sections: Dictionary = {}


func is_sectioned() -> bool:
	return schema_version == SECTION_SCHEMA_VERSION


func sectioned_copy() -> EmberTerrainPilotResource:
	return Sections.convert(self) as EmberTerrainPilotResource


func has_column(x: int, z: int) -> bool:
	return Sections.has_cell(self, x, z)


func column_value(channel: String, index: int) -> int:
	if not is_sectioned(): return get(channel)[index] if index >= 0 and index < width * depth else 0
	return Sections.read(self, channel, index)


func dense_window(bounds: Rect2i) -> EmberTerrainPilotResource:
	return Sections.window(self, bounds) as EmberTerrainPilotResource


func tile_keys(size: int) -> Array[Vector2i]:
	return Sections.tile_keys(self, size)


func has_flow() -> bool:
	if not is_sectioned(): return not water_flow.is_empty()
	for part: EmberTerrainPilotResource in sections.values():
		if not part.water_flow.is_empty(): return true
	return false


func stored_column_count() -> int:
	if not is_sectioned(): return heights.size()
	var count := 0
	for part: EmberTerrainPilotResource in sections.values(): count += part.heights.size()
	return count


func write_columns(indices: PackedInt32Array, values: PackedInt32Array, tops: PackedByteArray, waters: PackedInt32Array, colors: PackedByteArray) -> void:
	if is_sectioned():
		Sections.write(self, indices, values, tops, waters, colors)
		return
	for i in indices.size():
		var index := indices[i]
		heights[index] = values[i]
		top_materials[index] = tops[i]
		water_levels[index] = waters[i]
		water_materials[index] = colors[i]


func column_index(x: int, z: int) -> int:
	return x + z * width


func same_terrain_data(other: EmberTerrainPilotResource) -> bool:
	return same_terrain_geometry(other) and palette_surface_roles == other.palette_surface_roles and palette_material_ids == other.palette_material_ids


func same_terrain_geometry(other: EmberTerrainPilotResource, ignore_height_limit := false) -> bool:
	if other == null:
		return false
	for field in ["schema_version", "width", "depth", "height_limit", "origin_y", "palette", "heights", "top_materials", "base_materials", "cap_depths", "water_levels", "water_materials", "water_flow", "column_material_overrides", "unsupported_holes"]:
		# Raising the storage ceiling changes saved metadata, not existing faces.
		if ignore_height_limit and field == "height_limit": continue
		if get(field) != other.get(field):
			return false
	if sections.size() != other.sections.size(): return false
	for key in sections:
		if not other.sections.has(key): return false
		if sections[key] != other.sections[key] and not sections[key].same_terrain_geometry(other.sections[key], ignore_height_limit): return false
	return true


func validation_errors(local_sections: Array[Vector2i] = []) -> Array[String]:
	var errors: Array[String] = []
	var count := width * depth
	if is_sectioned():
		if width < 1 or depth < 1: errors.append("terrain pilot extent must be positive")
		if palette.size() < 2: errors.append("terrain pilot palette is missing")
		if unsupported_holes > 0: errors.append("terrain pilot cannot represent internal holes")
		errors.append_array(surface_role_errors())
		errors.append_array(material_id_errors())
		errors.append_array(Sections.validation_errors(self, local_sections))
		return errors
	if schema_version != SCHEMA_VERSION:
		errors.append("unsupported terrain pilot schema")
	if width < 1 or depth < 1:
		errors.append("terrain pilot extent must be positive")
	if not sections.is_empty(): errors.append("dense terrain also contains section payloads")
	for channel in [heights, top_materials, base_materials, cap_depths, water_levels, water_materials]:
		if channel.size() != count:
			errors.append("terrain pilot column channel has wrong size")
			break
	var flow_count := ceili(float(width) / float(CELLS_PER_BLOCK)) * ceili(float(depth) / float(CELLS_PER_BLOCK))
	if not water_flow.is_empty() and water_flow.size() != flow_count:
		errors.append("terrain water flow has wrong size")
	if errors.is_empty():
		for vector in water_flow:
			if not is_finite(vector.x) or not is_finite(vector.y) or vector.length_squared() > 1.0001:
				errors.append("terrain water flow is out of range")
				break
	if palette.size() < 2:
		errors.append("terrain pilot palette is missing")
	errors.append_array(surface_role_errors())
	errors.append_array(material_id_errors())
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


func surface_role_errors() -> Array[String]:
	var errors: Array[String] = []
	if palette_surface_roles.is_empty(): return errors
	if palette_surface_roles.size() != palette.size():
		errors.append("terrain surface roles must match palette size")
		return errors
	for index in palette_surface_roles.size():
		var role := palette_surface_roles[index]
		if (index == 0 and not role.is_empty()) or (not role.is_empty() and role not in SURFACE_ROLE_IDS):
			errors.append("terrain surface role is unknown")
			break
	return errors


func material_id_errors() -> Array[String]:
	var errors: Array[String] = []
	if palette_material_ids.is_empty(): return errors
	if palette_material_ids.size() != palette.size():
		errors.append("terrain material IDs must match palette size")
		return errors
	for index in palette_material_ids.size():
		var id := palette_material_ids[index]
		if (index == 0 and not id.is_empty()) or (not id.is_empty() and not id.is_valid_identifier()):
			errors.append("terrain material ID is invalid")
			break
		if id.is_empty(): continue
		var path := "res://content/terrain_materials/%s.tres" % id
		var pattern := ResourceLoader.load(path) as EmberCompactTerrainPattern if ResourceLoader.exists(path) else null
		if pattern == null or pattern.role_id != surface_role_for_palette(index) or not pattern.validation_errors().is_empty():
			errors.append("terrain material ID has no matching pattern")
			break
	return errors


func working_copy() -> EmberTerrainPilotResource:
	if is_sectioned():
		var result := duplicate(false) as EmberTerrainPilotResource
		result.sections = sections.duplicate()
		# Payloads are persistent until write_columns replaces a touched section.
		# Root arrays/metadata must still be private: PackedArrays are references.
		result.palette = palette.duplicate()
		result.palette_surface_roles = palette_surface_roles.duplicate()
		result.palette_material_ids = palette_material_ids.duplicate()
		for channel in Sections.CHANNELS:
			result.set(channel, get(channel).duplicate())
		result.water_flow = water_flow.duplicate()
		result.column_material_overrides = column_material_overrides.duplicate(true)
		return result
	var copy := duplicate(true) as EmberTerrainPilotResource
	copy.palette_surface_roles = palette_surface_roles.duplicate()
	copy.palette_material_ids = palette_material_ids.duplicate()
	copy.heights = heights.duplicate()
	copy.top_materials = top_materials.duplicate()
	copy.base_materials = base_materials.duplicate()
	copy.cap_depths = cap_depths.duplicate()
	copy.water_levels = water_levels.duplicate()
	copy.water_materials = water_materials.duplicate()
	copy.water_flow = water_flow.duplicate()
	copy.column_material_overrides = column_material_overrides.duplicate(true)
	return copy


func flow_at_cell(x: int, z: int) -> Vector2:
	if is_sectioned():
		if not has_column(x, z): return Vector2.ZERO
		var part := sections[Vector2i(x / Sections.CELLS, z / Sections.CELLS)] as EmberTerrainPilotResource
		return part.flow_at_cell(x % Sections.CELLS, z % Sections.CELLS)
	if water_flow.is_empty() or x < 0 or z < 0 or x >= width or z >= depth:
		return Vector2.ZERO
	var blocks_wide := ceili(float(width) / float(CELLS_PER_BLOCK))
	return water_flow[x / CELLS_PER_BLOCK + (z / CELLS_PER_BLOCK) * blocks_wide]


func surface_role_for_palette(index: int) -> String:
	return palette_surface_roles[index] if index >= 0 and index < palette_surface_roles.size() else ""


func material_id_for_palette(index: int) -> String:
	if index < 0 or index >= palette.size(): return ""
	if index < palette_material_ids.size() and not palette_material_ids[index].is_empty():
		return palette_material_ids[index]
	return surface_role_for_palette(index)


static func surface_role_name(role: String) -> String:
	return str(SURFACE_ROLE_NAMES.get(role, "Без роли"))


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
