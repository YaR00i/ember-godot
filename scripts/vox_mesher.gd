class_name VoxMesher
extends RefCounted
## MagicaVoxel Z-up → Ember/Godot Y-up: ember(x, y, z) = vox(x, z, y).
## Same mapping as joi-conductor `emberVoxCodec.ts`.

const VOXELS_PER_BLOCK := 16
const DENSE_VOXELS_PER_BLOCK := 32
const OCCLUSION_TRANSPARENCY_MAX := 127


static func ember_size(vox_size: Vector3i) -> Vector3i:
	return Vector3i(vox_size.x, vox_size.z, vox_size.y)


static func vox_to_ember(vx: int, vy: int, vz: int) -> Vector3i:
	return Vector3i(vx, vz, vy)


static func ember_grid_size(model: Dictionary) -> Vector3i:
	var density := voxels_per_block(model)
	var blocks: Dictionary = model.get("sizeBlocks", {})
	var sx := maxi(1, int(blocks.get("x", 1))) * density
	var sz := maxi(1, int(blocks.get("z", 1))) * density
	var from_blocks := maxi(1, int(blocks.get("y", 1))) * density
	var sy := from_blocks
	if model.has("heightVoxels"):
		sy = clampi(int(model.get("heightVoxels", from_blocks)), 1, 8 * density)
	return Vector3i(sx, sy, sz)


static func voxels_per_block(model: Dictionary) -> int:
	return DENSE_VOXELS_PER_BLOCK if int(model.get("voxelsPerBlock", VOXELS_PER_BLOCK)) == DENSE_VOXELS_PER_BLOCK else VOXELS_PER_BLOCK


static func normalized_voxel_size(model: Dictionary) -> float:
	return 1.0 / float(voxels_per_block(model))


static func cell_index(x: int, y: int, z: int, sx: int, sz: int) -> int:
	return x + z * sx + y * sx * sz


static func apply_skip(filled: PackedByteArray, skip: PackedByteArray) -> void:
	if skip.is_empty() or skip.size() != filled.size():
		return
	for i in filled.size():
		if skip[i] != 0:
			filled[i] = 0


static func model_channel(model: Dictionary, key: String) -> PackedByteArray:
	var size := ember_grid_size(model)
	var n := size.x * size.y * size.z
	var out := PackedByteArray()
	out.resize(n)
	out.fill(0)
	var raw: Variant = model.get(key, [])
	if raw is PackedByteArray:
		var packed := raw as PackedByteArray
		for i in mini(n, packed.size()):
			out[i] = packed[i]
		return out
	if typeof(raw) != TYPE_ARRAY:
		return out
	var values := raw as Array
	for i in mini(n, values.size()):
		out[i] = clampi(int(values[i]), 0, 255)
	return out


static func opacity_from_transparency(amount: int) -> float:
	var t := clampf(float(amount) / 255.0, 0.0, 1.0)
	# Match JOI: even maximum transparency keeps a little glass body.
	return maxf(0.08, 1.0 - t * 0.92)


static func build_from_ember_model(
	model: Dictionary,
	voxel_size := 1.0,
	skip := PackedByteArray(),
) -> ArrayMesh:
	return _build_from_ember_model_region(
		model, voxel_size, skip, Vector3i.ZERO, Vector3i(-1, -1, -1)
	)


static func build_from_ember_model_region(
	model: Dictionary,
	region_min: Vector3i,
	region_size: Vector3i,
	voxel_size := 1.0,
	skip := PackedByteArray(),
) -> ArrayMesh:
	return _build_from_ember_model_region(model, voxel_size, skip, region_min, region_size)


static func build_from_packed_voxel_region(
	voxels: PackedByteArray,
	global_size: Vector3i,
	palette: PackedColorArray,
	transparency: PackedByteArray,
	region_min: Vector3i,
	region_size: Vector3i,
	voxel_size := 1.0,
	skip := PackedByteArray(),
	visible_height := -1,
) -> ArrayMesh:
	var expected := global_size.x * global_size.y * global_size.z
	if expected < 1 or voxels.size() != expected:
		return ArrayMesh.new()
	global_size = preload("res://scripts/ember_voxel_edit_bounds.gd").visible_size(global_size, visible_height)
	return _build_padded_voxel_region(
		voxels,
		global_size,
		_colors_from_packed_palette(palette),
		transparency,
		region_min,
		region_size,
		voxel_size,
		skip,
	)


static func build_heightfield_preview_region(
	voxels: PackedByteArray,
	global_size: Vector3i,
	palette: PackedColorArray,
	transparency: PackedByteArray,
	region_min: Vector3i,
	region_size: Vector3i,
	voxel_size := 1.0,
) -> ArrayMesh:
	var expected := global_size.x * global_size.y * global_size.z
	if expected < 1 or voxels.size() != expected:
		return ArrayMesh.new()
	var start := Vector3i(
		clampi(region_min.x, 0, global_size.x),
		0,
		clampi(region_min.z, 0, global_size.z),
	)
	var end := Vector3i(
		clampi(start.x + region_size.x, start.x, global_size.x),
		global_size.y,
		clampi(start.z + region_size.z, start.z, global_size.z),
	)
	var opaque_vertices := PackedVector3Array()
	var opaque_normals := PackedVector3Array()
	var opaque_colors := PackedColorArray()
	var opaque_indices := PackedInt32Array()
	var transparent_vertices := PackedVector3Array()
	var transparent_normals := PackedVector3Array()
	var transparent_colors := PackedColorArray()
	var transparent_indices := PackedInt32Array()
	# Cache the one-cell padded heightfield once. Looking up the four neighbor
	# columns by rescanning Y was the remaining dominant cost in GDScript.
	var cache_min := Vector2i(maxi(0, start.x - 1), maxi(0, start.z - 1))
	var cache_max := Vector2i(
		mini(global_size.x, end.x + 1), mini(global_size.z, end.z + 1)
	)
	var cache_size := cache_max - cache_min
	var heights := PackedInt32Array()
	heights.resize(cache_size.x * cache_size.y)
	heights.fill(-1)
	for cached_z in range(cache_min.y, cache_max.y):
		for cached_x in range(cache_min.x, cache_max.x):
			heights[
				(cached_x - cache_min.x) + (cached_z - cache_min.y) * cache_size.x
			] = _packed_column_top(voxels, global_size, cached_x, cached_z)
	var side_normals := [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]
	var side_offsets := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for z in range(start.z, end.z):
		for x in range(start.x, end.x):
			var top := heights[(x - cache_min.x) + (z - cache_min.y) * cache_size.x]
			if top < 0:
				continue
			_append_packed_preview_face(
				voxels, global_size, palette, transparency, x, top, z, Vector3.UP,
				opaque_vertices, opaque_normals, opaque_colors, opaque_indices,
				transparent_vertices, transparent_normals, transparent_colors,
				transparent_indices, voxel_size,
			)
			for face_index in 4:
				var offset: Vector2i = side_offsets[face_index]
				var nx := x + offset.x
				var nz := z + offset.y
				var neighbor_top := -1
				if nx >= cache_min.x and nz >= cache_min.y and nx < cache_max.x and nz < cache_max.y:
					neighbor_top = heights[
						(nx - cache_min.x) + (nz - cache_min.y) * cache_size.x
					]
				for y in range(neighbor_top + 1, top + 1):
					var voxel_index := cell_index(x, y, z, global_size.x, global_size.z)
					if voxels[voxel_index] == 0:
						continue
					_append_packed_preview_face(
						voxels, global_size, palette, transparency, x, y, z,
						side_normals[face_index],
						opaque_vertices, opaque_normals, opaque_colors, opaque_indices,
						transparent_vertices, transparent_normals, transparent_colors,
						transparent_indices, voxel_size,
					)
	var mesh := ArrayMesh.new()
	_append_array_mesh_surface(
		mesh, opaque_vertices, opaque_normals, opaque_colors, opaque_indices, "opaque"
	)
	_append_array_mesh_surface(
		mesh,
		transparent_vertices,
		transparent_normals,
		transparent_colors,
		transparent_indices,
		"transparent",
	)
	return mesh


static func _build_from_ember_model_region(
	model: Dictionary,
	voxel_size: float,
	skip: PackedByteArray,
	region_min: Vector3i,
	region_size: Vector3i,
) -> ArrayMesh:
	var size := ember_grid_size(model)
	var voxels: Variant = model.get("voxels", [])
	var n := size.x * size.y * size.z
	var valid_voxels := voxels is Array or voxels is PackedByteArray
	if n < 1 or not valid_voxels or voxels.is_empty():
		return ArrayMesh.new()
	if region_size.x >= 0 and region_size.y >= 0 and region_size.z >= 0:
		return _build_padded_model_region(
			model, voxels, size, region_min, region_size, voxel_size, skip
		)
	var filled := PackedByteArray()
	filled.resize(n)
	filled.fill(0)
	var index_at := PackedInt32Array()
	index_at.resize(n)
	index_at.fill(0)
	var any := false
	var limit := mini(n, voxels.size())
	for i in limit:
		var pi := int(voxels[i])
		if pi <= 0:
			continue
		filled[i] = 1
		index_at[i] = pi
		any = true
	if not any:
		return ArrayMesh.new()
	apply_skip(filled, skip)
	var transparency := model_channel(model, "transparency")
	var colors := _model_colors(model)
	return _build_culled(
		size.x, size.y, size.z, filled, index_at, colors, transparency, voxel_size,
		region_min, region_size,
	)


static func _build_padded_model_region(
	model: Dictionary,
	voxels: Variant,
	global_size: Vector3i,
	region_min: Vector3i,
	region_size: Vector3i,
	voxel_size: float,
	skip: PackedByteArray,
) -> ArrayMesh:
	return _build_padded_voxel_region(
		voxels,
		global_size,
		_model_colors(model),
		model.get("transparency", []),
		region_min,
		region_size,
		voxel_size,
		skip,
	)


static func _build_padded_voxel_region(
	voxels: Variant,
	global_size: Vector3i,
	colors: PackedColorArray,
	raw_transparency: Variant,
	region_min: Vector3i,
	region_size: Vector3i,
	voxel_size: float,
	skip: PackedByteArray,
) -> ArrayMesh:
	var start := Vector3i(
		clampi(region_min.x, 0, global_size.x),
		clampi(region_min.y, 0, global_size.y),
		clampi(region_min.z, 0, global_size.z),
	)
	var end := Vector3i(
		clampi(start.x + region_size.x, start.x, global_size.x),
		clampi(start.y + region_size.y, start.y, global_size.y),
		clampi(start.z + region_size.z, start.z, global_size.z),
	)
	if start == end:
		return ArrayMesh.new()
	# One-voxel padding keeps occlusion correct across preview chunk seams while
	# avoiding a scan/allocation for the entire connected canvas.
	var padded_start := Vector3i(
		maxi(0, start.x - 1), maxi(0, start.y - 1), maxi(0, start.z - 1)
	)
	var padded_end := Vector3i(
		mini(global_size.x, end.x + 1),
		mini(global_size.y, end.y + 1),
		mini(global_size.z, end.z + 1),
	)
	var local_size := padded_end - padded_start
	var local_count := local_size.x * local_size.y * local_size.z
	var filled := PackedByteArray()
	filled.resize(local_count)
	filled.fill(0)
	var index_at := PackedInt32Array()
	index_at.resize(local_count)
	index_at.fill(0)
	var transparency := PackedByteArray()
	transparency.resize(local_count)
	transparency.fill(0)
	var any := false
	for local_y in local_size.y:
		for local_z in local_size.z:
			for local_x in local_size.x:
				var global_cell := padded_start + Vector3i(local_x, local_y, local_z)
				var global_index := cell_index(
					global_cell.x, global_cell.y, global_cell.z,
					global_size.x, global_size.z,
				)
				if skip.size() == global_size.x * global_size.y * global_size.z and skip[global_index] != 0:
					continue
				var palette_index := _raw_byte(voxels, global_index)
				var local_index := cell_index(local_x, local_y, local_z, local_size.x, local_size.z)
				transparency[local_index] = _raw_byte(raw_transparency, global_index)
				if palette_index <= 0:
					continue
				filled[local_index] = 1
				index_at[local_index] = palette_index
				any = true
	if not any:
		return ArrayMesh.new()
	return _build_culled(
		local_size.x, local_size.y, local_size.z,
		filled, index_at, colors, transparency, voxel_size,
		start - padded_start, end - start, padded_start,
	)


static func _raw_byte(values: Variant, index: int) -> int:
	if index < 0:
		return 0
	if values is PackedByteArray:
		return int(values[index]) if index < values.size() else 0
	if values is Array:
		return int(values[index]) if index < values.size() else 0
	return 0


static func _packed_column_top(
	voxels: PackedByteArray,
	size: Vector3i,
	x: int,
	z: int,
) -> int:
	for y in range(size.y - 1, -1, -1):
		if voxels[cell_index(x, y, z, size.x, size.z)] != 0:
			return y
	return -1


static func _append_packed_preview_face(
	voxels: PackedByteArray,
	size: Vector3i,
	palette: PackedColorArray,
	transparency: PackedByteArray,
	x: int,
	y: int,
	z: int,
	normal: Vector3,
	opaque_vertices: PackedVector3Array,
	opaque_normals: PackedVector3Array,
	opaque_colors: PackedColorArray,
	opaque_indices: PackedInt32Array,
	transparent_vertices: PackedVector3Array,
	transparent_normals: PackedVector3Array,
	transparent_colors: PackedColorArray,
	transparent_indices: PackedInt32Array,
	voxel_size: float,
) -> void:
	var voxel_index := cell_index(x, y, z, size.x, size.z)
	var palette_index := clampi(int(voxels[voxel_index]), 0, palette.size() - 1)
	var color := palette[palette_index] if palette_index < palette.size() else Color(0.55, 0.52, 0.48)
	var transparency_amount := int(transparency[voxel_index]) if voxel_index < transparency.size() else 0
	color.a *= opacity_from_transparency(transparency_amount)
	if transparency_amount > 0:
		_append_face_arrays(
			transparent_vertices, transparent_normals, transparent_colors, transparent_indices,
			Vector3(x, y, z), normal, color, voxel_size,
		)
	else:
		_append_face_arrays(
			opaque_vertices, opaque_normals, opaque_colors, opaque_indices,
			Vector3(x, y, z), normal, color, voxel_size,
		)


static func _model_colors(model: Dictionary) -> PackedColorArray:
	var colors := PackedColorArray()
	colors.resize(256)
	colors.fill(Color(0.55, 0.52, 0.48))
	var raw_palette: Variant = model.get("palette", [])
	if not raw_palette is Array:
		return colors
	var palette := raw_palette as Array
	for palette_index in palette.size():
		if palette_index <= 0 or palette_index >= 256:
			continue
		colors[palette_index] = EmberLights.hex_color(
			str(palette[palette_index]), Color(0.5, 0.5, 0.5)
		)
	return colors


static func _colors_from_packed_palette(palette: PackedColorArray) -> PackedColorArray:
	var colors := PackedColorArray()
	colors.resize(256)
	colors.fill(Color(0.55, 0.52, 0.48))
	for palette_index in mini(palette.size(), 256):
		if palette_index > 0:
			colors[palette_index] = palette[palette_index]
	return colors


static func build_mesh(
	doc: Dictionary,
	voxel_size := 1.0,
	skip := PackedByteArray(),
	transparency := PackedByteArray(),
) -> ArrayMesh:
	if doc.is_empty() or (doc.get("models", []) as Array).is_empty():
		return ArrayMesh.new()
	var model: Dictionary = doc.models[0]
	var vox_size: Vector3i = model.size
	var sx: int = vox_size.x
	var sy: int = vox_size.z
	var sz: int = vox_size.y
	var filled := PackedByteArray()
	filled.resize(sx * sy * sz)
	filled.fill(0)
	var index_at := PackedInt32Array()
	index_at.resize(sx * sy * sz)
	index_at.fill(0)
	for v in model.voxels:
		if int(v.i) <= 0:
			continue
		var e := vox_to_ember(int(v.x), int(v.y), int(v.z))
		if e.x < 0 or e.y < 0 or e.z < 0 or e.x >= sx or e.y >= sy or e.z >= sz:
			continue
		var i := cell_index(e.x, e.y, e.z, sx, sz)
		filled[i] = 1
		index_at[i] = int(v.i)
	apply_skip(filled, skip)
	if transparency.size() != filled.size():
		transparency = PackedByteArray()
		transparency.resize(filled.size())
		transparency.fill(0)
	var colors := PackedColorArray()
	colors.resize(256)
	var palette: PackedByteArray = doc.palette
	for pi in 256:
		colors[pi] = _palette_color(palette, pi)
	return _build_culled(sx, sy, sz, filled, index_at, colors, transparency, voxel_size)


static func _build_culled(
	sx: int,
	sy: int,
	sz: int,
	filled: PackedByteArray,
	index_at: PackedInt32Array,
	colors: PackedColorArray,
	transparency: PackedByteArray,
	voxel_size: float,
	region_min := Vector3i.ZERO,
	region_size := Vector3i(-1, -1, -1),
	cell_origin := Vector3i.ZERO,
) -> ArrayMesh:
	# This is the shared editor/runtime hot path. Building indexed buffers directly
	# avoids six SurfaceTool calls per quad followed by SurfaceTool.index() hashing.
	# Flat voxel faces deliberately keep four vertices per quad because adjacent
	# faces have different normals/colors and therefore cannot share them.
	var opaque_vertices := PackedVector3Array()
	var opaque_normals := PackedVector3Array()
	var opaque_colors := PackedColorArray()
	var opaque_indices := PackedInt32Array()
	var transparent_vertices := PackedVector3Array()
	var transparent_normals := PackedVector3Array()
	var transparent_colors := PackedColorArray()
	var transparent_indices := PackedInt32Array()
	var faces := [
		{"n": Vector3.RIGHT, "d": Vector3i(1, 0, 0)},
		{"n": Vector3.LEFT, "d": Vector3i(-1, 0, 0)},
		{"n": Vector3.UP, "d": Vector3i(0, 1, 0)},
		{"n": Vector3.DOWN, "d": Vector3i(0, -1, 0)},
		{"n": Vector3.BACK, "d": Vector3i(0, 0, 1)},
		{"n": Vector3.FORWARD, "d": Vector3i(0, 0, -1)},
	]
	var start := Vector3i(
		clampi(region_min.x, 0, sx),
		clampi(region_min.y, 0, sy),
		clampi(region_min.z, 0, sz),
	)
	var end := Vector3i(sx, sy, sz)
	if region_size.x >= 0 and region_size.y >= 0 and region_size.z >= 0:
		end = Vector3i(
			clampi(start.x + region_size.x, start.x, sx),
			clampi(start.y + region_size.y, start.y, sy),
			clampi(start.z + region_size.z, start.z, sz),
		)
	for y in range(start.y, end.y):
		for z in range(start.z, end.z):
			for x in range(start.x, end.x):
				var i := cell_index(x, y, z, sx, sz)
				if filled[i] == 0:
					continue
				var pi := clampi(index_at[i], 0, colors.size() - 1)
				var color: Color = colors[pi]
				var transparency_amount := int(transparency[i]) if i < transparency.size() else 0
				color.a *= opacity_from_transparency(transparency_amount)
				for face in faces:
					var d: Vector3i = face.d
					var nx := x + d.x
					var ny := y + d.y
					var nz := z + d.z
					var exposed := (
						nx < 0 or ny < 0 or nz < 0 or nx >= sx or ny >= sy or nz >= sz
						or not _occludes(filled, transparency, cell_index(nx, ny, nz, sx, sz))
					)
					if exposed:
						if transparency_amount > 0:
							_append_face_arrays(
								transparent_vertices,
								transparent_normals,
								transparent_colors,
								transparent_indices,
								Vector3(Vector3i(x, y, z) + cell_origin),
								face.n,
								color,
								voxel_size,
							)
						else:
							_append_face_arrays(
								opaque_vertices,
								opaque_normals,
								opaque_colors,
								opaque_indices,
								Vector3(Vector3i(x, y, z) + cell_origin),
								face.n,
								color,
								voxel_size,
							)
	var mesh := ArrayMesh.new()
	_append_array_mesh_surface(
		mesh, opaque_vertices, opaque_normals, opaque_colors, opaque_indices, "opaque"
	)
	_append_array_mesh_surface(
		mesh,
		transparent_vertices,
		transparent_normals,
		transparent_colors,
		transparent_indices,
		"transparent",
	)
	return mesh


static func _occludes(
	filled: PackedByteArray,
	transparency: PackedByteArray,
	index: int,
) -> bool:
	if index < 0 or index >= filled.size() or filled[index] == 0:
		return false
	return index >= transparency.size() or transparency[index] <= OCCLUSION_TRANSPARENCY_MAX


static func _palette_color(palette: PackedByteArray, pi: int) -> Color:
	var o := clampi(pi, 0, 255) * 4
	if o + 3 >= palette.size():
		return Color(0.6, 0.6, 0.6)
	return Color(
		palette[o] / 255.0,
		palette[o + 1] / 255.0,
		palette[o + 2] / 255.0,
		palette[o + 3] / 255.0,
	)


static func _append_face_arrays(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	cell: Vector3,
	normal: Vector3,
	color: Color,
	s: float,
) -> void:
	var o := cell * s
	var a: Vector3
	var b: Vector3
	var c: Vector3
	var d: Vector3
	if normal == Vector3.RIGHT:
		a = o + Vector3(s, 0, s)
		b = o + Vector3(s, s, s)
		c = o + Vector3(s, s, 0)
		d = o + Vector3(s, 0, 0)
	elif normal == Vector3.LEFT:
		a = o + Vector3(0, 0, 0)
		b = o + Vector3(0, s, 0)
		c = o + Vector3(0, s, s)
		d = o + Vector3(0, 0, s)
	elif normal == Vector3.UP:
		a = o + Vector3(0, s, s)
		b = o + Vector3(0, s, 0)
		c = o + Vector3(s, s, 0)
		d = o + Vector3(s, s, s)
	elif normal == Vector3.DOWN:
		a = o + Vector3(0, 0, 0)
		b = o + Vector3(0, 0, s)
		c = o + Vector3(s, 0, s)
		d = o + Vector3(s, 0, 0)
	elif normal == Vector3.BACK:
		a = o + Vector3(0, 0, s)
		b = o + Vector3(0, s, s)
		c = o + Vector3(s, s, s)
		d = o + Vector3(s, 0, s)
	else:
		a = o + Vector3(s, 0, 0)
		b = o + Vector3(s, s, 0)
		c = o + Vector3(0, s, 0)
		d = o + Vector3(0, 0, 0)
	var first := vertices.size()
	vertices.append(a)
	vertices.append(b)
	vertices.append(c)
	vertices.append(d)
	for unused in 4:
		normals.append(normal)
		colors.append(color)
	indices.append(first)
	indices.append(first + 1)
	indices.append(first + 2)
	indices.append(first)
	indices.append(first + 2)
	indices.append(first + 3)


static func _append_array_mesh_surface(
	mesh: ArrayMesh,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	surface_name: String,
) -> void:
	if vertices.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_name(mesh.get_surface_count() - 1, surface_name)
