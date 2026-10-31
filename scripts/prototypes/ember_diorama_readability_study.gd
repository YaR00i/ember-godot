extends "res://scripts/prototypes/ember_painted_light_study.gd"
## Stage 0a: compare one cause at a time on the same voxel Source and paint.
const Prefab=preload("res://scripts/ember_voxel_prefab.gd")
const Followers=preload("res://scripts/ember_party_followers.gd")
const HeroScale=preload("res://scripts/ember_exploration_hero_scale.gd")
const Fixture=preload("res://scripts/prototypes/ember_diorama_readability_fixture.gd")
const CAMERA_SETTINGS := [
	{"distance":9.5,"fov":40.0,"polar":0.95,"yaw":0.35,"look":0.6},
	{"distance":12.5,"fov":42.0,"polar":1.05,"yaw":0.35,"look":1.35},
	{"distance":14.0,"fov":32.0,"polar":1.05,"yaw":0.35,"look":1.35}]
const NAMES := ["А · исходная камера", "Б · только камера", "В · спокойнее фактура", "Г · только размер двери"]
@export_enum("Original", "Camera", "Quiet detail", "Door proportions") var comparison_mode:=0
var ready_for_diorama:=false
var camera_candidate:=1
var followers: EmberPartyFollowers
var door: EmberVoxelProp
var tree: EmberVoxelProp
var architecture_probe_available:=false
var base_shader: Shader
var quiet_shader: Shader
var _caption: Label
var _d_button: Button

func prepare() -> void:
	await super.prepare()
	base_shader=depth_shader
	quiet_shader=Shader.new()
	quiet_shader.code="#define EMBER_DIORAMA_READABILITY\n"+base_shader.code
	quiet_shader.set_meta("ember_compact_terrain_shader",true)
	# Use the real party projection and private progress already owned by the LAB player.
	walker.progress_state.set_active_hero_ids(["protagonist","mira"],false)
	followers=Followers.new();followers.name="DioramaParty"
	followers.leader=walker;followers.tile_size=1.0;followers.progress_state=walker.progress_state
	add_child(followers);walker.party_followers=followers
	reset_actors()
	tree=_place_prop("res://content/voxel_models/vox_tree_1511837690.tres",Vector2(8.0,4.6))
	# Proportion probe, independent of a retired city prop.
	var door_source: EmberVoxelModelResource=preload("res://addons/ember_import/ember_voxel_shapes.gd").build("block",Vector3i(16,24,3),16,Color.BROWN,"readability_door_probe","Door proportion probe").source
	door=_place_resource(door_source,Vector2(6.3,6.25))
	architecture_probe_available=door.get_node("Mesh").get_aabb().size.y<HeroScale.height("protagonist",1.0)
	for child in get_node("Instructions").get_children():
		if child is CanvasItem:child.hide()
	_build_diorama_controls()
	ready_for_diorama=true
	set_comparison(comparison_mode)
	# All comparisons start with this one fixed shared light preset and pose.
	set_lighting_preset(1);set_sun_pose(1)
	print("DIORAMA_READY voxel Source; Кай1.8м/Мира1.5м; grass=",tuft_points.size()," door_probe=",architecture_probe_available)

func _prepare_rock_field() -> void:
	# Stage 0a starts with the existing voxel renderer, no smooth LAB replacement.
	var projection=get_node("Map")._visual_surface_projection
	while projection.pending_tile_count()>0:await get_tree().process_frame

func _tuft_support(point: Vector3,_endpoint: int) -> Vector3:
	# The accepted scatter/mesh stays inherited; its anchors follow the active
	# Map floor rather than the smooth-only morph cache on this voxel fixture.
	return get_node("Map").surface_floor_sample(Vector3(point.x,8.0,point.z)).position

func apply_depth() -> void:
	super.apply_depth()
	if depth_material!=null:depth_material.set_shader_parameter("smooth_surface_enabled",false)
	if ready_for_diorama:set_comparison(comparison_mode)

func _place_prop(path: String,point: Vector2) -> EmberVoxelProp:
	var resource: EmberVoxelModelResource=load(path)
	return _place_resource(resource,point)

func _place_resource(resource: EmberVoxelModelResource,point: Vector2) -> EmberVoxelProp:
	var packed:=Prefab.prepare_resource(resource)
	assert(packed!=null)
	var prop:=packed.instantiate() as EmberVoxelProp
	prop.configure_voxel_scale(resource.normalized_density(),1.0)
	add_child(prop)
	prop.global_position=get_node("Map").surface_floor_sample(Vector3(point.x,8.0,point.y)).position
	return prop

func reset_actors() -> void:
	walker.global_position=Vector3(walk_start.x,8.0,walk_start.y)
	walker.global_position.y=get_node("Map").surface_floor_sample(walker.global_position).position.y+0.04
	walker.velocity=Vector3.ZERO
	if followers!=null:
		followers.reset_to_leader()
		var mira: Node3D=followers.get_node("PartyFollower_mira")
		mira.global_position.y=get_node("Map").surface_floor_sample(mira.global_position).position.y
		var body: MeshInstance3D=mira.get_node("Body")
		body.position.y=HeroScale.height("mira",1.0)*0.5;body.rotation=Vector3.ZERO;body.scale=Vector3.ONE
		followers._elapsed=0.0
	follow_camera.reset_follow_height()

func set_camera_candidate(index: int) -> void:
	camera_candidate=clampi(index,1,2)
	set_comparison(1)

func set_comparison(mode: int) -> void:
	comparison_mode=clampi(mode,0,3)
	if comparison_mode==3 and not architecture_probe_available:comparison_mode=1
	var camera: Dictionary=CAMERA_SETTINGS[0 if comparison_mode==0 else camera_candidate]
	follow_camera.follow_distance=camera.distance;follow_camera.fov=camera.fov
	follow_camera.polar_angle=camera.polar;follow_camera.yaw=camera.yaw;follow_camera.look_height=camera.look
	follow_camera.reset_follow_height()
	follow_camera._process(0.0);follow_camera._cam.make_current()
	depth_material.shader=quiet_shader if comparison_mode==2 else base_shader
	depth_material.set_shader_parameter("readability_quiet_strength",0.65 if comparison_mode==2 else 0.0)
	depth_material.set_shader_parameter("surface_detail_enabled",comparison_mode!=2)
	_sync_tuft_material()
	# The selected native door is 1.5m tall against an unchanged 1.8m Kai.
	# Only this category is scaled, including its existing collider/offsets.
	door.configure_voxel_scale(door.voxels_per_block,1.5 if comparison_mode==3 else 1.0)
	_update_caption()

func measurements() -> Dictionary:
	var camera: Camera3D=follow_camera._cam
	var size:=get_viewport().get_visible_rect().size
	var projected:=projected_body(walker.get_node("Viz"),camera)
	var mira: Node3D=followers.get_node("PartyFollower_mira")
	var mira_rect:=projected_body(mira.get_node("Body"),camera)
	var door_height: float=door.get_node("Mesh").get_aabb().size.y*door.block_world_size
	var tree_height: float=tree.get_node("Mesh").get_aabb().size.y*tree.block_world_size
	return {"mode":comparison_mode,"camera_candidate":0 if comparison_mode==0 else camera_candidate,
		"kai_height_m":HeroScale.height("protagonist",1.0),"mira_height_m":HeroScale.height("mira",1.0),
		"kai_rect":[projected.position.x,projected.position.y,projected.size.x,projected.size.y],
		"kai_height_px":projected.size.y,"kai_frame_share":projected.size.y/size.y,
		"mira_height_px":mira_rect.size.y,"door_height_m":door_height,"door_to_kai":door_height/1.8,
		"tree_height_m":tree_height,"tree_to_kai":tree_height/1.8,
		"path_width_m":1.10,"physical_capsule_diameter_m":HeroScale.collision_radius(1.0)*2.0,
		"path_to_capsule":1.10/(HeroScale.collision_radius(1.0)*2.0),
		"fov":camera.fov,"distance_m":follow_camera.follow_distance,"polar":follow_camera.polar_angle,
		"viewport":[size.x,size.y],"grass_tufts":tuft_points.size(),"ground_style":get_node("Map").compact_ground_style}

static func projected_body(body: MeshInstance3D,camera: Camera3D) -> Rect2:
	var bounds:=body.get_aabb()
	var lo:=Vector2(INF,INF);var hi:=Vector2(-INF,-INF)
	for corner in 8:
		var p:=bounds.position+Vector3(bounds.size.x if corner&1 else 0.0,bounds.size.y if corner&2 else 0.0,bounds.size.z if corner&4 else 0.0)
		var screen:=camera.unproject_position(body.global_transform*p)
		lo=lo.min(screen);hi=hi.max(screen)
	return Rect2(lo,hi-lo)

func _build_diorama_controls() -> void:
	var panel:=PanelContainer.new();panel.position=Vector2(18,18);get_node("Instructions").add_child(panel)
	var column:=VBoxContainer.new();column.custom_minimum_size.x=370;panel.add_child(column)
	_caption=Label.new();column.add_child(_caption)
	for i in 4:
		var button:=Button.new();button.text=NAMES[i];column.add_child(button)
		button.pressed.connect(func():set_comparison(i))
		if i==3:_d_button=button;button.disabled=not architecture_probe_available
	var lens:=Button.new();lens.text="Другая камера Б · сравнить";column.add_child(lens)
	lens.pressed.connect(func():set_camera_candidate(2 if camera_candidate==1 else 1))
	var reset:=Button.new();reset.text="Вернуть Кая и Миру на старт";column.add_child(reset);reset.pressed.connect(reset_actors)
	var hint:=Label.new();hint.text="1/2/3/4 — варианты · WASD — ходить · ПКМ — камера\nF1 — панель · свет фиксирован · F6-правки временные";column.add_child(hint)

func _update_caption() -> void:
	if _caption!=null:
		_caption.text=NAMES[comparison_mode]+"\nКай 1.8 м · Мира 1.5 м · рост неизменен\nДверь %.2f м · дерево %.2f м"%[door.get_node("Mesh").get_aabb().size.y*door.block_world_size,tree.get_node("Mesh").get_aabb().size.y]

func _unhandled_input(event: InputEvent) -> void:
	if ready_for_diorama and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_1,KEY_2,KEY_3,KEY_4]:set_comparison(event.keycode-KEY_1);return
		# Keep this readability matrix on fixed light and the accepted material.
		if event.keycode in [KEY_B,KEY_R,KEY_G,KEY_H,KEY_J,KEY_C,KEY_L,KEY_M,KEY_O,KEY_P]:return
	super._unhandled_input(event)
