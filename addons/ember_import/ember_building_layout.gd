@tool
extends RefCounted
const CANOPY_HALF_WIDTH_M := 0.625
const CANOPY_DEPTH_M := 0.625
const DETAIL_HALF_WIDTH_M := 0.125
const DETAIL_END_CLEARANCE_M := 0.1875
const BEAM_HEIGHT_M := 0.1875
const BALCONY_HALF_WIDTH_M := 0.75
const BALCONY_DEPTH_M := 0.875
const BALCONY_DECK_M := 0.125
const BALCONY_DOOR_M := 1.75
const BALCONY_PARTS := 5
const PART_LIMIT := 32
const ROOF_GABLE := 0
const ROOF_HIP := 1
const ROOF_FLAT := 2
const ROOF_PARAPET := 3
const FENCE_OUTSET_KEYS := ["fence_front_m", "fence_right_m", "fence_rear_m", "fence_left_m"]
const FENCE_NORMALS := [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
const FENCE_GATE_HALF_M := 0.625
## Building-provider authoring data in the existing GeneratorRecipe.structure.
static func has_wing(p:Dictionary)->bool:return int(p.get("wing_side",0))!=0

static func has_opposite_wing(p: Dictionary) -> bool:
	return has_wing(p) and bool(p.get("opposite_wing", false))


static func has_gabled_wing(p: Dictionary, opposite := false) -> bool:
	var enabled := has_opposite_wing(p) if opposite else has_wing(p)
	return enabled and int(p.get("opposite_roof" if opposite else "wing_roof", 0)) >= 1


static func has_cross_gable(p: Dictionary, opposite := false) -> bool:
	return has_gabled_wing(p, opposite) and int(p.get("opposite_roof" if opposite else "wing_roof", 0)) == 2


static func wing_turn(p: Dictionary) -> int:
	if not has_wing(p) or not p.get("wing_on_side", false):
		return 0
	return 1 if int(p.wing_side) == 1 else -1


static func turn_point(point: Vector2, turn: int) -> Vector2:
	if turn == 2:
		return -point
	return Vector2(point.y * turn, -point.x * turn) if turn != 0 else point


# In this frame the wing is always attached to the back, along +Z.
static func wing_plan(p: Dictionary) -> Dictionary:
	if wing_turn(p) == 0:
		return p
	var local := p.duplicate()
	local.width_m = p.depth_m
	local.depth_m = p.width_m
	local.wing_on_side = false
	local.wing_side = 2 if wing_turn(p) == 1 else 1
	return local


static func wing_rect(p: Dictionary, opposite := false) -> Rect2:
	var turn := wing_turn(p)
	if turn != 0:
		var local := wing_rect(wing_plan(p), opposite)
		var a := turn_point(local.position, turn)
		var b := turn_point(local.end, turn)
		return Rect2(a.min(b), (b - a).abs())
	var width := float(p.width_m)
	var depth := float(p.depth_m)
	var wing_width := float(p.get("opposite_width_m" if opposite else "wing_width_m", 1.5 if opposite else 2.0))
	var length := float(p.get("opposite_length_m" if opposite else "wing_length_m", 2.0))
	var right := (int(p.get("wing_side", 1)) == 1) != opposite
	var inset := float(p.get("opposite_inset_m" if opposite else "wing_inset_m", 0.0))
	var x := width * 0.5 - wing_width - inset if right else -width * 0.5 + inset
	return Rect2(Vector2(x, depth * 0.5), Vector2(wing_width, length))


static func is_wing_wall(side: int) -> bool:
	return side >= 4 and side <= 9


static func rear_wing(p: Dictionary, right: bool) -> Rect2:
	if not has_wing(p) or wing_turn(p) != 0:
		return Rect2()
	var opposite := (int(p.wing_side) == 1) != right
	return Rect2() if opposite and not has_opposite_wing(p) else wing_rect(p, opposite)


static func wall_ids(p: Dictionary) -> Array[int]:
	var result: Array[int] = [0, 1, 2, 3]
	if has_wing(p):
		result.append_array([4, 5, 6])
	if has_opposite_wing(p):
		result.append_array([7, 8, 9])
	if wing_turn(p) != 0 and float(p.get("wing_inset_m", 0.0)) > 0.0:
		result.append(12)
	var left := rear_wing(p, false)
	var right := rear_wing(p, true)
	var half_width := float(p.width_m) * 0.5
	if left.has_area() and left.position.x > -half_width:
		result.append(10)
	if right.has_area() and right.end.x < half_width:
		result.append(11)
	return result


static func minimum_wing_gap(p: Dictionary) -> float:
	return 2.0 * float(p.overhang_m) + 0.25


static func max_wing_inset(p: Dictionary, opposite: bool) -> float:
	var local := wing_plan(p)
	var width := float(local.width_m) - wing_rect(local, opposite).size.x
	if has_opposite_wing(p):
		var other := wing_rect(p, not opposite)
		var other_inset := float(p.get("wing_inset_m" if opposite else "opposite_inset_m", 0.0))
		return width - other.size.x - other_inset - minimum_wing_gap(p)
	return width - 0.25
static func bounds(p:Dictionary)->Rect2:
	var result=Rect2(Vector2(-p.width_m/2,-p.depth_m/2),Vector2(p.width_m,p.depth_m))
	if has_wing(p):
		result = result.merge(wing_rect(p))
	if has_opposite_wing(p):
		result = result.merge(wing_rect(p, true))
	return result

static func model_offset(p:Dictionary)->Vector2:return -bounds(p).get_center()

static func front_corner(p: Dictionary) -> Vector2:
	return model_offset(p) - Vector2(p.width_m, p.depth_m) * 0.5


static func placement_offset(p: Dictionary) -> Vector3:
	if not p.has("fixed_corner"):
		return Vector3.ZERO
	var delta: Vector2 = p.fixed_corner - front_corner(p)
	return Vector3(delta.x, 0.0, delta.y)


static func wing_heights(p:Dictionary)->Vector2:
	var eave=.25+float(p.floor_height_m)
	return Vector2(eave-1.0/16.0,maxf(2.375,eave-.5))

static func edge(side:int,p:Dictionary)->Dictionary:
	var x0=-float(p.width_m)/2;var x1=-x0;var z0=-float(p.depth_m)/2;var z1=-z0
	var turn := wing_turn(p)
	if turn != 0:
		var attached_wall := 1 if turn == 1 else 3
		if is_wing_wall(side) or side == attached_wall or side == 12:
			var local_id := side
			if side == attached_wall:
				local_id = 2
			elif side == 12:
				local_id = 10 if turn == 1 else 11
			var wall := edge(local_id, wing_plan(p))
			var a := turn_point(wall.a, turn)
			var b := turn_point(wall.b, turn)
			var normal := turn_point(Vector2(wall.normal.x, wall.normal.z), turn)
			if side == attached_wall and a.y > b.y:
				var first := a
				a = b
				b = first
			return {"a": a, "b": b, "normal": Vector3(normal.x, 0.0, normal.y)}
	if side in [2, 10, 11]:
		var left := rear_wing(p, false)
		var right := rear_wing(p, true)
		var start: float = left.end.x if left.has_area() else x0
		var end: float = right.position.x if right.has_area() else x1
		if side == 10:
			start = x0
			end = left.position.x
		elif side == 11:
			start = right.end.x
			end = x1
		return {"a": Vector2(start, z1), "b": Vector2(end, z1), "normal": Vector3.BACK}
	var opposite := side >= 7
	var right := (int(p.get("wing_side", 0)) == 1) != opposite
	var wing := wing_rect(p, opposite)
	if opposite:
		side -= 3
	match side:
		0:return {"a":Vector2(x0,z0),"b":Vector2(x1,z0),"normal":Vector3.FORWARD}
		1:return {"a":Vector2(x1,z0),"b":Vector2(x1,z1),"normal":Vector3.RIGHT}
		3:return {"a":Vector2(x0,z0),"b":Vector2(x0,z1),"normal":Vector3.LEFT}
		4:return {"a":Vector2(wing.end.x if right else wing.position.x,z1),"b":Vector2(wing.end.x if right else wing.position.x,wing.end.y),"normal":Vector3.RIGHT if right else Vector3.LEFT}
		5:return {"a":Vector2(wing.position.x,wing.end.y),"b":wing.end,"normal":Vector3.BACK}
		_:return {"a":wing.position if right else Vector2(wing.end.x,z1),"b":Vector2(wing.position.x if right else wing.end.x,wing.end.y),"normal":Vector3.LEFT if right else Vector3.RIGHT}

static func outline(p:Dictionary)->PackedVector2Array:
	var turn := wing_turn(p)
	if turn != 0:
		var rotated := PackedVector2Array()
		for vertex in outline(wing_plan(p)):
			rotated.append(turn_point(vertex, turn))
		return rotated
	var corner := Vector2(float(p.width_m) * 0.5, float(p.depth_m) * 0.5)
	var path := PackedVector2Array([-corner, Vector2(corner.x, -corner.y), corner])
	for right: bool in [true, false]:
		var wing := rear_wing(p, right)
		if wing.has_area():
			path.append_array(PackedVector2Array([
				Vector2(wing.end.x, wing.position.y), wing.end,
				Vector2(wing.position.x, wing.end.y), wing.position
			]))
	path.append(Vector2(-corner.x, corner.y))
	var unique := PackedVector2Array()
	for vertex in path:
		if unique.is_empty() or unique[-1] != vertex:
			unique.append(vertex)
	var result := PackedVector2Array()
	for index in unique.size():
		var before := unique[index] - unique[index - 1]
		var after := unique[(index + 1) % unique.size()] - unique[index]
		if not is_zero_approx(before.cross(after)):
			result.append(unique[index])
	return result
static func defaults(floors:int)->Dictionary:
	var windows:Array=[]
	for level in floors:
		for side in [0,1,3]:
			for t in ([0.23,0.77] if side==0 else [0.5]):
				windows.append({"side":side,"t":t,"level":level})
	return {"version":1,"windows":windows,"door":{"side":0,"t":0.5}}

static func data(value:Dictionary,floors:int)->Dictionary:
	return defaults(floors) if value.is_empty() else value.duplicate(true)


static func fence_plan(p: Dictionary, door: Dictionary) -> Dictionary:
	var base := bounds(p).grow(0.75)
	var lo := base.position - Vector2(p.fence_left_m, p.fence_front_m)
	var hi := base.end + Vector2(p.fence_right_m, p.fence_rear_m)
	var corners := [Vector2(lo.x, lo.y), Vector2(hi.x, lo.y), Vector2(lo.x, hi.y), Vector2(hi.x, hi.y)]
	var starts := [corners[0], corners[1], corners[2], corners[0]]
	var ends := [corners[1], corners[3], corners[3], corners[2]]
	var face: Vector3 = edge(door.side, p).normal
	var gate_side := FENCE_NORMALS.find(Vector2(face.x, face.z))
	var door_point := point(door, p.width_m, p.depth_m, p)
	var bay_side: int = [-1, 3, 1, 2][int(p.fence_bay_side)]
	var segments: Array[Dictionary] = []
	var extent := Rect2(lo, hi - lo)
	var hinge := Vector2.ZERO
	for side in 4:
		var start: Vector2 = starts[side]
		var end: Vector2 = ends[side]
		var along := (end - start).normalized()
		var length := start.distance_to(end)
		var breaks := PackedVector2Array([start, end])
		var gap := Vector2(-1, -1)
		if side == gate_side:
			var center := clampf((door_point - start).dot(along), 0.75, length - 0.75)
			gap = Vector2(center - FENCE_GATE_HALF_M, center + FENCE_GATE_HALF_M)
			hinge = start + along * gap.x
		if side == bay_side:
			var size_m: float = p.fence_bay_m
			var half := size_m * 0.5
			var center := clampf(length * float(p.fence_bay_position), half + 0.25, length - half - 0.25)
			var left := center - half
			var right := center + half
			if side == gate_side and left < gap.y + 0.125 and right > gap.x - 0.125:
				return {"error": "Карман задевает калитку. Сдвиньте карман или выберите другую сторону."}
			var a := start + along * left
			var b := start + along * right
			var outward: Vector2 = FENCE_NORMALS[side] * size_m
			breaks = PackedVector2Array([start, a, a + outward, b + outward, b, end])
			extent = extent.expand(a + outward).expand(b + outward)
		for index in range(breaks.size() - 1):
			var a := breaks[index]
			var b := breaks[index + 1]
			if side == gate_side and is_equal_approx((a - start).dot(FENCE_NORMALS[side]), 0.0) and is_equal_approx((b - start).dot(FENCE_NORMALS[side]), 0.0) and (a - start).dot(along) <= gap.x and (b - start).dot(along) >= gap.y:
				segments.append({"from": a, "to": hinge})
				segments.append({"from": start + along * gap.y, "to": b})
			else:
				segments.append({"from": a, "to": b})
	return {"segments": segments, "bounds": extent, "rectangle": Rect2(lo, hi - lo), "hinge": hinge, "gate_side": gate_side}


static func errors(value:Dictionary,parameters:Dictionary)->Array[String]:
	var out:Array[String]=[]
	if parameters.get("opposite_wing", false) and not has_wing(parameters):
		return ["Сначала добавьте основную пристройку."]
	if wing_turn(parameters) != 0 and (has_opposite_wing(parameters) or has_gabled_wing(parameters)):
		return ["Боковая стена доступна для одной низкой пристройки."]
	var roof_shape := int(parameters.get("roof_shape", ROOF_GABLE))
	if roof_shape != ROOF_GABLE and (has_gabled_wing(parameters) or has_gabled_wing(parameters, true)):
		return ["Для этой крыши выберите низкий односкатный вариант у каждого крыла."]
	for opposite: bool in [false, true]:
		if not (has_opposite_wing(parameters) if opposite else has_wing(parameters)):
			continue
		var inset := float(parameters.get("opposite_inset_m" if opposite else "wing_inset_m", 0.0))
		if inset > 0.0 and has_gabled_wing(parameters, opposite):
			return ["Для двускатной крыши верните крыло к краю стены: сдвиг 0 м."]
		if inset > max_wing_inset(parameters, opposite):
			return ["Крыло не помещается. Уменьшите сдвиг, ширину крыла или свес."]
	if value.is_empty():return out
	if value.get("version")!=1 or not value.get("windows") is Array or not value.get("door") is Dictionary:
		return ["Некорректный план дома."]
	if value.windows.size()>8:return ["В первом наборе дома допускается до восьми окон."]
	var openings:Array=value.windows.duplicate(true);openings.append(value.door)
	var walls := wall_ids(parameters)
	for index in openings.size():
		var opening:Variant=openings[index]
		if not opening is Dictionary or not opening.get("side") is int or opening.side not in walls or opening.side == 12 or not (opening.get("t") is float or opening.get("t") is int):
			out.append("У проёма нет допустимой стены/позиции.");continue
		var t=float(opening.t)
		var level:Variant=opening.get("level",0)
		if not is_finite(t) or t<0.12 or t>0.88 or not level is int or level<0 or level>=int(parameters.floors):
			out.append("Окно или дверь выходит за границы стены/этажа.");continue
		if is_wing_wall(opening.side) and level != 0 and not has_gabled_wing(parameters, opening.side >= 7):
			out.append("У низкой пристройки только первый этаж.")
		var wall=edge(opening.side,parameters)
		var position=point(opening,parameters.width_m,parameters.depth_m,parameters)
		var half_width=0.5 if index==value.windows.size() else 0.375
		var fits := fits_wall(position, wall, half_width)
		var attached_wall := 1 if wing_turn(parameters) == 1 else 3
		if not fits and opening.side == attached_wall and 12 in walls:
			fits = fits_wall(position, edge(12, parameters), half_width)
		if not fits:
			out.append("Рама проёма выходит за край стены или попадает на стык пристройки.")
		var length_m: float = wall.a.distance_to(wall.b)
		if opening.side == 2:
			length_m = float(parameters.width_m)
		elif opening.side in [1, 3]:
			length_m = float(parameters.depth_m)
		for other in openings.slice(index+1):
			if other is Dictionary and other.get("side")==opening.side and other.get("level",0)==level and (other.get("t") is float or other.get("t") is int):
				if absf(t-float(other.t))*length_m<1.05:out.append("Окно и соседний проём расположены слишком близко.")
	var parts=10+int(parameters.floors)+value.windows.size()*2+(6 if parameters.get("fence",false) else 0)+(5 if has_wing(parameters) else 0)
	if parameters.get("fence", false) and parameters.get("fence_custom", false):
		var yard := fence_plan(parameters, value.door)
		if yard.has("error"):
			return [yard.error]
		parts += yard.segments.size() + 1 - 6
	match roof_shape:
		ROOF_HIP, ROOF_FLAT: parts -= 1
		ROOF_PARAPET: parts += 3
	if has_opposite_wing(parameters):
		parts += 5
	if not parameters.get("corner_posts", true):
		parts -= 4
	for opposite in [false, true]:
		if has_cross_gable(parameters, opposite):
			parts += 1
		if not parameters.get("corner_posts", true) and (has_opposite_wing(parameters) if opposite else has_wing(parameters)) and not has_gabled_wing(parameters, opposite):
			parts -= 2
	if parts>PART_LIMIT:out.append("Слишком много деталей для этого дома: уберите часть окон или ограду.")
	if parameters.get("entry_canopy", false) and out.is_empty():
		parts += 3
		if parts > PART_LIMIT:
			out.append("Для козырька нужны ещё три детали. Уберите часть окон или выключите ограду.")
		elif canopy_intersects_house(value.door, parameters):
			out.append("Козырёк задевает соседнюю секцию. Сдвиньте вход или отключите козырёк.")
	if out.is_empty():
		var details: Variant = value.get("facade_details", [])
		if not details is Array:
			return ["Некорректный список деталей фасада."]
		if parts + details.size() > PART_LIMIT:
			return ["В доме не осталось места для детали фасада. Уберите другую деталь, окно или ограду."]
		var detail_error := facade_detail_error(details, openings, parameters, walls)
		if not detail_error.is_empty():
			out.append(detail_error)
		else:
			for detail: Dictionary in details:
				parts += BALCONY_PARTS if detail.kind == "balcony" else 1
			if parts > PART_LIMIT:
				out.append("В доме не осталось места для детали фасада. Уберите другую деталь, окно или ограду.")
	return out


static func wall_fraction(position: Vector2, wall: Dictionary) -> float:
	var length: float = wall.a.distance_squared_to(wall.b)
	if length <= 0.000001:
		return 0.0
	return clampf(snappedf((position - wall.a).dot(wall.b - wall.a) / length, 0.025), 0.0, 1.0)


static func facade_detail_profile(detail: Dictionary, p: Dictionary) -> Dictionary:
	var wall := edge(detail.side, p)
	var from: Vector2 = wall.a.lerp(wall.b, detail.t)
	var to: Vector2 = wall.a.lerp(wall.b, detail.get("end_t", detail.t))
	var bottom := 0.25 + float(p.floor_height_m) * int(detail.level)
	if detail.kind == "balcony":
		var outward := Vector2(wall.normal.x, wall.normal.z)
		var half_width := float(p.get("balcony_width_m", BALCONY_HALF_WIDTH_M * 2.0)) * 0.5
		var depth := float(p.get("balcony_depth_m", BALCONY_DEPTH_M))
		var along := outward.orthogonal() * half_width
		var a := from - along
		var b := from + along + outward * depth
		return {"from": from, "to": to, "normal": wall.normal, "half_width": half_width, "depth": depth,
			"bottom": bottom - BALCONY_DECK_M, "top": bottom + BALCONY_DOOR_M,
			"footprint": Rect2(a.min(b), (a - b).abs())}
	var top := bottom + float(p.floor_height_m) - 0.125
	if is_wing_wall(detail.side) and not has_gabled_wing(p, detail.side >= 7):
		top = wing_heights(p).y - 0.125
	var is_beam: bool = detail.kind == "beam"
	return {"from": from, "to": to, "normal": wall.normal,
		"half_width": from.distance_to(to) * 0.5 if is_beam else DETAIL_HALF_WIDTH_M,
		"bottom": top - BEAM_HEIGHT_M if is_beam else bottom, "top": top}


static func facade_detail_error(details: Array, openings: Array, p: Dictionary, walls: Array[int]) -> String:
	var placed: Array[Dictionary] = []
	for detail in details:
		if not detail is Dictionary or detail.get("kind") not in ["column", "beam", "balcony"] or not detail.get("side") is int or detail.side not in walls:
			return "У детали фасада нет допустимой стены."
		if not detail.get("level") is int or detail.level < 0 or detail.level >= int(p.floors):
			return "Деталь фасада выходит за границы этажа."
		if detail.level != 0 and is_wing_wall(detail.side) and not has_gabled_wing(p, detail.side >= 7):
			return "У низкой пристройки только первый этаж."
		var balcony: bool = detail.kind == "balcony"
		if balcony and (detail.level != 1 or is_wing_wall(detail.side)):
			return "Ставьте балкон на втором этаже основного корпуса."
		var start: Variant = detail.get("t")
		var end: Variant = detail.get("end_t") if detail.kind == "beam" else start
		for fraction in [start, end]:
			if not (fraction is float or fraction is int) or not is_finite(float(fraction)) or fraction < 0.0 or fraction > 1.0:
				return "Деталь фасада выходит за границы стены."
		if detail.kind != "beam" and detail.has("end_t"):
			return "У колонны или балкона должна быть одна точка привязки."
		var wall := edge(detail.side, p)
		var profile := facade_detail_profile(detail, p)
		var clearance: float = profile.half_width + 0.125 if balcony else DETAIL_END_CLEARANCE_M
		if not fits_wall(profile.from, wall, clearance) or not fits_wall(profile.to, wall, clearance):
			return "Оставьте место между деталью и краем стены."
		if detail.kind == "beam" and profile.from.distance_to(profile.to) < 0.25 - 0.00001:
			return "Протяните балку хотя бы на 0,25 м."
		var center: Vector2 = (profile.from + profile.to) * 0.5
		var normal: Vector3 = profile.normal
		var along := Vector2(absf(normal.z), absf(normal.x))
		var normal_2d := Vector2(normal.x, normal.z)
		var offset := center.dot(normal_2d)
		var rect := facade_rect(center.dot(along), profile.half_width, profile.bottom, profile.top)
		for other in placed:
			if (detail.kind == other.kind or balcony or other.kind == "balcony") and normal == other.normal and is_equal_approx(offset, other.offset) and rect.intersects(other.rect):
				return "Детали фасада перекрываются."
		for index in openings.size():
			var opening: Dictionary = openings[index]
			var opening_wall := edge(opening.side, p)
			var opening_position := point(opening, p.width_m, p.depth_m, p)
			if normal != opening_wall.normal or not is_equal_approx(offset, opening_position.dot(normal_2d)):
				continue
			var door := index == openings.size() - 1
			var opening_bottom := 0.25 if door else 0.25 + (int(opening.level) + 0.38) * float(p.floor_height_m)
			var opening_top := 35.0 / 16.0 if door else opening_bottom + 1.0
			var half_width := 0.5 if door else 0.375
			if door and p.get("entry_canopy", false):
				if rect.intersects(facade_rect(opening_position.dot(along), CANOPY_HALF_WIDTH_M, 29.0 / 16.0, 39.0 / 16.0)):
					return "Деталь фасада задевает козырёк над входом."
			if rect.intersects(facade_rect(opening_position.dot(along), half_width, opening_bottom, opening_top)):
				return "Деталь фасада перекрывает окно или вход."
		placed.append({"kind": detail.kind, "normal": normal, "offset": offset, "rect": rect})
	return ""


static func facade_rect(center: float, half_width: float, bottom: float, top: float) -> Rect2:
	return Rect2(center - half_width, bottom, half_width * 2.0, top - bottom)


static func canopy_intersects_house(door: Dictionary, p: Dictionary) -> bool:
	var center := point(door, p.width_m, p.depth_m, p)
	var wall := edge(door.side, p)
	var normal := Vector2(wall.normal.x, wall.normal.z)
	var along := Vector2(normal.y, -normal.x)
	var a := center - along * CANOPY_HALF_WIDTH_M
	var b := center + along * CANOPY_HALF_WIDTH_M + normal * CANOPY_DEPTH_M
	var strip := Rect2(a.min(b), (b - a).abs())
	var core_size := Vector2(p.width_m, p.depth_m)
	if strip.intersects(Rect2(-core_size * 0.5, core_size)):
		return true
	for opposite: bool in [false, true]:
		var enabled := has_opposite_wing(p) if opposite else has_wing(p)
		var owns_door := is_wing_wall(door.side) and (int(door.side) >= 7) == opposite
		if enabled and not owns_door and strip.intersects(wing_rect(p, opposite).grow(float(p.overhang_m))):
			return true
	return false


static func fits_wall(point: Vector2, wall: Dictionary, half_width: float) -> bool:
	var projected := Geometry2D.get_closest_point_to_segment(point, wall.a, wall.b)
	return point.distance_to(projected) <= 0.001 and minf(point.distance_to(wall.a), point.distance_to(wall.b)) + 0.00001 >= half_width


static func nearest(point:Vector2,width:float,depth:float,p:Dictionary={})->Dictionary:
	if p.is_empty():p={"width_m":width,"depth_m":depth}
	var side=0;var distance=INF;var closest=Vector2.ZERO
	for id in wall_ids(p):
		var wall=edge(id,p);var candidate=Geometry2D.get_closest_point_to_segment(point,wall.a,wall.b)
		if point.distance_squared_to(candidate)<distance:side=id;closest=candidate;distance=point.distance_squared_to(candidate)
	var wall=edge(side,p)
	var t: float = wall.a.distance_to(closest)/wall.a.distance_to(wall.b)
	if side == 12:
		side = 1 if wing_turn(p) == 1 else 3
	if side == 2:
		t = closest.x / width + 0.5
	elif side in [1, 3]:
		t = closest.y / depth + 0.5
	return {"side":side,"t":clampf(snappedf(t,0.025),0.12,0.88),"level":0}

static func point(opening:Dictionary,width:float,depth:float,p:Dictionary={})->Vector2:
	if opening.side>=4 and not p.is_empty():
		var wall=edge(opening.side,p)
		return wall.a.lerp(wall.b,float(opening.t))
	match int(opening.side):
		0:return Vector2((float(opening.t)-0.5)*width,-depth/2)
		1:return Vector2(width/2,(float(opening.t)-0.5)*depth)
		2:return Vector2((float(opening.t)-0.5)*width,depth/2)
		_:return Vector2(-width/2,(float(opening.t)-0.5)*depth)
