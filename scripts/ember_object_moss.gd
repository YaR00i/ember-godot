@tool
extends RefCounted
## One bounded object-local mask. The shared stone mesh and collision are never modified.

const SIZE := 32
const BYTE_COUNT := SIZE * SIZE * SIZE
const MAX_TUFTS := 3200
const GROUND_KIND := 5
const PRESET_PATH := "res://content/terrain_materials/moss.tres"
const PAINTED_GROUP := &"ember_moss_covered_props"
const Detail := preload("res://scripts/ember_detail_scatter.gd")
const GROUND_TEXTURE_SIZE := 64
const GROUND_APRON := 4
const GROUND_HALO := 2
static var preset: EmberCompactTerrainPattern = preload(PRESET_PATH)
static var _tuft_material: StandardMaterial3D


static func dab(mask: PackedByteArray, bounds: AABB, frame: Transform3D, point: Vector3,
		normal: Vector3, radius: float, strength: float, erase: bool) -> PackedByteArray:
	if not bounds.has_volume() or radius <= 0.0 or strength <= 0.0 or (mask.is_empty() and erase):
		return mask
	var result := mask.duplicate()
	if result.size() != BYTE_COUNT:
		result.resize(BYTE_COUNT)
		result.fill(0)
	var cell := bounds.size / float(SIZE)
	var scale := frame.basis.get_scale().abs()
	if minf(scale.x, minf(scale.y, scale.z)) <= 0.00001:
		return mask
	var center := frame.affine_inverse() * point
	var thickness := maxf((cell * scale).length() * 0.9, radius * 0.30)
	var local_radius := Vector3.ONE * Vector2(radius, thickness).length() / scale
	var first := Vector3i(((center - local_radius - bounds.position) / cell).floor()).max(Vector3i.ZERO)
	var last := Vector3i(((center + local_radius - bounds.position) / cell).ceil()).min(Vector3i.ONE * (SIZE - 1))
	for z in range(first.z, last.z + 1):
		for y in range(first.y, last.y + 1):
			for x in range(first.x, last.x + 1):
				var local := bounds.position + (Vector3(x, y, z) + Vector3.ONE * 0.5) * cell
				var delta := frame * local - point
				var depth := absf(delta.dot(normal))
				var lateral := delta.slide(normal).length()
				var weight := (1.0 - smoothstep(radius * 0.60, radius, lateral)) * (1.0 - smoothstep(thickness * 0.65, thickness, depth))
				var index := x + SIZE * (y + SIZE * z)
				var amount := roundi(weight * strength * 255.0)
				result[index] = roundi(result[index] * (1.0 - weight * strength)) if erase else maxi(result[index], amount)
	return result


static func texture(mask: PackedByteArray) -> ImageTexture3D:
	var images: Array[Image] = []
	var slice_size := SIZE * SIZE
	for z in SIZE:
		images.append(Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_R8,
			mask.slice(z * slice_size, (z + 1) * slice_size)))
	var result := ImageTexture3D.new()
	return result if result.create(Image.FORMAT_R8, SIZE, SIZE, SIZE, false, images) == OK else null


static func saved_detail() -> Vector3:
	return Vector3(preset.detail_height, preset.detail_width, preset.detail_density)


static func ground_texture(cells: Dictionary, halo := {}) -> ImageTexture:
	var image := preset.albedo_texture.get_image() if preset.albedo_texture != null else preset.to_image()
	if image == null or image.is_empty(): return null
	if image.is_compressed() and image.decompress() != OK: return null
	image.clear_mipmaps()
	image.resize(GROUND_TEXTURE_SIZE, GROUND_TEXTURE_SIZE, Image.INTERPOLATE_BILINEAR)
	var size := GROUND_TEXTURE_SIZE + 2 * GROUND_APRON
	var result := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var mask := cells.duplicate()
	mask.merge(halo)
	var samples := PackedVector3Array()
	var blend_radius := GROUND_APRON - 0.5
	for pixel in size:
		var local := pixel - GROUND_APRON + 0.5
		var coordinate := local * Detail.CELLS / GROUND_TEXTURE_SIZE - 0.5
		var enter := smoothstep(-blend_radius, blend_radius, local)
		var leave := smoothstep(GROUND_TEXTURE_SIZE - blend_radius, GROUND_TEXTURE_SIZE + blend_radius, local)
		var ownership := enter * (1.0 - leave)
		samples.append(Vector3(floorf(coordinate), fposmod(coordinate, 1.0), ownership))
	for y in size:
		for x in size:
			var cell := Vector2i(int(samples[x].x), int(samples[y].x))
			var top := lerpf(mask.get(cell, 0.0), mask.get(cell + Vector2i.RIGHT, 0.0), samples[x].y)
			var bottom := lerpf(mask.get(cell + Vector2i.DOWN, 0.0), mask.get(cell + Vector2i.ONE, 0.0), samples[x].y)
			var opacity := lerpf(top, bottom, samples[y].y) / 200.0
			var color := image.get_pixel(posmod(x - GROUND_APRON, GROUND_TEXTURE_SIZE), posmod(y - GROUND_APRON, GROUND_TEXTURE_SIZE))
			# Overlapping decals compose alpha multiplicatively. The two
			# ownership weights add to one (four at the intersection).
			# Even saturated paint must have a transparent outer texel, so
			# atlas filtering cannot pull a dark line from outside this decal.
			var transmission := maxf(1.0 - opacity, 1.0 / 255.0)
			color.a = 1.0 - pow(transmission, samples[x].z * samples[y].z)
			result.set_pixel(x, y, color)
	result.generate_mipmaps()
	return ImageTexture.create_from_image(result)


static func ground_tuft_mesh(hits: Dictionary, cells: Dictionary, frame: Transform3D,
		unit: float, seed: int, detail: Vector3) -> ArrayMesh:
	if detail.z <= 0.0: return null
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var keys := hits.keys()
	keys.sort()
	var inverse := frame.affine_inverse()
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 0
	for cell: Vector2i in keys:
		var hit: Dictionary = hits[cell]
		var normal: Vector3 = (frame.basis.transposed() * hit.get("normal", Vector3.UP)).normalized()
		var center: Vector3 = inverse * hit.position
		var tangent := Basis(Quaternion(Vector3.UP, normal))
		var weight := float(cells[cell]) / 200.0
		var amount := roundi(minf(680.0 * Detail.CELL_M * Detail.CELL_M, float(MAX_TUFTS) / keys.size()) * detail.z * weight)
		for sample in amount:
			var offset := Vector3(rng.randf_range(-0.46, 0.46), 0.0, rng.randf_range(-0.46, 0.46))
			var point := center + tangent * offset * (unit * Detail.CELL_M)
			_append_tuft(builder, rng, point, normal, weight, Vector2(detail.x, detail.y), unit)
			count += 1
			if count >= MAX_TUFTS: return _finish_tufts(builder, count)
	return _finish_tufts(builder, count)


static func bark_faces(source: Mesh) -> PackedVector3Array:
	var arrays := source.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: Variant = arrays[Mesh.ARRAY_INDEX]
	if indices == null or indices.is_empty(): return vertices
	var faces := PackedVector3Array()
	faces.resize(indices.size())
	for i in indices.size(): faces[i] = vertices[indices[i]]
	return faces


static func tuft_mesh(source: Mesh, bounds: AABB, mask: PackedByteArray, detail: Vector3, bark_only := false) -> ArrayMesh:
	if detail.z <= 0.0: return null
	var faces := bark_faces(source) if bark_only else source.get_faces()
	var areas := PackedFloat32Array()
	var total := 0.0
	for i in range(0, faces.size(), 3):
		total += (faces[i + 2] - faces[i]).cross(faces[i + 1] - faces[i]).length() * 0.5
		areas.append(total)
	var samples := ceili(minf(22000.0, total * 680.0) * detail.z)
	if samples <= 0: return null
	var rng := RandomNumberGenerator.new()
	rng.seed = 4139
	var tuft_rng := RandomNumberGenerator.new()
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 0
	for sample in samples:
		var index := areas.bsearch(total * rng.randf()) * 3
		if index >= faces.size(): break
		var a := faces[index]
		var ab := faces[index + 1] - a
		var ac := faces[index + 2] - a
		var normal := ac.cross(ab).normalized()
		var t := sqrt(rng.randf())
		var s := rng.randf()
		var point := a + ab * (t * (1.0 - s)) + ac * (t * s)
		var cell := Vector3i((((point - bounds.position) / bounds.size) * SIZE).floor())
		cell = cell.clamp(Vector3i.ZERO, Vector3i.ONE * (SIZE - 1))
		var weight := float(mask[cell.x + SIZE * (cell.y + SIZE * cell.z)]) / 255.0
		if rng.randf() > smoothstep(0.14, 0.87, weight): continue
		tuft_rng.seed = sample + 4139
		_append_tuft(builder, tuft_rng, point, normal, weight, Vector2(detail.x, detail.y))
		count += 1
		if count >= MAX_TUFTS: break
	return _finish_tufts(builder, count)


static func _finish_tufts(builder: SurfaceTool, count: int) -> ArrayMesh:
	if count == 0: return null
	if _tuft_material == null:
		_tuft_material = StandardMaterial3D.new()
		_tuft_material.vertex_color_use_as_albedo = true
		_tuft_material.vertex_color_is_srgb = true
		_tuft_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_tuft_material.roughness = 0.95
	builder.set_material(_tuft_material)
	return builder.commit()


static func _append_tuft(builder: SurfaceTool, rng: RandomNumberGenerator, point: Vector3, normal: Vector3,
		weight: float, size: Vector2, unit := 1.0) -> void:
	var basis := Basis(Quaternion(Vector3.UP, normal))
	var root_color := Color("71963a")
	var tip_color := Color("9cb951").lerp(Color("b2c963"), rng.randf())
	for blade in 4:
		var angle := rng.randf_range(0.0, TAU)
		var lean := basis * Vector3(cos(angle), 0.0, sin(angle))
		var side := normal.cross(lean) * rng.randf_range(0.004, 0.009) * size.y * unit
		var base := point + (normal * 0.004 + lean * rng.randf_range(0.0, 0.015)) * unit
		var tip := base + (normal * rng.randf_range(0.022, 0.054) * lerpf(0.60, 1.0, weight) * size.x + lean * 0.022) * unit
		builder.set_normal(normal)
		builder.set_color(root_color)
		builder.add_vertex(base - side)
		builder.add_vertex(base + side)
		builder.set_color(tip_color)
		builder.add_vertex(tip)
