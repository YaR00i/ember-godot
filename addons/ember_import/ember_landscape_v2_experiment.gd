@tool
extends RefCounted
## Temporary editor-only gate. Never owns a scene, save file or gameplay data.
## Only EmberWorldEditor may instantiate this, and only for the disposable lab scene.

const Heightfield = preload("res://tools/prototypes/ember_landscape_v2_heightfield.gd")
const GpuPreview = preload("res://tools/prototypes/ember_landscape_v2_gpu_preview.gd")
const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")

var field: RefCounted
var preview: Node3D
var resource: EmberVoxelModelResource
var projection: Node3D
var prepared := false
var _scan_column := 0
var _scan_values := PackedByteArray()
var _source_heights := PackedInt32Array()
var _source_controls := PackedByteArray()
var _changed_columns := {}
var _applied_amount := {}
var _bake_queue: Array[int] = []
var _bake_cursor := 0
var _scope := Rect2i()
var _mode := ""
var _depth := 0
var _radius := 0
var _level := 0
var _empty_floor := -1
var _palette := 1
var _hidden_material: ShaderMaterial
var _hidden_surfaces := {}
var last_bake_preview_sync_usec := 0


func begin_prepare(source: EmberVoxelModelResource, parent: Node3D, frame: Transform3D) -> void:
	clear()
	resource = source
	field = Heightfield.new()
	field.configure(Vector2i(source.size_blocks.x, source.size_blocks.z), source.height_voxels)
	_scan_values = source.voxels
	_scan_column = 0
	preview = GpuPreview.new()
	parent.add_child(preview, false, Node.INTERNAL_MODE_BACK)
	preview.global_transform = frame
	preview.visible = false
	prepared = false
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded, depth_draw_never, cull_disabled; void fragment() { ALPHA = 0.0; }"
	_hidden_material = ShaderMaterial.new()
	_hidden_material.shader = shader


func prepare_step(budget_usec := 4000) -> bool:
	if prepared:
		return true
	var size: Vector3i = field.size
	var started := Time.get_ticks_usec()
	if _scan_column < size.x * size.z:
		while _scan_column < size.x * size.z and Time.get_ticks_usec() - started < budget_usec:
			var top := -1
			for y in range(size.y - 1, -1, -1):
				var value := int(_scan_values[_scan_column + y * size.x * size.z])
				if value != 0:
					top = y
					field.controls[_scan_column] = value
					break
			field.heights[_scan_column] = top + 1
			if top < 0:
				field.controls[_scan_column] = 0
			_scan_column += 1
		if _scan_column == size.x * size.z:
			_scan_values = PackedByteArray()
			preview.begin_configure(field, resource.palette, true)
		return false
	if preview.pending_regions() > 0:
		preview.build_next_region()
		return false
	prepared = true
	return true


func preparation_progress() -> String:
	if field == null:
		return "нет данных"
	var columns: int = field.size.x * field.size.z
	return "высоты %d/%d" % [_scan_column, columns] if _scan_column < columns else "GPU-регионы %d/%d" % [preview.mesh_creations, preview.mesh_creations + preview.pending_regions()]


func begin_stroke(baseline: EmberVoxelModelResource, mode: String, radius: int, depth: int, level: int, palette: int, scope: Rect2i, next_projection: Node3D, empty_floor := -1) -> void:
	assert(prepared)
	assert(mode in ["level", "raise", "lower"])
	_source_heights = field.heights.duplicate()
	_source_controls = field.controls.duplicate()
	_changed_columns.clear()
	_applied_amount.clear()
	_bake_queue.clear()
	_bake_cursor = 0
	_mode = mode
	_radius = radius
	_depth = depth
	_level = level
	_empty_floor = empty_floor
	_palette = palette
	_scope = scope
	projection = next_projection
	if is_instance_valid(projection): preview.exact_chunk_size = projection.chunk_size
	preview.visible = true
	ensure_ground_hidden()


func cancel_stroke() -> void:
	# Keep the previous committed preview visible while its exact projection
	# catches up. Only the current gesture's height/control samples are restored.
	field.last_input_regions.clear()
	field.last_changed_samples.clear()
	for raw_column in _changed_columns:
		var column := int(raw_column)
		var cell := Vector2i(column % field.size.x, column / field.size.x)
		field.set_height_sample(cell, int(_source_heights[column]))
		field.set_control(cell, int(_source_controls[column]))
	if not field.last_changed_samples.is_empty():
		preview.update_regions(field.sorted_regions(field.last_input_regions), field.last_changed_samples)
	_changed_columns.clear()
	_bake_queue.clear()
	_bake_cursor = 0


func apply_sample(from: Vector3i, to: Vector3i) -> Dictionary:
	var started := Time.get_ticks_usec()
	field.last_input_regions.clear()
	field.last_changed_samples.clear()
	if _mode == "level":
		field.apply_level_segment(from, to, _level, _radius, _scope)
	else:
		var amounts: Dictionary = Model._relief_segment_amount_changes(field.size, from, to, _radius, _depth, 0, false, _applied_amount, _scope)
		for raw_column in amounts:
			var column := int(raw_column)
			var base_top := int(_source_heights[column]) - 1
			if base_top < 0 and _mode == "raise" and _empty_floor >= 0:
				base_top = mini(field.size.y - 1, _empty_floor)
			var amount := int((amounts[raw_column] as Vector2i).y)
			var next_top := mini(field.size.y - 1, base_top + amount) if _mode == "raise" else maxi(-1, base_top - amount)
			field.set_height_sample(Vector2i(column % field.size.x, column / field.size.x), next_top + 1)
	for raw_cell in field.last_changed_samples.duplicate():
		var cell: Vector2i = raw_cell
		var column: int = cell.x + cell.y * int(field.size.x)
		if int(field.heights[column]) == 0:
			field.set_control(cell, 0)
		elif int(_source_heights[column]) == 0:
			field.set_control(cell, _palette)
	for cell in field.last_changed_samples:
		_changed_columns[cell.x + cell.y * field.size.x] = true
	var brush_usec := Time.get_ticks_usec() - started
	var upload: Dictionary = preview.update_regions(field.sorted_regions(field.last_input_regions), field.last_changed_samples)
	ensure_ground_hidden()
	return {"height_cpu_usec": brush_usec, "upload_cpu_usec": int(upload.cpu_usec), "changed_columns": field.last_changed_samples.size(), "texture_regions": int(upload.regions)}


func pick(ray_origin: Vector3, ray_direction: Vector3) -> Dictionary:
	# During the gesture the canonical fine voxels are deliberately unchanged.
	# Picking them would make the brush lag behind the displaced preview surface.
	if not prepared or ray_direction.is_zero_approx():
		return {}
	var direction := ray_direction.normalized()
	var density := float(Heightfield.SAMPLES_PER_BLOCK)
	var interval: Vector2 = Model._ray_box_interval(ray_origin, direction, Vector3(field.size) / density)
	if interval.x < 0.0 or interval.y < interval.x:
		return {}
	var step := 0.32 / density
	var distance := maxf(interval.x, 0.0) + step * 0.25
	var last_empty := Model.INVALID_CELL
	var previous := Model.INVALID_CELL
	while distance <= interval.y + step:
		var point := ray_origin + direction * distance
		var cell := Vector3i(clampi(floori(point.x * density), 0, field.size.x - 1), clampi(floori(point.y * density), 0, field.size.y - 1), clampi(floori(point.z * density), 0, field.size.z - 1))
		if cell != previous:
			var column: int = cell.x + cell.z * int(field.size.x)
			if cell.y < int(field.heights[column]):
				var normal := Model.axis_normal(last_empty - cell) if last_empty != Model.INVALID_CELL else Vector3i.UP
				return {"hit": cell, "adjacent": last_empty, "normal": normal, "view_normal": -direction, "ray_origin": ray_origin, "ray_direction": direction}
			last_empty = cell
			previous = cell
		distance += step
	return {}


func begin_bake() -> void:
	_bake_queue.clear()
	for raw_index in _changed_columns:
		_bake_queue.append(int(raw_index))
	_bake_queue.sort()
	_bake_cursor = 0


func bake_done() -> bool:
	return _bake_cursor >= _bake_queue.size()


func bake_step(baseline: EmberVoxelModelResource, budget_usec := 4000) -> Dictionary:
	var started := Time.get_ticks_usec()
	last_bake_preview_sync_usec = 0
	var changes := {}
	var size: Vector3i = field.size
	var values := baseline.voxels
	while not bake_done() and Time.get_ticks_usec() - started < budget_usec:
		var column := _bake_queue[_bake_cursor]
		_bake_cursor += 1
		var before_count := int(_source_heights[column])
		var after_count := int(field.heights[column])
		if after_count == before_count:
			continue
		for y in range(mini(before_count, after_count), maxi(before_count, after_count)):
			var index := column + y * size.x * size.z
			var before := int(values[index])
			var after := _palette if after_count > before_count and before == 0 else 0 if after_count < before_count else before
			if before != after:
				changes[index] = {"before": before, "after": after}
	if bake_done():
		var preview_sync_started := Time.get_ticks_usec()
		_sync_baked_preview_controls(baseline)
		last_bake_preview_sync_usec = Time.get_ticks_usec() - preview_sync_started
	return changes


func _sync_baked_preview_controls(baseline: EmberVoxelModelResource) -> void:
	# The next gesture reuses this preview. Its top palette must match the fine
	# result just baked, not the top palette scanned before the previous gesture.
	field.last_input_regions.clear()
	field.last_changed_samples.clear()
	var size: Vector3i = field.size
	var layer_stride := size.x * size.z
	for raw_column in _changed_columns:
		var column := int(raw_column)
		var before_count := int(_source_heights[column])
		var after_count := int(field.heights[column])
		if after_count == before_count:
			continue
		var top_palette := 0
		if after_count > before_count:
			top_palette = _palette
		elif after_count > 0:
			top_palette = int(baseline.voxels[column + (after_count - 1) * layer_stride])
		field.set_control(Vector2i(column % size.x, column / size.x), top_palette)
	if not field.last_changed_samples.is_empty():
		preview.update_regions(field.sorted_regions(field.last_input_regions), field.last_changed_samples)


func ensure_ground_hidden() -> void:
	if not is_instance_valid(projection):
		return
	for chunk in preview.edited_chunks:
		var visual: MeshInstance3D = projection._chunks.get(chunk)
		if not is_instance_valid(visual) or not visual.mesh is ArrayMesh:
			continue
		var key: int = int(visual.get_instance_id())
		if not _hidden_surfaces.has(key):
			_hidden_surfaces[key] = {"node": weakref(visual), "surfaces": {}}
		var saved: Dictionary = _hidden_surfaces[key].surfaces
		for index in visual.mesh.get_surface_count():
			var surface_name: StringName = (visual.mesh as ArrayMesh).surface_get_name(index)
			if surface_name in ["water", "water_foam"]:
				continue
			if not saved.has(index):
				saved[index] = {"name": surface_name, "material": visual.get_surface_override_material(index)}
			if visual.get_surface_override_material(index) != _hidden_material:
				visual.set_surface_override_material(index, _hidden_material)


func end_visual() -> void:
	for saved in _hidden_surfaces.values():
		var visual: MeshInstance3D = saved.node.get_ref()
		if not is_instance_valid(visual) or not visual.mesh is ArrayMesh:
			continue
		for raw_index in saved.surfaces:
			var index := int(raw_index)
			if index >= visual.mesh.get_surface_count():
				continue
			var original: Dictionary = saved.surfaces[index]
			var current_name: StringName = (visual.mesh as ArrayMesh).surface_get_name(index)
			visual.set_surface_override_material(index, original.material if current_name == original.name else null)
	_hidden_surfaces.clear()
	if is_instance_valid(preview):
		preview.visible = false
		preview.clear_edited_chunks()
	projection = null


func clear() -> void:
	end_visual()
	if is_instance_valid(preview):
		preview.free()
	preview = null
	field = null
	resource = null
	prepared = false
	_scan_values = PackedByteArray()
	_source_heights = PackedInt32Array()
	_source_controls = PackedByteArray()
	_changed_columns.clear()
	_applied_amount.clear()
	_bake_queue.clear()
