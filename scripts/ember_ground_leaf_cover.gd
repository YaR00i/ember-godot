@tool
extends RefCounted
## Derived texture and folded leaves for the existing painted detail mask.

const KIND := 4
const GROUND_LAYER := 1 << 15
const DETAIL := preload("res://scripts/ember_detail_scatter.gd")
const PRESET_PATH := "res://content/terrain_materials/covers/ground_leaves.tres"
const PAINTED_GROUP := &"ember_ground_leaf_patches"
const PIXELS_PER_CELL := 16
const MAX_FOLDED_LEAVES := 18
static var _leaves: Array[Image] = []
static var _stamps: Dictionary = {}
static var _folded_material: StandardMaterial3D
static var preset: EmberCompactTerrainPattern = preload(PRESET_PATH)

static func painted_density_at(map: Node3D, unit: float, point: Vector3) -> float:
	var local := map.to_local(point) / unit
	var ground := Vector2(local.x, local.z)
	var address := DETAIL.patch_address(ground)
	var group := DETAIL.ground_cover_group(map.get_instance_id(), KIND, address)
	var patch := map.get_tree().get_first_node_in_group(group)
	if patch == null: return 0.0
	var cell := DETAIL.cell_address(ground) - address * DETAIL.CELLS
	return float(patch.density_cells.get(cell, 0)) / DETAIL.MAX_DENSITY


static func paint_texture(cells: Dictionary, seed: int, leaf_scale: float) -> ImageTexture:
	if _leaves.is_empty():
		var atlas := preset.albedo_texture
		var source := atlas.get_image()
		if source.is_compressed():
			source.decompress()
		source.convert(Image.FORMAT_RGBA8)
		var half := source.get_size() / 2
		for y in 2:
			for x in 2:
				var leaf := source.get_region(Rect2i(Vector2i(x, y) * half, half))
				leaf.resize(64, 64, Image.INTERPOLATE_LANCZOS)
				_leaves.append(leaf)
	var resolution := DETAIL.CELLS * PIXELS_PER_CELL
	var result := Image.create_empty(resolution, resolution, false, Image.FORMAT_RGBA8)
	var ordered := cells.keys()
	ordered.sort()
	for cell: Vector2i in ordered:
		var random := RandomNumberGenerator.new()
		random.seed = hash(Vector3i(cell.x, cell.y, seed))
		var coverage := float(cells[cell]) / DETAIL.MAX_DENSITY
		if random.randf() >= coverage:
			continue
		var kind := random.randi_range(0, _leaves.size() - 1)
		var pixels := clampi(roundi(random.randf_range(14.0, 26.0) * leaf_scale), 4, 64)
		var key := Vector2i(kind, pixels)
		if not _stamps.has(key):
			var stamp := _leaves[kind].duplicate() as Image
			stamp.resize(pixels, pixels, Image.INTERPOLATE_LANCZOS)
			var shade := Image.create_empty(pixels, pixels, false, Image.FORMAT_RGBA8)
			for y in pixels:
				for x in pixels:
					var color := stamp.get_pixel(x, y)
					var alpha := smoothstep(0.18, 0.76, color.a)
					color = color.lerp(Color(0.43, 0.28, 0.14), 0.18)
					color.a = alpha
					stamp.set_pixel(x, y, color)
					shade.set_pixel(x, y, Color(0.18, 0.10, 0.05, alpha * 0.28))
			_stamps[key] = [stamp, shade]
		var center := cell * PIXELS_PER_CELL + Vector2i(random.randi_range(2, 14), random.randi_range(2, 14))
		var destination := center - Vector2i.ONE * (pixels / 2)
		_blend_stamp(result, _stamps[key][1], destination + Vector2i.ONE)
		_blend_stamp(result, _stamps[key][0], destination)
	result.fix_alpha_edges()
	result.generate_mipmaps()
	return ImageTexture.create_from_image(result)


static func _blend_stamp(target: Image, stamp: Image, destination: Vector2i) -> void:
	var clipped := Rect2i(destination, stamp.get_size()).intersection(Rect2i(Vector2i.ZERO, target.get_size()))
	if clipped.has_area():
		target.blend_rect(stamp, Rect2i(clipped.position - destination, clipped.size), clipped.position)


static func folded_mesh(cells: Dictionary, world_from_patch: Transform3D, floor_sample: Callable,
		unit: float, seed: int, leaf_scale: float, density := 1.0) -> ArrayMesh:
	var limit := roundi(MAX_FOLDED_LEAVES * density)
	if limit <= 0: return null
	var ordered := cells.keys()
	ordered.sort()
	var random := RandomNumberGenerator.new()
	random.seed = seed
	# Shuffle with the tile seed so full patches don't concentrate geometry at one edge.
	for i in range(ordered.size() - 1, 0, -1):
		var j := random.randi_range(0, i)
		var cell: Vector2i = ordered[i]
		ordered[i] = ordered[j]
		ordered[j] = cell
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	var patch_from_world := world_from_patch.affine_inverse()
	var count := 0
	for cell: Vector2i in ordered:
		if random.randf() >= float(cells[cell]) / DETAIL.MAX_DENSITY * 0.17 * density:
			continue
		var offset := Vector2(random.randf_range(0.27, 0.73), random.randf_range(0.27, 0.73))
		var position := (Vector2(cell) + offset) * DETAIL.CELL_M * unit
		var hit: Dictionary = floor_sample.call(world_from_patch * Vector3(position.x, 0.0, position.y))
		if not hit.get("solid", false):
			continue
		var center: Vector3 = hit.position
		var width := clampf(random.randf_range(0.19, 0.29) * leaf_scale, 0.045, 0.50) * unit
		var angle := random.randf() * TAU
		var along := Vector3(cos(angle), 0.0, sin(angle))
		var across := Vector3(-along.z, 0.0, along.x)
		var support_a: Dictionary = floor_sample.call(center + along * width * 0.5)
		var support_b: Dictionary = floor_sample.call(center + across * width * 0.5)
		if not support_a.get("solid", false) or not support_b.get("solid", false):
			continue
		var tangent_a: Vector3 = support_a.position - center
		var tangent_b: Vector3 = support_b.position - center
		# Leave very steep or discontinuous edges to the projected texture.
		if absf(tangent_a.y) > width * 0.42 or absf(tangent_b.y) > width * 0.42:
			continue
		along = tangent_a.normalized()
		across = tangent_b.slide(along).normalized()
		var up := across.cross(along).normalized()
		var tile := Vector2(random.randi_range(0, 1), random.randi_range(0, 1))
		var lift := random.randf_range(0.10, 0.19)
		var points := [
			Vector3(-0.5, 0.012, -0.5), Vector3(0.5, lift, -0.5),
			Vector3(-0.5, 0.018, 0.5), Vector3(0.5, lift * 0.42, 0.5),
			Vector3(0.0, lift * 0.45, 0.0),
		]
		var uvs := [Vector2.ZERO, Vector2(1, 0), Vector2(0, 1), Vector2.ONE, Vector2(0.5, 0.5)]
		for index in [0, 4, 1, 1, 4, 3, 3, 4, 2, 2, 4, 0]:
			var point: Vector3 = points[index]
			builder.set_uv((uvs[index] * 0.98 + Vector2.ONE * 0.01 + tile) * 0.5)
			builder.add_vertex(patch_from_world * (center + up * unit * 0.004
				+ (along * point.x + up * point.y + across * point.z) * width))
		count += 1
		if count >= limit:
			break
	if count == 0:
		return null
	builder.generate_normals()
	return builder.commit()


static func folded_material() -> StandardMaterial3D:
	if _folded_material == null:
		_folded_material = StandardMaterial3D.new()
		_folded_material.albedo_texture = preset.albedo_texture
		_folded_material.albedo_color = Color(0.76, 0.66, 0.55)
		_folded_material.roughness = 1.0
		_folded_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_folded_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		_folded_material.alpha_scissor_threshold = 0.40
	return _folded_material
