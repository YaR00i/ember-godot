@tool
extends Node3D
## Disposable GPU preview: a region grid is allocated once; edits only update its texture.

const Heightfield = preload("res://tools/prototypes/ember_landscape_v2_heightfield.gd")

var source: RefCounted
var palette_colors := PackedColorArray()
var region_views := {}
var _region_queue: Array[Vector2i] = []
var mesh_creations := 0
var texture_uploads := 0
var uploaded_pixels := 0
var edited_chunks := {}
var exact_chunk_size := 16
var _edited_only := false

const HEIGHT_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D height_map : filter_nearest, repeat_disable;
uniform sampler2D color_map : source_color, filter_nearest, repeat_disable;
uniform float vertical_scale = 2.0;
uniform float height_steps = 32.0;
varying float authored_height;
void vertex() {
	authored_height = textureLod(height_map, UV, 0.0).r;
	VERTEX.y = authored_height * vertical_scale;
}
void fragment() {
	if (texture(color_map, UV).a < 0.5) discard;
	ALBEDO = texture(color_map, UV).rgb;
}
"""


func configure(next_source: RefCounted, colors := PackedColorArray()) -> void:
	begin_configure(next_source, colors)
	while not _region_queue.is_empty():
		build_next_region()


func begin_configure(next_source: RefCounted, colors := PackedColorArray(), edited_only := false) -> void:
	source = next_source
	_edited_only = edited_only
	edited_chunks.clear()
	palette_colors = colors if not colors.is_empty() else PackedColorArray([Color.TRANSPARENT, Color("#705447"), Color("#80a46d"), Color("#d1a55f"), Color("#777777")])
	_region_queue = source.all_regions()
	region_views.clear()
	mesh_creations = 0
	texture_uploads = 0
	uploaded_pixels = 0


func pending_regions() -> int:
	return _region_queue.size()


func build_next_region() -> void:
	if _region_queue.is_empty():
		return
	var region: Vector2i = _region_queue.pop_front()
	var shader := Shader.new()
	shader.code = HEIGHT_SHADER
	var rect: Rect2i = source.region_rect(region)
	var image := Image.create(rect.size.x + 1, rect.size.y + 1, false, Image.FORMAT_RF)
	var color_image := Image.create(rect.size.x + 1, rect.size.y + 1, false, Image.FORMAT_RGBA8)
	_write_region_image(rect, image, color_image)
	var texture := ImageTexture.create_from_image(image)
	var color_texture := ImageTexture.create_from_image(color_image)
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("height_map", texture)
	material.set_shader_parameter("color_map", color_texture)
	material.set_shader_parameter("vertical_scale", float(source.size.y) / Heightfield.SAMPLES_PER_BLOCK)
	material.set_shader_parameter("height_steps", float(source.size.y))
	var visual := MeshInstance3D.new()
	visual.mesh = _make_grid(rect)
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	region_views[region] = {"image": image, "color_image": color_image, "texture": texture, "color_texture": color_texture, "mesh": visual.mesh, "node": visual, "rect": rect}
	mesh_creations += 1


func update_regions(regions: Array[Vector2i], changed_samples: Array[Vector2i]) -> Dictionary:
	var started := Time.get_ticks_usec()
	var count := 0
	var pixels := 0
	var samples := changed_samples.duplicate()
	var upload_regions := {}
	for region in regions: upload_regions[region] = true
	if _edited_only:
		for sample in changed_samples:
			var chunk := Vector2i(sample.x / exact_chunk_size, sample.y / exact_chunk_size)
			if edited_chunks.has(chunk): continue
			edited_chunks[chunk] = true
			var start := chunk * exact_chunk_size
			_add_chunk_regions(chunk, upload_regions)
			for z in range(start.y, mini(start.y + exact_chunk_size, source.size.z)):
				for x in range(start.x, mini(start.x + exact_chunk_size, source.size.x)):
					var cell := Vector2i(x, z)
					samples.append(cell)
	for region in upload_regions:
		var view: Dictionary = region_views[region]
		var image: Image = view.image
		var color_image: Image = view.color_image
		var rect: Rect2i = view.rect
		for sample in samples:
			if sample.x < rect.position.x or sample.y < rect.position.y or sample.x > rect.end.x or sample.y > rect.end.y:
				continue
			var height_count: int = int(source.heights[sample.x + sample.y * source.size.x])
			image.set_pixel(sample.x - rect.position.x, sample.y - rect.position.y, Color(float(height_count) / float(source.size.y), 0.0, 0.0))
			color_image.set_pixel(sample.x - rect.position.x, sample.y - rect.position.y, _sample_color(sample.x, sample.y))
		(view.texture as ImageTexture).update(image)
		(view.color_texture as ImageTexture).update(color_image)
		count += 1
		pixels += image.get_width() * image.get_height()
	texture_uploads += count
	uploaded_pixels += pixels
	return {"cpu_usec": Time.get_ticks_usec() - started, "regions": count, "pixels": pixels}


func clear_edited_chunks() -> void:
	if edited_chunks.is_empty(): return
	var touched_regions := {}
	for chunk in edited_chunks:
		_add_chunk_regions(chunk, touched_regions)
	edited_chunks.clear()
	for region in touched_regions:
		var view: Dictionary = region_views[region]
		_write_region_image(view.rect, view.image, view.color_image)
		(view.color_texture as ImageTexture).update(view.color_image)


func _add_chunk_regions(chunk: Vector2i, target: Dictionary) -> void:
	var start := chunk * exact_chunk_size
	# Region grids share a one-sample border; include the previous region when
	# a newly edited exact chunk begins on that border.
	var first := Vector2i(maxi(0, start.x - 1) / Heightfield.REGION, maxi(0, start.y - 1) / Heightfield.REGION)
	var last := Vector2i(mini(source.size.x - 1, start.x + exact_chunk_size) / Heightfield.REGION, mini(source.size.z - 1, start.y + exact_chunk_size) / Heightfield.REGION)
	for z in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			target[Vector2i(x, z)] = true


func _write_region_image(rect: Rect2i, image: Image, color_image: Image) -> void:
	for local_z in range(rect.size.y + 1):
		for local_x in range(rect.size.x + 1):
			var x := mini(source.size.x - 1, rect.position.x + local_x)
			var z := mini(source.size.z - 1, rect.position.y + local_z)
			var height_count: int = int(source.heights[x + z * source.size.x])
			image.set_pixel(local_x, local_z, Color(float(height_count) / float(source.size.y), 0.0, 0.0))
			color_image.set_pixel(local_x, local_z, _sample_color(x, z))


func _sample_color(x: int, z: int) -> Color:
	if _edited_only and not edited_chunks.has(Vector2i(x / exact_chunk_size, z / exact_chunk_size)):
		return Color.TRANSPARENT
	var index: int = int(source.controls[x + z * source.size.x])
	return palette_colors[index] if index >= 0 and index < palette_colors.size() else Color("#705447")


func _make_grid(rect: Rect2i) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var stride := rect.size.x + 1
	for z in range(rect.size.y + 1):
		for x in range(rect.size.x + 1):
			vertices.append(Vector3(float(rect.position.x + x) / Heightfield.SAMPLES_PER_BLOCK, 0.0, float(rect.position.y + z) / Heightfield.SAMPLES_PER_BLOCK))
			uvs.append(Vector2(float(x) / rect.size.x, float(z) / rect.size.y))
	for z in rect.size.y:
		for x in rect.size.x:
			var a := x + z * stride
			var b := a + 1
			var c := a + stride
			var d := c + 1
			indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
