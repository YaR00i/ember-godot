@tool
extends Control
## Light plan feedback; only release commits the recipe, never a mesh build.
const Layout=preload("res://addons/ember_import/ember_building_layout.gd")
const COLUMN := 6
const BEAM := 7
const ERASE_DETAIL := 8
const BALCONY := 9
const FENCE := 10
signal changed(parameters:Dictionary,structure:Dictionary)
var parameters:Dictionary={}
var structure:Dictionary={}
var mode:=0 # contour / window / door / erase / wing / move wing
var enabled_3d:=false
var level:=0
var _drag:=false
var _draft:Dictionary={}
var _beam_draft: Dictionary = {}
var _fence_side := -1
var _fence_start := Vector2.ZERO
var _yard_plan: Dictionary = {}
var _wing_length_drag:=false
var _wing_width_drag:=false
var _opposite_drag := false
var _move_start_x := 0.0
var _resize_width := true
var _resize_depth := true
var _wire:MeshInstance3D
var _wire_frame:=Transform3D.IDENTITY

func _ready()->void:
	custom_minimum_size=Vector2(220,180);mouse_filter=Control.MOUSE_FILTER_STOP;focus_mode=Control.FOCUS_ALL
	tooltip_text="Контур — потянуть угол. Сдвиг крыла — потянуть крыло вдоль стены. Колонна — щелчок по стене. Балка — протянуть вдоль стены. Esc — отмена."
	visibility_changed.connect(func():
		if not is_visible_in_tree():cancel()
		else:_draw_wire())

func add_tools(parent:Node,allow_3d:=true)->void:
	var label=Label.new();label.text="ПЛАН ДОМА · ВИД СВЕРХУ";parent.add_child(label)
	var row=HBoxContainer.new();parent.add_child(row)
	var choice=OptionButton.new()
	for title in ["Контур","Окно","Вход","Убрать окно","Пристройка","Сдвиг крыла","Колонна","Балка","Убрать деталь","Балкон","Ограда"]:choice.add_item(title)
	choice.item_selected.connect(func(index:int):cancel();mode=index);row.add_child(choice)
	var floor_choice=OptionButton.new();floor_choice.add_item("Этаж 1");floor_choice.add_item("Этаж 2")
	floor_choice.item_selected.connect(func(index:int):level=index;cancel());row.add_child(floor_choice)
	var toggle=CheckButton.new();toggle.text="Рисовать в 3D"
	toggle.visible=allow_3d
	toggle.toggled.connect(func(on:bool):enabled_3d=on;cancel());parent.add_child(toggle)
	parent.add_child(self)
	# The plan is the primary action; numeric provider fields remain below it.
	for i in 4:parent.move_child(parent.get_child(parent.get_child_count()-1),0)

func configure(p:Dictionary,s:Dictionary)->void:
	_drag=false;_draft={};_beam_draft={};_fence_side=-1
	parameters=p.duplicate(true);structure=Layout.data(s,int(p.floors))
	_yard_plan = _yard(parameters)
	queue_redraw();_draw_wire()

func _point_to_screen(p:Vector2)->Vector2:
	var active=_draft if _drag else parameters
	var bounds: Rect2 = _yard_plan.get("bounds", Layout.bounds(active))
	return size/2+(p-bounds.get_center())*_scale()
func _scale()->float:
	var bounds: Rect2 = _yard_plan.get("bounds", Layout.bounds(parameters))
	var span := bounds.size
	return minf((size.x-34)/maxf(8,span.x+2),(size.y-30)/maxf(7,span.y+2))
func _screen_to_point(p:Vector2)->Vector2:
	var bounds: Rect2 = _yard_plan.get("bounds", Layout.bounds(parameters))
	return (p-size/2)/_scale()+bounds.get_center()

func _yard(p: Dictionary) -> Dictionary:
	return Layout.fence_plan(p, structure.door) if p.get("fence", false) and p.get("fence_custom", false) and structure.has("door") else {}

func _draw()->void:
	if parameters.is_empty():return
	draw_style_box(get_theme_stylebox("panel","Tree"),Rect2(Vector2.ZERO,size))
	for x in range(-8,9):draw_line(_point_to_screen(Vector2(x*.5,-3.5)),_point_to_screen(Vector2(x*.5,3.5)),Color(1,1,1,.08))
	for z in range(-7,8):draw_line(_point_to_screen(Vector2(-4,z*.5)),_point_to_screen(Vector2(4,z*.5)),Color(1,1,1,.08))
	var p=_draft if _drag else parameters
	var yard := _yard(p) if _drag else _yard_plan
	for segment: Dictionary in yard.get("segments", []):
		draw_line(_point_to_screen(segment.from), _point_to_screen(segment.to), Color(0.8, 0.6, 0.36), 2.0)
	var points=PackedVector2Array()
	for corner in Layout.outline(p):points.append(_point_to_screen(corner))
	draw_colored_polygon(points,Color(.35,.7,.85,.13))
	var closed=points.duplicate();closed.append(points[0]);draw_polyline(closed,Color(.35,.8,1),2)
	for corner in points:draw_circle(corner,4,Color(.35,.8,1))
	for window in structure.get("windows",[]):
		if int(window.level)==level:draw_circle(_point_to_screen(Layout.point(window,p.width_m,p.depth_m,p)),4,Color(.9,.9,.5))
	if structure.has("door"):draw_circle(_point_to_screen(Layout.point(structure.door,p.width_m,p.depth_m,p)),6,Color(.5,1,.5))
	for detail in visible_details():
		var profile := Layout.facade_detail_profile(detail, p)
		var start := _point_to_screen(profile.from)
		var tint := Color(1.0, 0.64, 0.36)
		if detail.kind == "beam":
			draw_line(start, _point_to_screen(profile.to), tint, 4.0)
		elif detail.kind == "balcony":
			var footprint: Rect2 = profile.footprint
			draw_rect(Rect2(_point_to_screen(footprint.position), footprint.size * _scale()), tint, false, 2.0)
		else:
			draw_rect(Rect2(start - Vector2(4, 4), Vector2(8, 8)), tint)

func cancel()->void:
	_drag=false;_draft={};_beam_draft={};_fence_side=-1;queue_redraw();_draw_wire()

func _gui_input(event:InputEvent)->void:
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:cancel();accept_event();return
	if event is InputEventMouse:
		if _handle(event,_screen_to_point(event.position)):accept_event()

func _handle(event:InputEvent,point:Vector2, fixed_frame := false)->bool:
	if parameters.is_empty():return false
	if mode in [COLUMN, BEAM, ERASE_DETAIL, BALCONY]:
		return _handle_facade_detail(event, point)
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			grab_focus()
			if mode == FENCE:
				return _begin_fence_drag(point)
			if mode == 5:
				return _begin_wing_move(point)
			if mode in [0,4]:
				_drag=true;_draft=parameters.duplicate(true);_wing_length_drag=mode==4;_wing_width_drag=false
				_resize_width = not fixed_frame or point.x >= 0.0
				_resize_depth = not fixed_frame or point.y >= 0.0
				_begin_wing_drag(point)
			else:
				var next=structure.duplicate(true);var item=Layout.nearest(point,parameters.width_m,parameters.depth_m,parameters);item.level=level
				if Layout.point(item,parameters.width_m,parameters.depth_m,parameters).distance_to(point)>0.55:return false
				if mode==1:next.windows.append(item)
				elif mode==2:next.door={"side":item.side,"t":item.t}
				else:
					var best=-1;var distance=0.65
					for i in next.windows.size():
						if next.windows[i].level!=level:continue
						var d=Layout.point(next.windows[i],parameters.width_m,parameters.depth_m,parameters).distance_to(point)
						if d<distance:best=i;distance=d
					if best>=0:next.windows.remove_at(best)
				changed.emit(parameters.duplicate(true),next)
		elif _drag:
			_drag=false;_fence_side=-1;changed.emit(_draft.duplicate(true),structure.duplicate(true));_draft={};queue_redraw();_draw_wire()
		return true
	if event is InputEventMouseMotion and _drag:
		var step=0.25
		if mode == FENCE:
			var key: String = Layout.FENCE_OUTSET_KEYS[_fence_side]
			var delta := (point - _fence_start).dot(Layout.FENCE_NORMALS[_fence_side])
			_draft[key] = clampf(snappedf(float(parameters[key]) + delta, step), 0.0, 2.0)
		elif mode == 5:
			var key := "opposite_inset_m" if _opposite_drag else "wing_inset_m"
			var local := Layout.wing_plan(parameters)
			var along := Layout.turn_point(point, -Layout.wing_turn(parameters)).x
			var right := (int(local.wing_side) == 1) != _opposite_drag
			var delta := (_move_start_x - along) if right else (along - _move_start_x)
			var inset := float(parameters.get(key, 0.0)) + delta
			_draft[key] = clampf(snappedf(inset, step), 0.0, Layout.max_wing_inset(parameters, _opposite_drag))
		elif _wing_length_drag:
			_resize_wing(point, fixed_frame)
		else:
			var width: float = point.x + parameters.width_m / 2 if fixed_frame else absf(point.x) * 2
			var depth: float = point.y + parameters.depth_m / 2 if fixed_frame else absf(point.y) * 2
			if _resize_width:
				_draft.width_m = clampf(snappedf(width, step), 3, 6.5)
			if _resize_depth:
				_draft.depth_m = clampf(snappedf(depth, step), 3, 5.5)
		queue_redraw();_draw_wire();return true
	return false


func _begin_fence_drag(point: Vector2) -> bool:
	var yard := _yard(parameters)
	if not yard.has("rectangle"):
		return false
	var rect: Rect2 = yard.rectangle
	var a := rect.position
	var b := rect.end
	var sides := [absf(point.y - a.y), absf(point.x - b.x), absf(point.y - b.y), absf(point.x - a.x)]
	var distance: float = sides.min()
	if distance > 0.55 or not rect.grow(0.55).has_point(point):
		return false
	_fence_side = sides.find(distance)
	_fence_start = point
	_drag = true
	_draft = parameters.duplicate(true)
	return true


func visible_details() -> Array:
	var details: Array = structure.get("facade_details", []).filter(func(detail: Dictionary) -> bool: return detail.level == level)
	if not _beam_draft.is_empty():
		details.append(_beam_draft)
	return details


func _handle_facade_detail(event: InputEvent, position: Vector2) -> bool:
	if not _beam_draft.is_empty() and (event is InputEventMouseMotion or event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed):
		var wall := Layout.edge(_beam_draft.side, parameters)
		_beam_draft.end_t = Layout.wall_fraction(position, wall)
		if event is InputEventMouseButton:
			var detail := _beam_draft
			cancel()
			_commit_detail(detail)
		else:
			queue_redraw()
			_draw_wire()
		return true
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return false
	if mode == ERASE_DETAIL:
		return _erase_detail(position)
	var side := -1
	var distance := 0.55
	for id in Layout.wall_ids(parameters):
		var wall := Layout.edge(id, parameters)
		if wall.a == wall.b:
			continue
		var gap := position.distance_to(Geometry2D.get_closest_point_to_segment(position, wall.a, wall.b))
		if gap < distance:
			side = id
			distance = gap
	if side == -1:
		return false
	grab_focus()
	var t := Layout.wall_fraction(position, Layout.edge(side, parameters))
	var kind := "beam" if mode == BEAM else ("balcony" if mode == BALCONY else "column")
	var detail := {"kind": kind, "side": side, "t": t, "level": level}
	if mode == BEAM:
		_beam_draft = detail
		_beam_draft.end_t = t
		_drag = true
		_draft = parameters
	else:
		_commit_detail(detail)
	return true


func _commit_detail(detail: Dictionary) -> void:
	var next := structure.duplicate(true)
	if not next.has("facade_details"):
		next.facade_details = []
	next.facade_details.append(detail)
	changed.emit(parameters.duplicate(true), next)


func _erase_detail(position: Vector2) -> bool:
	var next := structure.duplicate(true)
	var details: Array = next.get("facade_details", [])
	var best := -1
	var distance := 0.35
	for index in details.size():
		var detail: Dictionary = details[index]
		if detail.level != level:
			continue
		var profile := Layout.facade_detail_profile(detail, parameters)
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(position, profile.from, profile.to) if detail.kind == "beam" else profile.from
		if detail.kind == "balcony":
			var footprint: Rect2 = profile.footprint
			closest = position.clamp(footprint.position, footprint.end)
		var gap := position.distance_to(closest)
		if gap < distance or (best >= 0 and is_equal_approx(gap, distance) and detail.kind == "column"):
			distance = gap
			best = index
	if best == -1:
		return false
	details.remove_at(best)
	if details.is_empty():
		next.erase("facade_details")
	changed.emit(parameters.duplicate(true), next)
	return true


func _begin_wing_move(point: Vector2) -> bool:
	if not Layout.has_wing(parameters):
		return false
	for index in (2 if Layout.has_opposite_wing(parameters) else 1):
		var opposite := index == 1
		if Layout.has_gabled_wing(parameters, opposite):
			continue
		if not Layout.wing_rect(parameters, opposite).grow(0.2).has_point(point):
			continue
		_drag = true
		_draft = parameters.duplicate(true)
		_opposite_drag = opposite
		_move_start_x = Layout.turn_point(point, -Layout.wing_turn(parameters)).x
		return true
	return false


func _begin_wing_drag(point: Vector2) -> void:
	_opposite_drag = false
	var both := Layout.has_opposite_wing(parameters)
	if mode == 4:
		if Layout.wing_turn(parameters) != 0:
			return
		if both:
			var primary := Layout.wing_rect(parameters).get_center().x
			var opposite := Layout.wing_rect(parameters, true).get_center().x
			_opposite_drag = absf(point.x - opposite) < absf(point.x - primary)
		else:
			_draft.wing_side = 1 if point.x >= 0.0 else 2
		return
	if not Layout.has_wing(parameters):
		return
	var local := Layout.wing_plan(parameters)
	point = Layout.turn_point(point, -Layout.wing_turn(parameters))
	var closest := 0.8
	for index in (2 if both else 1):
		var opposite := index == 1
		var wing := Layout.wing_rect(local, opposite)
		var right := (int(local.wing_side) == 1) != opposite
		var inner := Vector2(wing.position.x if right else wing.end.x, wing.end.y)
		var outer := Vector2(wing.end.x if right else wing.position.x, wing.end.y)
		var inner_distance := point.distance_to(inner)
		var outer_distance := point.distance_to(outer)
		var distance := minf(inner_distance, outer_distance)
		if distance < closest:
			closest = distance
			_opposite_drag = opposite
			_wing_length_drag = true
			_wing_width_drag = inner_distance < outer_distance


func _resize_wing(point: Vector2, fixed_frame: bool) -> void:
	var local := Layout.wing_plan(parameters)
	var local_draft := Layout.wing_plan(_draft)
	point = Layout.turn_point(point, -Layout.wing_turn(parameters))
	var both := Layout.has_opposite_wing(parameters)
	var length: float = point.y - local.depth_m * 0.5
	var other := Layout.wing_rect(parameters, not _opposite_drag) if both else Rect2()
	if not fixed_frame:
		# Undo the thumbnail's centering on the longer wing, keeping the other
		# wing's dimensions unchanged when it defines the back of the plan.
		var previous_depth := Layout.bounds(local).size.y - float(local.depth_m)
		length -= previous_depth * 0.5
		length = length * 2.0 if length >= other.size.y * 0.5 else length + other.size.y * 0.5
	_draft["opposite_length_m" if _opposite_drag else "wing_length_m"] = clampf(snappedf(length, 0.25), 1.0, 3.0)
	if _wing_width_drag:
		var right := (int(local_draft.wing_side) == 1) != _opposite_drag
		var width: float = local.width_m * 0.5 - point.x if right else point.x + local.width_m * 0.5
		var inset := float(parameters.get("opposite_inset_m" if _opposite_drag else "wing_inset_m", 0.0))
		var current_width := Layout.wing_rect(local, _opposite_drag).size.x
		var limit := current_width + Layout.max_wing_inset(parameters, _opposite_drag) - inset
		_draft["opposite_width_m" if _opposite_drag else "wing_width_m"] = clampf(snappedf(width - inset, 0.25), 1.5, minf(3.0, minf(limit, local.width_m - 1.0)))


func forward_input(camera:Camera3D,event:InputEvent,frame:Transform3D)->bool:
	if not enabled_3d or parameters.is_empty() or mode == FENCE:return false
	_wire_frame=frame
	if not is_instance_valid(_wire):
		_wire=MeshInstance3D.new();_wire.name="BuildingPlanPreview";camera.get_parent().add_child(_wire)
		var material=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=Color(.25,.85,1);material.no_depth_test=true;_wire.material_override=material
	_draw_wire()
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:cancel();return true
	if not event is InputEventMouse:return false
	var effective := _placed_frame(parameters)
	if mode in [1,2,3,COLUMN,BEAM,ERASE_DETAIL,BALCONY]:
		var inverse=effective.affine_inverse()
		var origin=inverse*camera.project_ray_origin(event.position)
		var direction=inverse.basis*camera.project_ray_normal(event.position)
		var closest:Variant=null;var distance=INF
		var wall_ids: Array = Layout.wall_ids(parameters) if _beam_draft.is_empty() else [_beam_draft.side]
		for side in wall_ids:
			var wall=Layout.edge(side,parameters);var normal:Vector3=wall.normal
			var candidate=Plane(normal,normal.dot(Vector3(wall.a.x,0,wall.a.y))).intersects_ray(origin,direction)
			if candidate==null:continue
			if not _beam_draft.is_empty():
				return _handle(event, Vector2(candidate.x, candidate.z))
			if candidate.y<.25 or candidate.y>.25+float(parameters.floor_height_m)*int(parameters.floors):continue
			var flat=Vector2(candidate.x,candidate.z)
			if flat.distance_to(Geometry2D.get_closest_point_to_segment(flat,wall.a,wall.b))>.001:continue
			if Layout.is_wing_wall(side) and not Layout.has_gabled_wing(parameters, side >= 7):
				var heights=Layout.wing_heights(parameters)
				var local := Layout.wing_plan(parameters)
				var wing := Layout.wing_rect(local, side >= 7)
				var local_point := Layout.turn_point(flat, -Layout.wing_turn(parameters))
				if candidate.y > lerpf(heights.x, heights.y, (local_point.y - wing.position.y) / wing.size.y) - .125:
					continue
			var d=origin.distance_squared_to(candidate)
			if d<distance:closest=candidate;distance=d
		if closest != null:
			return _handle(event,Vector2(closest.x,closest.z))
		if not _beam_draft.is_empty() and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			cancel()
			return true
		return false
	var hit=Plane(Vector3.UP,frame.origin.y+0.25).intersects_ray(camera.project_ray_origin(event.position),camera.project_ray_normal(event.position))
	if hit==null:return false
	var point=effective.affine_inverse()*hit
	return _handle(event,Vector2(point.x,point.z),parameters.has("fixed_corner"))


func _placed_frame(p: Dictionary) -> Transform3D:
	var frame := _wire_frame
	var offset := Layout.model_offset(p)
	frame.origin += frame.basis * (Vector3(offset.x, 0.0, offset.y) + Layout.placement_offset(p))
	return frame

func _draw_wire()->void:
	if not is_instance_valid(_wire):return
	_wire.visible=enabled_3d and is_visible_in_tree()
	if parameters.is_empty() or not _wire.visible:return
	var p=_draft if _drag else parameters
	var extent := Layout.outline(p)
	_wire.transform = _placed_frame(p)
	var details := visible_details()
	var profile_key := [extent, details, p.floors, p.floor_height_m, p.wing_roof, p.opposite_roof, p.balcony_width_m, p.balcony_depth_m]
	if _wire.mesh!=null and _wire.get_meta("building_profile",[])==profile_key:return
	_wire.set_meta("building_profile",profile_key.duplicate(true))
	var mesh=ImmediateMesh.new();mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var corners=[]
	for corner in extent:corners.append(Vector3(corner.x,.26,corner.y))
	for i in corners.size():
		mesh.surface_add_vertex(corners[i]);mesh.surface_add_vertex(corners[(i+1)%corners.size()]);mesh.surface_add_vertex(corners[i]);mesh.surface_add_vertex(corners[i]+Vector3.UP*.4)
	for detail in details:
		var profile := Layout.facade_detail_profile(detail, p)
		if detail.kind == "balcony":
			var front: Vector3 = Vector3(profile.from.x, profile.bottom, profile.from.y) + profile.normal * profile.depth
			var along: Vector3 = profile.normal.cross(Vector3.UP) * profile.half_width
			mesh.surface_add_vertex(front - along)
			mesh.surface_add_vertex(front + along)
			continue
		mesh.surface_add_vertex(Vector3(profile.from.x, profile.bottom, profile.from.y))
		mesh.surface_add_vertex(Vector3(profile.to.x, profile.top if detail.kind == "column" else profile.bottom, profile.to.y))
	mesh.surface_end();_wire.mesh=mesh

func _exit_tree()->void:
	if is_instance_valid(_wire):_wire.queue_free()
