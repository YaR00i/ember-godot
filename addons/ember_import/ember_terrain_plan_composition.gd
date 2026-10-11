@tool
extends RefCounted
## Bounded editor job: immutable input -> one terrain candidate + local plan provenance.
const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Plan = preload("res://scripts/ember_terrain_plan_resource.gd")
const Math = preload("res://scripts/prototypes/ember_terrain_plan_math.gd")
const TILE := 64
const GROUP := 8
var before: Terrain
var candidate: Terrain
var output_plan: Resource
var error := ""
var bounds := Rect2i()
var addition := {}
var finished := false
var cancelled := false
var elapsed_us := 0
var worst_step_us := 0
var protected_blocks := {}
var changed_tiles: Array[Vector2i] = []
var validated_sections: Array[Vector2i] = []
var _layers: Array[Dictionary] = []
var _old := {}
var _keys: Array[Vector2i] = []
var _total := 0
var _completed := 0
var _key := Vector2i(-1, -1)
var _patch := {}
var _previous := {}
var _point := 0
var _part: Terrain
var _part_key := Vector2i(-1, -1)
var _changed := false
var _retained := false
var _tile_layers: Array[Dictionary] = []
var _influences := {}
var _part_heights := PackedInt32Array()
var _part_caps := PackedByteArray()
var _part_tops := PackedByteArray()
var _part_bases := PackedByteArray()
var _part_waters := PackedInt32Array()
var _part_colors := PackedByteArray()
var _sand := 0
var _soil := 0
var _water := 0
var _prepare_index := 0
var _probe_index := 0
var _probe: Array[Dictionary] = []
var _flow_targets := {}
var _before_values := PackedInt32Array()
var _after_values := PackedInt32Array()
var _before_caps_values := PackedByteArray()
var _after_caps_values := PackedByteArray()
var _tops_values := PackedByteArray()
var _bases_values := PackedByteArray()
var _waters_values := PackedInt32Array()
var _colors_values := PackedByteArray()
var _affected_values := PackedByteArray()
var _protected_values := PackedByteArray()
var _before_tops_values := PackedByteArray()
var _before_bases_values := PackedByteArray()
var _before_waters_values := PackedInt32Array()
var _before_colors_values := PackedByteArray()

func begin(source: Terrain, plan: Resource) -> bool:
	cancel()
	cancelled = false; finished = false; error = ""; bounds = Rect2i()
	elapsed_us = 0; worst_step_us = 0; _completed = 0; _total = 0; _part_key = Vector2i(-1, -1)
	_prepare_index = 0; _probe_index = 0; _probe.clear(); _flow_targets.clear()
	protected_blocks.clear(); changed_tiles.clear(); validated_sections.clear()
	if source == null or plan == null: error = "Нет земли или плана."; return false
	var errors: Array[String] = plan.validation_errors(Vector2i(source.width / 16, source.depth / 16))
	if not errors.is_empty(): error = errors[0]; return false
	before = source
	output_plan = plan.working_copy(); output_plan.schema_version = Plan.VERSION; output_plan.patches.clear()
	var wanted := {}
	for patch: Dictionary in plan.patches:
		var key: Vector2i = patch.rect.position / TILE
		_old[key] = patch; wanted[key] = true
	for region: Dictionary in plan.regions:
		if region.get("kind", "generation") not in ["plateau","lake","river","mountain","road"] or not region.get("enabled", true): continue
		if region.get("kind") == "lake" and region.parameters.water_m-region.parameters.depth_m < float(source.origin_y+4)/16.0:
			error = "Дно озера оказалось ниже основания существующего рельефа. Измените уровень или глубину."; return false
		var layer := region.duplicate(true)
		_layers.append(layer)
		var rect: Rect2i = Rect2i(region.bounds.position * 16, region.bounds.size * 16)
		if region.get("kind") in ["river","road"]:
			layer.curve = Math.path_curve(region.points_m)
			layer.samples = layer.curve.get_baked_points()
			var radius: float = region.parameters.width_m*0.5+region.parameters.get("edge_m",region.parameters.get("shore_m",0))+0.5
			for point: Vector2 in layer.samples:
				if not Rect2(0,0,source.width/16,source.depth/16).has_point(point): error = "Изгиб линии выходит за карту. Измените точки."; return false
				var swept := Rect2i(Vector2i(((point-Vector2.ONE*radius)*16.0).floor()),Vector2i.ONE*ceili(radius*32)).intersection(Rect2i(0,0,source.width,source.depth))
				for z in range(swept.position.y/TILE,(swept.end.y-1)/TILE+1):
					for x in range(swept.position.x/TILE,(swept.end.x-1)/TILE+1): wanted[Vector2i(x,z)] = true
		else:
			for z in range(rect.position.y / TILE, (rect.end.y - 1) / TILE + 1):
				for x in range(rect.position.x / TILE, (rect.end.x - 1) / TILE + 1): wanted[Vector2i(x, z)] = true
		if wanted.size() > Plan.MAX_PATCHES: error = "Суммарный след локальных областей ограничен 256 плитками 4×4 м. Уменьшите области."; return false
	if wanted.is_empty(): error = "Добавьте локальную область: плато, озеро, реку, гору или дорогу."; return false
	var sections_to_check := {}
	for key: Vector2i in wanted:
		sections_to_check[key * TILE / Terrain.Sections.CELLS] = true
	validated_sections.assign(sections_to_check.keys())
	if not source.validation_errors(validated_sections).is_empty(): error = "Проверьте исходную землю."; return false
	_sand = source.palette_surface_roles.find("sand"); _soil = source.palette_surface_roles.find("soil"); _water = 0
	if _soil <= 0 and _layers.any(func(layer): return layer.get("kind") == "road"):
		error = "Назначьте грунт одному из существующих слотов материала карты для покрытия дороги."; return false
	if _layers.any(func(layer): return layer.get("kind") in ["lake","river"]):
		for key in validated_sections:
			var water_part: Terrain = source.sections.get(key) if source.is_sectioned() else source
			if water_part == null: continue
			for slot in range(1,source.palette.size()):
				if water_part.water_materials.has(slot): _water = slot; break
			if _water > 0: break
		if _water <= 0 and source.palette.size() > 5: _water = 5
		if _sand <= 0 or _soil <= 0 or _water <= 0:
			error = "Для водоёма нужны назначенные песок, грунт и существующий слот воды."; return false
	candidate = source.sectioned_copy()
	# Headers alone expand ceiling; untouched section payloads stay shared.
	var ceiling := source.height_limit
	for region in _layers:
		if region.get("kind") in ["river","road"]: continue # End levels are derived during the budgeted preparation.
		var height_m: float = region.parameters.water_m+0.25 if region.get("kind") == "lake" else region.parameters.height_m
		ceiling = maxi(ceiling, ceili(height_m * 16) - source.origin_y)
	if ceiling > candidate.height_limit:
		candidate.height_limit = ceiling
		for key in candidate.sections:
			var part: Terrain = candidate.sections[key].duplicate(false); part.height_limit = ceiling; candidate.sections[key] = part
	_keys.assign(wanted.keys()); _keys.sort_custom(func(a, b):
		var sa: Vector2i = a * TILE / Terrain.Sections.CELLS
		var sb: Vector2i = b * TILE / Terrain.Sections.CELLS
		if sa != sb: return sa.y < sb.y or (sa.y == sb.y and sa.x < sb.x)
		return a.y < b.y or (a.y == b.y and a.x < b.x))
	_total = _keys.size()
	for key in _keys:
		var rect := Rect2i(key * TILE, Vector2i.ONE * TILE).intersection(Rect2i(0, 0, source.width, source.depth))
		bounds = rect if not bounds.has_area() else bounds.merge(rect)
	return true

func progress() -> float: return 1.0 if finished else float(_completed) / maxf(1, _total)
func cancel() -> void:
	cancelled = true; candidate = null; output_plan = null; before = null; _part = null
	_patch.clear(); _old.clear(); _layers.clear(); _keys.clear(); _previous.clear()
	_tile_layers.clear(); _influences.clear()
	_probe.clear(); _flow_targets.clear()
	_part_heights = PackedInt32Array(); _part_caps = PackedByteArray()
	_part_tops = PackedByteArray(); _part_bases = PackedByteArray(); _part_waters = PackedInt32Array(); _part_colors = PackedByteArray()
	for channel in Plan.PATCH_CHANNELS:
		set("_" + channel + "_values", PackedInt32Array() if Plan.PATCH_CHANNELS[channel] == TYPE_PACKED_INT32_ARRAY else PackedByteArray())

func step(budget_us := 4000) -> void:
	if finished or cancelled or candidate == null: return
	var started := Time.get_ticks_usec()
	while Time.get_ticks_usec() - started < budget_us:
		if _prepare_index < _layers.size():
			_prepare_layer()
			if not error.is_empty(): cancel(); return
			continue
		if _patch.is_empty():
			if _keys.is_empty(): _flush_part(); finished = true; break
			_start_tile(_keys.pop_front())
		_column()
		if not error.is_empty(): cancel(); return
		_point += 1
		if _point >= _patch.rect.size.x * _patch.rect.size.y:
			_finalize_flows()
			if _retained:
				for channel in Plan.PATCH_CHANNELS: _patch[channel] = get("_" + channel + "_values")
				output_plan.patches.append(_patch)
			if _changed: changed_tiles.append(_key)
			_patch = {}; _previous = {}; _completed += 1
	var duration := Time.get_ticks_usec() - started
	elapsed_us += duration; worst_step_us = maxi(worst_step_us, duration)

func _start_tile(key: Vector2i) -> void:
	_key = key; _previous = _old.get(key, {}); _point = 0; _changed = false; _retained = false
	var rect := Rect2i(key * TILE, Vector2i.ONE * TILE).intersection(Rect2i(0, 0, before.width, before.depth))
	_patch = {"rect": rect, "sides": {}, "before_sides": {}, "flows": {}, "before_flows": {}}
	_flow_targets.clear()
	_tile_layers.clear(); _influences.clear()
	for layer in _layers:
		if Rect2i(layer.bounds.position * 16, layer.bounds.size * 16).intersects(rect): _tile_layers.append(layer)
	for channel in Plan.PATCH_CHANNELS:
		var values: Variant = PackedInt32Array() if Plan.PATCH_CHANNELS[channel] == TYPE_PACKED_INT32_ARRAY else PackedByteArray()
		values.resize(rect.size.x * rect.size.y); set("_" + channel + "_values", values)
	var section_key: Vector2i = key * TILE / Terrain.Sections.CELLS
	if _part_key != section_key:
		_flush_part()
		_part_key = section_key
		_part = candidate.sections[section_key].working_copy() if candidate.sections.has(section_key) else null
		if _part != null:
			candidate.sections[section_key] = _part
			_part_heights = _part.heights; _part_caps = _part.cap_depths
			_part_tops = _part.top_materials; _part_bases = _part.base_materials
			_part_waters = _part.water_levels; _part_colors = _part.water_materials

func _flush_part() -> void:
	if _part != null:
		_part.heights = _part_heights; _part.cap_depths = _part_caps
		_part.top_materials = _part_tops; _part.base_materials = _part_bases
		_part.water_levels = _part_waters; _part.water_materials = _part_colors
		var has_flow := false
		for vector in _part.water_flow:
			if vector != Vector2.ZERO: has_flow = true; break
		if not has_flow: _part.water_flow = PackedVector2Array()

func _column() -> void:
	var x: int = _patch.rect.position.x + _point % _patch.rect.size.x
	var z: int = _patch.rect.position.y + _point / _patch.rect.size.x
	var point := Vector2i(x, z)
	var group: Vector2i = point / GROUP
	var influences: Array[Dictionary] = []
	if _influences.has(group): influences = _influences[group]
	else:
		var sample := Vector2(group * GROUP + Vector2i.ONE * (GROUP / 2)) / 16.0
		for layer in _tile_layers:
			var influence := _influence_at(layer,sample)
			if not influence.is_empty(): influences.append(influence)
		_influences[group] = influences
	var active := not influences.is_empty()
	if not before.has_column(x, z):
		if active: error = "Область попала в пустое место. Сначала добавьте участки."
		return
	var source_part: Terrain = before.sections[point / Terrain.Sections.CELLS] if before.is_sectioned() else before
	var local: int = (x % Terrain.Sections.CELLS) + (z % Terrain.Sections.CELLS) * source_part.width if before.is_sectioned() else x + z * before.width
	var live_height: int = source_part.heights[local]
	var live_cap: int = source_part.cap_depths[local]
	var block := point/16
	var state := _original_state(point)
	if state.is_empty(): return
	var height: int = state.height; var cap: int = state.cap
	var top: int = state.top; var base: int = state.base; var water: int = state.water; var color: int = state.color
	var locked: bool = state.locked; var side: Dictionary = state.side
	_before_values[_point] = height; _before_caps_values[_point] = cap
	_before_tops_values[_point] = top; _before_bases_values[_point] = base
	_before_waters_values[_point] = water; _before_colors_values[_point] = color
	if not side.is_empty(): _patch.before_sides[_point] = side.duplicate()
	if active and not locked:
		for influence in influences:
			_project(state,influence)
			if not error.is_empty(): return
		height = state.height; cap = state.cap; top = state.top; base = state.base; water = state.water; color = state.color; side = state.side
	_after_values[_point] = height; _after_caps_values[_point] = cap
	_tops_values[_point] = top; _bases_values[_point] = base
	_waters_values[_point] = water; _colors_values[_point] = color
	_protected_values[_point] = 1 if locked else 0; _affected_values[_point] = 1 if active else 0
	if not side.is_empty(): _patch.sides[_point] = side.duplicate()
	if not _flow_targets.has(block):
		var center := block*16+Vector2i(8,8)
		var flow_state := _original_state(center)
		if flow_state.is_empty(): return
		_patch.before_flows[block] = flow_state.flow
		if not flow_state.locked:
			for layer in _tile_layers:
				var influence := _influence_at(layer,Vector2(center)/16.0)
				if not influence.is_empty(): _project(flow_state,influence)
				if not error.is_empty(): return
		_flow_targets[block] = flow_state.flow
	_retained = _retained or active or locked
	if locked: protected_blocks[point / 16] = true
	if height != live_height or cap != live_cap or top != source_part.top_materials[local] or base != source_part.base_materials[local] or water != source_part.water_levels[local] or color != source_part.water_materials[local] or side != source_part.column_material_overrides.get(local,{}):
		var target_local: int = x % Terrain.Sections.CELLS + (z % Terrain.Sections.CELLS) * _part.width
		_part_heights[target_local] = height; _part_caps[target_local] = cap; _changed = true
		_part_tops[target_local] = top; _part_bases[target_local] = base
		_part_waters[target_local] = water; _part_colors[target_local] = color
		if side.is_empty(): _part.column_material_overrides.erase(target_local)
		else: _part.column_material_overrides[target_local] = side.duplicate()

func _original_state(point: Vector2i) -> Dictionary:
	if not before.has_column(point.x,point.y): error = "Линия попала в пустое место. Сначала добавьте участки."; return {}
	var source: Terrain = before.sections[point/Terrain.Sections.CELLS] if before.is_sectioned() else before
	var local: int = point.x%Terrain.Sections.CELLS+(point.y%Terrain.Sections.CELLS)*source.width if before.is_sectioned() else point.x+point.y*source.width
	var state := {"height":source.heights[local],"cap":source.cap_depths[local],"top":source.top_materials[local],"base":source.base_materials[local],"water":source.water_levels[local],"color":source.water_materials[local],"side":source.column_material_overrides.get(local,{}),"flow":before.flow_at_cell(point.x,point.y),"locked":false}
	var previous: Dictionary = _old.get(point/TILE,{})
	if previous.is_empty() or not previous.rect.has_point(point): return state
	var index: int = point.x-previous.rect.position.x+(point.y-previous.rect.position.y)*previous.rect.size.x
	if previous.before[index] < 0 or previous.before[index] > candidate.height_limit or previous.after[index] < 0 or previous.after[index] > before.height_limit or previous.before_caps[index] > previous.before[index] or previous.after_caps[index] > previous.after[index]:
		error = "Повреждены высоты сохранённого локального слоя."; return {}
	for channel in ["waters","before_waters"]:
		var saved: int = previous.get(channel,previous.waters)[index]
		if saved < 0 or saved > candidate.height_limit: error = "Повреждена вода сохранённого локального слоя."; return {}
	for channel in ["tops","bases","colors","before_tops","before_bases","before_colors"]:
		if previous.get(channel,previous[channel.trim_prefix("before_")])[index] >= before.palette.size(): error = "Повреждены материалы сохранённого локального слоя."; return {}
	state.locked = bool(previous.protected[index])
	if previous.affected[index] or state.locked:
		for pair in [["height","after"],["cap","after_caps"],["top","tops"],["base","bases"],["water","waters"],["color","colors"]]:
			state.locked = state.locked or state[pair[0]] != previous[pair[1]][index]
		state.locked = state.locked or state.side != previous.sides.get(index,{}) or (previous.get("flows",{}).has(point/16) and previous.flows[point/16] != state.flow)
		if not state.locked:
			for pair in [["height","before"],["cap","before_caps"],["top","before_tops"],["base","before_bases"],["water","before_waters"],["color","before_colors"]]:
				state[pair[0]] = previous.get(pair[1],previous.get(pair[1].trim_prefix("before_")))[index]
			state.side = previous.get("before_sides",previous.sides).get(index,{})
	if not state.locked: state.flow = previous.get("before_flows",previous.get("flows",{})).get(point/16,state.flow)
	return state

func _influence_at(layer: Dictionary, sample: Vector2) -> Dictionary:
	if layer.get("kind") == "road":
		var sampled := Math.path_sample(layer.curve,sample,layer.parameters.width_m,layer.parameters.edge_m)
		if sampled.is_empty(): return {}
		var height_m: float = lerpf(layer.start_height_m,layer.end_height_m,clampf(sampled.offset/layer.curve.get_baked_length(),0,1))
		return {"kind":"road","height":height_m*16-before.origin_y,"weight":Math.road_weight(sampled.distance,layer.parameters),"surface":sampled.distance<float(layer.parameters.width_m)*0.5}
	if layer.get("kind") == "mountain":
		var weight := Math.mountain_weight(layer.bounds,sample,layer.parameters)
		return {"kind":"mountain","height":float(layer.parameters.height_m)*16-before.origin_y,"weight":weight} if weight > 0 else {}
	if layer.get("kind") == "lake":
		var distance := Math.lake_distance(layer.bounds,sample)
		return {"kind":"lake","distance":distance,"parameters":layer.parameters} if distance > 0 else {}
	if layer.get("kind") == "river":
		var sampled := Math.river_sample(layer.curve,sample,layer.parameters)
		if sampled.is_empty(): return {}
		var along := clampf(inverse_lerp(layer.start_s,layer.end_s,sampled.offset),0,1)
		sampled.water_m = lerpf(layer.start_water_m,layer.end_water_m,along)
		sampled.kind = "river"; sampled.parameters = layer.parameters
		var fade_in := smoothstep(0.0,maxf(0.5,layer.start_s),sampled.offset)
		var fade_out := 1.0-smoothstep(layer.end_s,maxf(layer.end_s+0.5,layer.curve.get_baked_length()),sampled.offset)
		sampled.flow = sampled.tangent*float(layer.parameters.flow)*(1.0-smoothstep(0.0,float(layer.parameters.width_m)*0.5,sampled.distance))*fade_in*fade_out
		return sampled
	var weight := Math.weight(layer.bounds,sample,layer.parameters.transition_m)
	return {"kind":"plateau","height":float(layer.parameters.height_m)*16-before.origin_y,"weight":weight} if weight > 0 else {}

func _project(state: Dictionary, influence: Dictionary) -> void:
	if influence.kind != "river" and state.water > state.height:
		error = "Сухая область пересекает воду. Измените её границы или перенесите на сушу."; return
	if influence.kind == "lake":
		if state.flow != Vector2.ZERO: error = "Озеро создаётся на земле без исходного течения. Реку добавляйте после озера в списке."; return
		var sampled := Math.lake_height(influence.distance,float(state.height+before.origin_y)/16.0,influence.parameters)
		state.height = clampi(roundi((sampled*16.0-before.origin_y)/4.0)*4,4,candidate.height_limit)
		if influence.distance >= float(influence.parameters.shore_m):
			state.water = roundi((float(influence.parameters.water_m)*16.0-before.origin_y)/4.0)*4
			state.color = _water
			if state.height <= state.water+8: state.top = _sand; state.base = _soil
		state.side = {}
	elif influence.kind == "river":
		var wet: bool = state.water > state.height
		var half: float = influence.parameters.width_m*0.5
		if wet and influence.distance >= half: return # Preserve the existing body beyond the channel.
		var sampled := Math.river_height(influence.distance,float(state.height+before.origin_y)/16.0,influence.water_m,influence.parameters)
		var height := clampi(roundi((sampled*16.0-before.origin_y)/4.0)*4,4,candidate.height_limit)
		state.height = mini(state.height,height) if wet else height
		if influence.distance < half:
			if not wet: state.water = roundi(influence.water_m*16.0-before.origin_y); state.color = _water
			if state.water > state.height: state.flow = influence.flow
			if state.height <= state.water+8: state.top = _sand; state.base = _soil
		state.side = {}
	elif influence.kind == "mountain":
		# A lower peak is not a cutting tool. Constant target height makes the
		# summit flat and repeat/move independent of previously applied relief.
		state.height = maxi(state.height,clampi(roundi(lerpf(float(state.height),influence.height,influence.weight)/4.0)*4,4,candidate.height_limit))
	elif influence.kind == "road":
		state.height = clampi(roundi(lerpf(float(state.height),influence.height,influence.weight)/4.0)*4,4,candidate.height_limit)
		if state.water > 0 and state.height <= state.water:
			error = "Дорога опустит землю под воду. Измените линию или высоты конечных площадок; мост добавим отдельно."; return
		if influence.surface: state.top = _soil
		state.side = {}
	else:
		state.height = clampi(roundi(lerpf(float(state.height),influence.height,influence.weight)/4.0)*4,4,candidate.height_limit)
		if state.water > 0 and state.height <= state.water: error = "Плато опустит землю под воду. Поднимите его или измените границы."; return
	state.cap = mini(state.cap,state.height)

func _prepare_layer() -> void:
	var layer := _layers[_prepare_index]
	if layer.get("kind") not in ["river","road"]: _prepare_index += 1; return
	var length: float = layer.curve.get_baked_length()
	var count := ceili(length/0.5)+1
	if _probe_index < count:
		var point: Vector2 = layer.curve.sample_baked(minf(_probe_index*0.5,length))
		var state := _original_state(Vector2i(point*16.0))
		if state.is_empty(): return
		if not state.locked:
			for index in _prepare_index:
				var influence := _influence_at(_layers[index],point)
				if not influence.is_empty(): _project(state,influence)
				if not error.is_empty(): return
		_probe.append({"wet":state.water>state.height,"water_m":float(state.water+before.origin_y)/16.0,"flow":state.flow,"height_m":float(state.height+before.origin_y)/16.0,"ground":state.height>0 and state.top>0})
		_probe_index += 1; return
	if layer.get("kind") == "road":
		for sample in _probe:
			if sample.wet or not sample.ground:
				error = "Дорога должна идти по готовой сухой земле. Пересечение с водой требует отдельного моста или изменения линии."; return
		layer.start_height_m = _probe[0].height_m; layer.end_height_m = _probe[-1].height_m
		var grade: float = absf(layer.end_height_m-layer.start_height_m)/length*100.0
		if grade > float(layer.parameters.grade_percent)+0.00001:
			error = "Уклон между концами %.1f%% превышает заданные %.1f%%. Удлините линию или измените конечные площадки." % [grade,layer.parameters.grade_percent]; return
		_prepare_index += 1; _probe_index = 0; _probe.clear(); return
	if not _probe[0].wet or not _probe[-1].wet:
		error = "Начните и закончите линию внутри двух водоёмов. Озеро должно стоять выше реки в списке."; return
	var first_dry := -1; var last_dry := -1
	for index in _probe.size():
		if not _probe[index].wet:
			if first_dry < 0: first_dry = index
			last_dry = index
	if first_dry < 0 or last_dry-first_dry < 2: error = "Между концами нужна сухая перемычка хотя бы 1 м. Для потока внутри воды используйте кисть воды."; return
	for index in range(first_dry,last_dry+1):
		if _probe[index].wet: error = "Первая проба русла соединяет два водоёма без пересечения третьей воды или другой реки."; return
	layer.start_water_m = _probe[0].water_m; layer.end_water_m = _probe[-1].water_m
	if layer.start_water_m < layer.end_water_m: error = "Река не может течь вверх. В плане нажмите «Развернуть реку»."; return
	if layer.end_water_m-float(layer.parameters.depth_m) < float(before.origin_y+4)/16.0:
		error = "Дно русла ниже основания карты. Уменьшите глубину."; return
	for index in _probe.size():
		if _probe[index].flow != Vector2.ZERO or (index < first_dry and not is_equal_approx(_probe[index].water_m,layer.start_water_m)) or (index > last_dry and not is_equal_approx(_probe[index].water_m,layer.end_water_m)):
			error = "Концы должны лежать в водоёмах без исходного течения и с постоянным уровнем. Развилки пока не поддерживаются."; return
	layer.start_s = float(first_dry-1)*0.5; layer.end_s = minf(float(last_dry+1)*0.5,length)
	_prepare_index += 1; _probe_index = 0; _probe.clear()

func _finalize_flows() -> void:
	for block: Vector2i in _flow_targets:
		var live := before.flow_at_cell(block.x*16,block.y*16)
		var flow: Vector2 = live if protected_blocks.has(block) else _flow_targets[block]
		_patch.flows[block] = flow
		if flow == live: continue
		var blocks_wide := _part.width/16
		if _part.water_flow.is_empty(): _part.water_flow.resize(blocks_wide*(_part.depth/16))
		var local: Vector2i = block-(_part_key*Terrain.Sections.CELLS/16)
		_part.water_flow[local.x+local.y*blocks_wide] = flow; _changed = true
