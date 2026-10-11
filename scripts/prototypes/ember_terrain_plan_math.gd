@tool
extends RefCounted
## Shared influence sampling. No scene, renderer or storage mutation.
const DEFAULTS := {"height_m": 4.0, "transition_m": 4.0}
const LAKE_DEFAULTS := {"water_m": 4.0, "depth_m": 2.0, "shore_m": 2.0}
const RIVER_DEFAULTS := {"width_m": 4.0, "depth_m": 1.0, "shore_m": 2.0, "flow": 0.65}
const MOUNTAIN_DEFAULTS := {"height_m": 12.0, "summit_m": 4.0, "slope_m": 8.0}
const ROAD_DEFAULTS := {"width_m":4.0,"edge_m":2.0,"grade_percent":25.0}
const GROVE_DEFAULTS := {"density":0.6,"spacing_m":6.0,"slope_percent":25.0,"seed":7,"model_ids":[]}
const PLACEMENT_DEFAULTS := {"density":0.6,"spacing_m":6.0,"clearance_m":0.5,"slope_percent":25.0,"seed":7,"model_ids":[]}
static func parameter_error(values: Dictionary, kind := "plateau") -> String:
	if kind in ["grove","placement"]:
		if kind == "placement":
			if typeof(values.get("clearance_m")) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(values.clearance_m)) or values.clearance_m < 0 or values.clearance_m > 8: return "Свободное место вокруг основания: от 0 до 8 м."
		for key in ["density","spacing_m","slope_percent"]:
			if typeof(values.get(key)) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(values[key])): return "Параметры расстановки должны быть конечными числами."
		if values.density < 0 or values.density > 1: return "Плотность: от 0 до 100%."
		if values.spacing_m < 2 or values.spacing_m > 24: return "Интервал между центрами объектов: от 2 до 24 м."
		if values.slope_percent < 0 or values.slope_percent > 50: return "Уклон для объектов: от 0 до 50%."
		if typeof(values.get("seed")) != TYPE_INT or values.seed < 0 or values.seed > 2147483646: return "Номер варианта: от 0 до 2147483646."
		var ids: Variant = values.get("model_ids")
		if not (ids is PackedStringArray or ids is Array) or ids.size() > 4: return "Выберите до четырёх готовых объектов."
		var seen := {}
		for id in ids:
			if not id is String or not id.is_valid_identifier() or (kind == "grove" and not id.begins_with("vox_")) or seen.has(id): return "Некорректный или повторный объект в наборе."
			seen[id] = true
		return ""
	for key in ROAD_DEFAULTS if kind == "road" else MOUNTAIN_DEFAULTS if kind == "mountain" else RIVER_DEFAULTS if kind == "river" else LAKE_DEFAULTS if kind == "lake" else DEFAULTS:
		var value: Variant = values.get(key)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
			return "Параметры области должны быть конечными числами."
	if kind == "road":
		if values.width_m < 2 or values.width_m > 12: return "Ширина дороги: от 2 до 12 м."
		if values.edge_m < 0.5 or values.edge_m > 8: return "Мягкий край дороги: от 0,5 до 8 м."
		if values.grade_percent < 1 or values.grade_percent > 50: return "Допустимый уклон дороги: от 1 до 50%."
		return ""
	if kind == "mountain":
		if values.height_m < 0.25 or values.height_m > 28: return "Высота вершины: от 0,25 до 28 м от основания карты."
		if values.summit_m < 0 or values.summit_m > 48: return "Ширина вершины: от 0 до 48 м."
		if values.slope_m < 0.5 or values.slope_m > 32: return "Ширина склонов: от 0,5 до 32 м."
		return ""
	if kind == "river":
		if values.width_m < 2 or values.width_m > 12: return "Ширина русла: от 2 до 12 м."
		if values.depth_m < 0.25 or values.depth_m > 8: return "Глубина русла: от 0,25 до 8 м."
		if values.shore_m < 0.5 or values.shore_m > 8: return "Ширина берега: от 0,5 до 8 м."
		if values.flow < 0 or values.flow > 1: return "Сила течения: от 0 до 1."
		return ""
	if kind == "lake":
		if values.water_m < 0.5 or values.water_m > 28: return "Уровень озера: от 0,5 до 28 м."
		if values.depth_m < 0.25 or values.depth_m > 16: return "Глубина озера: от 0,25 до 16 м."
		if values.water_m-values.depth_m < 0.25: return "Дно озера должно быть выше основания карты минимум на 0,25 м."
		if values.shore_m < 0.5 or values.shore_m > 16: return "Ширина берега: от 0,5 до 16 м."
		return ""
	if values.height_m < 0.25 or values.height_m > 28.0: return "Высота плато: от 0,25 до 28 м."
	if values.transition_m < 0.5 or values.transition_m > 16.0: return "Переход плато: от 0,5 до 16 м."
	return ""
static func weight(bounds: Rect2i, point_m: Vector2, transition_m: float) -> float:
	if not Rect2(bounds).has_point(point_m): return 0.0
	var distance := minf(minf(point_m.x - bounds.position.x, bounds.end.x - point_m.x),
		minf(point_m.y - bounds.position.y, bounds.end.y - point_m.y))
	return smoothstep(0.0, transition_m, maxf(distance, 0.0))

static func mountain_defaults(bounds: Rect2i) -> Dictionary:
	var values := MOUNTAIN_DEFAULTS.duplicate()
	var side := float(min(bounds.size.x,bounds.size.y))
	values.summit_m = minf(values.summit_m,floorf(side*0.25*4.0)/4.0)
	values.slope_m = minf(values.slope_m,maxf(0.5,floorf((side-values.summit_m)*2.0)/4.0))
	return values

static func mountain_bounds_error(bounds: Rect2i, values: Dictionary) -> String:
	if min(bounds.size.x,bounds.size.y) < 8: return "Выделите для горы область хотя бы 8×8 м."
	if values.summit_m+values.slope_m*2.0 > min(bounds.size.x,bounds.size.y): return "Вершина и два склона должны помещаться в меньшей стороне области. Уменьшите их ширину или расширьте границы."
	return ""

static func mountain_weight(bounds: Rect2i, point_m: Vector2, values: Dictionary) -> float:
	# An elliptical raised shape with a level summit and a smooth return to
	# original land. Horizontal widths are measured along the shorter axis.
	if not Rect2(bounds).has_point(point_m): return 0.0
	var summit := float(values.summit_m)*0.5
	var radius := summit+float(values.slope_m)
	var scale := Vector2(bounds.size)/float(min(bounds.size.x,bounds.size.y))
	var distance := ((point_m-Rect2(bounds).get_center())/scale).length()
	return 1.0-smoothstep(summit,radius,distance)

static func lake_bounds_error(bounds: Rect2i, values: Dictionary) -> String:
	if min(bounds.size.x,bounds.size.y) < 8: return "Выделите для озера область хотя бы 8×8 м."
	if values.shore_m > min(bounds.size.x,bounds.size.y)*0.25: return "Берег должен быть не шире четверти меньшей стороны области."
	return ""

static func lake_distance(bounds: Rect2i, point_m: Vector2) -> float:
	var radius := Vector2(bounds.size)*0.5
	return (1.0-((point_m-Rect2(bounds).get_center())/radius).length())*minf(radius.x,radius.y)

static func lake_height(distance_m: float, original_m: float, values: Dictionary) -> float:
	# A closed bank lies inside the authoring rectangle. The outside edge
	# matches the original land; the inner slope descends to an absolute bed.
	var shore := float(values.shore_m)
	var bank := maxf(original_m,float(values.water_m)+0.25)
	if distance_m < shore: return lerpf(original_m,bank,smoothstep(0.0,shore,distance_m))
	return lerpf(bank,float(values.water_m)-float(values.depth_m),smoothstep(shore,shore*2.0,distance_m))

static func path_curve(points: PackedVector2Array) -> Curve2D:
	# A private derived cache. Only control points belong to the scene plan.
	var curve := Curve2D.new(); curve.bake_interval = 0.5
	for i in points.size():
		var handle := Vector2.ZERO
		if i > 0 and i < points.size()-1:
			handle = (points[i+1]-points[i-1]).normalized()*minf(points[i].distance_to(points[i-1]),points[i].distance_to(points[i+1]))*0.22
		curve.add_point(points[i],-handle,handle)
	return curve

static func path_error(points: Variant, extent := Vector2i.ZERO) -> String:
	if not points is PackedVector2Array or points.size() < 2 or points.size() > 32: return "У линии должно быть от 2 до 32 точек."
	var length := 0.0
	for i in points.size():
		if not is_finite(points[i].x) or not is_finite(points[i].y) or points[i].x < 0 or points[i].y < 0 or points[i].x >= 528 or points[i].y >= 528: return "Точки линии должны находиться внутри карты."
		if extent != Vector2i.ZERO and not Rect2(Vector2.ZERO,Vector2(extent)).has_point(points[i]): return "Линия выходит за карту."
		if i > 0:
			var distance: float = points[i].distance_to(points[i-1])
			if distance < 1: return "Между соседними точками нужен хотя бы 1 м."
			length += distance
	if length > 96: return "Первая проба линии ограничена длиной 96 м."
	for i in range(points.size()-1):
		for j in range(i+2,points.size()-1):
			if Geometry2D.segment_intersects_segment(points[i],points[i+1],points[j],points[j+1]) != null:
				return "Линия не должна пересекать сама себя. Развилки добавим отдельно."
	return ""

static func path_bounds(points: PackedVector2Array, width_m: float, edge_m: float, extent: Vector2i) -> Rect2i:
	var samples := path_curve(points).get_baked_points()
	var lower := samples[0]; var upper := lower
	for point in samples: lower = lower.min(point); upper = upper.max(point)
	var radius := width_m*0.5+edge_m
	var start := Vector2i((lower-Vector2.ONE*radius).floor())
	var end := Vector2i((upper+Vector2.ONE*radius).ceil())
	return Rect2i(start,end-start).intersection(Rect2i(Vector2i.ZERO,extent))

static func path_sample(curve: Curve2D, point: Vector2, width_m: float, edge_m: float) -> Dictionary:
	var offset := curve.get_closest_offset(point)
	var center := curve.sample_baked(offset)
	var distance := point.distance_to(center)
	if distance >= width_m*0.5+edge_m: return {}
	var tangent := (curve.sample_baked(minf(offset+0.5,curve.get_baked_length()))-curve.sample_baked(maxf(offset-0.5,0))).normalized()
	return {"distance":distance,"offset":offset,"tangent":tangent}

# Compatibility entrypoints route to the same path math; no second sampler.
static func river_curve(points: PackedVector2Array) -> Curve2D: return path_curve(points)
static func river_path_error(points: Variant, extent := Vector2i.ZERO) -> String: return path_error(points,extent)
static func river_bounds(points: PackedVector2Array, values: Dictionary, extent: Vector2i) -> Rect2i: return path_bounds(points,values.width_m,values.shore_m,extent)
static func river_sample(curve: Curve2D, point: Vector2, values: Dictionary) -> Dictionary: return path_sample(curve,point,values.width_m,values.shore_m)
static func road_bounds(points: PackedVector2Array, values: Dictionary, extent: Vector2i) -> Rect2i: return path_bounds(points,values.width_m,values.edge_m,extent)

static func road_weight(distance_m: float, values: Dictionary) -> float:
	var half := float(values.width_m)*0.5
	return 1.0-smoothstep(half,half+float(values.edge_m),distance_m)

static func river_height(distance: float, original_m: float, water_m: float, values: Dictionary) -> float:
	var half := float(values.width_m)*0.5
	# The wet profile and the outer slope meet at the same lip. Using the
	# original high land at this seam would create a vertical cut along it.
	var bank := water_m+0.25
	if distance >= half: return lerpf(bank,original_m,smoothstep(half,half+float(values.shore_m),distance))
	return lerpf(water_m-float(values.depth_m),water_m+0.25,smoothstep(0.0,half,distance))

static func grove_random(seed: int, cell: Vector2i, channel: int) -> float:
	# Stable channels: rejecting a wet/occupied point never shifts later variants.
	var value := (seed*104729+cell.x*73856093+cell.y*19349663+channel*83492791)&0x7fffffff
	value = ((value^(value>>13))*1274126177)&0x7fffffff
	return float(value)/2147483648.0

static func grove_candidate(bounds: Rect2i, values: Dictionary, cell: Vector2i) -> Dictionary:
	var spacing: float = values.spacing_m
	var point := Vector2(bounds.position)+(Vector2(cell)+Vector2.ONE*0.5)*spacing
	point += Vector2(grove_random(values.seed,cell,1)-0.5,grove_random(values.seed,cell,2)-0.5)*spacing*0.7
	if not Rect2(bounds).has_point(point) or grove_random(values.seed,cell,3) >= values.density: return {}
	return {"key":"%d_%d"%[cell.x,cell.y],"point":point,"turn":grove_random(values.seed,cell,4)*TAU,
		"variant":mini(values.model_ids.size()-1,int(grove_random(values.seed,cell,5)*values.model_ids.size()))}
