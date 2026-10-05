@tool
extends RefCounted
## Bounded, cancellable authoring job. Produces a private candidate in the
## existing terrain Resource; applying and history belong to WorldEditor.

const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Math = preload("res://scripts/prototypes/ember_terrain_generation_math.gd")
const Selection = preload("res://addons/ember_import/ember_compact_section_selection.gd")
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


func begin(source: EmberTerrainPilotResource, area_blocks: Rect2i, parameters: Dictionary, new_sections := false) -> bool:
	cancel()
	cancelled = false
	finished = false
	elapsed_us = 0
	worst_step_us = 0
	_completed = 0
	_water = 0
	error = Math.parameter_error(parameters)
	if not error.is_empty(): return false
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
	if mini(mini(_soil, _grass), mini(_sand, _stone)) <= 0 or _water <= 0:
		error = "Нужны назначенные материалы грунта, травы, песка, камня и слот воды. Старые цвета не переопределяются автоматически."; return false
	before = Selection.rebase(source, addition) if new_sections else source
	candidate = before.sectioned_copy()
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
	var needed := ceili((float(parameters.sea_m) + float(parameters.land_m) + float(parameters.relief_m)) * 4.0) * 4
	if candidate.height_limit < needed:
		candidate.height_limit = needed
		for key in candidate.sections:
			var header := candidate.sections[key].duplicate(false) as EmberTerrainPilotResource
			header.height_limit = needed
			candidate.sections[key] = header
	_sea = roundi(float(parameters.sea_m) * 4.0) * 4
	_sampler = Math.new()
	_sampler.configure(Rect2(Vector2(area_blocks.position), Vector2(area_blocks.size)), parameters)
	return true


func cancel() -> void:
	addition = {}
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


func progress() -> float:
	return 1.0 if finished else float(_completed) / float(maxi(1, _completed + _addresses.size() + (1 if _part != null else 0)))


func step(budget_us := 4000) -> void:
	if finished or cancelled or candidate == null: return
	var started := Time.get_ticks_usec()
	while Time.get_ticks_usec() - started < budget_us:
		if _part == null:
			if _addresses.is_empty(): finished = true; break
			_start_part(_addresses.pop_front())
		_generate_group()
		_point.x += GROUP
		if _point.x >= _rect.end.x: _point.x = _rect.position.x; _point.y += GROUP
		if _point.y >= _rect.end.y: _finish_part()
	var duration := Time.get_ticks_usec() - started
	elapsed_us += duration
	worst_step_us = maxi(worst_step_us, duration)


func _start_part(key: Vector2i) -> void:
	_part_key = key
	_part = candidate.sections[key].working_copy() if candidate.sections.has(key) else Selection.empty_section(candidate)
	_rect = bounds.intersection(Rect2i(key * Terrain.Sections.CELLS, Vector2i(_part.width, _part.depth)))
	_point = _rect.position
	_heights = _part.heights
	_tops = _part.top_materials
	_bases = _part.base_materials
	_caps = _part.cap_depths
	_waters = _part.water_levels
	_colors = _part.water_materials
	# Generated stationary sea replaces authored flow only inside the selection.
	if not _part.water_flow.is_empty():
		for z in range((_rect.position.y - key.y * Terrain.Sections.CELLS) / 16, (_rect.end.y - key.y * Terrain.Sections.CELLS) / 16):
			for x in range((_rect.position.x - key.x * Terrain.Sections.CELLS) / 16, (_rect.end.x - key.x * Terrain.Sections.CELLS) / 16):
				_part.water_flow[x + z * (_part.width / 16)] = Vector2.ZERO


func _blend_weight(point: Vector2i) -> float:
	var edge := BLEND_M
	# Blend only where existing land adjoins the selection. A full-map island
	# must remain submerged at its outer boundary, without a retained land ring.
	if before.has_column(bounds.position.x - 1, point.y): edge = minf(edge, float(point.x - bounds.position.x) / 16.0)
	if before.has_column(bounds.end.x, point.y): edge = minf(edge, float(bounds.end.x - point.x - GROUP) / 16.0)
	if before.has_column(point.x, bounds.position.y - 1): edge = minf(edge, float(point.y - bounds.position.y) / 16.0)
	if before.has_column(point.x, bounds.end.y): edge = minf(edge, float(bounds.end.y - point.y - GROUP) / 16.0)
	return smoothstep(0.0, BLEND_M, maxf(0.0, edge))


func _generate_group() -> void:
	var weight := _blend_weight(_point)
	var reference := {}
	if not addition.is_empty():
		reference = _addition_edge(_point)
		weight = float(reference.get("weight", 1.0))
	elif weight <= 0.0: return
	var sampled := float(_sampler.height_m((Vector2(_point) + Vector2.ONE * 4.0) / 16.0)) * 16.0
	var part_start := _part_key * Terrain.Sections.CELLS
	for z in range(_point.y, mini(_point.y + GROUP, _rect.end.y)):
		for x in range(_point.x, mini(_point.x + GROUP, _rect.end.x)):
			var local := x - part_start.x + (z - part_start.y) * _part.width
			var retained: float = reference.get("height", _heights[local])
			var value := clampi(roundi(lerpf(retained, sampled, weight) / 4.0) * 4, 4, candidate.height_limit)
			_heights[local] = value
			_tops[local] = _sand if value <= _sea + 8 else _stone if value > _sea + 16 * 6 and _sampler.parameters.profile != "hills" else _grass
			_bases[local] = _stone if _tops[local] == _stone else _soil
			_caps[local] = mini(3, value)
			var water_level := roundi(lerpf(float(reference.get("water", _sea)), float(_sea), weight) / 4.0) * 4
			_waters[local] = water_level if value < water_level else 0
			_colors[local] = _water if _waters[local] > 0 else 0
			_part.column_material_overrides.erase(local)


func _addition_edge(point: Vector2i) -> Dictionary:
	# New neighbouring sections share the same sampler. Only retained, untouched
	# terrain supplies a join; occupied sections inside the rectangle stay intact.
	var patch := Rect2i(_part_key * Terrain.Sections.CELLS, Vector2i.ONE * Terrain.Sections.CELLS)
	var nearest := BLEND_M * 16.0
	var sample := Vector2i.ZERO
	var found := false
	for edge in [[Vector2i(patch.position.x - 1, point.y), point.x - patch.position.x],
		[Vector2i(patch.end.x, point.y), patch.end.x - point.x - GROUP],
		[Vector2i(point.x, patch.position.y - 1), point.y - patch.position.y],
		[Vector2i(point.x, patch.end.y), patch.end.y - point.y - GROUP]]:
		if float(edge[1]) <= nearest and before.has_column(edge[0].x, edge[0].y):
			nearest = edge[1]
			sample = edge[0]
			found = true
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
