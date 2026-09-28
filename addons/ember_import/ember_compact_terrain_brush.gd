@tool
extends RefCounted
## Column brush adapter for the existing World Editor input and Undo history.

const BrushMath = preload("res://scripts/prototypes/ember_terrain_pilot_brush_math.gd")
const TerrainResource = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")

var _entry: Dictionary
var _history: Object
var _scene: Node
var _mode := ""
var _cell_stride := 1
var _height_step := 1
var _shape := "circle"
var _radius := 1
var _depth := 1
var _palette := 1
var _water_level := 0
var _target_height := -1
var _last := Vector2i(-1, -1)
var _indices := PackedInt32Array()
var _touched := PackedByteArray()
var _influence := PackedInt32Array()
var _before_heights := PackedInt32Array()
var _before_tops := PackedByteArray()
var _before_waters := PackedInt32Array()
var _before_water_colors := PackedByteArray()
var _noise: FastNoiseLite
var _detail := 0
var _direction := 0
var _falloff_by_distance := PackedFloat64Array()
var _amount_by_distance := PackedInt32Array()
var _strength_by_distance := PackedInt32Array()
var _row_extents := PackedInt32Array()
var _group_offsets := PackedInt32Array()
var diagnostic_sink: RefCounted


func configure(entry: Dictionary, history: Object, scene: Node) -> void:
	_entry = entry
	_history = history
	_scene = scene


func active() -> bool:
	return not _mode.is_empty()


func begin(mode: String, radius_blocks: float, depth_voxels: int, palette_index: int, water_world: int, feature_scale: int, detail: int, seed: int, direction: int, target_world := -99999, edit_scale := "detail", brush_shape := "auto", requested_height_step := 0) -> bool:
	if _entry.is_empty() or active():
		return false
	var source: TerrainResource = _entry.resource
	if mode not in ["raise", "lower", "level", "smooth", "generator", "paint", "water", "dry"]:
		return false
	_mode = mode
	var profile := BrushMath.edit_profile(edit_scale, brush_shape, requested_height_step)
	_cell_stride = int(profile.cell_stride)
	_height_step = int(profile.height_step)
	_shape = str(profile.shape)
	_group_offsets.resize(_cell_stride * _cell_stride)
	for oz in _cell_stride:
		for ox in _cell_stride:
			_group_offsets[ox + oz * _cell_stride] = ox + oz * source.width
	_radius = clampi(roundi(radius_blocks * (float(TerrainResource.CELLS_PER_BLOCK) / float(_cell_stride))), 1, 128)
	_depth = clampi(depth_voxels, 1, source.height_limit)
	_palette = clampi(palette_index, 1, source.palette.size() - 1)
	_water_level = clampi(water_world - source.origin_y, 0, source.height_limit)
	_target_height = clampi(target_world - source.origin_y, 1, source.height_limit) if target_world > -99999 else -1
	if _target_height >= 0: _target_height = BrushMath.stepped_height(_target_height, _height_step, source.height_limit)
	_detail = clampi(detail, 0, 5)
	_direction = clampi(direction, -1, 1)
	var distance_count := _radius * _radius + 1
	_falloff_by_distance.resize(distance_count)
	_amount_by_distance.resize(distance_count)
	_strength_by_distance.resize(distance_count)
	_row_extents.resize(_radius * 2 + 1)
	for distance_squared in distance_count:
		var influence := BrushMath.falloff_squared(distance_squared, _radius)
		_falloff_by_distance[distance_squared] = influence
		_amount_by_distance[distance_squared] = ceili(float(BrushMath.relief_amount(influence, _depth)) / float(_height_step)) * _height_step
		_strength_by_distance[distance_squared] = roundi(influence * 4096.0)
	for dz in range(-_radius, _radius + 1):
		_row_extents[dz + _radius] = _radius if _shape == "square" else floori(sqrt(float(_radius * _radius - dz * dz)))
	_last = Vector2i(-1, -1)
	_indices = PackedInt32Array()
	_touched = PackedByteArray()
	_touched.resize(source.heights.size())
	_influence = PackedInt32Array()
	_influence.resize(source.heights.size())
	_before_heights = source.heights.duplicate()
	_before_tops = source.top_materials.duplicate()
	_before_waters = source.water_levels.duplicate()
	_before_water_colors = source.water_materials.duplicate()
	if mode == "generator":
		_noise = FastNoiseLite.new()
		_noise.seed = seed
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.frequency = 1.0 / float(clampi(ceili(float(feature_scale) / float(_cell_stride)), 4 / _cell_stride, 64 / _cell_stride))
		_noise.fractal_type = FastNoiseLite.FRACTAL_FBM if _detail > 0 else FastNoiseLite.FRACTAL_NONE
		_noise.fractal_octaves = maxi(1, _detail)
		_noise.fractal_gain = 0.5
		_noise.fractal_lacunarity = 2.0
	var projection := _live_projection()
	if projection != null: projection.begin_live_brush()
	return true


func stamp(cell: Vector2i, bounds := Rect2i()) -> void:
	if not active():
		return
	if _last.x < 0:
		_stamp_point(cell, bounds, Vector2i(-1, -1))
	else:
		var previous_point := _last
		var spacing := maxf(float(_cell_stride), float(_radius * _cell_stride) * (1.0 if _cell_stride > 1 else 0.5))
		var steps := maxi(1, ceili(Vector2(_last).distance_to(Vector2(cell)) / spacing))
		for step in range(1, steps + 1):
			var point := Vector2(_last).lerp(Vector2(cell), float(step) / float(steps))
			var next_point := Vector2i(roundi(point.x), roundi(point.y))
			_stamp_point(next_point, bounds, previous_point)
			previous_point = next_point
	_last = cell


func _stamp_point(cell: Vector2i, bounds: Rect2i, previous_center: Vector2i) -> void:
	var source: TerrainResource = _entry.resource
	if cell.x < 0 or cell.y < 0 or cell.x >= source.width or cell.y >= source.depth:
		return
	var center := Vector2i(cell.x / _cell_stride, cell.y / _cell_stride)
	var group_width := source.width / _cell_stride
	var group_depth := source.depth / _cell_stride
	var can_skip_previous := _cell_stride == 1 and _shape == "circle" and _mode in ["raise", "lower", "generator"] and previous_center.x >= 0 and previous_center.y >= 0 and previous_center.x < source.width and previous_center.y < source.depth
	var center_delta := center - previous_center if can_skip_previous else Vector2i.ZERO
	var delta_squared := center_delta.length_squared()
	if can_skip_previous and delta_squared == 0:
		return
	if _mode == "level" and _target_height < 0:
		_target_height = BrushMath.group_height(_before_heights, source.width, center.x * _cell_stride, center.y * _cell_stride, _cell_stride, _height_step, source.height_limit)
	var gather_started := Time.get_ticks_usec() if diagnostic_sink != null else 0
	var indices := PackedInt32Array()
	var heights := PackedInt32Array()
	var tops := PackedByteArray()
	var waters := PackedInt32Array()
	var water_colors := PackedByteArray()
	var changes_height := _mode in ["raise", "lower", "level", "smooth", "generator"]
	var repeated_height := _mode in ["raise", "lower", "generator"]
	var paint_surface := _mode == "paint"
	var fill_water := _mode == "water"
	var clear_water := _mode == "dry"
	var square := _shape == "square"
	var coarse := _cell_stride > 1
	for dz in range(-_radius, _radius + 1):
		var group_z := center.y + dz
		if group_z < 0 or group_z >= group_depth: continue
		var extent := _row_extents[dz + _radius]
		var min_dx := maxi(-extent, -center.x)
		var max_dx := mini(extent, group_width - center.x - 1)
		if can_skip_previous:
			var row_offset := 2 * dz * center_delta.y + delta_squared
			if center_delta.x > 0:
				min_dx = maxi(min_dx, floori(-float(row_offset) / float(2 * center_delta.x)) + 1)
			elif center_delta.x < 0:
				max_dx = mini(max_dx, ceili(-float(row_offset) / float(2 * center_delta.x)) - 1)
			elif row_offset <= 0:
				continue
		for dx in range(min_dx, max_dx + 1):
			var distance := maxi(absi(dx), absi(dz)) if square else 0
			var distance_squared := distance * distance if square else dx * dx + dz * dz
			var influence: float = _falloff_by_distance[distance_squared]
			if coarse and influence <= 0.0: continue
			var group_x := center.x + dx
			var x := group_x * _cell_stride
			var z := group_z * _cell_stride
			if bounds.has_area() and (x < bounds.position.x or z < bounds.position.y or x + _cell_stride > bounds.end.x or z + _cell_stride > bounds.end.y): continue
			var representative := x + z * source.width
			if repeated_height:
				var strength := _strength_by_distance[distance_squared] if _mode == "generator" else _amount_by_distance[distance_squared]
				if strength <= _influence[representative]: continue
				_influence[representative] = strength
			elif _touched[representative] != 0:
				continue
			var height := 0
			if changes_height:
				var baseline: int = _before_heights[representative] if _cell_stride == 1 else BrushMath.group_height(_before_heights, source.width, x, z, _cell_stride, _height_step, source.height_limit)
				match _mode:
					"raise": height = clampi(baseline + _amount_by_distance[distance_squared], 1, source.height_limit) if _height_step == 1 else BrushMath.stepped_height(baseline + _amount_by_distance[distance_squared], _height_step, source.height_limit)
					"lower": height = clampi(baseline - _amount_by_distance[distance_squared], 1, source.height_limit) if _height_step == 1 else BrushMath.stepped_height(baseline - _amount_by_distance[distance_squared], _height_step, source.height_limit)
					"level": height = _target_height
					"smooth": height = clampi(BrushMath.smooth_height(_before_heights, source.width, source.depth, x, z, _depth, influence), 1, source.height_limit) if _cell_stride == 1 else BrushMath.smooth_group_height(_before_heights, source.width, source.depth, group_x, group_z, _cell_stride, _height_step, maxi(1, _depth / _height_step), influence, source.height_limit)
					"generator":
						var steps := BrushMath.noise_offset(_noise, group_x, group_z, influence, maxi(1, _depth / _height_step), _detail, _direction)
						height = clampi(baseline + steps, 1, source.height_limit) if _height_step == 1 else BrushMath.stepped_height(baseline + steps * _height_step, _height_step, source.height_limit)
			var group_changed := false
			for offset in _group_offsets:
				var index := representative + offset
				var next_height: int = height if changes_height else source.heights[index]
				var next_top: int = _palette if paint_surface else source.top_materials[index]
				var next_water: int = _water_level if fill_water else 0 if clear_water else source.water_levels[index]
				var next_water_color: int = _palette if fill_water else 0 if clear_water else source.water_materials[index]
				if next_height == source.heights[index] and next_top == source.top_materials[index] and next_water == source.water_levels[index] and next_water_color == source.water_materials[index]: continue
				if _touched[index] == 0:
					_touched[index] = 1
					_indices.append(index)
				group_changed = true
				indices.append(index)
				heights.append(next_height)
				tops.append(next_top)
				waters.append(next_water)
				water_colors.append(next_water_color)
			if group_changed: _touched[representative] = 1
	if diagnostic_sink != null:
		diagnostic_sink.stage("brush_collect", Time.get_ticks_usec() - gather_started)
	if not indices.is_empty(): _apply(source, _entry.target, indices, heights, tops, waters, water_colors)


func _apply(source: TerrainResource, target_ref: WeakRef, indices: PackedInt32Array, heights: PackedInt32Array, tops: PackedByteArray, waters: PackedInt32Array, water_colors: PackedByteArray) -> void:
	var map := target_ref.get_ref() as EmberMapLoader
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection if is_instance_valid(map) and _entry.get("resource") == source else null
	var write_started := Time.get_ticks_usec() if diagnostic_sink != null else 0
	var all_heights := source.heights
	var all_tops := source.top_materials
	var all_waters := source.water_levels
	var all_water_colors := source.water_materials
	for i in indices.size():
		var index := indices[i]
		all_heights[index] = heights[i]
		all_tops[index] = tops[i]
		all_waters[index] = waters[i]
		all_water_colors[index] = water_colors[i]
	source.heights = all_heights
	source.top_materials = all_tops
	source.water_levels = all_waters
	source.water_materials = all_water_colors
	if diagnostic_sink != null:
		diagnostic_sink.stage("resource_write", Time.get_ticks_usec() - write_started)
	if projection != null:
		var projection_started := Time.get_ticks_usec() if diagnostic_sink != null else 0
		projection.apply_columns(indices, heights, tops, waters, water_colors)
		if diagnostic_sink != null:
			diagnostic_sink.stage("projection_apply", Time.get_ticks_usec() - projection_started)


func changed_column_count() -> int:
	return _indices.size()


func end() -> void:
	if not active(): return
	var projection := _live_projection()
	if projection != null: projection.end_live_brush()
	var snapshot_started := Time.get_ticks_usec() if diagnostic_sink != null else 0
	var source: TerrainResource = _entry.resource
	var target_ref: WeakRef = _entry.target
	var indices := _indices.duplicate()
	var before_heights := PackedInt32Array()
	var before_tops := PackedByteArray()
	var before_waters := PackedInt32Array()
	var before_water_colors := PackedByteArray()
	var after_heights := PackedInt32Array()
	var after_tops := PackedByteArray()
	var after_waters := PackedInt32Array()
	var after_water_colors := PackedByteArray()
	var changed_count := indices.size()
	var current_heights := source.heights
	var current_tops := source.top_materials
	var current_waters := source.water_levels
	var current_water_colors := source.water_materials
	var run_starts := PackedInt32Array()
	var run_ends := PackedInt32Array()
	if _cell_stride > 1 and changed_count >= 32768:
		indices.sort()
		var run_start: int = indices[0]
		for i in range(1, changed_count):
			if indices[i] != indices[i - 1] + 1:
				run_starts.append(run_start)
				run_ends.append(indices[i - 1] + 1)
				run_start = indices[i]
		run_starts.append(run_start)
		run_ends.append(indices[changed_count - 1] + 1)
	if not run_starts.is_empty() and run_starts.size() * 32 <= changed_count:
		# Broad strokes form long row spans. PackedArray copies these spans in
		# native code; fragmented edits stay on the preallocated per-cell path.
		for run_index in run_starts.size():
			var start: int = run_starts[run_index]
			var end: int = run_ends[run_index]
			before_heights.append_array(_before_heights.slice(start, end))
			before_tops.append_array(_before_tops.slice(start, end))
			before_waters.append_array(_before_waters.slice(start, end))
			before_water_colors.append_array(_before_water_colors.slice(start, end))
			after_heights.append_array(current_heights.slice(start, end))
			after_tops.append_array(current_tops.slice(start, end))
			after_waters.append_array(current_waters.slice(start, end))
			after_water_colors.append_array(current_water_colors.slice(start, end))
	else:
		before_heights.resize(changed_count)
		before_tops.resize(changed_count)
		before_waters.resize(changed_count)
		before_water_colors.resize(changed_count)
		after_heights.resize(changed_count)
		after_tops.resize(changed_count)
		after_waters.resize(changed_count)
		after_water_colors.resize(changed_count)
		for i in changed_count:
			var index := indices[i]
			before_heights[i] = _before_heights[index]
			before_tops[i] = _before_tops[index]
			before_waters[i] = _before_waters[index]
			before_water_colors[i] = _before_water_colors[index]
			after_heights[i] = current_heights[index]
			after_tops[i] = current_tops[index]
			after_waters[i] = current_waters[index]
			after_water_colors[i] = current_water_colors[index]
	if snapshot_started > 0: diagnostic_sink.stage("undo_snapshot", Time.get_ticks_usec() - snapshot_started)
	var title := "Мир · компактная земля · " + _mode
	var clear_started := Time.get_ticks_usec() if diagnostic_sink != null else 0
	_clear()
	if clear_started > 0: diagnostic_sink.stage("brush_clear", Time.get_ticks_usec() - clear_started)
	if indices.is_empty(): return
	var commit_started := Time.get_ticks_usec() if diagnostic_sink != null else 0
	if _history is EditorUndoRedoManager:
		(_history as EditorUndoRedoManager).create_action(title, UndoRedo.MERGE_DISABLE, _scene)
		Callable(_history, "add_do_method").callv([self, "_apply", source, target_ref, indices, after_heights, after_tops, after_waters, after_water_colors])
		Callable(_history, "add_undo_method").callv([self, "_apply", source, target_ref, indices, before_heights, before_tops, before_waters, before_water_colors])
		(_history as EditorUndoRedoManager).commit_action(false)
	else:
		(_history as UndoRedo).create_action(title, UndoRedo.MERGE_DISABLE)
		(_history as UndoRedo).add_do_method(Callable(self, "_apply").bind(source, target_ref, indices, after_heights, after_tops, after_waters, after_water_colors))
		(_history as UndoRedo).add_undo_method(Callable(self, "_apply").bind(source, target_ref, indices, before_heights, before_tops, before_waters, before_water_colors))
		(_history as UndoRedo).commit_action(false)
	if commit_started > 0: diagnostic_sink.stage("history_commit", Time.get_ticks_usec() - commit_started)


func cancel() -> void:
	if not active(): return
	var projection := _live_projection()
	if projection != null: projection.end_live_brush()
	if not _indices.is_empty():
		var heights := PackedInt32Array()
		var tops := PackedByteArray()
		var waters := PackedInt32Array()
		var water_colors := PackedByteArray()
		for index in _indices:
			heights.append(_before_heights[index])
			tops.append(_before_tops[index])
			waters.append(_before_waters[index])
			water_colors.append(_before_water_colors[index])
		_apply(_entry.resource, _entry.target, _indices, heights, tops, waters, water_colors)
	_clear()


func _live_projection() -> EmberTerrainPilotProjection:
	if _entry.is_empty(): return null
	var map := (_entry.target as WeakRef).get_ref() as EmberMapLoader
	return map._visual_surface_projection as EmberTerrainPilotProjection if is_instance_valid(map) else null


func _clear() -> void:
	_mode = ""
	_cell_stride = 1
	_height_step = 1
	_shape = "circle"
	_group_offsets = PackedInt32Array()
	_indices = PackedInt32Array()
	_touched = PackedByteArray()
	_influence = PackedInt32Array()
	_before_heights = PackedInt32Array()
	_before_tops = PackedByteArray()
	_before_waters = PackedInt32Array()
	_before_water_colors = PackedByteArray()
	_noise = null
	_falloff_by_distance = PackedFloat64Array()
	_amount_by_distance = PackedInt32Array()
	_strength_by_distance = PackedInt32Array()
	_row_extents = PackedInt32Array()
	_last = Vector2i(-1, -1)
