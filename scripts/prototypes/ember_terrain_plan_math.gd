@tool
extends RefCounted
const Sections=preload("res://scripts/prototypes/ember_terrain_sections.gd")
const MAX_WORLD_M:=Sections.MAX_AXIS*Sections.CELLS/16
## Shared influence sampling. No scene, renderer or storage mutation.
static func plan_is_path(region: Dictionary) -> bool:
	return region.get("kind") in ["river","road","coast"]

static func plan_controls(region: Dictionary) -> PackedVector2Array:
	if plan_is_path(region): return region.points_m.duplicate()
	return rectangle_points(plot_rect(region), plot_frame(region))

static func plot_frame(region: Dictionary) -> Transform2D:
	return region.get("plot_frame", Transform2D.IDENTITY)

static func plot_rect(region: Dictionary) -> Rect2:
	if region.has("plot_frame"):
		return Rect2(Vector2.ZERO, Vector2(region.plot_size_m))
	return Rect2(region.bounds)

static func rectangle_points(rect: Rect2, frame := Transform2D.IDENTITY) -> PackedVector2Array:
	return PackedVector2Array([frame * rect.position, frame * Vector2(rect.end.x, rect.position.y),
		frame * rect.end, frame * Vector2(rect.position.x, rect.end.y)])

static func plot_bounds(frame: Transform2D, size: Vector2i) -> Rect2i:
	var corners := rectangle_points(Rect2(Vector2.ZERO, Vector2(size)), frame)
	var box := Rect2(corners[0], Vector2.ZERO)
	for corner in corners:
		box = box.expand(corner)
	return Rect2i(Vector2i(box.position.floor()), Vector2i(box.end.ceil() - box.position.floor()))

static func plot_has_point(region: Dictionary, point: Vector2) -> bool:
	return plot_rect(region).has_point(plot_frame(region).affine_inverse() * point)

static func plan_anchor(region: Dictionary) -> Vector2:
	if not plan_is_path(region): return plot_frame(region) * plot_rect(region).get_center()
	var curve := path_curve(region.points_m)
	return curve.sample_baked(curve.get_baked_length()*0.5)

static func plan_edit(region: Dictionary, index: int, delta: Vector2, translate: bool) -> Dictionary:
	var next := region.duplicate(true)
	if region.has("plot_frame"):
		var frame := plot_frame(region)
		var local_delta := frame.affine_inverse().basis_xform(delta).snapped(Vector2.ONE)
		var size: Vector2i = region.plot_size_m
		if translate:
			frame.origin += frame.basis_xform(local_delta)
		else:
			var corners := rectangle_points(plot_rect(region))
			var opposite := corners[(index + 2) % 4]
			var direction := (corners[index] - opposite).sign()
			var extent := (corners[index] + local_delta - opposite) * direction
			var moved := opposite + extent.max(Vector2.ONE) * direction
			frame.origin = frame * moved.min(opposite)
			size = Vector2i((moved - opposite).abs())
		next.plot_frame = frame
		next.plot_size_m = size
		next.bounds = plot_bounds(frame, size)
		return next
	var path := plan_is_path(region)
	delta = delta.snapped(Vector2.ONE*(0.25 if path and region.has("support_placement_id") else 0.5 if path else 1.0))
	if path:
		var points := plan_controls(region)
		for i in points.size():
			if translate or i == index: points[i] += delta
		next.points_m = points
	elif translate:
		next.bounds = Rect2i(region.bounds.position+Vector2i(delta),region.bounds.size)
	else:
		var points := plan_controls(region)
		var opposite := points[(index+2)%4]
		var corner := points[index]+delta
		var lower := Vector2i(corner.min(opposite))
		next.bounds = Rect2i(lower,Vector2i(corner.max(opposite))-lower)
	return next

const DEFAULTS := {"height_m": 4.0, "transition_m": 4.0}
const LAKE_DEFAULTS := {"water_m": 4.0, "depth_m": 2.0, "shore_m": 2.0}
const COAST_DEFAULTS := {"water_m":0.0,"depth_m":1.25,"shore_m":3.0}
const RIVER_DEFAULTS := {"width_m": 4.0, "depth_m": 1.0, "shore_m": 2.0, "flow": 0.65}
const MOUNTAIN_DEFAULTS := {"height_m": 12.0, "summit_m": 4.0, "slope_m": 8.0}
const ROAD_DEFAULTS := {"width_m":4.0,"edge_m":2.0,"grade_percent":25.0}
const ROAD_SURFACES := ["soil", "paving"]
const STREET_GATE_WIDTH_M := 1.5
const GROVE_DEFAULTS := {"density":0.6,"spacing_m":6.0,"slope_percent":25.0,"seed":7,"model_ids":[]}
const PLACEMENT_DEFAULTS := {"density":0.6,"spacing_m":6.0,"clearance_m":0.5,"slope_percent":25.0,"seed":7,"model_ids":[]}
const PLACEMENT_GROUP_DEFAULTS := {"pattern":"uniform","cluster_strength":0.75,"cluster_size_m":24.0}
static func parameter_error(values: Dictionary, kind := "plateau") -> String:
	if values.get("terrain_sampling","legacy8") not in ["legacy8","fine16"]:return "Неизвестная точность рельефа."
	if kind == "mountain":
		if values.get("mountain_shape","ellipse") not in ["ellipse","massif"]:return "Неизвестная форма горы."
		var seed_value: Variant = values.get("shape_seed",7)
		if typeof(seed_value)!=TYPE_INT or seed_value<0 or seed_value>1000000:return "Вариант массива: целое число от 0 до 1000000."
	if kind in ["grove","placement"]:
		if kind == "placement":
			if typeof(values.get("clearance_m")) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(values.clearance_m)) or values.clearance_m < 0 or values.clearance_m > 8: return "Свободное место вокруг основания: от 0 до 8 м."
			if values.get("pattern","uniform") not in ["uniform","groups"]: return "Выберите рисунок расстановки."
			for key in ["cluster_strength","cluster_size_m"]:
				var value: Variant = values.get(key,PLACEMENT_GROUP_DEFAULTS[key])
				var limits := Vector2(0,1) if key == "cluster_strength" else Vector2(8,96)
				if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or value < limits.x or value > limits.y: return "Кучность: от 0 до 100%; размер группы: от 8 до 96 м."
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
	for key in ROAD_DEFAULTS if kind == "road" else MOUNTAIN_DEFAULTS if kind == "mountain" else RIVER_DEFAULTS if kind == "river" else COAST_DEFAULTS if kind == "coast" else LAKE_DEFAULTS if kind == "lake" else DEFAULTS:
		var value: Variant = values.get(key)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
			return "Параметры области должны быть конечными числами."
	if kind == "road":
		if values.get("surface", "soil") not in ROAD_SURFACES: return "Покрытие дороги: грунт или брусчатка."
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
	if kind == "coast":
		if values.water_m < -16 or values.water_m > 28:return "Уровень моря: от −16 до 28 м."
		if values.depth_m < 0.25 or values.depth_m > 16:return "Глубина моря: от 0,25 до 16 м."
		if values.shore_m < 0.5 or values.shore_m > 16:return "Ширина берега: от 0,5 до 16 м."
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
	var local := (point_m-Rect2(bounds).get_center())/scale
	if values.get("mountain_shape","ellipse") == "massif":
		# Large coherent lobes, broad crest and a compact, zero-slope foot.
		# No fine noise here: surface detail remains a separate operation.
		var angle := fmod(float(values.get("shape_seed",7))*2.399963229728653,TAU)
		var p := local.rotated(angle)/radius
		var theta := atan2(p.y,p.x)
		var reach := 0.82+0.10*sin(3.0*theta+0.7)+0.06*cos(5.0*theta-0.4)
		var radial := p.length()/reach
		var foot := 1.0-smoothstep(0.55,1.0,radial)
		var crest := Vector2(p.x+0.10-0.12*sin(p.y*3.0),p.y-0.07)
		var distance := Vector2(crest.x*1.9,crest.y*0.85).length()
		var crown := clampf(summit/radius,0.04,0.55)
		var body := pow(1.0-smoothstep(crown*0.15,1.08,distance),1.25)
		body *= 0.82+0.18*cos((p.y+0.13)*7.0)
		var shoulder_a := 0.48*(1.0-smoothstep(0.0,0.60,(p-Vector2(0.30,-0.29)).length()))
		var shoulder_b := 0.34*(1.0-smoothstep(0.0,0.52,(p-Vector2(-0.33,0.35)).length()))
		# Rounded union of broad shoulders; no creases where lobes meet.
		var mass := pow(pow(body,4.0)+pow(shoulder_a,4.0)+pow(shoulder_b,4.0),0.25)
		return clampf(mass*foot,0.0,1.0)
	var distance := local.length()
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
		if not is_finite(points[i].x) or not is_finite(points[i].y) or points[i].x < 0 or points[i].y < 0 or points[i].x >= MAX_WORLD_M or points[i].y >= MAX_WORLD_M: return "Точки линии должны находиться внутри карты."
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

static func street_block(selected_id: String, regions: Array) -> Dictionary:
	var roads := {}
	var ends := {}
	var connections := {}
	for road: Dictionary in regions:
		if road.get("kind") != "road" or not road.get("enabled", true) or road.has("support_placement_id"):
			continue
		var points: PackedVector2Array = road.points_m
		roads[road.id] = road
		ends[road.id] = [points[0], points[-1]]
		for point in ends[road.id]:
			if not connections.has(point):
				connections[point] = []
			connections[point].append(road.id)
	if not roads.has(selected_id):
		return {}
	# Remove dead ends from the perimeter search. They can still be alleys.
	var loose := connections.keys().filter(func(point: Vector2): return connections[point].size() == 1)
	while not loose.is_empty():
		var point: Vector2 = loose.pop_back()
		if connections[point].size() != 1:
			continue
		var id: String = connections[point][0]
		for end in ends[id]:
			connections[end].erase(id)
			if connections[end].size() == 1:
				loose.append(end)
	if not connections[ends[selected_id][0]].has(selected_id):
		return {}
	var start: Vector2 = ends[selected_id][0]
	var point := start
	var id := selected_id
	var outline := PackedVector2Array()
	var ring := {}
	while not ring.has(id):
		var road: Dictionary = roads[id]
		var reversed: bool = point != ends[id][0]
		var samples := path_curve(road.points_m).get_baked_points()
		if reversed:
			samples.reverse()
		samples.resize(samples.size() - 1)
		outline.append_array(samples)
		if outline.size() > 512 or ring.size() >= 12:
			return {}
		ring[id] = -1 if reversed else 1
		point = ends[id][0 if reversed else 1]
		var joined: Array = connections[point]
		if joined.size() != 2:
			return {}
		id = joined[1] if joined[0] == id else joined[0]
		if point == start:
			break
	if point != start or Geometry2D.triangulate_polygon(outline).is_empty():
		return {}
	for i in outline.size():
		for j in range(i + 2, outline.size() - (1 if i == 0 else 0)):
			if Geometry2D.segment_intersects_segment(outline[i], outline[i + 1], outline[j], outline[(j + 1) % outline.size()]) != null:
				return {}
	var seeds: Array[Dictionary] = []
	for road: Dictionary in roads.values():
		if ring.has(road.id):
			continue
		var line := path_curve(road.points_m).get_baked_points()
		if not Geometry2D.clip_polyline_with_polygon(line, outline).is_empty():
			continue
		var attached := false
		for endpoint in ends[road.id]:
			for i in outline.size():
				if Geometry2D.get_closest_point_to_segment(endpoint, outline[i], outline[(i + 1) % outline.size()]).distance_to(endpoint) <= 0.06:
					attached = true
					break
			if attached:
				break
		if attached:
			seeds.append({"road": road, "side": 1})
			seeds.append({"road": road, "side": -1})
	var inside := -1 if Geometry2D.is_polygon_clockwise(outline) else 1
	var outside_seeds: Array[Dictionary] = []
	for road_id in ring:
		var side: int = ring[road_id] * inside
		seeds.append({"road": roads[road_id], "side": side})
		outside_seeds.append({"road": roads[road_id], "side": -side})
	return {"outline": outline, "seeds": seeds, "outside_seeds": outside_seeds}


static func street_block_fits(shape: PackedVector2Array, outline: PackedVector2Array, outside: bool) -> bool:
	if outside:
		return Geometry2D.intersect_polygons(shape, outline).is_empty()
	return Geometry2D.clip_polygons(shape, outline).is_empty()


static func street_plot_candidates(road: Dictionary, regions: Array, extent: Vector2i, size: Vector2i,
		side: int, gap: int, setback: int, limit: int, available: Callable, anchor := Vector2.INF) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if limit <= 0 or path_error(road.get("points_m"), extent) != "":
		return result
	var reserved: Array[PackedVector2Array] = []
	var existing_lots: Array[PackedVector2Array] = []
	var corridors: Array[PackedVector2Array] = []
	var curve := path_curve(road.points_m)
	var distance_from_road := float(road.parameters.width_m) * 0.5 + float(road.parameters.edge_m) + setback
	for region: Dictionary in regions:
		var kind: String = region.get("kind", "")
		if kind == "construction":
			existing_lots.append(plan_controls(region))
		elif region.get("enabled", true):
			if kind in ["lake", "placement", "grove"]:
				reserved.append(plan_controls(region))
			elif kind in ["road", "river"]:
				var selected: bool = region.id == road.id
				var line := curve if selected else path_curve(region.points_m)
				var edge := float(region.parameters.edge_m if kind == "road" else region.parameters.shore_m)
				var radius := distance_from_road if selected else float(region.parameters.width_m) * 0.5 + edge
				corridors.append_array(Geometry2D.offset_polyline(line.get_baked_points(), radius, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND))
	var map_bounds := Rect2i(Vector2i.ZERO, extent)
	var length := curve.get_baked_length()
	var station := size.x * 0.5
	var manual := anchor.is_finite()
	if manual:
		station = snappedf(curve.get_closest_offset(anchor), 0.5)
		if station < size.x * 0.5:
			return result
		var offset := (anchor - curve.sample_baked(station)).dot(_street_normal(curve, station))
		if absf(offset) < 0.25:
			return result
		side = 1 if offset > 0.0 else -1
	while station <= length - size.x * 0.5 + 0.001 and result.size() < limit:
		var at := station
		# A blocked position need only cost half a metre of frontage.
		station = INF if manual else station + 0.5
		var tangent := curve.sample_baked(maxf(0, at - 0.5)).direction_to(curve.sample_baked(minf(length, at + 0.5)))
		if tangent.is_zero_approx():
			continue
		var normal := Vector2(-tangent.y, tangent.x) * side
		var along := tangent * side
		var front := curve.sample_baked(at) + normal * (distance_from_road + 0.75)
		var frame := Transform2D(along, normal, front - along * (size.x * 0.5))
		var bounds := plot_bounds(frame, size)
		var lot := {"bounds": bounds, "plot_frame": frame, "plot_size_m": size}
		var corners := plan_controls(lot)
		if not map_bounds.encloses(bounds) or reserved.any(func(area: PackedVector2Array): return not Geometry2D.intersect_polygons(corners, area).is_empty()):
			continue
		var clearance := rectangle_points(plot_rect(lot).grow(gap), frame)
		if existing_lots.any(func(other: PackedVector2Array): return not Geometry2D.intersect_polygons(clearance, other).is_empty()):
			continue
		if result.any(func(other: Dictionary): return not Geometry2D.intersect_polygons(clearance, plan_controls(other)).is_empty()):
			continue
		if corridors.any(func(path: PackedVector2Array): return not Geometry2D.intersect_polygons(corners, path).is_empty()):
			continue
		if available.call(lot):
			result.append(lot)
	return result


static func street_frontage(road: Dictionary, plot: Dictionary) -> Dictionary:
	var frame := plot_frame(plot)
	var inverse := frame.affine_inverse()
	var curve := path_curve(inverse * road.points_m)
	var rect := plot_rect(plot)
	var center := rect.get_center()
	var toward := curve.get_closest_point(center) - center
	if toward.is_zero_approx():
		return {}
	var a := rect.position
	var b := rect.end
	if absf(toward.x) >= absf(toward.y):
		a.x = b.x if toward.x > 0.0 else a.x
		b.x = a.x
	else:
		a.y = b.y if toward.y > 0.0 else a.y
		b.y = a.y
	var first := curve.get_closest_offset(a)
	var last := curve.get_closest_offset(b)
	if first > last:
		var corner := a
		a = b
		b = corner
		var station := first
		first = last
		last = station
	var middle := (first + last) * 0.5
	var axis := _street_normal(curve, middle)
	var side := signf(axis.dot(center - curve.sample_baked(middle)))
	var lane := float(road.parameters.width_m) * 0.5
	var shoulder := lane + float(road.parameters.edge_m)
	var offset := shoulder + 0.2
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	if last - first < 3.5 or last - first > 48.0 or side == 0.0:
		return {}
	for points in [[first, middle - STREET_GATE_WIDTH_M * 0.5], [middle + STREET_GATE_WIDTH_M * 0.5, last]]:
		var run := PackedVector2Array()
		var steps := ceili((points[1] - points[0]) / 0.5)
		for index in range(steps + 1):
			var station := lerpf(points[0], points[1], float(index) / steps)
			var point := curve.sample_baked(station) + _street_normal(curve, station) * side * offset
			if rect.grow(-0.02).has_point(point) or curve.get_closest_point(point).distance_to(point) < shoulder + 0.08:
				return {}
			run.append(point)
		if left.is_empty():
			left = run
		else:
			right = run
	# Shift the two gate ends in their own plane to keep the clear opening
	# constant on both the outside and inside of a bend.
	var gate := curve.sample_baked(middle) + axis * side * offset
	var gate_axis := Vector2(axis.y, -axis.x)
	left[-1] = gate - gate_axis * STREET_GATE_WIDTH_M * 0.5
	right[0] = gate + gate_axis * STREET_GATE_WIDTH_M * 0.5
	if a.distance_to(left[0]) > 6.0 or b.distance_to(right[-1]) > 6.0:
		return {}
	if a.distance_to(left[0]) > 0.05:
		left.insert(0, a)
	if b.distance_to(right[-1]) > 0.05:
		right.append(b)
	var approach := PackedVector2Array([gate, curve.sample_baked(middle) + axis * side * maxf(0.0, lane - 0.18)])
	for run in [left, right]:
		for index in range(run.size() - 1):
			if run[index].distance_to(run[index + 1]) < 0.02:
				return {}
			var steps := maxi(1, ceili(run[index].distance_to(run[index + 1]) / 0.25))
			for j in range(steps + 1):
				var point: Vector2 = run[index].lerp(run[index + 1], float(j) / steps)
				if curve.get_closest_point(point).distance_to(point) < shoulder + 0.07:
					return {}
	return {"runs": [frame * left, frame * right], "approach": frame * approach, "road": road.id}


static func _street_normal(curve: Curve2D, station: float) -> Vector2:
	var tangent := curve.sample_baked(maxf(0.0, station - 0.25)).direction_to(
		curve.sample_baked(minf(curve.get_baked_length(), station + 0.25)))
	return Vector2(-tangent.y, tangent.x)


static func street_plot_envelope(plot: Dictionary, frontage: Dictionary) -> PackedVector2Array:
	# Reserve the ground between the lot and the road as well as the lot itself.
	var points := plan_controls(plot)
	for run: PackedVector2Array in frontage.runs:
		points.append_array(run)
	var approach: PackedVector2Array = frontage.approach
	var axis := approach[0].direction_to(approach[1])
	var side := Vector2(-axis.y, axis.x) * 0.65
	var landing := approach[0] - axis * 0.25
	points.append_array(PackedVector2Array([landing + side, landing - side, approach[1] + side, approach[1] - side]))
	var hull := Geometry2D.convex_hull(points)
	hull.remove_at(hull.size() - 1)
	return hull


static func path_sample(curve: Curve2D, point: Vector2, width_m: float, edge_m: float) -> Dictionary:
	var offset := curve.get_closest_offset(point)
	var center := curve.sample_baked(offset)
	var distance := point.distance_to(center)
	if distance >= width_m*0.5+edge_m: return {}
	var tangent := (curve.sample_baked(minf(offset+0.5,curve.get_baked_length()))-curve.sample_baked(maxf(offset-0.5,0))).normalized()
	return {"distance":distance,"offset":offset,"tangent":tangent}


static func bridge_road_edge(curve: Curve2D, center: Vector2, toward: Vector2, half_width: float) -> Vector2:
	var axis := center.direction_to(toward)
	var limit := center.distance_to(toward) * 0.5
	var previous := 0.0
	var steps := maxi(1, ceili(limit / 0.25))
	for step in range(1, steps + 1):
		var distance := limit * float(step) / steps
		var sample := center + axis * distance
		if curve.get_closest_point(sample).distance_to(sample) >= half_width:
			var low := previous
			var high := distance
			for iteration in 12:
				var mid := (low + high) * 0.5
				sample = center + axis * mid
				if curve.get_closest_point(sample).distance_to(sample) >= half_width:
					high = mid
				else:
					low = mid
			return center + axis * high
		previous = distance
	return Vector2.INF

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

static func placement_group_noise(values: Dictionary) -> FastNoiseLite:
	if values.get("pattern","uniform") != "groups" or values.get("cluster_strength",PLACEMENT_GROUP_DEFAULTS.cluster_strength) == 0: return null
	var noise := FastNoiseLite.new()
	noise.seed = (int(values.seed)+1669)&0x7fffffff
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	noise.frequency = 1.0/float(values.get("cluster_size_m",PLACEMENT_GROUP_DEFAULTS.cluster_size_m))
	return noise

static func placement_density(point: Vector2, values: Dictionary, group_noise: FastNoiseLite = null) -> float:
	var density: float = values.density
	if group_noise == null or density <= 0 or density >= 1: return density
	# Coherent variation in map metres; endpoints still mean none / all candidates.
	var strength: float = values.get("cluster_strength",PLACEMENT_GROUP_DEFAULTS.cluster_strength)
	return clampf(density+group_noise.get_noise_2dv(point)*3.0*minf(density,1.0-density)*strength,0,1)

static func grove_candidate(bounds: Rect2i, values: Dictionary, cell: Vector2i, group_noise: FastNoiseLite = null) -> Dictionary:
	var spacing: float = values.spacing_m
	var point := Vector2(bounds.position)+(Vector2(cell)+Vector2.ONE*0.5)*spacing
	point += Vector2(grove_random(values.seed,cell,1)-0.5,grove_random(values.seed,cell,2)-0.5)*spacing*0.7
	if not Rect2(bounds).has_point(point) or grove_random(values.seed,cell,3) >= placement_density(point,values,group_noise): return {}
	return {"key":"%d_%d"%[cell.x,cell.y],"point":point,"turn":grove_random(values.seed,cell,4)*TAU,
		"variant":mini(values.model_ids.size()-1,int(grove_random(values.seed,cell,5)*values.model_ids.size()))}


static func coast_bounds(points: PackedVector2Array, values: Dictionary, extent: Vector2i) -> Rect2i:
	var samples:=path_curve(points).get_baked_points()
	var lower:=samples[0];var upper:=lower
	for p in samples:lower=lower.min(p);upper=upper.max(p)
	var tangent: Vector2=(points[-1]-points[0]).normalized()
	var side:=Vector2(tangent.y,-tangent.x)
	if absf(side.x)>=absf(side.y):
		lower.x-=values.shore_m;upper.x+=values.shore_m
		if side.x>0:upper.x=extent.x
		else:lower.x=0
	else:
		lower.y-=values.shore_m;upper.y+=values.shore_m
		if side.y>0:upper.y=extent.y
		else:lower.y=0
	# Rect2i excludes its upper edge; integer control points must stay inside.
	var start:=Vector2i(lower.floor());var end:=Vector2i(upper.floor())+Vector2i.ONE
	return Rect2i(start,end-start).intersection(Rect2i(Vector2i.ZERO,extent))


static func existing_water_level_m(source) -> float:
	# A new sea starts at the dominant existing body, including negative origins.
	var counts: Dictionary={}
	var parts: Array=source.sections.values() if source.is_sectioned() else [source]
	for part in parts:
		var levels: PackedInt32Array=part.water_levels
		var unique: Dictionary={}
		for level in levels:
			if level>0:unique[level]=true
		for level in unique:counts[level]=counts.get(level,0)+levels.count(level)
	var best:=0;var count:=0
	for level: int in counts:
		if counts[level]>count:best=level;count=counts[level]
	return float(best+source.origin_y)/16.0 if count>0 else 0.0


static func coast_sample(curve: Curve2D, point: Vector2, values: Dictionary) -> Dictionary:
	var offset:=curve.get_closest_offset(point)
	var centre:=curve.sample_baked(offset)
	var tangent: Vector2=(curve.sample_baked(minf(offset+0.5,curve.get_baked_length()))-curve.sample_baked(maxf(0,offset-0.5))).normalized()
	# The sea is to the right of the directed coastline (x/z plan view).
	var distance: float=(point-centre).dot(Vector2(tangent.y,-tangent.x))
	return {"distance":distance} if distance> -float(values.shore_m) else {}


static func coast_height(distance: float, original_m: float, values: Dictionary) -> float:
	if distance<0:return lerpf(original_m,float(values.water_m),smoothstep(-float(values.shore_m),0.0,distance))
	return lerpf(float(values.water_m),float(values.water_m)-float(values.depth_m),smoothstep(0.0,float(values.shore_m),distance))
