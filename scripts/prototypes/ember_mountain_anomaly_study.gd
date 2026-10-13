extends "res://scripts/prototypes/ember_cartoon_ground_study.gd"
## A saved, isolated presentation study; not a gameplay anomaly owner.
const Smooth=preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")
@export var anomaly_zones: Array[Vector4]=[Vector4(21,19,2.6,0.8),Vector4(13,23,2.4,0.8)]
@export var walk_test_enabled:=false
@export var walk_start:=Vector2(23,29)
@export var walk_route:=PackedVector2Array([Vector2(23,29),Vector2(31,29)])
var walker: EmberPlayer
var follow_camera: EmberFollowCamera
var carry_support_enabled:=true
var carry_count:=0
var blocked_phases:=0
var demo_walking:=false
var _route_index:=1
var ready_for_morph:=false
var phase:=0.0
var playing:=false
var worst_phase_us:=0
var worst_bake_us:=0
var worst_field_us:=0
var worst_collision_us:=0
var preparations: Dictionary={}
var _projection
var _slider: HSlider
var _status: Label
var _cycle:=0.0
var _morph_accum:=0.0

func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():return
	process_physics_priority=-50
	_create_controls()
	prepare.call_deferred()

func _create_controls() -> void:
	var panel:=VBoxContainer.new();panel.position=Vector2(20,54);panel.custom_minimum_size=Vector2(410,0)
	get_node("Instructions").add_child(panel)
	_status=Label.new();_status.text="Подготовка горы…";panel.add_child(_status)
	_slider=HSlider.new();_slider.max_value=1;_slider.step=0.001;_slider.custom_minimum_size.y=30;_slider.editable=false;panel.add_child(_slider)
	_slider.value_changed.connect(func(value):playing=false;set_phase(value))
	var row:=HBoxContainer.new();panel.add_child(row)
	for i in 3:
		var button:=Button.new();button.text=["Гладко","Полублоки","Воксели"][i];row.add_child(button)
		button.pressed.connect(func():playing=false;set_phase(i*0.5))
	var play:=Button.new();play.text="Плавное превращение / пауза";panel.add_child(play)
	play.pressed.connect(func():playing=not playing;_cycle=phase*8.0)

func prepare() -> void:
	_projection=get_node("Map")._visual_surface_projection
	while _projection.pending_tile_count()>0:await get_tree().process_frame
	await prepare_morph_fields()

func prepare_morph_fields() -> void:
	# Existing morph owner, reused after an explicit LAB shape comparison.
	var source: Resource=_projection.document
	for key: Vector2i in _projection._tiles:
		var bounds:=Rect2i(key*64,Vector2i(64,64))
		var affected:=false
		for zone in anomaly_zones:
			var closest:=Vector2(clampf(zone.x,bounds.position.x/16.0,bounds.end.x/16.0),clampf(zone.y,bounds.position.y/16.0,bounds.end.y/16.0))
			if closest.distance_to(Vector2(zone.x,zone.y))<=zone.z+0.15:affected=true
		if not affected:continue
		var ground:=(_projection._tiles[key] as Node3D).get_node("Ground") as MeshInstance3D
		var original:=ground.mesh as ArrayMesh
		var base: Dictionary=_projection._smooth_field(key)
		# A snapped 1m group may sample eight fine cells beyond a tile edge.
		# Keep the full smoothing halo around those centres as well.
		var coarse_data:=Smooth.field(source,bounds.grow(8))
		var targets:=Smooth.anomaly_targets(base,bounds,anomaly_zones,source.origin_y,coarse_data)
		var shapes: Array[Array]=[Smooth.anomaly_mesh_target(original,targets[0]),Smooth.anomaly_mesh_target(original,targets[1])]
		var mesh:=ArrayMesh.new();mesh.blend_shape_mode=Mesh.BLEND_SHAPE_MODE_NORMALIZED
		mesh.add_blend_shape("half");mesh.add_blend_shape("voxel")
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,original.surface_get_arrays(0),shapes)
		mesh.custom_aabb=original.get_aabb().grow(16.0)
		mesh.surface_set_material(0,original.surface_get_material(0));ground.mesh=mesh
		var changed:=PackedInt32Array()
		for i in base.heights.size():
			if base.heights[i]!=targets[0].heights[i] or base.heights[i]!=targets[1].heights[i]:changed.append(i)
		var current: Dictionary=base.duplicate();current.heights=base.heights.duplicate()
		# Keep stationary triangles in a static shape. Refit only triangles
		# whose vertices actually move, rather than the whole affected tile.
		var points: PackedVector3Array=original.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var half_points: PackedVector3Array=shapes[0][Mesh.ARRAY_VERTEX]
		var voxel_points: PackedVector3Array=shapes[1][Mesh.ARRAY_VERTEX]
		var fixed:=PackedVector3Array();var moving:=PackedVector3Array()
		var half_moving:=PackedVector3Array();var voxel_moving:=PackedVector3Array()
		for i in range(0,points.size(),3):
			var moves:=false
			for j in 3:
				if points[i+j]!=half_points[i+j] or points[i+j]!=voxel_points[i+j]:moves=true
			for j in 3:
				if moves:
					moving.append(points[i+j]);half_moving.append(half_points[i+j]);voxel_moving.append(voxel_points[i+j])
				else:fixed.append(points[i+j])
		var rest_shape:=CollisionShape3D.new();rest_shape.name="StudyStationaryGround"
		var rest:=ConcavePolygonShape3D.new();rest.set_faces(fixed);rest_shape.shape=rest
		ground.get_parent().get_node("GroundPhysics").add_child(rest_shape)
		var collision_mesh:=ArrayMesh.new();collision_mesh.blend_shape_mode=Mesh.BLEND_SHAPE_MODE_NORMALIZED
		collision_mesh.add_blend_shape("half");collision_mesh.add_blend_shape("voxel")
		var arrays:=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=moving
		var half_arrays:=[];half_arrays.resize(Mesh.ARRAY_MAX);half_arrays[Mesh.ARRAY_VERTEX]=half_moving
		var voxel_arrays:=[];voxel_arrays.resize(Mesh.ARRAY_MAX);voxel_arrays[Mesh.ARRAY_VERTEX]=voxel_moving
		collision_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[half_arrays,voxel_arrays])
		var collision_instance:=MeshInstance3D.new();collision_instance.mesh=collision_mesh;collision_instance.visible=false
		ground.get_parent().add_child(collision_instance)
		preparations[key]={"ground":ground,"collision_mesh":collision_instance,"base":base,"half":targets[0],"voxel":targets[1],"changed":changed,"current":current,"baked":ArrayMesh.new()}
		await get_tree().process_frame
	ready_for_morph=true;_slider.editable=true;set_phase(0.0)
	if walk_test_enabled and not is_instance_valid(walker):_create_walker()
	print("MOUNTAIN_ANOMALY_READY affected_tiles=",preparations.size())

func set_phase(value: float) -> void:
	if not ready_for_morph:return
	var support:=_support_change(clampf(value,0.0,1.0))
	if support.get("blocked",false):
		playing=false;blocked_phases+=1;_slider.set_value_no_signal(phase)
		_status.text="Пауза: над персонажем недостаточно места для подъёма земли."
		return
	if support.get("rise",0.0)>0.0:walker.move_and_collide(Vector3.UP*support.rise)
	var started:=Time.get_ticks_usec();phase=clampf(value,0.0,1.0)
	var weights:=Smooth.anomaly_weights(phase)
	var bake_us:=0;var field_us:=0;var collision_us:=0
	for key: Vector2i in preparations:
		var entry: Dictionary=preparations[key]
		var ground:=entry.ground as MeshInstance3D
		ground.set_blend_shape_value(0,weights.x);ground.set_blend_shape_value(1,weights.y)
		var collision_instance:=entry.collision_mesh as MeshInstance3D
		collision_instance.set_blend_shape_value(0,weights.x);collision_instance.set_blend_shape_value(1,weights.y)
		var stage:=Time.get_ticks_usec()
		var baked:=collision_instance.bake_mesh_from_current_blend_shape_mix(entry.baked)
		bake_us+=Time.get_ticks_usec()-stage;stage=Time.get_ticks_usec()
		var heights: PackedFloat32Array=entry.current.heights
		var base_heights: PackedFloat32Array=entry.base.heights
		var half_heights: PackedFloat32Array=entry.half.heights
		var voxel_heights: PackedFloat32Array=entry.voxel.heights
		for i: int in entry.changed:
			heights[i]=base_heights[i]*(1.0-weights.x-weights.y)+half_heights[i]*weights.x+voxel_heights[i]*weights.y
		entry.current.heights=heights
		field_us+=Time.get_ticks_usec()-stage;stage=Time.get_ticks_usec()
		_projection.apply_study_smooth_tile(key,entry.current,baked.get_faces())
		collision_us+=Time.get_ticks_usec()-stage
	if not support.is_empty():
		if support.get("rise",0.0)<0.0:walker.move_and_collide(Vector3.UP*support.rise)
		walker.velocity.y=0.0;carry_count+=1
	_slider.set_value_no_signal(phase)
	_status.text="Гладко → полублоки → воксели   %d%%" % roundi(phase*100)
	worst_phase_us=maxi(worst_phase_us,Time.get_ticks_usec()-started)
	worst_bake_us=maxi(worst_bake_us,bake_us);worst_field_us=maxi(worst_field_us,field_us);worst_collision_us=maxi(worst_collision_us,collision_us)

func _physics_process(delta: float) -> void:
	if playing and ready_for_morph:
		_cycle=fmod(_cycle+delta,16.0)
		_morph_accum+=delta
		if _morph_accum>=1.0/30.0:
			_morph_accum=fmod(_morph_accum,1.0/30.0)
			set_phase(_cycle/8.0 if _cycle<=8.0 else (16.0-_cycle)/8.0)
	if demo_walking:_drive_demo_route()

func _support_change(next_phase: float) -> Dictionary:
	if not carry_support_enabled or not is_instance_valid(walker) or not walker.is_on_floor() or walker._step_active:return {}
	# Use the real last floor contact, not a fabricated character-centre ray.
	var contact:=walker.global_position
	var supported:=false
	for i in walker.get_slide_collision_count():
		var hit:=walker.get_slide_collision(i)
		var collider:=hit.get_collider() as Node
		if hit.get_normal().y>=cos(walker.floor_max_angle) and collider!=null and _projection.is_ancestor_of(collider):
			contact=hit.get_position();supported=true;break
	if not supported:
		# Floor snapping can retain is_on_floor without a slide collision.
		# A short real capsule sweep obtains the missing contact safely.
		var floor_hit:=KinematicCollision3D.new()
		if walker.test_move(walker.global_transform,Vector3.DOWN*maxf(0.012,walker.safe_margin*4.0),floor_hit):
			var collider:=floor_hit.get_collider() as Node
			if floor_hit.get_normal().y>=cos(walker.floor_max_angle) and collider!=null and _projection.is_ancestor_of(collider):
				contact=floor_hit.get_position();supported=true
	if not supported:return {}
	var p: Vector3=_projection.to_local(contact)
	var point:=Vector2(p.x,p.z)
	var key:=Vector2i(floori(point.x/64.0),floori(point.y/64.0))
	if not preparations.has(key):return {}
	var entry: Dictionary=preparations[key];var weights:=Smooth.anomaly_weights(next_phase)
	var next:=Smooth.sample(entry.base,point)*(1.0-weights.x-weights.y)+Smooth.sample(entry.half,point)*weights.x+Smooth.sample(entry.voxel,point)*weights.y
	var previous:=Smooth.sample(entry.current,point)
	var rise: float=_projection.to_global(Vector3(p.x,next,p.z)).y-_projection.to_global(Vector3(p.x,previous,p.z)).y
	if absf(rise)<0.000001:return {}
	if rise>0.0 and walker.test_move(walker.global_transform,Vector3.UP*rise):return {"blocked":true}
	return {"rise":rise}

func _create_walker() -> void:
	walker=EmberPlayer.new();walker.name="StudyPlayer";walker.tile_size=1.0
	# Own disposable state; F6 never changes the user's exploration save.
	var state:=EmberExploreState.new();state.persistence_enabled=false;state.restore_enabled=false
	add_child(state);state.reset_new_game();walker.progress_state=state
	walker.position=Vector3(walk_start.x,25,walk_start.y);add_child(walker)
	var floor: Dictionary=get_node("Map").surface_floor_sample(walker.global_position)
	walker.position.y=floor.position.y+0.04
	follow_camera=EmberFollowCamera.new();follow_camera.name="WalkCamera";follow_camera.target=walker
	follow_camera.follow_distance=8.0;follow_camera.look_height=0.9;follow_camera.cam_near=0.05
	follow_camera.cam_far=250.0;follow_camera.polar_angle=0.85;follow_camera.yaw=0.0
	add_child(follow_camera);walker.camera_rig=follow_camera
	var row:=HBoxContainer.new();_status.get_parent().add_child(row)
	var view:=Button.new();view.text="Поляна / камера персонажа";row.add_child(view);view.pressed.connect(toggle_walk_view)
	var demo:=Button.new();demo.text="Проход через пятно / стоп";row.add_child(demo)
	demo.pressed.connect(func():set_demo_walking(not demo_walking))
	var hint:=Label.new();hint.text="WASD — ходить · V — общий вид / персонаж";_status.get_parent().add_child(hint)

func toggle_walk_view() -> void:
	if not is_instance_valid(follow_camera):return
	var overview:=get_node("Camera3D") as Camera3D
	if overview.current:follow_camera._cam.make_current()
	else:overview.make_current()

func set_demo_walking(enabled: bool) -> void:
	demo_walking=enabled
	for action in ["move_west","move_east","move_north","move_south"]:Input.action_release(action)
	if enabled:_route_index=1;playing=true;_cycle=phase*8.0

func _drive_demo_route() -> void:
	if not is_instance_valid(walker) or walk_route.size()<2:return
	var point:=Vector2(walker.position.x,walker.position.z)
	if point.distance_to(walk_route[_route_index])<0.18:_route_index=1-_route_index
	var direction:=walk_route[_route_index]-point
	var axis:=Vector2(direction.x,direction.y).rotated(follow_camera.yaw).normalized()
	for action in ["move_west","move_east","move_north","move_south"]:Input.action_release(action)
	Input.action_press("move_east" if axis.x>=0.0 else "move_west",absf(axis.x))
	Input.action_press("move_south" if axis.y>=0.0 else "move_north",absf(axis.y))

func _exit_tree() -> void:
	if demo_walking:set_demo_walking(false)

func _unhandled_input(event: InputEvent) -> void:
	# Keep one orbit controller; M/B are disabled in this fixed-topology study.
	if event is InputEventKey and event.keycode in [KEY_M,KEY_B]:return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_V:toggle_walk_view();return
	if is_instance_valid(follow_camera) and follow_camera._cam.current:return
	super._unhandled_input(event)
