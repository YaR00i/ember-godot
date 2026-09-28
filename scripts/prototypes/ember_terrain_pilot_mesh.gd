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

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, normal: Vector3, uv := Vector2.ZERO) -> void:
		# Godot's front-face winding is clockwise from the visible side.
		for point in [a, c, b, a, d, c]:
			vertices.append(point)
			normals.append(normal)
			colors.append(color)
			uvs.append(uv)

	func mesh() -> ArrayMesh:
		var result := ArrayMesh.new()
		if vertices.is_empty():
			return result
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return result


static func build_tile(source: TerrainResource, min_x: int, min_z: int, tile_size: int) -> Dictionary:
	var geometry_started := Time.get_ticks_usec()
	var end_x := mini(source.width, min_x + tile_size)
	var end_z := mini(source.depth, min_z + tile_size)
	var uniform := _build_uniform_dry_tile(source, min_x, min_z, end_x, end_z)
	if not uniform.is_empty():
		return uniform
	var grouped := _build_grouped_tile(source, min_x, min_z, end_x, end_z)
	if not grouped.is_empty():
		return grouped
	var ground := Triangles.new()
	var water := Triangles.new()
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
	_build_water_rectangles(source, water, min_x, min_z, end_x, end_z)
	var water_us := Time.get_ticks_usec() - pass_started
	var geometry_us := Time.get_ticks_usec() - geometry_started
	var resource_started := Time.get_ticks_usec()
	var ground_mesh := ground.mesh()
	var water_mesh := water.mesh()
	return {"terrain": ground_mesh, "water": water_mesh, "collision_faces": ground.vertices,
		"water_vertices": water.vertices.size(), "uniform_dry": false,
		"geometry_us": geometry_us, "top_us": top_us, "side_us": side_us, "water_us": water_us, "uniform_us": 0,
		"mesh_resource_us": Time.get_ticks_usec() - resource_started}


static func _build_grouped_tile(source: TerrainResource, min_x: int, min_z: int, end_x: int, end_z: int) -> Dictionary:
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
	var water_mesh_data := Triangles.new()
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
			ground.quad(Vector3(x, y, z), Vector3(x, y, min_z + back * GROUP_SIZE), Vector3(min_x + right * GROUP_SIZE, y, min_z + back * GROUP_SIZE), Vector3(min_x + right * GROUP_SIZE, y, z), _color(source, tops[first]), Vector3.UP)
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
			water_mesh_data.quad(Vector3(x, y, z), Vector3(x, y, min_z + back * GROUP_SIZE), Vector3(min_x + right * GROUP_SIZE, y, min_z + back * GROUP_SIZE), Vector3(min_x + right * GROUP_SIZE, y, z), _color(source, material), Vector3.UP, Vector2((float(band) - 0.5) / 4.0, 0))
	var water_us := Time.get_ticks_usec() - pass_started
	var geometry_us := Time.get_ticks_usec() - started
	var resource_started := Time.get_ticks_usec()
	var ground_mesh := ground.mesh()
	var water_mesh := water_mesh_data.mesh()
	return {"terrain": ground_mesh, "water": water_mesh, "collision_faces": ground.vertices,
		"water_vertices": water_mesh_data.vertices.size(), "uniform_dry": false, "grouped_8": true,
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
		_group_side_quad(triangles, x, z, low + source.origin_y, cap_start + source.origin_y, direction, _color(source, base))
	_group_side_quad(triangles, x, z, maxi(low, cap_start) + source.origin_y, high + source.origin_y, direction, _color(source, top))


static func _group_side_quad(triangles: Triangles, x: int, z: int, low: int, high: int, direction: int, color: Color) -> void:
	if high <= low: return
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
			triangles.quad(Vector3(x, y, z), Vector3(x, y, back), Vector3(right, y, back), Vector3(right, y, z), _color(source, material), Vector3.UP)
	return skip_sides


static func _build_water_rectangles(source: TerrainResource, triangles: Triangles, min_x: int, min_z: int, end_x: int, end_z: int) -> void:
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
			triangles.quad(Vector3(x, y, z), Vector3(x, y, back), Vector3(right, y, back), Vector3(right, y, z), _color(source, material), Vector3.UP, Vector2(depth, 0))


static func _build_uniform_dry_tile(source: TerrainResource, min_x: int, min_z: int, end_x: int, end_z: int) -> Dictionary:
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
	var y := float(source.origin_y + height)
	ground.quad(Vector3(min_x, y, min_z), Vector3(min_x, y, end_z), Vector3(end_x, y, end_z), Vector3(end_x, y, min_z), _color(source, material), Vector3.UP)
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
			_side_quad(triangles, x, z, at + source.origin_y, end + source.origin_y, direction, _color(source, palette))
			at = end
		return
	if low < cap_start:
		_side_quad(triangles, x, z, low + source.origin_y, cap_start + source.origin_y, direction, _color(source, int(source.base_materials[index])))
	_side_quad(triangles, x, z, maxi(low, cap_start) + source.origin_y, high + source.origin_y, direction, _color(source, int(source.top_materials[index])))


static func _side_quad(triangles: Triangles, x: int, z: int, low: int, high: int, direction: int, color: Color) -> void:
	if high <= low:
		return
	match direction:
		0:
			triangles.quad(Vector3(x, low, z), Vector3(x, low, z + 1), Vector3(x, high, z + 1), Vector3(x, high, z), color, Vector3.LEFT)
		1:
			triangles.quad(Vector3(x + 1, low, z), Vector3(x + 1, high, z), Vector3(x + 1, high, z + 1), Vector3(x + 1, low, z + 1), color, Vector3.RIGHT)
		2:
			triangles.quad(Vector3(x, low, z), Vector3(x, high, z), Vector3(x + 1, high, z), Vector3(x + 1, low, z), color, Vector3.FORWARD)
		3:
			triangles.quad(Vector3(x, low, z + 1), Vector3(x + 1, low, z + 1), Vector3(x + 1, high, z + 1), Vector3(x, high, z + 1), color, Vector3.BACK)
