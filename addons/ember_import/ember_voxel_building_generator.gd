@tool
extends RefCounted
## Exterior massing. One canonical source and the existing convex-part look path.
const Geometry = preload("res://addons/ember_import/ember_voxel_generator_geometry.gd")
const Solid = preload("res://scripts/ember_voxel_solid_surface.gd")
const Layout = preload("res://addons/ember_import/ember_building_layout.gd")
const DENSITY := 16
const MAX_STORAGE_CELLS := 2_097_152
const FLAT_ROOF_THICKNESS := 3
const PARAPET_HEIGHT := 8

static func fields() -> Array[Dictionary]:
	return [
		{"key":"width_m","title":"Ширина, м","min":3.0,"max":6.5,"step":0.25,"type":"float"},
		{"key":"depth_m","title":"Глубина, м","min":3.0,"max":5.5,"step":0.25,"type":"float"},
		{"key":"floors","title":"Этажи","min":1,"max":2},
		{"key":"floor_height_m","title":"Высота этажа, м","min":2.25,"max":3.0,"step":0.25,"type":"float"},
		{"key":"roof_shape","title":"Форма крыши","min":Layout.ROOF_GABLE,"max":Layout.ROOF_PARAPET,"options":["Двускатная","Четырёхскатная","Плоская","Плоская с парапетом"]},
		{"key":"roof_height_m","title":"Высота скатов, м","min":0.75,"max":1.5,"step":0.25,"type":"float"},
		{"key":"overhang_m","title":"Свес крыши, м","min":0.125,"max":0.5,"step":0.125,"type":"float"},
		{"key":"wall_color","title":"Стены","type":"color"},
		{"key":"roof_color","title":"Кровля","type":"color"},
		{"key":"timber_color","title":"Деревянные детали","type":"color"},
		{"key":"facade_style","title":"Оформление фасада","min":0,"max":1,"options":["Штукатурка и балки","Светлая кладка"]},
		{"key":"corner_posts","title":"Декоративные угловые стойки","type":"bool"},
		{"key":"entry_canopy","title":"Козырёк над входом","type":"bool"},
		{"key":"entry_style","title":"Оформление входа","min":0,"max":2,"options":["Деревянная рама","Каменный портал","Каменная арка"]},
		{"key":"window_style","title":"Оформление окон","min":0,"max":2,"options":["Деревянные прямоугольные","Каменные со скосом","Арочные"]},
		{"key":"balcony_width_m","title":"Ширина балконов, м","min":1.0,"max":2.5,"step":0.125,"type":"float"},
		{"key":"balcony_depth_m","title":"Вынос балконов, м","min":0.5,"max":1.0,"step":0.125,"type":"float"},
		{"key":"fence","title":"Ограда с калиткой","type":"bool"},
		{"key":"fence_custom","title":"Свободный контур ограды","type":"bool"},
		{"key":"fence_front_m","title":"Двор спереди, +м","min":0.0,"max":2.0,"step":0.25,"type":"float"},
		{"key":"fence_right_m","title":"Двор справа, +м","min":0.0,"max":2.0,"step":0.25,"type":"float"},
		{"key":"fence_rear_m","title":"Двор сзади, +м","min":0.0,"max":2.0,"step":0.25,"type":"float"},
		{"key":"fence_left_m","title":"Двор слева, +м","min":0.0,"max":2.0,"step":0.25,"type":"float"},
		{"key":"fence_bay_side","title":"Карман ограды","min":0,"max":3,"options":["Нет","Слева","Справа","Сзади"]},
		{"key":"fence_bay_m","title":"Сторона кармана, м","min":1.0,"max":2.0,"step":0.25,"type":"float"},
		{"key":"fence_bay_position","title":"Положение кармана вдоль стены","min":0.2,"max":0.8,"step":0.05,"type":"float"},
		{"key":"fence_style","title":"Оформление ограды","min":0,"max":1,"options":["Деревянная","Низкая каменная"]},
		{"key":"gate_style","title":"Оформление калитки","min":0,"max":2,"options":["Прямая","Со скошенными углами","С арочным верхом"]},
		{"key":"wing_side","title":"Сторона пристройки","min":0,"max":2,"options":["Нет","Справа","Слева"]},
		{"key":"wing_on_side","title":"Крепить к боковой стене","type":"bool"},
		{"key":"wing_roof","title":"Крыша пристройки","min":0,"max":2,"options":["Односкатная низкая","Двускатная","Поперечная с ендовой"]},
		{"key":"wing_width_m","title":"Ширина пристройки, м","min":1.5,"max":3.0,"step":0.25,"type":"float"},
		{"key":"wing_length_m","title":"Длина пристройки, м","min":1.0,"max":3.0,"step":0.25,"type":"float"},
		{"key":"wing_inset_m","title":"Сдвиг пристройки от края, м","min":0.0,"max":5.0,"step":0.25,"type":"float"},
		{"key":"opposite_wing","title":"Второе крыло","type":"bool"},
		{"key":"opposite_roof","title":"Крыша второго крыла","min":0,"max":2,"options":["Односкатная низкая","Двускатная","Поперечная с ендовой"]},
		{"key":"opposite_width_m","title":"Ширина второго крыла, м","min":1.5,"max":3.0,"step":0.25,"type":"float"},
		{"key":"opposite_length_m","title":"Длина второго крыла, м","min":1.0,"max":3.0,"step":0.25,"type":"float"},
		{"key":"opposite_inset_m","title":"Сдвиг второго крыла от края, м","min":0.0,"max":5.0,"step":0.25,"type":"float"},
	]

static func normalize(parameters: Dictionary) -> Dictionary:
	var result := {"width_m":4.5,"depth_m":3.5,"floors":1,"floor_height_m":2.75,"roof_shape":Layout.ROOF_GABLE,"roof_height_m":1.25,"overhang_m":0.25,
		"wall_color":Color("e2d2ac"),"roof_color":Color("775247"),"timber_color":Color("4c4035"),"density":DENSITY,"facade_style":0,"corner_posts":true,"fence":false,"fence_style":0,"gate_style":0,"wing_side":0,"wing_roof":0,"wing_width_m":2.0,"wing_length_m":2.0,
		"wing_inset_m":0.0,"wing_on_side":false,"opposite_wing":false,"opposite_roof":1,"opposite_width_m":1.5,"opposite_length_m":2.0,"opposite_inset_m":0.0,"entry_canopy":false,"entry_style":0,"window_style":0,
		"balcony_width_m":Layout.BALCONY_HALF_WIDTH_M * 2.0,"balcony_depth_m":Layout.BALCONY_DEPTH_M,
		"fence_custom":false,"fence_front_m":0.0,"fence_right_m":0.0,"fence_rear_m":0.0,"fence_left_m":0.0,
		"fence_bay_side":0,"fence_bay_m":1.5,"fence_bay_position":0.5}
	for field in fields():
		var value: Variant = parameters.get(field.key,result[field.key])
		if field.get("type","")=="color":
			if value is Color and is_finite(value.r) and is_finite(value.g) and is_finite(value.b): result[field.key]=Color(value,1.0)
		elif field.get("type","")=="bool":result[field.key]=value if value is bool else false
		elif (value is float or value is int) and is_finite(float(value)):
			var step: float = field.get("step",1.0)
			var number: float = clampf(snappedf(float(value),step),field.min,field.max)
			result[field.key]=number if field.get("type","")=="float" else int(number)
	var wall_span := float(result.depth_m if result.wing_on_side else result.width_m)
	result.wing_width_m = minf(result.wing_width_m, maxf(1.5, wall_span - 1.0))
	result.opposite_width_m = minf(result.opposite_width_m, result.width_m - 1.0)
	var corner: Variant = parameters.get("fixed_corner")
	if corner is Vector2 and corner.is_finite() and maxf(absf(corner.x), absf(corner.y)) <= 5.0:
		result.fixed_corner = corner
	return result

static func build(parameters: Dictionary, _seed: int, _color: Color, material: Dictionary, title: String, model_id: String,structure:Dictionary={}) -> Dictionary:
	var settings := normalize(parameters)
	var layout_errors:=Layout.errors(structure,settings)
	if not layout_errors.is_empty():return {"error":layout_errors[0]}
	var width := roundi(settings.width_m*DENSITY); var depth := roundi(settings.depth_m*DENSITY)
	var span := Layout.bounds(settings).size * DENSITY
	var floor_height := roundi(settings.floor_height_m*DENSITY)
	var eave := 4 + floor_height*int(settings.floors)
	var roof_height := roundi(settings.roof_height_m*DENSITY); var overhang := roundi(settings.overhang_m*DENSITY)
	var margin := maxi(overhang+2,16 if settings.fence else 0)
	if settings.entry_canopy:
		margin = maxi(margin, ceili(Layout.CANOPY_DEPTH_M * DENSITY) + 1)
	for detail: Dictionary in structure.get("facade_details", []):
		if detail.kind == "balcony":
			margin = maxi(margin, ceili(settings.balcony_depth_m * DENSITY) + 1)
			break
	var height := eave+roof_height+3
	if settings.roof_shape >= Layout.ROOF_FLAT:
		height = eave + FLAT_ROOF_THICKNESS
		if settings.roof_shape == Layout.ROOF_PARAPET:
			height += PARAPET_HEIGHT
	var needed: Vector2 = span + Vector2.ONE * margin * 2.0
	var grid_center_shift := Vector2.ZERO
	var yard := {}
	if settings.fence and settings.fence_custom:
		yard = Layout.fence_plan(settings, structure.get("door", {"side": 0, "t": 0.5}))
		if yard.has("error"):
			return yard
		var extent: Rect2 = yard.bounds.grow(0.125)
		var offset := Layout.model_offset(settings)
		var lo := (-needed * 0.5).min((extent.position + offset) * DENSITY)
		var hi := (needed * 0.5).max((extent.end + offset) * DENSITY)
		grid_center_shift = ((lo + hi) * 0.5).round()
		needed = (hi - grid_center_shift).max(grid_center_shift - lo) * 2.0
	var grid := Vector3i(ceili(needed.x / DENSITY) * DENSITY, height, ceili(needed.y / DENSITY) * DENSITY)
	if grid.x*grid.y*grid.z>MAX_STORAGE_CELLS:
		if not yard.is_empty():
			return {"error":"Участок превышает бюджет сетки. Уменьшите отступы ограды, карман или размер дома."}
		return {"error":"Дом превышает бюджет сетки. Уменьшите ширину, глубину или высоту."}
	var source := EmberVoxelModelResource.new()
	source.model_id=model_id; source.display_name=title; source.voxels_per_block=DENSITY
	source.size_blocks=Vector3i(grid.x/DENSITY,ceili(float(height)/DENSITY),grid.z/DENSITY); source.height_voxels=height
	source.tags=PackedStringArray(["generated","building","coastal_house","godot-native"])
	source.material=material.duplicate(true)
	source.palette=PackedColorArray([Color.TRANSPARENT,settings.wall_color,settings.roof_color,settings.timber_color,Color("727570"),Color("779a9b")])
	if settings.facade_style==1:source.palette[1]=settings.wall_color.darkened(.08);source.palette[3]=Color("a99d88")
	source.voxels.resize(grid.x*grid.y*grid.z); source.voxel_part_ids.resize(source.voxels.size())
	var origin := Layout.model_offset(settings) * DENSITY + Vector2(grid.x, grid.z) * 0.5 - grid_center_shift
	var x0 := origin.x - width * 0.5
	var z0 := origin.y - depth * 0.5
	var x1 := x0+width; var z1 := z0+depth
	var slope := float(roof_height)/(width*0.5)
	var parts: Array[Dictionary]=[]
	box(parts,Vector3(x0-1,0,z0-1),Vector3(x1+1,4,z1+1),4,"Каменное основание")
	append_main_roof(parts, settings, Rect2(x0, z0, width, depth), eave, roof_height, slope, overhang)
	if settings.corner_posts:
		for x in [x0,x1-2]:
			for z in [z0,z1-2]: box(parts,Vector3(x-1,4,z-1),Vector3(x+3,eave,z+3),3,"Угловая стойка")
	for level in range(1,int(settings.floors)+1):
		var y := 4+level*floor_height-2
		box(parts,Vector3(x0-1,y,z0-1),Vector3(x1+1,y+2,z1+1),3,"Пояс фасада %d"%level)
	if Layout.has_wing(settings) and not Layout.has_cross_gable(settings):
		if Layout.wing_turn(settings) != 0:
			append_side_wing(parts, settings, origin)
		else:
			append_wing(parts, settings, Vector2(x0, z1), eave, slope, overhang, false)
	if Layout.has_opposite_wing(settings) and not Layout.has_cross_gable(settings, true):
		append_wing(parts, settings, Vector2(x0, z1), eave, slope, overhang, true)
	if structure.is_empty():
		legacy_openings(parts,settings,x0,x1,z0,z1,floor_height,(x0+x1)*0.5,origin)
	else:
		for window:Dictionary in structure.windows:
			var y:=4+int(window.level)*floor_height+floor_height*.38
			if int(settings.window_style) == 0:
				layout_facade_box(parts,window,settings,origin,y,6,16,3,"Рама окна")
				layout_facade_box(parts,window,settings,origin,y+2,4,12,5,"Стекло окна",-1)
			else:
				append_styled_window(parts, settings, window, origin, y)
		if int(settings.entry_style) == 0:
			layout_facade_box(parts,structure.door,settings,origin,4,8,31,3,"Дверная рама")
			layout_facade_box(parts,structure.door,settings,origin,4,6,29,3,"Дверь · внешний объём",-1)
	if int(settings.entry_style) != 0:
		var door: Dictionary = structure.get("door", {"side": 0, "t": 0.5})
		append_styled_entry(parts, settings, door, origin)
	if settings.entry_canopy:
		var door: Dictionary = structure.get("door", {"side": 0, "t": 0.5})
		append_entry_canopy(parts, settings, door, origin)
	if settings.fence:
		var door:Dictionary=structure.get("door",{"side":0,"t":0.5})
		var normal:Vector3=Layout.edge(door.side,settings).normal
		var side=[Vector3.FORWARD,Vector3.RIGHT,Vector3.BACK,Vector3.LEFT].find(normal)
		var point=Layout.point(door,settings.width_m,settings.depth_m,settings)*DENSITY+Vector2(grid.x,grid.z)*.5+Layout.model_offset(settings)*DENSITY
		# Recipes saved before gate styles must reproduce their original Source
		# for the editor's manual-change check. The editor normalizes new drafts.
		var gate_style := int(settings.gate_style) if parameters.has("gate_style") else -1
		if yard.is_empty():
			fence_parts(parts, grid, side, point, int(settings.fence_style), gate_style)
		else:
			append_yard(parts, yard, origin, int(settings.fence_style), int(settings.gate_style))
	for detail: Dictionary in structure.get("facade_details", []):
		append_facade_detail(parts, settings, detail, origin)
	if parts.size()>Layout.PART_LIMIT:return {"error":"Слишком много деталей: уменьшите количество окон или выключите ограду."}
	var guides: Array[PackedVector3Array]=[]
	for part in parts:
		var directions:=PackedVector3Array()
		for plane: Plane in part.planes: directions.append(plane.normal)
		guides.append(directions); source.merge_parts.append(part.title)
		paint(source,grid,part,source.merge_parts.size())
	var roles:=PackedStringArray();var ids:=PackedStringArray();roles.resize(source.palette.size());ids.resize(source.palette.size())
	source.solid_surface={"version":1,"parts":guides,"occupancy":Solid.occupancy_hash(source.voxels),"roles":roles,"material_ids":ids}
	var placement := Layout.placement_offset(settings) + Vector3(grid_center_shift.x, 0, grid_center_shift.y) / DENSITY
	if placement != Vector3.ZERO:
		source.solid_surface["building_offset"] = placement
	if not structure.is_empty():
		var location=(Layout.point(structure.door,settings.width_m,settings.depth_m,settings)+Layout.model_offset(settings))*DENSITY
		location += Vector2(grid.x, grid.z) * 0.5 - grid_center_shift
		var normal:Vector3=Layout.edge(structure.door.side,settings).normal
		source.solid_surface["building_entry"]={"point":Vector3(location.x,20,location.y)+normal*4,"normal":normal}
	var errors:=source.validation_errors()
	if not errors.is_empty():return {"error":errors[0]}
	return {"geometry":source,"parameters":settings,"structure":structure.duplicate(true)}

static func append_main_roof(parts: Array[Dictionary], settings: Dictionary, wall: Rect2, eave: float, rise: float, pitch: float, overhang: float) -> void:
	var shape: int = settings.roof_shape
	var side_turn := Layout.wing_turn(settings)
	if shape != Layout.ROOF_GABLE:
		box(parts, Vector3(wall.position.x, 4, wall.position.y), Vector3(wall.end.x, eave, wall.end.y), 1, "Стены")
		var outline := wall.grow(overhang)
		if shape == Layout.ROOF_HIP:
			if int(settings.floors) == 1 and Layout.has_wing(settings):
				# Stop the sloping overhang at the wall above a low wing.
				if side_turn == -1:
					outline.position.x = wall.position.x
					outline.size.x -= overhang
				elif side_turn == 1:
					outline.size.x -= overhang
				else:
					outline.size.y -= overhang
			hip_roof(parts, wall, outline, eave, rise, overhang)
		else:
			flat_roof(parts, outline, eave, shape == Layout.ROOF_PARAPET)
		return

	gable_wall(parts, wall, eave, rise, pitch, "Стены и фронтоны")
	var joined_gable := Layout.has_gabled_wing(settings) or Layout.has_gabled_wing(settings, true)
	var rear_edge := wall.end.y if joined_gable else wall.end.y + overhang
	var roof_start := parts.size()
	gable_roof(parts, Vector2(wall.position.x, wall.end.x), Vector2(wall.position.y - overhang, rear_edge), eave, rise, pitch, overhang, "Скат крыши")
	if side_turn != 0 and int(settings.floors) == 1:
		var right := side_turn == 1
		parts[roof_start + int(right)].planes.append(Plane(Vector3.RIGHT if right else Vector3.LEFT, wall.end.x if right else -wall.position.x))
	for opposite: bool in [false, true]:
		if Layout.has_cross_gable(settings, opposite):
			var wing := wing_footprint(settings, Vector2(wall.position.x, wall.end.y), opposite)
			var right := (int(settings.wing_side) == 1) != opposite
			var wing_rise := minf(rise * 0.75, pitch * wing.size.x * 0.8)
			append_cross_gable(parts, roof_start + int(right), wing, eave, pitch, wing_rise, wall.position.y - overhang, overhang, right)


static func hip_roof(parts: Array[Dictionary], wall: Rect2, outline: Rect2, eave: float, rise: float, overhang: float) -> void:
	var pitch := Vector2(2.0 * rise / wall.size.x, 2.0 * rise / wall.size.y)
	var bottom := floorf(eave - maxf(pitch.x, pitch.y) * overhang)
	var crown := eave + rise + 3.0
	var center := wall.get_center()
	var roof := bounds_planes(Vector3(outline.position.x, bottom, outline.position.y), Vector3(outline.end.x, crown, outline.end.y))
	for direction: float in [-1.0, 1.0]:
		roof.append(Plane(Vector3(direction * pitch.x, 1, 0), crown + direction * pitch.x * center.x).normalized())
		roof.append(Plane(Vector3(0, 1, direction * pitch.y), crown + direction * pitch.y * center.y).normalized())
	parts.append({"planes": roof, "slot": 2, "title": "Четырёхскатная кровля"})


static func flat_roof(parts: Array[Dictionary], outline: Rect2, eave: float, parapet: bool) -> void:
	var left := outline.position.x
	var right := outline.end.x
	var front := outline.position.y
	var rear := outline.end.y
	var deck := eave + FLAT_ROOF_THICKNESS
	box(parts, Vector3(left, eave, front), Vector3(right, deck, rear), 2, "Плоская кровля")
	if not parapet:
		return
	var top := deck + PARAPET_HEIGHT
	box(parts, Vector3(left + 1, deck, front + 1), Vector3(right - 1, top, front + 3), 4, "Парапет · передний")
	box(parts, Vector3(left + 1, deck, rear - 3), Vector3(right - 1, top, rear - 1), 4, "Парапет · задний")
	box(parts, Vector3(left + 1, deck, front + 3), Vector3(left + 3, top, rear - 3), 4, "Парапет · левый")
	box(parts, Vector3(right - 3, deck, front + 3), Vector3(right - 1, top, rear - 3), 4, "Парапет · правый")


static func gable_wall(parts: Array[Dictionary], footprint: Rect2, eave: float, rise: float, pitch: float, title: String) -> void:
	var left := footprint.position.x
	var right := footprint.end.x
	var wall := bounds_planes(Vector3(left, 4, footprint.position.y), Vector3(right, eave + rise, footprint.end.y))
	var normal_length := sqrt(1.0 + pitch * pitch)
	wall.append(Plane(Vector3(-pitch, 1, 0).normalized(), (eave - pitch * left) / normal_length))
	wall.append(Plane(Vector3(pitch, 1, 0).normalized(), (eave + pitch * right) / normal_length))
	parts.append({"planes": wall, "slot": 1, "title": title})


static func gable_roof(parts: Array[Dictionary], wall_x: Vector2, roof_z: Vector2, eave: float, rise: float, pitch: float, overhang: float, title: String) -> void:
	var ridge_x := (wall_x.x + wall_x.y) * 0.5
	for side in 2:
		var left := wall_x.x - overhang if side == 0 else ridge_x
		var right := ridge_x if side == 0 else wall_x.y + overhang
		var gradient := pitch if side == 0 else -pitch
		var intercept := eave - gradient * wall_x[side] + 3.0
		var roof := bounds_planes(
			Vector3(left, eave - pitch * overhang - 1, roof_z.x),
			Vector3(right, eave + rise + 3, roof_z.y)
		)
		var normal := Vector3(-gradient, 1, 0).normalized()
		var normal_length := sqrt(1.0 + gradient * gradient)
		roof.append(Plane(normal, intercept / normal_length))
		roof.append(Plane(-normal, (-intercept + 3) / normal_length))
		parts.append({"planes": roof, "slot": 2, "title": "%s %d" % [title, side + 1]})


static func gabled_wing_parts(parts: Array[Dictionary], footprint: Rect2, eave: float, pitch: float, overhang: float) -> void:
	var left := footprint.position.x
	var right := footprint.end.x
	var front := footprint.position.y
	var rear := footprint.end.y
	var rise := footprint.size.x * 0.5 * pitch
	box(parts, Vector3(left - 1, 0, front), Vector3(right + 1, 4, rear + 1), 4, "Крыло · основание")
	gable_wall(parts, footprint, eave, rise, pitch, "Крыло · стены и фронтон")
	gable_roof(parts, Vector2(left, right), Vector2(front, rear + overhang), eave, rise, pitch, overhang, "Крыло · скат")
	box(parts, Vector3(left - 1, eave - 2, rear - 1), Vector3(right + 1, eave, rear + 1), 3, "Крыло · пояс фронтона")


static func wing_footprint(settings: Dictionary, rear_left: Vector2, opposite: bool) -> Rect2:
	var wing := Layout.wing_rect(settings, opposite)
	var x := rear_left.x + (wing.position.x + float(settings.width_m) * 0.5) * DENSITY
	return Rect2(Vector2(x, rear_left.y), wing.size * DENSITY)


static func append_wing(parts: Array[Dictionary], settings: Dictionary, rear_left: Vector2, eave: float, pitch: float, overhang: float, opposite: bool) -> void:
	var footprint := wing_footprint(settings, rear_left, opposite)
	if Layout.has_gabled_wing(settings, opposite):
		gabled_wing_parts(parts, footprint, eave, pitch, overhang)
	else:
		var right := (int(settings.wing_side) == 1) != opposite
		wing_parts(parts, settings, footprint, right)


static func append_side_wing(parts: Array[Dictionary], settings: Dictionary, origin: Vector2) -> void:
	var local := Layout.wing_plan(settings)
	var rect := Layout.wing_rect(local)
	var start := parts.size()
	wing_parts(parts, local, Rect2(rect.position * DENSITY, rect.size * DENSITY), int(local.wing_side) == 1)
	place_horizontal_parts(parts, start, origin, Layout.wing_turn(settings))


static func append_entry_canopy(parts: Array[Dictionary], settings: Dictionary, door: Dictionary, origin: Vector2) -> void:
	var start := parts.size()
	var half_width := Layout.CANOPY_HALF_WIDTH_M * DENSITY
	var depth := Layout.CANOPY_DEPTH_M * DENSITY
	var pitch := 0.25
	var roof := bounds_planes(Vector3(-half_width, 33, -1), Vector3(half_width, 39, depth))
	roof.append(Plane(Vector3(0, 1, pitch), 38.5).normalized())
	roof.append(Plane(Vector3(0, -1, -pitch), -36.0).normalized())
	parts.append({"planes": roof, "slot": 2, "title": "Вход · кровля козырька"})
	for x: float in [-7.0, 7.0]:
		var bracket := bounds_planes(Vector3(x - 1, 29, -1), Vector3(x + 1, 37, 7))
		bracket.append(Plane(Vector3(0, 1, pitch), 36.0).normalized())
		bracket.append(Plane(Vector3(0, -1, 0.625), -29.0).normalized())
		parts.append({"planes": bracket, "slot": 3, "title": "Вход · деревянный раскос"})
	place_opening_parts(parts, start, settings, door, origin)


static func append_styled_entry(parts: Array[Dictionary], settings: Dictionary, door: Dictionary, origin: Vector2) -> void:
	var start := parts.size()
	var frame := bounds_planes(Vector3(-8, 4, -1), Vector3(8, 35, 3))
	var panel := bounds_planes(Vector3(-6, 4, 2), Vector3(6, 33, 4))
	var arched := int(settings.entry_style) == 2
	if arched:
		append_arch_planes(frame, 26.0, 8.0, 9.0)
		append_arch_planes(panel, 26.0, 6.0, 7.0)
	else:
		for direction: float in [-1.0, 1.0]:
			frame.append(Plane(Vector3(direction, 0, 1), 9.5).normalized())
	parts.append({"planes": frame, "slot": 4, "title": "Вход · каменная арка" if arched else "Вход · каменный портал"})
	parts.append({"planes": panel, "slot": 3, "title": "Дверь · внешний объём"})
	place_opening_parts(parts, start, settings, door, origin)


static func place_opening_parts(parts: Array[Dictionary], start: int, settings: Dictionary, opening: Dictionary, origin: Vector2) -> void:
	var normal: Vector3 = Layout.edge(opening.side, settings).normal
	var center := Layout.point(opening, settings.width_m, settings.depth_m, settings)
	place_horizontal_parts(parts, start, origin + center * DENSITY, facade_turn(normal))


static func append_facade_detail(parts: Array[Dictionary], settings: Dictionary, detail: Dictionary, origin: Vector2) -> void:
	var start := parts.size()
	var profile := Layout.facade_detail_profile(detail, settings)
	var center: Vector2 = (profile.from + profile.to) * 0.5
	if detail.kind == "balcony":
		append_balcony(parts, profile.bottom * DENSITY, profile.half_width * DENSITY, profile.depth * DENSITY)
	else:
		var half_width: float = profile.half_width * DENSITY
		var title := "Фасад · балка" if detail.kind == "beam" else "Фасад · колонна"
		box(parts, Vector3(-half_width, profile.bottom * DENSITY, -1), Vector3(half_width, profile.top * DENSITY, 3), 3, title)
	place_horizontal_parts(parts, start, origin + center * DENSITY, facade_turn(profile.normal))


static func append_balcony(parts: Array[Dictionary], bottom: float, half_width: float, depth: float) -> void:
	var deck := bottom + Layout.BALCONY_DECK_M * DENSITY
	var rail := deck + 12.0
	box(parts, Vector3(-half_width, bottom, -1), Vector3(half_width, deck, depth), 4, "Балкон · плита")
	box(parts, Vector3(-half_width, deck, depth - 2), Vector3(half_width, rail, depth), 3, "Балкон · передний борт")
	box(parts, Vector3(-half_width, deck, 0), Vector3(-half_width + 2, rail, depth - 2), 3, "Балкон · левый борт")
	box(parts, Vector3(half_width - 2, deck, 0), Vector3(half_width, rail, depth - 2), 3, "Балкон · правый борт")
	box(parts, Vector3(-6, deck, -1), Vector3(6, deck + Layout.BALCONY_DOOR_M * DENSITY, 2), 5, "Балкон · остекление")


static func facade_turn(normal: Vector3) -> int:
	match normal:
		Vector3.RIGHT: return 1
		Vector3.FORWARD: return 2
		Vector3.LEFT: return -1
		_: return 0


static func append_styled_window(parts: Array[Dictionary], settings: Dictionary, window: Dictionary, origin: Vector2, y: float) -> void:
	var start := parts.size()
	var frame := bounds_planes(Vector3(-6, y, -1), Vector3(6, y + 16, 3))
	var glass := bounds_planes(Vector3(-4, y + 2, 2), Vector3(4, y + 14, 4))
	var stone := int(settings.window_style) == 1
	if stone:
		# Chamfer the outer front edges without changing the wall footprint.
		for direction: float in [-1.0, 1.0]:
			frame.append(Plane(Vector3(direction, 0, 1), 7.0).normalized())
	else:
		append_arch_planes(frame, y + 8, 6.0, 8.0)
		append_arch_planes(glass, y + 8, 4.0, 6.0)
	parts.append({"planes": frame, "slot": 4 if stone else 3, "title": "Каменная рама" if stone else "Арочная рама"})
	parts.append({"planes": glass, "slot": 5, "title": "Стекло окна"})
	place_opening_parts(parts, start, settings, window, origin)


static func append_arch_planes(planes: Array[Plane], spring_y: float, half_width: float, rise: float) -> void:
	# Both profiles spring at the same height. Tangents keep each piece convex.
	for direction: float in [-1.0, 1.0]:
		for degrees: float in [30.0, 55.0, 75.0]:
			var angle := deg_to_rad(degrees)
			var normal := Vector3(direction * cos(angle) / half_width, sin(angle) / rise, 0.0)
			planes.append(Plane(normal, 1.0 + spring_y * normal.y).normalized())


static func place_horizontal_parts(parts: Array[Dictionary], start: int, origin: Vector2, turn: int) -> void:
	for index in range(start, parts.size()):
		var planes: Array[Plane] = parts[index].planes
		var a := Layout.turn_point(Vector2(-planes[1].d, -planes[5].d), turn) + origin
		var b := Layout.turn_point(Vector2(planes[0].d, planes[4].d), turn) + origin
		# The fill helper reads its first six planes as ordered grid bounds.
		var rotated_planes := bounds_planes(
			Vector3(minf(a.x, b.x), -planes[3].d, minf(a.y, b.y)),
			Vector3(maxf(a.x, b.x), planes[2].d, maxf(a.y, b.y))
		)
		for plane_index in range(6, planes.size()):
			var plane := planes[plane_index]
			var rotated := Layout.turn_point(Vector2(plane.normal.x, plane.normal.z), turn)
			rotated_planes.append(Plane(Vector3(rotated.x, plane.normal.y, rotated.y), plane.d + rotated.dot(origin)))
		parts[index].planes = rotated_planes


static func append_cross_gable(parts: Array[Dictionary], main_roof_index: int, wing: Rect2, eave: float, main_pitch: float, rise: float, main_front: float, overhang: float, right: bool) -> void:
	var seam := wing.position.y
	var ridge := seam + wing.size.y * 0.25
	var pitch := rise / (wing.end.y - ridge)
	var front_eave := seam - wing.size.y * 0.5
	var front_intercept := eave - pitch * front_eave
	var back_intercept := eave + pitch * wing.end.y
	var main_gradient := -main_pitch if right else main_pitch
	var outer_x := wing.end.x if right else wing.position.x
	var main_intercept := eave - main_gradient * outer_x
	# Equal-height line of the two slope planes, extruded vertically. The
	# complementary cuts meet on this line, including the slab thickness.
	var valley := Plane(Vector3(-main_gradient, 0, pitch), main_intercept - front_intercept).normalized()
	parts[main_roof_index].planes.append(valley)

	var front_ceiling := Plane(Vector3(0, 1, -pitch), front_intercept).normalized()
	var back_ceiling := Plane(Vector3(0, 1, pitch), back_intercept).normalized()
	var main_ceiling := Plane(Vector3(-main_gradient, 1, 0), main_intercept).normalized()
	var left := wing.position.x
	var right_edge := wing.end.x
	var rear := wing.end.y
	box(parts, Vector3(left - 1, 0, seam), Vector3(right_edge + 1, 4, rear + 1), 4, "Поперечное крыло · основание")
	var wall := bounds_planes(Vector3(left, 4, seam), Vector3(right_edge, eave + rise, rear))
	wall.append(front_ceiling)
	wall.append(back_ceiling)
	parts.append({"planes": wall, "slot": 1, "title": "Поперечное крыло · стены и фронтоны"})

	var junction := bounds_planes(Vector3(left, 4, main_front), Vector3(right_edge, eave + rise, seam))
	junction.append(front_ceiling)
	junction.append(-main_ceiling)
	parts.append({"planes": junction, "slot": 1, "title": "Поперечное крыло · заполнение под ендовой"})

	for span in [Vector2(main_front, seam), Vector2(seam, ridge), Vector2(ridge, rear + overhang)]:
		var ceiling := back_ceiling if span.x == ridge else front_ceiling
		var roof := bounds_planes(
			Vector3(left - overhang, eave - pitch * overhang - main_pitch * overhang - 1, span.x),
			Vector3(right_edge + overhang, eave + rise + 3, span.y)
		)
		var top := ceiling
		top.d += ceiling.normal.y * 3.0
		roof.append(top)
		roof.append(-ceiling)
		if span.x == main_front:
			roof.append(-valley)
		parts.append({"planes": roof, "slot": 2, "title": "Поперечное крыло · скат"})


static func wing_parts(parts:Array[Dictionary],settings:Dictionary,footprint:Rect2,right:bool)->void:
	var width := footprint.size.x
	var length_m := footprint.size.y
	var x := footprint.position.x
	var z := footprint.position.y
	var z2 := footprint.end.y
	var heights=Layout.wing_heights(settings)*DENSITY
	var slope=(heights.y-heights.x)/length_m
	var roof_normal=Vector3(0,1,-slope).normalized()
	var intercept=heights.x-slope*z
	box(parts,Vector3(x-1,0,z),Vector3(x+width+1,4,z2+1),4,"Пристройка · основание")
	var wall=bounds_planes(Vector3(x,4,z),Vector3(x+width,heights.x-2,z2))
	wall.append(Plane(roof_normal,(intercept-2)/sqrt(1+slope*slope)))
	parts.append({"planes":wall,"slot":1,"title":"Пристройка · стены"})
	# The outer long edge stays under the main roof's overhang. The lean-to
	# meets the rear facade below its fascia; the two roof slabs never intersect.
	var overhang=float(settings.overhang_m)*DENSITY
	var roof=bounds_planes(Vector3(x-overhang if right else x,heights.y-absf(slope)*overhang-2,z),Vector3(x+width if right else x+width+overhang,heights.x,z2+overhang))
	roof.append(Plane(roof_normal,intercept/sqrt(1+slope*slope)))
	roof.append(Plane(-roof_normal,(-intercept+2)/sqrt(1+slope*slope)))
	parts.append({"planes":roof,"slot":2,"title":"Пристройка · примыкающий скат"})
	if settings.corner_posts:
		for at_x in [x,x+width-2]:box(parts,Vector3(at_x-1,4,z2-2),Vector3(at_x+3,heights.y-2,z2+2),3,"Пристройка · задняя стойка")

static func layout_facade_box(parts:Array[Dictionary],opening:Dictionary,p:Dictionary,origin:Vector2,y:float,half_width:float,height:float,slot:int,title:String,offset:=0.0)->void:
	if int(opening.side)<4:
		var x0=origin.x-roundi(p.width_m*DENSITY)*0.5
		var z0=origin.y-roundi(p.depth_m*DENSITY)*0.5
		facade_box(parts,opening,Vector3(x0,y,z0),Vector3(x0+p.width_m*DENSITY,y+height,z0+p.depth_m*DENSITY),half_width,height,slot,title,offset)
		return
	var point=Layout.point(opening,p.width_m,p.depth_m,p)*DENSITY+origin
	var normal:Vector3=Layout.edge(opening.side,p).normal
	var side=[Vector3.FORWARD,Vector3.RIGHT,Vector3.BACK,Vector3.LEFT].find(normal)
	var lo=Vector3(point.x-half_width if normal.z!=0 else point.x,y,point.y-half_width if normal.x!=0 else point.y)
	var hi=Vector3(point.x+half_width if normal.z!=0 else point.x,y+height,point.y+half_width if normal.x!=0 else point.y)
	facade_box(parts,{"side":side,"t":0.5},lo,hi,half_width,height,slot,title,offset)

static func facade_box(parts:Array[Dictionary],opening:Dictionary,lo:Vector3,hi:Vector3,half_width:float,height:float,slot:int,title:String,offset:=0.0)->void:
	var side=int(opening.side);var t=float(opening.t)
	if side in [0,2]:
		var x=lerpf(lo.x,hi.x,t);var z=lo.z-2+offset if side==0 else hi.z-1-offset
		box(parts,Vector3(x-half_width,lo.y,z),Vector3(x+half_width,lo.y+height,z+3),slot,title)
	else:
		var z=lerpf(lo.z,hi.z,t);var x=lo.x-2+offset if side==3 else hi.x-1-offset
		box(parts,Vector3(x,lo.y,z-half_width),Vector3(x+3,lo.y+height,z+half_width),slot,title)

static func fence_parts(parts: Array[Dictionary], grid: Vector3i, gate_side: int, door_point: Vector2, fence_style: int, gate_style: int) -> void:
	var stone := fence_style == 1
	var height := 10.0 if stone else 16.0
	var slot := 4 if stone else 3
	for side in 4:
		var along_x := side in [0, 2]
		var start := Vector3(1, 0, 1 if side == 0 else grid.z - 3) if along_x else Vector3(1 if side == 3 else grid.x - 3, 0, 1)
		var direction := Vector3.RIGHT if along_x else Vector3.BACK
		var length := float(grid.x - 2 if along_x else grid.z - 2)
		var section := Vector3(0, height, 2) if along_x else Vector3(2, height, 0)
		if side != gate_side:
			box(parts, start, start + direction * length + section, slot, "Ограда · стена %d" % side)
			continue
		var center := clampf((door_point.x if along_x else door_point.y) - 1, 11, length - 11)
		var hinge := start + direction * (center - 10)
		box(parts, start, hinge + section, slot, "Ограда · у входа слева")
		box(parts, start + direction * (center + 10), start + direction * length + section, slot, "Ограда · у входа справа")
		append_gate(parts, hinge, side, gate_style)


static func append_yard(parts: Array[Dictionary], yard: Dictionary, origin: Vector2, fence_style: int, gate_style: int) -> void:
	var stone := fence_style == 1
	var height := 10.0 if stone else 16.0
	var slot := 4 if stone else 3
	for segment: Dictionary in yard.segments:
		var a: Vector2 = origin + segment.from * DENSITY
		var b: Vector2 = origin + segment.to * DENSITY
		var lo := a.min(b) - Vector2.ONE
		var hi := a.max(b) + Vector2.ONE
		box(parts, Vector3(lo.x, 0, lo.y), Vector3(hi.x, height, hi.y), slot, "Ограда · секция")
	var hinge: Vector2 = origin + yard.hinge * DENSITY
	append_gate(parts, Vector3(hinge.x, 0, hinge.y), yard.gate_side, gate_style)


static func append_gate(parts: Array[Dictionary], hinge: Vector3, side: int, style: int) -> void:
	if style < 0:
		var old_angle := (0.0 if side in [0, 2] else -PI / 2) + (-PI / 3 if side in [0, 1] else PI / 3)
		var old_frame := Transform3D(Basis(Vector3.UP, old_angle), hinge + Vector3.UP)
		var old_planes := bounds_planes(Vector3.ZERO, Vector3(18, 14, 2))
		for index in old_planes.size():
			old_planes[index] = old_frame * old_planes[index]
		parts.append({"planes": old_planes, "slot": 3, "title": "Калитка · открыта"})
		return
	var lo := Vector3(-9, 0, 0)
	var hi := Vector3(9, 14, 2)
	var planes := bounds_planes(lo, hi)
	if style == 1:
		for direction: float in [-1.0, 1.0]:
			planes.append(Plane(Vector3(direction, 1, 0), 19.0).normalized())
	elif style == 2:
		append_arch_planes(planes, 8.0, 9.0, 6.0)
	# The same open leaf and hinge for every style. Its tip stays off the central walking line.
	var swing := deg_to_rad(78.0) * (-1.0 if side in [0, 1] else 1.0)
	var basis := Basis(Vector3.UP, swing + (0.0 if side in [0, 2] else -PI / 2))
	var frame := Transform3D(basis, hinge + Vector3.UP + basis * Vector3(9, 0, 0))
	for index in planes.size():
		planes[index] = frame * planes[index]
	parts.append({"planes": planes, "paint_bounds": frame * AABB(lo, hi - lo), "slot": 3, "title": "Калитка · открыта"})

static func legacy_openings(parts:Array[Dictionary],settings:Dictionary,x0:float,x1:float,z0:float,z1:float,floor_height:int,middle:float,origin:Vector2)->void:
	if int(settings.window_style) != 0:
		for window: Dictionary in Layout.defaults(int(settings.floors)).windows:
			var y := 4.0 + int(window.level) * floor_height + floor_height * 0.38
			append_styled_window(parts, settings, window, origin, y)
		if int(settings.entry_style) == 0:
			legacy_door(parts, middle, z0)
		return
	for level in int(settings.floors):
		var y := 4+level*floor_height+floor_height*0.38
		for fraction in [0.23,0.77]:
			var x := lerpf(x0,x1,fraction)
			box(parts,Vector3(x-6,y,z0-2),Vector3(x+6,y+16,z0+1),3,"Рама окна")
			box(parts,Vector3(x-4,y+2,z0-3),Vector3(x+4,y+14,z0-1),5,"Стекло окна")
		for side in 2:
			var x := x0-2 if side==0 else x1-1
			var z := (z0+z1)*0.5
			box(parts,Vector3(x,y,z-6),Vector3(x+3,y+16,z+6),3,"Боковая рама")
			box(parts,Vector3(x-1 if side==0 else x+2,y+2,z-4),Vector3(x+1 if side==0 else x+4,y+14,z+4),5,"Боковое стекло")
	if int(settings.entry_style) == 0:
		legacy_door(parts, middle, z0)


static func legacy_door(parts: Array[Dictionary], middle: float, z0: float) -> void:
	box(parts,Vector3(middle-8,4,z0-3),Vector3(middle+8,35,z0+1),3,"Дверная рама")
	box(parts,Vector3(middle-6,4,z0-4),Vector3(middle+6,33,z0-2),3,"Дверь · внешний объём")

static func bounds_planes(lo: Vector3, hi: Vector3) -> Array[Plane]:
	return Geometry.bounds_planes(lo, hi)

static func box(parts: Array[Dictionary], lo: Vector3, hi: Vector3, slot: int, title: String) -> void:
	parts.append({"planes":bounds_planes(lo,hi),"slot":slot,"title":title})

static func paint(source: EmberVoxelModelResource, grid: Vector3i, part: Dictionary, id: int) -> void:
	Geometry.paint_convex_part(source, grid, part, id)
