@tool
class_name EmberTerrainPilotMesh
extends RefCounted
## The same tile geometry is used in the pilot editor and play scene. Its
## collision faces are copied from the terrain triangles, never from a preview.

const TerrainResource = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const BrushMath = preload("res://scripts/prototypes/ember_terrain_pilot_brush_math.gd")
const GROUP_SIZE: int = BrushMath.COARSE_CELL_SIZE


class Triangles:
	extends RefCounted
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var coalesce_sides := false
	var _side_spans := {}
	var water_depth_cache: Variant = null # One build only; the editor allocates none.

	func side(direction: int, plane: int, begin: int, end: int, low: int, high: int, color: Color) -> void:
		if high <= low: return
		# Only identical coplanar material bands may join. Gaps, cap changes and
		# authored side exceptions keep their own rectangles and exact heights.
		var key := [direction, plane, low, high, color]
		if not _side_spans.has(key): _side_spans[key] = []
		(_side_spans[key] as Array).append(Vector2(begin, end))

	func _flush_sides() -> void:
		for key: Array in _side_spans:
			var spans: Array = _side_spans[key]
			spans.sort()
			var begin: float = spans[0].x
			var end: float = spans[0].y
			for i in range(1, spans.size()):
				if spans[i].x == end:
					end = spans[i].y
				else:
					_emit_side(key, begin, end)
					begin = spans[i].x
					end = spans[i].y
			_emit_side(key, begin, end)
		_side_spans.clear()

	func _emit_side(key: Array, begin: float, end: float) -> void:
		var plane := float(key[1])
		var low := float(key[2])
		var high := float(key[3])
		var color: Color = key[4]
		match int(key[0]):
			0: quad(Vector3(plane, low, begin), Vector3(plane, low, end), Vector3(plane, high, end), Vector3(plane, high, begin), color, Vector3.LEFT)
			1: quad(Vector3(plane, low, begin), Vector3(plane, high, begin), Vector3(plane, high, end), Vector3(plane, low, end), color, Vector3.RIGHT)
			2: quad(Vector3(begin, low, plane), Vector3(begin, high, plane), Vector3(end, high, plane), Vector3(end, low, plane), color, Vector3.FORWARD)
			3: quad(Vector3(begin, low, plane), Vector3(end, low, plane), Vector3(end, high, plane), Vector3(begin, high, plane), color, Vector3.BACK)

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, normal: Vector3, uv := Vector2.ZERO) -> void:
		# Godot's front-face winding is clockwise from the visible side.
		for point in [a, c, b, a, d, c]:
			vertices.append(point)
			normals.append(normal)
			colors.append(color)
			uvs.append(uv)

	func water_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3,
			color: Color, depth_uv: float, depths: Array[float]) -> void:
		# The optional study mesh shares depth samples at corners, so adjacent
		# quads interpolate the same shallow-to-deep transition.
		var points := [a, b, c, d]
		for corner in [0, 2, 1, 0, 3, 2]:
			vertices.append(points[corner])
			normals.append(Vector3.UP)
			var vertex_color := color
			vertex_color.a = depths[corner]
			colors.append(vertex_color)
			uvs.append(Vector2(depth_uv, 0.0))

	func water_wall(a: Vector3, b: Vector3, c: Vector3, d: Vector3,
			color: Color, normal: Vector3, depth_a: float, depth_b: float) -> void:
		# UV.y marks the visible vertical water body: 1 at the moving crest,
		# 2 at the fixed seabed. The top keeps UV.y = 0.
		var points := [a, b, c, d]
		var depths := [depth_a, depth_b, depth_b, depth_a]
		for corner in [0, 2, 1, 0, 3, 2]:
			var point: Vector3 = points[corner]
			vertices.append(point)
			normals.append(normal)
			var vertex_color := color
			vertex_color.a = depths[corner]
			colors.append(vertex_color)
			uvs.append(Vector2(0.0, 1.0 if is_equal_approx(point.y, a.y) else 2.0))

	func mesh(indexed := false) -> ArrayMesh:
		if coalesce_sides: _flush_sides()
		var result := ArrayMesh.new()
		if vertices.is_empty():
			return result
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		if indexed:
			var surface := SurfaceTool.new()
			surface.create_from_arrays(arrays)
			surface.index()
			arrays = surface.commit_to_arrays()
			# Preserve triangle order: this transparent surface also contains
			# walls and the falling sheet. Do not reorder for a vertex cache.
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return result


## Immediate side quads are the editable default; the gameplay projection opts
## into coalescing explicitly. Both modes keep the same authored surface.
static func build_tile(source: TerrainResource, min_x: int, min_z: int, tile_size: int,
		water_step := 0, water_volume_sides := false, swash_cells := PackedVector4Array(), waterfall_sheet := {}, coalesce_ground_sides := false, optimize_water_mesh := false) -> Dictionary:
	if source.is_sectioned():
		return _build_section_tile(source, min_x, min_z, tile_size, water_step, water_volume_sides, swash_cells, waterfall_sheet, coalesce_ground_sides, optimize_water_mesh)
	var geometry_started := Time.get_ticks_usec()
	var end_x := mini(source.width, min_x + tile_size)
	var end_z := mini(source.depth, min_z + tile_size)
	var uniform := _build_uniform_dry_tile(source, min_x, min_z, end_x, end_z, coalesce_ground_sides) if swash_cells.is_empty() and waterfall_sheet.is_empty() else {}
	if not uniform.is_empty():
		return uniform
	var grouped := _build_grouped_tile(source, min_x, min_z, end_x, end_z,
		water_step, water_volume_sides, coalesce_ground_sides, optimize_water_mesh) if swash_cells.is_empty() and waterfall_sheet.is_empty() else {}
	if not grouped.is_empty():
		return grouped
	var ground := Triangles.new()
	ground.coalesce_sides = coalesce_ground_sides
	var water := Triangles.new()
	if optimize_water_mesh: water.water_depth_cache = {}
	var pass_started := Time.get_ticks_usec()
	var skip_sides := _build_top_rectangles(source, ground, min_x, min_z, end_x, end_z)
	var top_us := Time.get_ticks_usec() - pass_started
	var side_us := 0
	for z in range(min_z, end_z):
		pass_started = Time.get_ticks_usec()
		for cell_x in range(min_x, end_x):
			if skip_sides[(cell_x - min_x) + (z - min_z) * (end_x - min_x)] != 0:
				continue
			var index := cell_x + z * source.width
			var height := source.heights[index]
			if height <= 0:
				continue
			var left := source.heights[index - 1] if cell_x > 0 else 0
			var right := source.heights[index + 1] if cell_x + 1 < source.width else 0
			var front := source.heights[index - source.width] if z > 0 else 0
			var back := source.heights[index + source.width] if z + 1 < source.depth else 0
			if height > left:
				_add_side(source, ground, cell_x, z, height, left, 0)
			if height > right:
				_add_side(source, ground, cell_x, z, height, right, 1)
			if height > front:
				_add_side(source, ground, cell_x, z, height, front, 2)
			if height > back:
				_add_side(source, ground, cell_x, z, height, back, 3)
		side_us += Time.get_ticks_usec() - pass_started
	pass_started = Time.get_ticks_usec()
	_build_water_rectangles(source, water, min_x, min_z, end_x, end_z, water_step)
	for cell in swash_cells:
		var y := cell.z + 0.025
		# Existing Water mesh/material: UV.y=-1 marks temporary dry-bank coverage.
		water.quad(Vector3(cell.x, y, cell.y), Vector3(cell.x + 1.0, y, cell.y),
			Vector3(cell.x + 1.0, y, cell.y + 1.0), Vector3(cell.x, y, cell.y + 1.0),
			Color(0.1, 0.7, 0.8, 0.0), Vector3.UP, Vector2(cell.x + 0.5, -cell.y - 1.5))
	if water_step > 0 or water_volume_sides:
		_stitch_water_edges(source, water, min_x, min_z, end_x, end_z, water_volume_sides)
	if water_volume_sides:
		_build_water_walls(source, water, min_x, min_z, end_x, end_z, waterfall_sheet.get("spill", {}))
	# The falling sheet has its own parameterised edges. Surface stitching must
	# not reinterpret it as flat water, and a farther water wall must not paint
	# over it in this material's existing depth_draw_never pass.
	if not waterfall_sheet.is_empty():
		water.vertices.append_array(waterfall_sheet.vertices)
		water.uvs.append_array(waterfall_sheet.uvs)
		for point in waterfall_sheet.vertices:
			water.normals.append(Vector3.UP)
			water.colors.append(Color(0.1, 0.7, 0.8, 0.1875))
	var water_us := Time.get_ticks_usec() - pass_started
	var geometry_us := Time.get_ticks_usec() - geometry_started
	var resource_started := Time.get_ticks_usec()
	var ground_mesh := ground.mesh()
	var water_mesh := water.mesh(optimize_water_mesh)
	return {"terrain": ground_mesh, "water": water_mesh, "collision_faces": ground.vertices,
		"water_vertices": water_mesh.surface_get_array_len(0) if water_mesh.get_surface_count() > 0 else 0,
		"water_source_vertices": water.vertices.size(), "water_indices": water_mesh.surface_get_array_index_len(0) if water_mesh.get_surface_count() > 0 else 0, "uniform_dry": false,
		"geometry_us": geometry_us, "top_us": top_us, "side_us": side_us, "water_us": water_us, "uniform_us": 0,
		"mesh_resource_us": Time.get_ticks_usec() - resource_started}


static func _build_section_tile(source: TerrainResource, x: int, z: int, size: int, step: int, sides: bool, swash: PackedVector4Array, sheet: Dictionary, coalesce: bool, optimize_water: bool) -> Dictionary:
	# Only this tile and an eight-column halo enter the existing mesher. The
	# halo keeps its grouped neighbour tests and shared water corners identical.
	var started := Time.get_ticks_usec()
	var start := Vector2i(maxi(0, x - GROUP_SIZE), maxi(0, z - GROUP_SIZE))
	var end := Vector2i(mini(source.width, x + size + GROUP_SIZE), mini(source.depth, z + size + GROUP_SIZE))
	var address := Vector2i(x / TerrainResource.Sections.CELLS, z / TerrainResource.Sections.CELLS)
	var part := source.sections.get(address) as TerrainResource
	var part_start := address * TerrainResource.Sections.CELLS
	var view: TerrainResource
	if part != null and Rect2i(part_start, Vector2i(part.width, part.depth)).encloses(Rect2i(start, end - start)):
		# An interior tile can read its immutable payload directly. Copy only
		# metadata for the authoritative palette; section seams still use a halo.
		start = part_start
		view = part.duplicate(false) as TerrainResource
		view.palette = source.palette
		view.palette_surface_roles = source.palette_surface_roles
		view.palette_material_ids = source.palette_material_ids
	else:
		view = source.dense_window(Rect2i(start, end - start))
	var bank := PackedVector4Array()
	for cell in swash: bank.append(Vector4(cell.x - start.x, cell.y - start.y, cell.z, cell.w))
	var falling := sheet.duplicate()
	if not sheet.is_empty():
		var points: PackedVector3Array = sheet.vertices.duplicate()
		for i in points.size(): points[i] -= Vector3(start.x, 0, start.y)
		falling.vertices = points
		if sheet.has("spill"):
			falling.spill = sheet.spill.duplicate()
			falling.spill.center -= Vector2(start)
	var generated := build_tile(view, x - start.x, z - start.y, size, step, sides, bank, falling, coalesce, optimize_water)
	var shift := Vector3(start.x, 0, start.y)
	for channel in ["terrain", "water"]:
		var old_mesh := generated[channel] as ArrayMesh
		var mesh := ArrayMesh.new()
		if old_mesh.get_surface_count() > 0:
			var arrays := old_mesh.surface_get_arrays(0)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for i in points.size(): points[i] += shift
			arrays[Mesh.ARRAY_VERTEX] = points
			if channel == "water":
				var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
				for i in uvs.size():
					if uvs[i].y < 0: uvs[i] += Vector2(start.x, -start.y)
				arrays[Mesh.ARRAY_TEX_UV] = uvs
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		generated[channel] = mesh
	var faces: PackedVector3Array = generated.collision_faces
	for i in faces.size(): faces[i] += shift
	generated.collision_faces = faces
	generated.section_window_columns = view.width * view.depth
	generated.geometry_us = Time.get_ticks_usec() - started
	return generated


static func _build_grouped_tile(source: TerrainResource, min_x: int, min_z: int,
		end_x: int, end_z: int, water_step: int, water_volume_sides: bool, coalesce: bool, optimize_water: bool) -> Dictionary:
	# Coarse editing changes whole 8x8 cells, but the authored Resource stays at
	# full resolution. A fine edit or a nonuniform neighbour falls back to the
	# exact per-column builder above without changing the stored map.
	if min_x % GROUP_SIZE != 0 or min_z % GROUP_SIZE != 0 or (end_x - min_x) % GROUP_SIZE != 0 or (end_z - min_z) % GROUP_SIZE != 0:
		return {}
	var groups_x := (end_x - min_x) / GROUP_SIZE
	var groups_z := (end_z - min_z) / GROUP_SIZE
	if groups_x == 0 or groups_z == 0:
		return {}
	var started := Time.get_ticks_usec()
	var heights := PackedInt32Array()
	var tops := PackedByteArray()
	var bases := PackedByteArray()
	var caps := PackedByteArray()
	var waters := PackedInt32Array()
	var water_colors := PackedByteArray()
	var group_count := groups_x * groups_z
	heights.resize(group_count)
	tops.resize(group_count)
	bases.resize(group_count)
	caps.resize(group_count)
	waters.resize(group_count)
	water_colors.resize(group_count)
	var source_heights := source.heights
	var source_tops := source.top_materials
	var source_bases := source.base_materials
	var source_caps := source.cap_depths
	var source_waters := source.water_levels
	var source_water_colors := source.water_materials
	var has_overrides := not source.column_material_overrides.is_empty()
	for gz in groups_z:
		for gx in groups_x:
			var x := min_x + gx * GROUP_SIZE
			var z := min_z + gz * GROUP_SIZE
			var first := x + z * source.width
			var group_index := gx + gz * groups_x
			var h := source_heights[first]
			var top := source_tops[first]
			var base := source_bases[first]
			var cap := source_caps[first]
			var water := source_waters[first]
			var water_color := source_water_colors[first]
			for dz in GROUP_SIZE:
				for dx in GROUP_SIZE:
					var index := first + dx + dz * source.width
					if source_heights[index] != h or source_tops[index] != top or source_bases[index] != base or source_caps[index] != cap or source_waters[index] != water or source_water_colors[index] != water_color or (has_overrides and source.column_material_overrides.has(index)):
						return {}
			heights[group_index] = h
			tops[group_index] = top
			bases[group_index] = base
			caps[group_index] = cap
			waters[group_index] = water
			water_colors[group_index] = water_color
	var ground := Triangles.new()
	ground.coalesce_sides = coalesce
	var water_mesh_data := Triangles.new()
	if optimize_water: water_mesh_data.water_depth_cache = {}
	var pass_started := Time.get_ticks_usec()
	var used := PackedByteArray()
	used.resize(group_count)
	for gz in groups_z:
		for gx in groups_x:
			var first := gx + gz * groups_x
			if used[first] != 0 or heights[first] <= 0 or tops[first] <= 0:
				continue
			var right := gx + 1
			while right < groups_x and used[right + gz * groups_x] == 0 and heights[right + gz * groups_x] == heights[first] and tops[right + gz * groups_x] == tops[first]:
				right += 1
			var back := gz + 1
			while back < groups_z:
				var matches := true
				for test_x in range(gx, right):
					var index := test_x + back * groups_x
					if used[index] != 0 or heights[index] != heights[first] or tops[index] != tops[first]:
						matches = false
						break
				if not matches: break
				back += 1
			for mark_z in range(gz, back):
				for mark_x in range(gx, right):
					used[mark_x + mark_z * groups_x] = 1
			var x := min_x + gx * GROUP_SIZE
			var z := min_z + gz * GROUP_SIZE
			var y := float(source.origin_y + heights[first])
			ground.quad(Vector3(x, y, z), Vector3(x, y, min_z + back * GROUP_SIZE), Vector3(min_x + right * GROUP_SIZE, y, min_z + back * GROUP_SIZE), Vector3(min_x + right * GROUP_SIZE, y, z), _ground_color(source, tops[first]), Vector3.UP)
	var top_us := Time.get_ticks_usec() - pass_started
	pass_started = Time.get_ticks_usec()
	for gz in groups_z:
		for gx in groups_x:
			var index := gx + gz * groups_x
			var high := heights[index]
			if high <= 0: continue
			var x := min_x + gx * GROUP_SIZE
			var z := min_z + gz * GROUP_SIZE
			for side in 4:
				var low := 0
				match side:
					0: low = heights[index - 1] if gx > 0 else _group_neighbour_height(source, x, z, side)
					1: low = heights[index + 1] if gx + 1 < groups_x else _group_neighbour_height(source, x, z, side)
					2: low = heights[index - groups_x] if gz > 0 else _group_neighbour_height(source, x, z, side)
					3: low = heights[index + groups_x] if gz + 1 < groups_z else _group_neighbour_height(source, x, z, side)
				if low < 0: return {}
				if high > low:
					_add_group_side(source, ground, x, z, high, low, side, tops[index], bases[index], caps[index])
	var side_us := Time.get_ticks_usec() - pass_started
	pass_started = Time.get_ticks_usec()
	used.fill(0)
	for gz in groups_z:
		for gx in groups_x:
			var first := gx + gz * groups_x
			var level := waters[first]
			var material := water_colors[first]
			if used[first] != 0 or level <= heights[first] or material <= 0:
				continue
			var band := clampi(level - heights[first], 1, 4)
			var right := gx + 1
			while right < groups_x:
				var next := right + gz * groups_x
				if used[next] != 0 or waters[next] != level or water_colors[next] != material or level <= heights[next] or clampi(level - heights[next], 1, 4) != band: break
				right += 1
			var back := gz + 1
			while back < groups_z:
				var matches := true
				for test_x in range(gx, right):
					var next := test_x + back * groups_x
					if used[next] != 0 or waters[next] != level or water_colors[next] != material or level <= heights[next] or clampi(level - heights[next], 1, 4) != band:
						matches = false
						break
				if not matches: break
				back += 1
			for mark_z in range(gz, back):
				for mark_x in range(gx, right):
					used[mark_x + mark_z * groups_x] = 1
			var x := min_x + gx * GROUP_SIZE
			var z := min_z + gz * GROUP_SIZE
			var y := float(source.origin_y + level) + 0.02
			_append_water_rectangle(source, water_mesh_data, x, z, min_x + right * GROUP_SIZE,
				min_z + back * GROUP_SIZE, y, _color(source, material),
				Vector2((float(band) - 0.5) / 4.0, 0), water_step, level)
	if water_step > 0 or water_volume_sides:
		_stitch_water_edges(source, water_mesh_data, min_x, min_z, end_x, end_z,
			water_volume_sides)
	if water_volume_sides:
		_build_water_walls(source, water_mesh_data, min_x, min_z, end_x, end_z)
	var water_us := Time.get_ticks_usec() - pass_started
	var geometry_us := Time.get_ticks_usec() - started
	var resource_started := Time.get_ticks_usec()
	var ground_mesh := ground.mesh()
	var water_mesh := water_mesh_data.mesh(optimize_water)
	return {"terrain": ground_mesh, "water": water_mesh, "collision_faces": ground.vertices,
		"water_vertices": water_mesh.surface_get_array_len(0) if water_mesh.get_surface_count() > 0 else 0,
		"water_source_vertices": water_mesh_data.vertices.size(), "water_indices": water_mesh.surface_get_array_index_len(0) if water_mesh.get_surface_count() > 0 else 0, "uniform_dry": false, "grouped_8": true,
		"geometry_us": geometry_us, "top_us": top_us, "side_us": side_us, "water_us": water_us, "uniform_us": 0,
		"mesh_resource_us": Time.get_ticks_usec() - resource_started}


static func _group_neighbour_height(source: TerrainResource, x: int, z: int, side: int) -> int:
	if side == 0 and x == 0 or side == 1 and x + GROUP_SIZE >= source.width or side == 2 and z == 0 or side == 3 and z + GROUP_SIZE >= source.depth:
		return 0
	var heights := source.heights
	var first := x - 1 + z * source.width if side == 0 else x + GROUP_SIZE + z * source.width if side == 1 else x + (z - 1) * source.width if side == 2 else x + (z + GROUP_SIZE) * source.width
	var step := source.width if side < 2 else 1
	var height := heights[first]
	for offset in range(1, GROUP_SIZE):
		if heights[first + offset * step] != height:
			return -1
	return height


static func _add_group_side(source: TerrainResource, triangles: Triangles, x: int, z: int, high: int, low: int, direction: int, top: int, base: int, cap: int) -> void:
	var cap_start := maxi(0, high - cap)
	if low < cap_start:
		_group_side_quad(triangles, x, z, low + source.origin_y, cap_start + source.origin_y, direction, _ground_color(source, base))
	_group_side_quad(triangles, x, z, maxi(low, cap_start) + source.origin_y, high + source.origin_y, direction, _ground_color(source, top))


static func _group_side_quad(triangles: Triangles, x: int, z: int, low: int, high: int, direction: int, color: Color) -> void:
	if high <= low: return
	if triangles.coalesce_sides:
		var plane := x if direction == 0 else x + GROUP_SIZE if direction == 1 else z if direction == 2 else z + GROUP_SIZE
		var begin := z if direction < 2 else x
		triangles.side(direction, plane, begin, begin + GROUP_SIZE, low, high, color)
		return
	match direction:
		0: triangles.quad(Vector3(x, low, z), Vector3(x, low, z + GROUP_SIZE), Vector3(x, high, z + GROUP_SIZE), Vector3(x, high, z), color, Vector3.LEFT)
		1: triangles.quad(Vector3(x + GROUP_SIZE, low, z), Vector3(x + GROUP_SIZE, high, z), Vector3(x + GROUP_SIZE, high, z + GROUP_SIZE), Vector3(x + GROUP_SIZE, low, z + GROUP_SIZE), color, Vector3.RIGHT)
		2: triangles.quad(Vector3(x, low, z), Vector3(x, high, z), Vector3(x + GROUP_SIZE, high, z), Vector3(x + GROUP_SIZE, low, z), color, Vector3.FORWARD)
		3: triangles.quad(Vector3(x, low, z + GROUP_SIZE), Vector3(x + GROUP_SIZE, low, z + GROUP_SIZE), Vector3(x + GROUP_SIZE, high, z + GROUP_SIZE), Vector3(x, high, z + GROUP_SIZE), color, Vector3.BACK)


static func _build_top_rectangles(source: TerrainResource, triangles: Triangles, min_x: int, min_z: int, end_x: int, end_z: int) -> PackedByteArray:
	var tile_width := end_x - min_x
	var used := PackedByteArray()
	used.resize(tile_width * (end_z - min_z))
	var skip_sides := PackedByteArray()
	skip_sides.resize(used.size())
	for z in range(min_z, end_z):
		for x in range(min_x, end_x):
			var local := (x - min_x) + (z - min_z) * tile_width
			if used[local] != 0:
				continue
			var index := x + z * source.width
			var height := source.heights[index]
			var material := source.top_materials[index]
			if height <= 0 or material <= 0:
				continue
			var right := x + 1
			while right < end_x:
				var next := right + z * source.width
				if used[local + right - x] != 0 or source.heights[next] != height or source.top_materials[next] != material:
					break
				right += 1
			var back := z + 1
			while back < end_z:
				var row := back * source.width
				var used_row := (back - min_z) * tile_width
				var matches := true
				for test_x in range(x, right):
					if used[used_row + test_x - min_x] != 0 or source.heights[row + test_x] != height or source.top_materials[row + test_x] != material:
						matches = false
						break
				if not matches:
					break
				back += 1
			for mark_z in range(z, back):
				var mark_row := (mark_z - min_z) * tile_width
				for mark_x in range(x, right):
					var mark := mark_row + mark_x - min_x
					used[mark] = 1
					if mark_x > x and mark_x + 1 < right and mark_z > z and mark_z + 1 < back:
						skip_sides[mark] = 1
			var y := float(source.origin_y + height)
			triangles.quad(Vector3(x, y, z), Vector3(x, y, back), Vector3(right, y, back), Vector3(right, y, z), _ground_color(source, material), Vector3.UP)
	return skip_sides


static func _build_water_rectangles(source: TerrainResource, triangles: Triangles, min_x: int, min_z: int, end_x: int, end_z: int, water_step: int) -> void:
	var tile_width := end_x - min_x
	var used := PackedByteArray()
	used.resize(tile_width * (end_z - min_z))
	for z in range(min_z, end_z):
		for x in range(min_x, end_x):
			var local := (x - min_x) + (z - min_z) * tile_width
			if used[local] != 0:
				continue
			var index := x + z * source.width
			var level := source.water_levels[index]
			var material := source.water_materials[index]
			if level <= source.heights[index] or material <= 0:
				continue
			var depth_band := clampi(level - source.heights[index], 1, 4)
			var right := x + 1
			while right < end_x:
				var next := right + z * source.width
				if used[local + right - x] != 0 or source.water_levels[next] != level or source.water_materials[next] != material or level <= source.heights[next] or clampi(level - source.heights[next], 1, 4) != depth_band:
					break
				right += 1
			var back := z + 1
			while back < end_z:
				var row := back * source.width
				var used_row := (back - min_z) * tile_width
				var matches := true
				for test_x in range(x, right):
					var next := row + test_x
					if used[used_row + test_x - min_x] != 0 or source.water_levels[next] != level or source.water_materials[next] != material or level <= source.heights[next] or clampi(level - source.heights[next], 1, 4) != depth_band:
						matches = false
						break
				if not matches:
					break
				back += 1
			for mark_z in range(z, back):
				var mark_row := (mark_z - min_z) * tile_width
				for mark_x in range(x, right):
					used[mark_row + mark_x - min_x] = 1
			var y := float(source.origin_y + level) + 0.02
			var depth := (float(depth_band) - 0.5) / 4.0
			_append_water_rectangle(source, triangles, x, z, right, back, y,
				_color(source, material), Vector2(depth, 0), water_step, level)


static func _append_water_rectangle(source: TerrainResource, triangles: Triangles, x: int, z: int, right: int, back: int,
		y: float, color: Color, uv: Vector2, step: int, level: int) -> void:
	if step <= 0:
		triangles.quad(Vector3(x, y, z), Vector3(x, y, back),
			Vector3(right, y, back), Vector3(right, y, z), color, Vector3.UP, uv)
		return
	# Alpha is visual depth metadata only on the opt-in refined water mesh.
	for cell_z in range(z, back, step):
		var next_z := mini(cell_z + step, back)
		for cell_x in range(x, right, step):
			var next_x := mini(cell_x + step, right)
			triangles.water_quad(Vector3(cell_x, y, cell_z), Vector3(cell_x, y, next_z),
				Vector3(next_x, y, next_z), Vector3(next_x, y, cell_z), color, uv.x,
				[_water_corner_depth(source, cell_x, cell_z, level, triangles.water_depth_cache),
				_water_corner_depth(source, cell_x, next_z, level, triangles.water_depth_cache),
				_water_corner_depth(source, next_x, next_z, level, triangles.water_depth_cache),
				_water_corner_depth(source, next_x, cell_z, level, triangles.water_depth_cache)])


static func _water_corner_depth(source: TerrainResource, x: int, z: int, level: int, cache: Variant = null) -> float:
	var key := Vector3i.ZERO
	if cache != null:
		key = Vector3i(x, z, level)
		var cached := float(cache.get(key, -1.0))
		if cached >= 0.0: return cached
	var total := 0.0
	var count := 0
	for cell_z in range(maxi(z - 1, 0), mini(z, source.depth - 1) + 1):
		for cell_x in range(maxi(x - 1, 0), mini(x, source.width - 1) + 1):
			var index := cell_x + cell_z * source.width
			if source.water_levels[index] == level and source.water_materials[index] > 0 and level > source.heights[index]:
				total += float(level - source.heights[index])
				count += 1
	var depth := clampf(total / float(maxi(count, 1)) / 64.0, 0.0, 1.0)
	if cache != null: cache[key] = depth
	return depth


static func _build_water_walls(source: TerrainResource, triangles: Triangles,
		min_x: int, min_z: int, end_x: int, end_z: int, spill := {}) -> void:
	for z in range(min_z, end_z):
		for x in range(min_x, end_x):
			var index := x + z * source.width
			var level := source.water_levels[index]
			var material := source.water_materials[index]
			if material <= 0 or level <= source.heights[index]:
				continue
			var top := float(source.origin_y + level) + 0.02
			for side in 4:
				if not spill.is_empty():
					var direction: Vector2 = spill.direction
					var edge := Vector2(x if side == 0 else x + 1 if side == 1 else x + 0.5,
						z if side == 2 else z + 1 if side == 3 else z + 0.5)
					var edge_normal: Vector2 = [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN][side]
					var delta: Vector2 = edge - Vector2(spill.center)
					if direction.dot(edge_normal) > 0.9 and absf(delta.dot(direction)) < 0.01 and absf(delta.dot(Vector2(direction.y, -direction.x))) <= float(spill.width) * 0.5:
						continue
				var nx := x - 1 if side == 0 else x + 1 if side == 1 else x
				var nz := z - 1 if side == 2 else z + 1 if side == 3 else z
				var inside := nx >= 0 and nx < source.width and nz >= 0 and nz < source.depth
				var neighbour := nx + nz * source.width if inside else -1
				var neighbour_level := source.water_levels[neighbour] if inside and source.water_materials[neighbour] > 0 and source.water_levels[neighbour] > source.heights[neighbour] else 0
				if neighbour_level >= level:
					continue
				var neighbour_ground := source.heights[neighbour] if inside else 0
				var bottom_level := maxi(source.heights[index],
					maxi(neighbour_ground, neighbour_level))
				if bottom_level >= level:
					continue
				var bottom := float(source.origin_y + bottom_level) + 0.02
				var a: Vector3
				var b: Vector3
				var normal: Vector3
				match side:
					0:
						a = Vector3(x, top, z + 1)
						b = Vector3(x, top, z)
						normal = Vector3.LEFT
					1:
						a = Vector3(x + 1, top, z)
						b = Vector3(x + 1, top, z + 1)
						normal = Vector3.RIGHT
					2:
						a = Vector3(x, top, z)
						b = Vector3(x + 1, top, z)
						normal = Vector3.FORWARD
					3:
						a = Vector3(x + 1, top, z + 1)
						b = Vector3(x, top, z + 1)
						normal = Vector3.BACK
				triangles.water_wall(a, b, Vector3(b.x, bottom, b.z),
					Vector3(a.x, bottom, a.z), _color(source, material), normal,
					_water_corner_depth(source, roundi(a.x), roundi(a.z), level, triangles.water_depth_cache),
					_water_corner_depth(source, roundi(b.x), roundi(b.z), level, triangles.water_depth_cache))


static func _stitch_water_edges(source: TerrainResource, triangles: Triangles,
		min_x: int, min_z: int, end_x: int, end_z: int,
		all_axis_edges := false) -> void:
	if triangles.vertices.is_empty():
		return
	# Separate wet rectangles can meet along only part of an edge. A moving
	# heightfield turns those T-junctions into visible holes. Split both sides
	# at existing vertices, and split tile borders at voxel coordinates so
	# independently built neighbouring tiles always have the same edge points.
	var known_points := {}
	for vertex in triangles.vertices:
		known_points[vertex] = true
	var stitched := Triangles.new()
	for index in range(0, triangles.vertices.size(), 3):
		var border: Array[Vector3] = []
		var border_colors: Array[Color] = []
		var border_uvs: Array[Vector2] = []
		for side in 3:
			var start_index := index + side
			var end_index := index + (side + 1) % 3
			var start := triangles.vertices[start_index]
			var finish := triangles.vertices[end_index]
			var start_color := triangles.colors[start_index]
			var finish_color := triangles.colors[end_index]
			var start_uv := triangles.uvs[start_index]
			var finish_uv := triangles.uvs[end_index]
			border.append(start)
			border_colors.append(start_color)
			border_uvs.append(start_uv)
			for split in _water_edge_splits(known_points, start, finish,
					min_x, min_z, end_x, end_z, all_axis_edges):
				var fraction := start.distance_to(split) / start.distance_to(finish)
				var split_color := start_color.lerp(finish_color, fraction)
				var level := roundi(start.y - 0.02) - source.origin_y
				split_color.a = _water_corner_depth(source, roundi(split.x), roundi(split.z), level, triangles.water_depth_cache)
				border.append(split)
				border_colors.append(split_color)
				border_uvs.append(start_uv.lerp(finish_uv, fraction))
		if border.size() == 3:
			for corner in 3:
				stitched.vertices.append(triangles.vertices[index + corner])
				stitched.normals.append(triangles.normals[index + corner])
				stitched.colors.append(triangles.colors[index + corner])
				stitched.uvs.append(triangles.uvs[index + corner])
			continue
		var center := (triangles.vertices[index] + triangles.vertices[index + 1]
			+ triangles.vertices[index + 2]) / 3.0
		var center_color := triangles.colors[index].lerp(triangles.colors[index + 1], 0.5)
		center_color = center_color.lerp(triangles.colors[index + 2], 1.0 / 3.0)
		var center_uv := (triangles.uvs[index] + triangles.uvs[index + 1]
			+ triangles.uvs[index + 2]) / 3.0
		for corner in border.size():
			var next_corner := (corner + 1) % border.size()
			for point in 3:
				stitched.vertices.append(center if point == 0 else border[corner] if point == 1 else border[next_corner])
				stitched.normals.append(Vector3.UP)
				stitched.colors.append(center_color if point == 0 else border_colors[corner] if point == 1 else border_colors[next_corner])
				stitched.uvs.append(center_uv if point == 0 else border_uvs[corner] if point == 1 else border_uvs[next_corner])
	triangles.vertices = stitched.vertices
	triangles.normals = stitched.normals
	triangles.colors = stitched.colors
	triangles.uvs = stitched.uvs


static func _water_edge_splits(known_points: Dictionary, start: Vector3, finish: Vector3,
		min_x: int, min_z: int, end_x: int, end_z: int,
		all_axis_edges := false) -> Array[Vector3]:
	var splits: Array[Vector3] = []
	if start.x == finish.x:
		var border := roundi(start.x) == min_x or roundi(start.x) == end_x
		for z in range(mini(roundi(start.z), roundi(finish.z)) + 1,
				maxi(roundi(start.z), roundi(finish.z))):
			var point := Vector3(start.x, start.y, float(z))
			if all_axis_edges or border or known_points.has(point):
				splits.append(point)
		if start.z > finish.z:
			splits.reverse()
	elif start.z == finish.z:
		var border := roundi(start.z) == min_z or roundi(start.z) == end_z
		for x in range(mini(roundi(start.x), roundi(finish.x)) + 1,
				maxi(roundi(start.x), roundi(finish.x))):
			var point := Vector3(float(x), start.y, start.z)
			if all_axis_edges or border or known_points.has(point):
				splits.append(point)
		if start.x > finish.x:
			splits.reverse()
	return splits


static func _build_uniform_dry_tile(source: TerrainResource, min_x: int, min_z: int, end_x: int, end_z: int, coalesce: bool) -> Dictionary:
	var geometry_started := Time.get_ticks_usec()
	if min_x >= end_x or min_z >= end_z:
		return {}
	var first_index := min_x + min_z * source.width
	var height := source.heights[first_index]
	var material := int(source.top_materials[first_index])
	if height <= 0 or material <= 0:
		return {}
	# A flat tile needs one top quad. Edge walls still inspect the neighbouring
	# columns so terrain across tile boundaries remains exactly connected.
	for z in range(min_z, end_z):
		var row := z * source.width
		for x in range(min_x, end_x):
			var index := row + x
			if source.heights[index] != height or source.top_materials[index] != material or source.water_levels[index] > height and source.water_materials[index] > 0:
				return {}
	var ground := Triangles.new()
	ground.coalesce_sides = coalesce
	var y := float(source.origin_y + height)
	ground.quad(Vector3(min_x, y, min_z), Vector3(min_x, y, end_z), Vector3(end_x, y, end_z), Vector3(end_x, y, min_z), _ground_color(source, material), Vector3.UP)
	for z in range(min_z, end_z):
		var left := source.heights[min_x - 1 + z * source.width] if min_x > 0 else 0
		if height > left:
			_add_side(source, ground, min_x, z, height, left, 0)
		var right := source.heights[end_x + z * source.width] if end_x < source.width else 0
		if height > right:
			_add_side(source, ground, end_x - 1, z, height, right, 1)
	for x in range(min_x, end_x):
		var front := source.heights[x + (min_z - 1) * source.width] if min_z > 0 else 0
		if height > front:
			_add_side(source, ground, x, min_z, height, front, 2)
		var back := source.heights[x + end_z * source.width] if end_z < source.depth else 0
		if height > back:
			_add_side(source, ground, x, end_z - 1, height, back, 3)
	var geometry_us := Time.get_ticks_usec() - geometry_started
	var resource_started := Time.get_ticks_usec()
	var ground_mesh := ground.mesh()
	return {"terrain": ground_mesh, "water": ArrayMesh.new(), "collision_faces": ground.vertices,
		"water_vertices": 0, "uniform_dry": true,
		"geometry_us": geometry_us, "top_us": 0, "side_us": 0, "water_us": 0, "uniform_us": geometry_us,
		"mesh_resource_us": Time.get_ticks_usec() - resource_started}


static func _color(source: TerrainResource, index: int) -> Color:
	return source.palette[index] if index > 0 and index < source.palette.size() else Color.MAGENTA


static func _ground_color(source: TerrainResource, index: int) -> Color:
	var color := _color(source, index)
	# The shader reads only alpha as an integer palette slot. RGB and collision
	# stay unchanged, including on maps whose slots have no semantic role.
	color.a = float(index) / 255.0
	return color


static func _add_side(source: TerrainResource, triangles: Triangles, x: int, z: int, high: int, low: int, direction: int) -> void:
	if high <= low:
		return
	var index := source.column_index(x, z)
	var cap_start := maxi(0, high - int(source.cap_depths[index]))
	if source.column_material_overrides.has(index):
		var exceptions: Dictionary = source.column_material_overrides[index]
		var at := low
		while at < high:
			var palette: int = int(exceptions.get(at, source.top_materials[index] if at >= cap_start else source.base_materials[index]))
			var end := at + 1
			while end < high and int(exceptions.get(end, source.top_materials[index] if end >= cap_start else source.base_materials[index])) == palette:
				end += 1
			_side_quad(triangles, x, z, at + source.origin_y, end + source.origin_y, direction, _ground_color(source, palette))
			at = end
		return
	if low < cap_start:
		_side_quad(triangles, x, z, low + source.origin_y, cap_start + source.origin_y, direction, _ground_color(source, int(source.base_materials[index])))
	_side_quad(triangles, x, z, maxi(low, cap_start) + source.origin_y, high + source.origin_y, direction, _ground_color(source, int(source.top_materials[index])))


static func _side_quad(triangles: Triangles, x: int, z: int, low: int, high: int, direction: int, color: Color) -> void:
	if high <= low: return
	if triangles.coalesce_sides:
		var plane := x if direction == 0 else x + 1 if direction == 1 else z if direction == 2 else z + 1
		var begin := z if direction < 2 else x
		triangles.side(direction, plane, begin, begin + 1, low, high, color)
		return
	match direction:
		0: triangles.quad(Vector3(x, low, z), Vector3(x, low, z + 1), Vector3(x, high, z + 1), Vector3(x, high, z), color, Vector3.LEFT)
		1: triangles.quad(Vector3(x + 1, low, z), Vector3(x + 1, high, z), Vector3(x + 1, high, z + 1), Vector3(x + 1, low, z + 1), color, Vector3.RIGHT)
		2: triangles.quad(Vector3(x, low, z), Vector3(x, high, z), Vector3(x + 1, high, z), Vector3(x + 1, low, z), color, Vector3.FORWARD)
		3: triangles.quad(Vector3(x, low, z + 1), Vector3(x + 1, low, z + 1), Vector3(x + 1, high, z + 1), Vector3(x, high, z + 1), color, Vector3.BACK)
