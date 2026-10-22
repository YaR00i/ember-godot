extends Node3D
## Play harness only. Authored Map, voxel prefabs and material Resources own
## the environment; opening this scene never runs a LAB geometry recipe.
@export var player_start:=Vector3(4.25,0.5,7.45)
@export var camera_distance:=12.5
@export var camera_polar:=1.05
@export var camera_yaw:=0.35
@export var camera_look:=1.35
@export var camera_fov:=42.0
var player: EmberPlayer
var camera: EmberFollowCamera
var ready_for_play:=false
var _light_preset:=1
var _sun_side:=1
var _object_look:=0

func _ready() -> void:
	var map:=get_node("Map") as EmberMapLoader
	while map._visual_surface_projection==null or map._visual_surface_projection.pending_tile_count()>0:await get_tree().process_frame
	var state:=EmberExploreState.new();state.name="ReviewProgress";state.persistence_enabled=false;state.restore_enabled=false
	add_child(state);state.reset_new_game()
	player=EmberPlayer.new();player.name="Kai";player.tile_size=1.0;player.progress_state=state
	player.position=player_start
	var floor:=map.surface_floor_sample(player_start)
	if floor.get("solid",false):player.position.y=floor.position.y+0.04
	add_child(player)
	camera=EmberFollowCamera.new();camera.name="GameCamera";camera.target=player
	camera.follow_distance=camera_distance;camera.polar_angle=camera_polar;camera.yaw=camera_yaw;camera.look_height=camera_look;camera.fov=camera_fov
	camera.cam_near=0.05;camera.cam_far=250.0;add_child(camera);player.camera_rig=camera
	camera._process(0)
	set_lighting(_light_preset,_sun_side)
	ready_for_play=true

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:return
	if event.keycode in [KEY_1,KEY_2,KEY_3]:set_lighting(event.keycode-KEY_1,_sun_side)
	elif event.keycode==KEY_L:set_lighting(_light_preset,1-_sun_side)
	elif event.keycode in [KEY_4,KEY_5,KEY_6]:set_object_look(1 if event.keycode==KEY_4 else (0 if event.keycode==KEY_5 else 2))

func set_lighting(preset: int, side: int) -> void:
	_light_preset=preset;_sun_side=side
	var sun:=get_node("Map/Look/Sun") as DirectionalLight3D
	EmberLights.apply_material_light_preset(sun,get_node("Map/Look/WorldEnvironment").environment,preset)
	sun.rotation_degrees=[Vector3(-32,-145,0),Vector3(-40,-65,0)][side]
	if preset==1:sun.rotation_degrees.x=-62.0
	elif preset==2:sun.rotation_degrees.x=-38.0

func set_object_look(look: int) -> void:
	# Key 4 = voxel cubes (look 1), key 5 = low poly (look 0, default), key 6 = detailed (look 2):
	# the same hull with depth derived from the painted colour.
	_object_look=look
	for prop in get_tree().get_nodes_in_group(&"ember_solid_surface"):
		if prop.has_method("set_solid_look"):prop.set_solid_look(look)
