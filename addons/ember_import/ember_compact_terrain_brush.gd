@tool
extends RefCounted
## Column brush adapter for the existing World Editor input and Undo history.

const BrushMath = preload("res://scripts/prototypes/ember_terrain_pilot_brush_math.gd")
const TerrainResource = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const SurfaceRules=preload("res://scripts/prototypes/ember_terrain_surface_rules.gd")
var _rule_cells: Dictionary={}
var _rule_exposure: Dictionary={}
var _rule_code:=0
const SurfaceForms = preload("res://scripts/prototypes/ember_terrain_surface_form_math.gd")
const Plan = preload("res://scripts/ember_terrain_plan_resource.gd")

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
var _before_cap_depths := PackedByteArray()
var _before_tops := PackedByteArray()
var _before_waters := PackedInt32Array()
var _before_water_colors := PackedByteArray()
var _noise: FastNoiseLite
var _surface_forms: SurfaceForms
var _surface_scale := 1.0
var _detail := 0
var _direction := 0
var _falloff_by_distance := PackedFloat64Array()
var _amount_by_distance := PackedInt32Array()
var _strength_by_distance := PackedInt32Array()
var _row_extents := PackedInt32Array()
var _group_offsets := PackedInt32Array()
var diagnostic_sink: RefCounted
var _section_baseline: TerrainResource
var _section_touched := {}
var _section_influence := {}
var _section_groups := {}
var _paint_columns := PackedInt32Array()
var _paint_groups := {}
var _side_before: Dictionary={}
var _side_after: Dictionary={}


func configure(entry: Dictionary, history: Object, scene: Node) -> void:
	_entry = entry
	_history = history
	_scene = scene


func active() -> bool:
	return not _mode.is_empty()


func begin(mode: String, radius_blocks: float, depth_voxels: int, palette_index: int, water_world: int, feature_scale: int, detail: int, seed: int, direction: int, target_world := -99999, edit_scale := "detail", brush_shape := "auto", requested_height_step := 0, material_detail := false,rule_code:=-1) -> bool:
	if _entry.is_empty() or active():
		return false
	var source: TerrainResource = _entry.resource
	if mode not in ["raise", "lower", "level", "smooth", "generator", "paint", "water", "dry","shape_round","shape_protect","shape_clear"]:
		return false
	var target:=(_entry.target as WeakRef).get_ref() as EmberMapLoader
	var shape_limit:=target.smooth_column_limit() if is_instance_valid(target) else 262144
	if mode.begins_with("shape_") and source.width*source.depth>shape_limit:return false
	_mode = mode
	_rule_code=rule_code;_rule_cells={};_rule_exposure={}
	if mode=="shape_round" and _rule_code<0:_rule_code=96
	if mode=="shape_protect" and _rule_code<0:_rule_code=255
	if mode.begins_with("shape_"):edit_scale="detail"
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
	if _mode.begins_with("shape_"):return true # Pending mask only; no live remesh.
	_indices = PackedInt32Array()
	_touched = PackedByteArray()
	_touched.resize(source.heights.size())
	_influence = PackedInt32Array()
	_influence.resize(source.heights.size())
	_before_heights = source.heights.duplicate()
	_before_cap_depths = source.cap_depths.duplicate()
	_before_tops = source.top_materials.duplicate()
	_before_waters = source.water_levels.duplicate()
	_before_water_colors = source.water_materials.duplicate()
	_section_baseline = source.working_copy() if source.is_sectioned() else null
	_section_touched.clear()
	_section_influence.clear()
	_section_groups.clear()
	if mode == "generator" and material_detail:
		_surface_forms=SurfaceForms.new();_surface_forms.configure(seed)
		_surface_scale=clampf(float(feature_scale)/16.0,0.25,4.0)
	elif mode == "generator":
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


func stamp_surface(pick: Dictionary,bounds:=Rect2i()) -> void:
	if not active() or pick.is_empty():return
	var normal:Vector3=pick.get("normal",Vector3.UP)
	if _mode!="paint" or normal.y>0.8:
		stamp(pick.cell,bounds);return
	var source:TerrainResource=_entry.resource
	var centre:Vector3=pick.local
	var radius:=float(_radius*_cell_stride)
	var touched:Dictionary={}
	# The exposed wall is sampled in world-height/source space, never through
	# the plateau above it. Depth is irrelevant for a material-only gesture.
	var extent:=ceili(radius)+1
	for z in range(maxi(0,pick.cell.y-extent),mini(source.depth,pick.cell.y+extent+1)):
		for x in range(maxi(0,pick.cell.x-extent),mini(source.width,pick.cell.x+extent+1)):
			if not source.has_column(x,z) or (bounds.has_area() and not bounds.has_point(Vector2i(x,z))):continue
			var index:=source.column_index(x,z);var high:=source.column_value("heights",index)
			var exposed_low:=high
			for delta:Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var neighbour:=Vector2i(x,z)+delta
				if Vector3(delta.x,0,delta.y).dot(normal)<0.4:continue
				var low:=source.column_value("heights",source.column_index(neighbour.x,neighbour.y)) if source.has_column(neighbour.x,neighbour.y) else 0
				exposed_low=mini(exposed_low,low)
			if exposed_low>=high:continue
			var values:Dictionary=source.side_overrides(index).duplicate()
			var before:Dictionary=values.duplicate()
			for y in range(maxi(exposed_low,floori(centre.y-source.origin_y-radius)),mini(high,ceili(centre.y-source.origin_y+radius))):
				var offset:=Vector3(x+0.5,source.origin_y+y+0.5,z+0.5)-centre
				var tangent:=offset-normal*offset.dot(normal)
				if absf(offset.dot(normal))>1.5 or (maxf(absf(tangent.x),maxf(absf(tangent.y),absf(tangent.z)))>radius if _shape=="square" else tangent.length_squared()>radius*radius):continue
				values[y]=_palette
			if values==before:continue
			if not _side_before.has(index):_side_before[index]=before
			_side_after[index]=values;touched[index]=values
			_paint_columns.append(index)
	if not touched.is_empty():_apply_side(source,_entry.target,touched)


func _apply_side(source:TerrainResource,target_ref:WeakRef,values:Dictionary) -> void:
	source.write_side_overrides(values)
	var map:=target_ref.get_ref() as EmberMapLoader
	if is_instance_valid(map) and _entry.get("resource")==source and map._visual_surface_projection!=null:
		map._visual_surface_projection.apply_side_materials(values,source)


func stamp(cell: Vector2i, bounds := Rect2i()) -> void:
	if not active():
		return
	var projection:=_live_projection()
	if projection!=null:projection.set_live_brush_center(cell)
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
	if _mode.begins_with("shape_"):
		_stamp_rules(cell,bounds);return
	if cell.x < 0 or cell.y < 0 or cell.x >= source.width or cell.y >= source.depth:
		return
	if not source.has_column(cell.x, cell.y): return
	var center := Vector2i(cell.x / _cell_stride, cell.y / _cell_stride)
	var group_width := source.width / _cell_stride
	var group_depth := source.depth / _cell_stride
	var can_skip_previous := _cell_stride == 1 and _shape == "circle" and _mode in ["raise", "lower", "generator"] and previous_center.x >= 0 and previous_center.y >= 0 and previous_center.x < source.width and previous_center.y < source.depth
	var center_delta := center - previous_center if can_skip_previous else Vector2i.ZERO
	var delta_squared := center_delta.length_squared()
	if can_skip_previous and delta_squared == 0:
		return
	if _mode == "level" and _target_height < 0:
		_target_height = _baseline_group(source, center.x * _cell_stride, center.y * _cell_stride)
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
	var sectioned := source.is_sectioned()
	var read_address := Vector2i(-1, -1)
	var read_part: TerrainResource = source
	var current_heights := source.heights
	var current_tops := source.top_materials
	var current_waters := source.water_levels
	var current_colors := source.water_materials
	var local_offsets := _group_offsets
	var offset_width := source.width
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
			# Dense group bounds were checked above. Sparse sections still need
			# allocation checks; dense input uses its already captured arrays.
			if sectioned and (not source.has_column(x, z) or not source.has_column(x + _cell_stride - 1, z + _cell_stride - 1)): continue
			if repeated_height:
				var strength := _strength_by_distance[distance_squared] if _mode == "generator" else _amount_by_distance[distance_squared]
				if strength <= (_section_influence.get(representative,0) if sectioned else _influence[representative]): continue
				if sectioned:_section_influence[representative]=strength
				else:_influence[representative]=strength
			elif (_section_touched.has(representative) if sectioned else _touched[representative]!=0):
				continue
			var height := 0
			if changes_height:
				var baseline: int=(_before_heights[representative] if not sectioned and not coarse else _baseline_group(source,x,z)) if repeated_height else 0
				match _mode:
					"raise": height = clampi(baseline + _amount_by_distance[distance_squared], 1, source.height_limit) if _height_step == 1 else BrushMath.stepped_height(baseline + _amount_by_distance[distance_squared], _height_step, source.height_limit)
					"lower": height = clampi(baseline - _amount_by_distance[distance_squared], 1, source.height_limit) if _height_step == 1 else BrushMath.stepped_height(baseline - _amount_by_distance[distance_squared], _height_step, source.height_limit)
					"level": height = _target_height
					"smooth": height = _smooth_baseline(source, x, z, group_x, group_z, influence)
					"generator":
						if _surface_forms==null:
							var steps := BrushMath.noise_offset(_noise, group_x, group_z, influence, maxi(1, _depth / _height_step), _detail, _direction)
							height = clampi(baseline + steps, 1, source.height_limit) if _height_step == 1 else BrushMath.stepped_height(baseline + steps * _height_step, _height_step, source.height_limit)
			var group_changed := false
			var protect_group:=paint_surface and not _paint_groups.has(representative)
			var local_representative := representative
			if sectioned:
				var address := Vector2i(x / TerrainResource.Sections.CELLS, z / TerrainResource.Sections.CELLS)
				if address != read_address:
					read_address = address
					read_part = source.sections[address]
					current_heights = read_part.heights
					current_tops = read_part.top_materials
					current_waters = read_part.water_levels
					current_colors = read_part.water_materials
					if offset_width != read_part.width:
						offset_width = read_part.width
						local_offsets = PackedInt32Array()
						for oz in _cell_stride:
							for ox in _cell_stride: local_offsets.append(ox + oz * offset_width)
				local_representative = x % TerrainResource.Sections.CELLS + (z % TerrainResource.Sections.CELLS) * read_part.width
			for group_index in _group_offsets.size():
				var offset := _group_offsets[group_index]
				var index := representative + offset
				var local_index := local_representative + local_offsets[group_index]
				var current_height := current_heights[local_index]
				if protect_group and current_height>0:_paint_columns.append(index)
				var current_top := current_tops[local_index]
				var current_water := current_waters[local_index]
				var current_color := current_colors[local_index]
				var next_height: int = height if changes_height else current_height
				if _surface_forms!=null:
					var original_height: int=_section_baseline.column_value("heights",index) if sectioned else _before_heights[index]
					# Preserve underwater ground, holes and the actual painted role.
					next_height=current_height
					if original_height>0 and not (current_water>original_height and current_color>0):
						var point:=Vector2((float(x+group_index%_cell_stride)+0.5)/16.0,(float(z+floori(float(group_index)/_cell_stride))+0.5)/16.0)
						var role: String=source.surface_role_for_palette(current_top)
						var delta: int=_surface_forms.brush_offset_voxels(point,role,_surface_scale,_depth,influence,_height_step,_direction)
						next_height=clampi(original_height+delta,maxi(1,source.column_value("cap_depths",index)),source.height_limit)
				var next_top: int = _palette if paint_surface else current_top
				var next_water: int = _water_level if fill_water else 0 if clear_water else current_water
				var next_water_color: int = _palette if fill_water else 0 if clear_water else current_color
				if next_height == current_height and next_top == current_top and next_water == current_water and next_water_color == current_color: continue
				if not (_section_touched.has(index) if sectioned else _touched[index]!=0):
					if sectioned:_section_touched[index]=true
					else:_touched[index]=1
					_indices.append(index)
				group_changed = true
				indices.append(index)
				heights.append(next_height)
				tops.append(next_top)
				waters.append(next_water)
				water_colors.append(next_water_color)
			# A level/smooth/paint result already equal to the original cannot
			# gain an effect by visiting it again in this stroke. Do not repeatedly
			# evaluate every flat column under a moving smooth brush.
			if group_changed or not repeated_height:
				if sectioned:_section_touched[representative]=true
				else:_touched[representative]=1
			if protect_group:_paint_groups[representative]=true
	if diagnostic_sink != null:
		diagnostic_sink.stage("brush_collect", Time.get_ticks_usec() - gather_started)
	if not indices.is_empty(): _apply(source, _entry.target, indices, heights, tops, waters, water_colors)


func _apply(source: TerrainResource, target_ref: WeakRef, indices: PackedInt32Array, heights: PackedInt32Array, tops: PackedByteArray, waters: PackedInt32Array, water_colors: PackedByteArray, caps := PackedByteArray()) -> void:
	var map := target_ref.get_ref() as EmberMapLoader
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection if is_instance_valid(map) and _entry.get("resource") == source else null
	var write_started := Time.get_ticks_usec() if diagnostic_sink != null else 0
	if source.is_sectioned():
		source.write_columns(indices, heights, tops, waters, water_colors)
		if diagnostic_sink != null: diagnostic_sink.stage("resource_write", Time.get_ticks_usec() - write_started)
		var projection_started := Time.get_ticks_usec() if diagnostic_sink != null else 0
		if projection != null: projection.apply_columns(indices, heights, tops, waters, water_colors, source)
		if diagnostic_sink != null: diagnostic_sink.stage("projection_apply", Time.get_ticks_usec() - projection_started)
		return
	var all_heights := source.heights
	var all_caps := source.cap_depths
	var all_tops := source.top_materials
	var all_waters := source.water_levels
	var all_water_colors := source.water_materials
	for i in indices.size():
		var index := indices[i]
		all_heights[index] = heights[i]
		all_caps[index] = mini(caps[i] if caps.size() == indices.size() else all_caps[index], heights[i])
		all_tops[index] = tops[i]
		all_waters[index] = waters[i]
		all_water_colors[index] = water_colors[i]
	source.heights = all_heights
	source.cap_depths = all_caps
	source.top_materials = all_tops
	source.water_levels = all_waters
	source.water_materials = all_water_colors
	if diagnostic_sink != null:
		diagnostic_sink.stage("resource_write", Time.get_ticks_usec() - write_started)
	if projection != null:
		var projection_started := Time.get_ticks_usec() if diagnostic_sink != null else 0
		projection.apply_columns(indices, heights, tops, waters, water_colors, source)
		if diagnostic_sink != null:
			diagnostic_sink.stage("projection_apply", Time.get_ticks_usec() - projection_started)


func changed_column_count() -> int:
	return _rule_cells.size() if _mode.begins_with("shape_") else _indices.size()+_side_after.size()


func end() -> void:
	if not active(): return
	if _mode.begins_with("shape_"):
		_commit_rules();return
	var projection := _live_projection()
	if projection != null: projection.end_live_brush()
	var snapshot_started := Time.get_ticks_usec() if diagnostic_sink != null else 0
	var source: TerrainResource = _entry.resource
	var target_ref: WeakRef = _entry.target
	var protection:=_paint_protection_delta()
	if not protection.is_empty():_apply_paint_protection(target_ref,protection.after)
	if not _side_before.is_empty():protection.merge({"side_before":_side_before.duplicate(true),"side_after":_side_after.duplicate(true),"source":source,"side_target":target_ref})
	if _section_baseline != null:
		var before_parts := _touched_parts(_section_baseline)
		var after_parts := _touched_parts(source)
		var changed_indices:=_indices.duplicate()
		var title := "Мир · компактная земля · " + _mode
		_clear()
		if after_parts.is_empty():_commit_paint_only(protection);return
		if _history is EditorUndoRedoManager:
			(_history as EditorUndoRedoManager).create_action(title, UndoRedo.MERGE_DISABLE, _scene)
			Callable(_history, "add_do_method").callv([self, "_apply_parts", source, target_ref, after_parts, changed_indices])
			Callable(_history, "add_undo_method").callv([self, "_apply_parts", source, target_ref, before_parts, changed_indices])
			_add_paint_history(protection)
			(_history as EditorUndoRedoManager).commit_action(false)
		else:
			(_history as UndoRedo).create_action(title, UndoRedo.MERGE_DISABLE)
			(_history as UndoRedo).add_do_method(Callable(self, "_apply_parts").bind(source, target_ref, after_parts, changed_indices))
			(_history as UndoRedo).add_undo_method(Callable(self, "_apply_parts").bind(source, target_ref, before_parts, changed_indices))
			_add_paint_history(protection)
			(_history as UndoRedo).commit_action(false)
		return
	var indices := _indices.duplicate()
	var before_heights := PackedInt32Array()
	var before_caps := PackedByteArray()
	var before_tops := PackedByteArray()
	var before_waters := PackedInt32Array()
	var before_water_colors := PackedByteArray()
	var after_heights := PackedInt32Array()
	var after_caps := PackedByteArray()
	var after_tops := PackedByteArray()
	var after_waters := PackedInt32Array()
	var after_water_colors := PackedByteArray()
	var changed_count := indices.size()
	var current_heights := source.heights
	var current_caps := source.cap_depths
	var current_tops := source.top_materials
	var current_waters := source.water_levels
	var current_water_colors := source.water_materials
	var run_starts := PackedInt32Array()
	var run_ends := PackedInt32Array()
	if _section_baseline == null and changed_count >= 8192:
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
			before_caps.append_array(_before_cap_depths.slice(start, end))
			before_tops.append_array(_before_tops.slice(start, end))
			before_waters.append_array(_before_waters.slice(start, end))
			before_water_colors.append_array(_before_water_colors.slice(start, end))
			after_heights.append_array(current_heights.slice(start, end))
			after_caps.append_array(current_caps.slice(start, end))
			after_tops.append_array(current_tops.slice(start, end))
			after_waters.append_array(current_waters.slice(start, end))
			after_water_colors.append_array(current_water_colors.slice(start, end))
	else:
		before_heights.resize(changed_count)
		before_caps.resize(changed_count)
		before_tops.resize(changed_count)
		before_waters.resize(changed_count)
		before_water_colors.resize(changed_count)
		after_heights.resize(changed_count)
		after_caps.resize(changed_count)
		after_tops.resize(changed_count)
		after_waters.resize(changed_count)
		after_water_colors.resize(changed_count)
		for i in changed_count:
			var index := indices[i]
			before_heights[i] = _before_heights[index]
			before_caps[i] = _before_cap_depths[index]
			before_tops[i] = _before_tops[index]
			before_waters[i] = _before_waters[index]
			before_water_colors[i] = _before_water_colors[index]
			after_heights[i] = current_heights[index]
			after_caps[i] = current_caps[index]
			after_tops[i] = current_tops[index]
			after_waters[i] = current_waters[index]
			after_water_colors[i] = current_water_colors[index]
	if snapshot_started > 0: diagnostic_sink.stage("undo_snapshot", Time.get_ticks_usec() - snapshot_started)
	var title := "Мир · компактная земля · " + _mode
	var clear_started := Time.get_ticks_usec() if diagnostic_sink != null else 0
	_clear()
	if clear_started > 0: diagnostic_sink.stage("brush_clear", Time.get_ticks_usec() - clear_started)
	if indices.is_empty():_commit_paint_only(protection);return
	var commit_started := Time.get_ticks_usec() if diagnostic_sink != null else 0
	if _history is EditorUndoRedoManager:
		(_history as EditorUndoRedoManager).create_action(title, UndoRedo.MERGE_DISABLE, _scene)
		Callable(_history, "add_do_method").callv([self, "_apply", source, target_ref, indices, after_heights, after_tops, after_waters, after_water_colors, after_caps])
		Callable(_history, "add_undo_method").callv([self, "_apply", source, target_ref, indices, before_heights, before_tops, before_waters, before_water_colors, before_caps])
		_add_paint_history(protection)
		(_history as EditorUndoRedoManager).commit_action(false)
	else:
		(_history as UndoRedo).create_action(title, UndoRedo.MERGE_DISABLE)
		(_history as UndoRedo).add_do_method(Callable(self, "_apply").bind(source, target_ref, indices, after_heights, after_tops, after_waters, after_water_colors, after_caps))
		(_history as UndoRedo).add_undo_method(Callable(self, "_apply").bind(source, target_ref, indices, before_heights, before_tops, before_waters, before_water_colors, before_caps))
		_add_paint_history(protection)
		(_history as UndoRedo).commit_action(false)
	if commit_started > 0: diagnostic_sink.stage("history_commit", Time.get_ticks_usec() - commit_started)

func _paint_protection_delta() -> Dictionary:
	if _mode!="paint" or _paint_columns.is_empty():return {}
	var target: Node=_entry.target.get_ref()
	if not is_instance_valid(target):return {}
	var previous: Resource=Plan.read(target)
	# Unchanged recipe/patch arrays stay immutable; only the paint bitmap is
	# copied. Ancient patches need the existing explicit migration first.
	var next: Resource=(previous.working_copy() if previous.schema_version<3 else previous.duplicate(false)) if previous!=null else Plan.new()
	next.protect_paint_columns(_paint_columns,_entry.resource.width)
	return {} if previous!=null and previous.schema_version==next.schema_version and previous.paint_locks==next.paint_locks else {"before":previous,"after":next,"target":_entry.target}

func _apply_paint_protection(target_ref: WeakRef,plan: Resource) -> void:
	var target: Node=target_ref.get_ref()
	if not is_instance_valid(target):return
	if plan==null:target.remove_meta(Plan.META)
	else:target.set_meta(Plan.META,plan)

func _add_paint_history(delta: Dictionary) -> void:
	if delta.is_empty():return
	if delta.has("side_before"):
		if _history is EditorUndoRedoManager:
			Callable(_history,"add_do_method").callv([self,"_apply_side",delta.source,delta.side_target,delta.side_after])
			Callable(_history,"add_undo_method").callv([self,"_apply_side",delta.source,delta.side_target,delta.side_before])
		else:
			(_history as UndoRedo).add_do_method(_apply_side.bind(delta.source,delta.side_target,delta.side_after))
			(_history as UndoRedo).add_undo_method(_apply_side.bind(delta.source,delta.side_target,delta.side_before))
	if not delta.has("target"):return
	if _history is EditorUndoRedoManager:
		Callable(_history,"add_do_method").callv([self,"_apply_paint_protection",delta.target,delta.after])
		Callable(_history,"add_undo_method").callv([self,"_apply_paint_protection",delta.target,delta.before])
	else:
		(_history as UndoRedo).add_do_method(_apply_paint_protection.bind(delta.target,delta.after))
		(_history as UndoRedo).add_undo_method(_apply_paint_protection.bind(delta.target,delta.before))

func _commit_paint_only(delta: Dictionary) -> void:
	if delta.is_empty():return
	if _history is EditorUndoRedoManager:(_history as EditorUndoRedoManager).create_action("Мир · защитить ручную покраску",UndoRedo.MERGE_DISABLE,_scene)
	else:(_history as UndoRedo).create_action("Мир · защитить ручную покраску",UndoRedo.MERGE_DISABLE)
	_add_paint_history(delta)
	_history.commit_action(false)


func cancel() -> void:
	if not active(): return
	if not _side_before.is_empty():_apply_side(_entry.resource,_entry.target,_side_before)
	if _mode.begins_with("shape_"):_clear();return
	var projection := _live_projection()
	if projection != null: projection.end_live_brush()
	if _section_baseline != null:
		if not _indices.is_empty():_apply_parts(_entry.resource, _entry.target, _touched_parts(_section_baseline),_indices)
		_clear()
		return
	if not _indices.is_empty():
		var heights := PackedInt32Array()
		var caps := PackedByteArray()
		var tops := PackedByteArray()
		var waters := PackedInt32Array()
		var water_colors := PackedByteArray()
		for index in _indices:
			heights.append(_baseline_value("heights", index))
			caps.append(_baseline_value("cap_depths", index))
			tops.append(_baseline_value("top_materials", index))
			waters.append(_baseline_value("water_levels", index))
			water_colors.append(_baseline_value("water_materials", index))
		_apply(_entry.resource, _entry.target, _indices, heights, tops, waters, water_colors, caps)
	_clear()


func _touched_parts(source: TerrainResource) -> Dictionary:
	var result := {}
	for index in _indices:
		var key := Vector2i((index % source.width) / TerrainResource.Sections.CELLS, (index / source.width) / TerrainResource.Sections.CELLS)
		result[key] = source.sections[key]
	return result


func _apply_parts(source: TerrainResource, target_ref: WeakRef, parts: Dictionary,indices:=PackedInt32Array()) -> void:
	for key: Vector2i in parts: source.sections[key] = parts[key]
	var map := target_ref.get_ref() as EmberMapLoader
	if is_instance_valid(map) and _entry.get("resource") == source:
		var projection := map._visual_surface_projection as EmberTerrainPilotProjection
		if projection == null:return
		if indices.is_empty():projection.open_document(source);return
		# History restores immutable section payloads, but only the stroke's
		# columns invalidate the display. Reopening whole 24m sections used to
		# remesh hundreds of unrelated tiles for a small Undo/Cancel.
		var heights:=PackedInt32Array();var tops:=PackedByteArray()
		var waters:=PackedInt32Array();var colors:=PackedByteArray()
		heights.resize(indices.size());tops.resize(indices.size());waters.resize(indices.size());colors.resize(indices.size())
		var address:=Vector2i(-1,-1);var part:TerrainResource
		var read_heights:=PackedInt32Array();var read_tops:=PackedByteArray()
		var read_waters:=PackedInt32Array();var read_colors:=PackedByteArray()
		for i in indices.size():
			var point:=Vector2i(indices[i]%source.width,indices[i]/source.width)
			var key:=point/TerrainResource.Sections.CELLS
			if key!=address:
				address=key;part=source.sections[key]
				read_heights=part.heights;read_tops=part.top_materials;read_waters=part.water_levels;read_colors=part.water_materials
			var local:=point.x%TerrainResource.Sections.CELLS+(point.y%TerrainResource.Sections.CELLS)*part.width
			heights[i]=read_heights[local];tops[i]=read_tops[local];waters[i]=read_waters[local];colors[i]=read_colors[local]
		projection.apply_columns(indices,heights,tops,waters,colors,source,true)


func _live_projection() -> EmberTerrainPilotProjection:
	if _entry.is_empty(): return null
	var map := (_entry.target as WeakRef).get_ref() as EmberMapLoader
	return map._visual_surface_projection as EmberTerrainPilotProjection if is_instance_valid(map) else null


func _stamp_rules(center: Vector2i,bounds: Rect2i) -> void:
	if _mode=="shape_protect" and _rule_code==0:return
	var source: TerrainResource=_entry.resource
	for z in range(maxi(0,center.y-_radius),mini(source.depth,center.y+_radius+1)):
		for x in range(maxi(0,center.x-_radius),mini(source.width,center.x+_radius+1)):
			var cell:=Vector2i(x,z)
			if not source.has_column(x,z) or (bounds.has_area() and not bounds.has_point(cell)):continue
			var delta:=cell-center
			var distance:=maxi(absi(delta.x),absi(delta.y))
			var d2:=distance*distance if _shape=="square" else delta.length_squared()
			if d2>_radius*_radius:continue
			var influence: float=_falloff_by_distance[d2]
			if influence<=0.001:continue
			if influence<=float(_rule_exposure.get(cell,0.0)):continue
			_rule_exposure[cell]=influence
			var code:=0
			if _mode=="shape_protect":code=SurfaceRules.protect_code(float(maxi(128,_rule_code)-127)/128.0*influence)
			elif _mode=="shape_round":
				var amount:=float((_rule_code-1)%32)/31.0
				var radius: int=(_rule_code-1)/32+1
				code=SurfaceRules.round_code(lerpf(1.0,amount,influence),roundi(lerpf(3.0,float(radius),influence)))
			# Keep the strongest exposure for overlapping dabs of one stroke.
			if _rule_cells.has(cell) and _mode=="shape_protect":code=maxi(code,_rule_cells[cell])
			_rule_cells[cell]=code

func _commit_rules() -> void:
	var source: TerrainResource=_entry.resource
	var before:=source.surface_rules.duplicate()
	var after:=SurfaceRules.changed(before,_rule_cells)
	var cells:=_rule_cells.keys();var target_ref: WeakRef=_entry.target
	_clear()
	if before==after:return
	_apply_rules(source,target_ref,after,cells)
	if _history is EditorUndoRedoManager:
		(_history as EditorUndoRedoManager).create_action("Мир · правило гладкой формы",UndoRedo.MERGE_DISABLE,_scene)
		Callable(_history,"add_do_method").callv([self,"_apply_rules",source,target_ref,after,cells])
		Callable(_history,"add_undo_method").callv([self,"_apply_rules",source,target_ref,before,cells])
		(_history as EditorUndoRedoManager).commit_action(false)
	else:
		(_history as UndoRedo).create_action("Мир · правило гладкой формы",UndoRedo.MERGE_DISABLE)
		(_history as UndoRedo).add_do_method(_apply_rules.bind(source,target_ref,after,cells))
		(_history as UndoRedo).add_undo_method(_apply_rules.bind(source,target_ref,before,cells))
		(_history as UndoRedo).commit_action(false)

func _apply_rules(source: TerrainResource,target_ref: WeakRef,rules: Dictionary,cells: Array) -> void:
	source.surface_rules=rules.duplicate()
	var map:=target_ref.get_ref() as EmberMapLoader
	if is_instance_valid(map) and map._visual_surface_projection!=null:
		map._visual_surface_projection.apply_surface_rules(rules,cells)

func _clear() -> void:
	_side_before={};_side_after={}
	_rule_cells={};_rule_exposure={};_rule_code=0
	_paint_columns=PackedInt32Array();_paint_groups.clear()
	_mode = ""
	_cell_stride = 1
	_height_step = 1
	_shape = "circle"
	_group_offsets = PackedInt32Array()
	_indices = PackedInt32Array()
	_touched = PackedByteArray()
	_influence = PackedInt32Array()
	_before_heights = PackedInt32Array()
	_before_cap_depths = PackedByteArray()
	_before_tops = PackedByteArray()
	_before_waters = PackedInt32Array()
	_before_water_colors = PackedByteArray()
	_noise = null
	_surface_forms = null
	_surface_scale = 1.0
	_falloff_by_distance = PackedFloat64Array()
	_amount_by_distance = PackedInt32Array()
	_strength_by_distance = PackedInt32Array()
	_row_extents = PackedInt32Array()
	_last = Vector2i(-1, -1)
	_section_baseline = null
	_section_touched.clear()
	_section_influence.clear()
	_section_groups.clear()


func _value(source: TerrainResource, channel: String, index: int) -> int:
	return source.column_value(channel, index) if source.is_sectioned() else source.get(channel)[index]


func _baseline_value(channel: String, index: int) -> int:
	if _section_baseline != null: return _section_baseline.column_value(channel, index)
	match channel:
		"heights": return _before_heights[index]
		"cap_depths": return _before_cap_depths[index]
		"top_materials": return _before_tops[index]
		"water_levels": return _before_waters[index]
		"water_materials": return _before_water_colors[index]
	return 0


func _baseline_group(source: TerrainResource, x: int, z: int) -> int:
	if _section_baseline != null: return BrushMath.section_group_height(_section_baseline, x, z, _cell_stride, _height_step, _section_groups)
	return BrushMath.group_height(_before_heights, source.width, x, z, _cell_stride, _height_step, source.height_limit)


func _smooth_baseline(source: TerrainResource, x: int, z: int, gx: int, gz: int, influence: float) -> int:
	if _section_baseline != null:
		return BrushMath.section_smooth_height(_section_baseline, x, z, _cell_stride, _height_step, _depth if _cell_stride == 1 else maxi(1, _depth / _height_step), influence, _section_groups)
	return clampi(BrushMath.smooth_height(_before_heights, source.width, source.depth, x, z, _depth, influence), 1, source.height_limit) if _cell_stride == 1 else BrushMath.smooth_group_height(_before_heights, source.width, source.depth, gx, gz, _cell_stride, _height_step, maxi(1, _depth / _height_step), influence, source.height_limit)


func _was_touched(index: int) -> bool:
	return _section_touched.has(index) if _section_baseline != null else _touched[index] != 0


func _mark_touched(index: int) -> void:
	if _section_baseline != null: _section_touched[index] = true
	else: _touched[index] = 1


func _influence_at(index: int) -> int:
	return _section_influence.get(index, 0) if _section_baseline != null else _influence[index]


func _set_influence(index: int, value: int) -> void:
	if _section_baseline != null: _section_influence[index] = value
	else: _influence[index] = value
