@tool
extends RefCounted
## Bounded, cancellable authoring job. Produces a private candidate in the
## existing terrain Resource; applying and history belong to WorldEditor.

const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Math = preload("res://scripts/prototypes/ember_terrain_generation_math.gd")
const Selection = preload("res://addons/ember_import/ember_compact_section_selection.gd")
const SurfaceForms = preload("res://scripts/prototypes/ember_terrain_surface_form_math.gd")
const Plan=preload("res://scripts/ember_terrain_plan_resource.gd")
const MAX_BLOCKS := 96
const GROUP := 8
const BLEND_M := 2.0

var error := ""
var candidate: EmberTerrainPilotResource
var before: EmberTerrainPilotResource
var bounds := Rect2i()
var finished := false
var cancelled := false
var elapsed_us := 0
var worst_step_us := 0
var _sampler: RefCounted
var _addresses: Array[Vector2i] = []
var _completed := 0
var _part: EmberTerrainPilotResource
var _part_key := Vector2i.ZERO
var _rect := Rect2i()
var _point := Vector2i.ZERO
var _heights := PackedInt32Array()
var _tops := PackedByteArray()
var _bases := PackedByteArray()
var _caps := PackedByteArray()
var _waters := PackedInt32Array()
var _colors := PackedByteArray()
var _soil := 0
var _grass := 0
var _sand := 0
var _stone := 0
var _water := 0
var _sea := 0
var addition := {}
var _surface_strength:=0.0
var _surface_scale:=1.0
var _surface_forms: RefCounted
var _surface_keys: Array[Vector2i]=[]
var _surface_phase:=false
var _macro: EmberTerrainPilotResource
var _total_parts:=0
var _fine_sampling := false
var _operation:="generate"
var _preserve_generated_cover:=false
var _coverage_scale:=1.0
var _coverage_sea:=2.0
var _coverage_parameters: Dictionary={}
var _coverage_field: SurfaceForms.CoverageField
var _paint_locks: Dictionary={}
var protected_paint_columns:=0
var _retained_areas: Array[Rect2i]=[]


func begin(source: EmberTerrainPilotResource, area_blocks: Rect2i, parameters: Dictionary, new_sections := false,paint_plan: Resource=null) -> bool:
	cancel()
	cancelled = false
	finished = false
	elapsed_us = 0
	worst_step_us = 0
	_completed = 0
	_water = 0
	error = Math.parameter_error(parameters)
	if not error.is_empty(): return false
	_operation=str(parameters.get("terrain_operation","generate"))
	_preserve_generated_cover=parameters.has("terrain_operation") and not new_sections
	if new_sections and _operation!="generate":error="Новые участки сначала создаются генератором рельефа.";return false
	if source == null: error = "Откройте компактную карту."; return false
	if new_sections:
		if area_blocks.position.x % Selection.BLOCKS != 0 or area_blocks.position.y % Selection.BLOCKS != 0 or area_blocks.size.x % Selection.BLOCKS != 0 or area_blocks.size.y % Selection.BLOCKS != 0:
			error = "Выделение должно совпадать с сеткой участков."; return false
		addition = Selection.plan(source, Rect2i(area_blocks.position / Selection.BLOCKS, area_blocks.size / Selection.BLOCKS))
		error = addition.error
		if not error.is_empty(): return false
		area_blocks = addition.area
	if not area_blocks.has_area() or area_blocks.size.x > MAX_BLOCKS or area_blocks.size.y > MAX_BLOCKS:
		error = "Выберите область от 1 до 96 метров по каждой оси."; return false
	error=Math.surface_bounds_error(area_blocks,parameters)
	if not error.is_empty():return false
	bounds = Rect2i(area_blocks.position * 16, area_blocks.size * 16)
	if not new_sections and not Rect2i(0, 0, source.width, source.depth).encloses(bounds):
		error = "Область выходит за границу карты."; return false
	var validation := source.validation_errors()
	if not validation.is_empty(): error = validation[0]; return false
	var roles := source.palette_surface_roles
	_soil = roles.find("soil")
	_grass = roles.find("grass")
	_sand = roles.find("sand")
	_stone = roles.find("stone")
	# Water has its existing authored slot, outside surface-role classification.
	var water_sources: Array = source.sections.values() if source.is_sectioned() else [source]
	for part: EmberTerrainPilotResource in water_sources:
		for slot in range(1, source.palette.size()):
			if part.water_materials.has(slot): _water = slot; break
		if _water > 0: break
	if _water <= 0 and source.palette.size() > 5: _water = 5
	if (_operation!="detail" and mini(mini(_soil, _grass), mini(_sand, _stone)) <= 0) or (_operation=="generate" and _water <= 0):
		error = "Нужны назначенные материалы грунта, травы, песка, камня и слот воды. Старые цвета не переопределяются автоматически."; return false
	before = Selection.rebase(source, addition) if new_sections else source
	candidate = before.sectioned_copy()
	if new_sections:
		for key: Vector2i in before.sections:
			var part: Terrain=before.sections[key]
			_retained_areas.append(Rect2i(key*Terrain.Sections.CELLS,Vector2i(part.width,part.depth)))
	var cells := Terrain.Sections.CELLS
	for z in range(bounds.position.y / cells, (bounds.end.y - 1) / cells + 1):
		for x in range(bounds.position.x / cells, (bounds.end.x - 1) / cells + 1):
			var key := Vector2i(x, z)
			if new_sections:
				if key in addition.keys: _addresses.append(key)
				continue
			var part: EmberTerrainPilotResource = candidate.sections.get(key)
			var required := Rect2i(key * cells, Vector2i.ONE * cells).intersection(bounds)
			if part == null or not Rect2i(key * cells, Vector2i(part.width, part.depth)).encloses(required):
				error = "В области есть пустое место. Сначала добавьте недостающие участки."; candidate = null; return false
			_addresses.append(key)
	var needed := ceili((float(parameters.sea_m) + float(parameters.land_m) + float(parameters.relief_m)) * 4.0) * 4 - candidate.origin_y
	if parameters.profile == "plains":
		needed = ceili((float(parameters.sea_m)+float(parameters.land_m)+float(parameters.relief_m)+float(parameters.get("micro_m",Math.PLAINS_DEFAULTS.micro_m)))*4.0)*4-candidate.origin_y
	_surface_strength=float(parameters.get("surface_strength",0.0))
	_surface_scale=float(parameters.get("surface_scale",1.0))
	if _operation!="generate":needed=source.height_limit
	if _surface_strength>0.0 or _operation!="generate":
		if _operation=="generate":needed+=ceili(_surface_strength*16.0)
		_surface_forms=SurfaceForms.new()
		_surface_forms.configure(int(parameters.get("coverage_seed",731)) if _operation=="coverage" else int(parameters.get("surface_seed",731)))
		if _operation=="generate":_surface_keys.assign(_addresses)
		else:
			_surface_phase=true;_macro=candidate.duplicate(false);_macro.sections=candidate.sections.duplicate(false)
	_coverage_scale=float(parameters.get("coverage_scale",1.0));_coverage_sea=float(parameters.get("coverage_sea_m",2.0))
	if _operation=="coverage":
		_coverage_parameters=parameters.duplicate(true)
		if paint_plan!=null:
			var paint_errors: Array[String]=paint_plan.validation_errors(Vector2i(source.width/16,source.depth/16))
			if not paint_errors.is_empty():error=paint_errors[0];candidate=null;return false
			_paint_locks=paint_plan.paint_locks.duplicate(true)
		if parameters.get("coverage_profile","legacy")=="large":_coverage_field=SurfaceForms.CoverageField.new(_macro,bounds,float(parameters.get("coverage_sand_width_m",Math.ZONE_DEFAULTS.coverage_sand_width_m)))
	_total_parts=_addresses.size()*(2 if _operation=="generate" and _surface_strength>0.0 else 1)
	if candidate.height_limit < needed:
		candidate.height_limit = needed
		for key in candidate.sections:
			var header := candidate.sections[key].duplicate(false) as EmberTerrainPilotResource
			header.height_limit = needed
			candidate.sections[key] = header
	_sea = roundi(float(parameters.sea_m) * 4.0) * 4 - candidate.origin_y
	_fine_sampling = parameters.get("terrain_sampling","legacy8") == "fine16"
	_sampler = Math.new()
	_sampler.configure(Rect2(Vector2(area_blocks.position), Vector2(area_blocks.size)), parameters)
	return true


func cancel() -> void:
	addition = {}
	_retained_areas.clear()
	cancelled = true
	candidate = null
	_part = null
	before = null
	_sampler = null
	_addresses.clear()
	_heights = PackedInt32Array()
	_tops = PackedByteArray()
	_bases = PackedByteArray()
	_caps = PackedByteArray()
	_waters = PackedInt32Array()
	_colors = PackedByteArray()
	_surface_keys.clear();_surface_phase=false;_surface_forms=null;_macro=null
	_surface_strength=0.0;_surface_scale=1.0;_total_parts=0
	_operation="generate";_preserve_generated_cover=false
	_coverage_field=null;_coverage_parameters={};_paint_locks={};protected_paint_columns=0


func progress() -> float:
	if finished:return 1.0
	var parts:=float(_completed)/float(maxi(1,_total_parts))
	return 0.25*_coverage_field.progress()+0.75*parts if _coverage_field!=null else parts


func step(budget_us := 4000) -> void:
	if finished or cancelled or candidate == null: return
	var started := Time.get_ticks_usec()
	while Time.get_ticks_usec() - started < budget_us:
		if _coverage_field!=null and not _coverage_field.finished:
			_coverage_field.step(maxi(1,budget_us-int(Time.get_ticks_usec()-started)));continue
		if _part == null:
			if _addresses.is_empty():
				if _surface_strength>0.0 and not _surface_phase:
					# Snapshot retains macro section resources. Each selected section
					# gets its own working_copy before writes; neighbours stay immutable.
					_macro=candidate.duplicate(false)
					_macro.sections=candidate.sections.duplicate(false)
					_surface_phase=true;_addresses.assign(_surface_keys);_surface_keys.clear()
				else:finished = true;_macro=null;_surface_forms=null;_coverage_field=null;_paint_locks={}; break
				if _addresses.is_empty():finished=true;break
			_start_part(_addresses.pop_front())
		if _surface_phase:_generate_surface_group()
		else:_generate_group()
		var stride := _stride()
		_point.x += stride
		if _point.x >= _rect.end.x: _point.x = _rect.position.x; _point.y += stride
		if _point.y >= _rect.end.y: _finish_part()
	var duration := Time.get_ticks_usec() - started
	elapsed_us += duration
	worst_step_us = maxi(worst_step_us, duration)


func _start_part(key: Vector2i) -> void:
	_part_key = key
	_part = candidate.sections[key].working_copy() if candidate.sections.has(key) else Selection.empty_section(candidate)
	if not addition.is_empty() and (_part.width<Terrain.Sections.CELLS or _part.depth<Terrain.Sections.CELLS):
		_part=Selection.completed_section(candidate,_part)
	_rect = bounds.intersection(Rect2i(key * Terrain.Sections.CELLS, Vector2i(_part.width, _part.depth)))
	_point = _rect.position
	_heights = _part.heights
	_tops = _part.top_materials
	_bases = _part.base_materials
	_caps = _part.cap_depths
	_waters = _part.water_levels
	_colors = _part.water_materials
	# Generated stationary sea replaces authored flow only inside the selection.
	if _operation=="generate" and not _surface_phase and not _part.water_flow.is_empty():
		for z in range((_rect.position.y - key.y * Terrain.Sections.CELLS) / 16, (_rect.end.y - key.y * Terrain.Sections.CELLS) / 16):
			for x in range((_rect.position.x - key.x * Terrain.Sections.CELLS) / 16, (_rect.end.x - key.x * Terrain.Sections.CELLS) / 16):
				if addition.is_empty() or not before.has_column(key.x*Terrain.Sections.CELLS+x*16,key.y*Terrain.Sections.CELLS+z*16):
					_part.water_flow[x + z * (_part.width / 16)] = Vector2.ZERO


func _stride() -> int:
	return 1 if _fine_sampling and not _surface_phase else GROUP

func _blend_weight(point: Vector2i) -> float:
	var edge := BLEND_M
	# Blend only where existing land adjoins the selection. A full-map island
	# must remain submerged at its outer boundary, without a retained land ring.
	if before.has_column(bounds.position.x - 1, point.y): edge = minf(edge, float(point.x - bounds.position.x) / 16.0)
	if before.has_column(bounds.end.x, point.y): edge = minf(edge, float(bounds.end.x - point.x - _stride()) / 16.0)
	if before.has_column(point.x, bounds.position.y - 1): edge = minf(edge, float(point.y - bounds.position.y) / 16.0)
	if before.has_column(point.x, bounds.end.y): edge = minf(edge, float(bounds.end.y - point.y - _stride()) / 16.0)
	return smoothstep(0.0, BLEND_M, maxf(0.0, edge))


func _generate_group() -> void:
	if not addition.is_empty() and before.has_column(_point.x,_point.y):return
	var weight := _blend_weight(_point)
	var reference := {}
	if not addition.is_empty():
		reference = _addition_edge(_point)
		weight = float(reference.get("weight", 1.0))
	elif weight <= 0.0: return
	var sampled := float(_sampler.height_m((Vector2(_point) + Vector2.ONE * (float(_stride()) * 0.5)) / 16.0)) * 16.0 - candidate.origin_y
	var part_start := _part_key * Terrain.Sections.CELLS
	for z in range(_point.y, mini(_point.y + _stride(), _rect.end.y)):
		for x in range(_point.x, mini(_point.x + _stride(), _rect.end.x)):
			var local := x - part_start.x + (z - part_start.y) * _part.width
			var retained: float = reference.get("height", _heights[local])
			var quantum := 1 if _fine_sampling else 4
			var value := clampi(roundi(lerpf(retained, sampled, weight) / float(quantum)) * quantum, 4, candidate.height_limit)
			_heights[local] = value
			if not _preserve_generated_cover or _tops[local]<=0:
				_tops[local] = _sand if _sampler.parameters.get("land_shape","island")=="island" and value <= _sea + 8 else _stone if value > _sea + 16 * 6 and _sampler.parameters.profile not in ["hills","plains"] else _grass
				_bases[local] = _stone if _tops[local] == _stone else _soil
				_caps[local] = mini(3, value)
			else:_caps[local]=mini(_caps[local],value)
			var water_level := roundi(lerpf(float(reference.get("water", _sea)), float(_sea), weight) / 4.0) * 4
			_waters[local] = water_level if value < water_level else 0
			_colors[local] = _water if _waters[local] > 0 else 0
			if not _preserve_generated_cover:_part.column_material_overrides.erase(local)

func _macro_height(x: int,z: int,fallback: float) -> float:
	x=clampi(x,0,_macro.width-1);z=clampi(z,0,_macro.depth-1)
	return float(_macro.column_value("heights",_macro.column_index(x,z))) if _macro.has_column(x,z) else fallback

func _generate_surface_group() -> void:
	if not addition.is_empty() and before.has_column(_point.x,_point.y):return
	var weight:=_blend_weight(_point) if addition.is_empty() else float(_addition_edge(_point).get("weight",1.0))
	if weight<=0.0:return
	var part_start:=_part_key*Terrain.Sections.CELLS
	for z in range(_point.y,mini(_point.y+GROUP,_rect.end.y)):
		for x in range(_point.x,mini(_point.x+GROUP,_rect.end.x)):
			var local:=x-part_start.x+(z-part_start.y)*_part.width
			var index:=_macro.column_index(x,z)
			var height:=float(_macro.column_value("heights",index))
			var wet:=_macro.column_value("water_levels",index)>0
			# Water and its bed retain the exact result of the primary generator.
			if wet:continue
			var p:=Vector2((x+0.5)/16.0,(z+0.5)/16.0)
			if height<=0:continue
			if _operation=="coverage":
				if weight<=0.5:continue
				if Plan.paint_locked(_paint_locks,Vector2i(x,z)) or not _part.column_material_overrides.get(local,{}).is_empty():protected_paint_columns+=1;continue
				var normal:=Vector3((_macro_height(x-8,z,height)-_macro_height(x+8,z,height))/16.0,1.0,(_macro_height(x,z-8,height)-_macro_height(x,z+8,height))/16.0).normalized()
				var role: String=_surface_forms.zone_role_at(p,_coverage_field,_coverage_parameters) if _coverage_field!=null else _surface_forms.role_at(p/_coverage_scale,height/16.0,1.0-normal.y,_coverage_sea)
				_tops[local]=candidate.palette_surface_roles.find(role)
				_bases[local]=_stone if role=="stone" else _soil
				continue
			var role: String=candidate.surface_role_for_palette(_macro.column_value("top_materials",index))
			var dry_weight:=smoothstep(float(_sea)/16.0+0.15,float(_sea)/16.0+0.7,height/16.0) if _operation=="generate" else 1.0
			var offset: int=_surface_forms.brush_offset_voxels(p,role,_surface_scale,roundi(_surface_strength*16.0),weight*dry_weight,1,0)
			var low:=maxi(4,_sea) if _operation=="generate" and height>=_sea else 1
			_heights[local]=clampi(int(height)+offset,maxi(low,_caps[local]),candidate.height_limit)


func _addition_edge(point: Vector2i) -> Dictionary:
	# New neighbouring sections share the same sampler. Only retained, untouched
	# terrain supplies a join; occupied sections inside the rectangle stay intact.
	var nearest := BLEND_M * 16.0
	var sample := Vector2i.ZERO
	var found := false
	# Include the true edge of a partial section, not its 24m capacity.
	for area: Rect2i in _retained_areas:
		var at:=Vector2i(clampi(point.x,area.position.x,area.end.x-1),clampi(point.y,area.position.y,area.end.y-1))
		var distance:=maxf(0.0,Vector2(point-at).length()-1.0)
		if distance<=nearest:
			nearest=distance;sample=at;found=true
	if not found: return {}
	var column := before.column_index(sample.x, sample.y)
	return {"weight": smoothstep(0.0, BLEND_M * 16.0, maxf(0.0, nearest)),
		"height": before.column_value("heights", column), "water": before.column_value("water_levels", column)}


func _finish_part() -> void:
	_part.heights = _heights
	_part.top_materials = _tops
	_part.base_materials = _bases
	_part.cap_depths = _caps
	_part.water_levels = _waters
	_part.water_materials = _colors
	candidate.sections[_part_key] = _part
	_part = null
	_completed += 1
