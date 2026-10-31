extends SceneTree
const Player=preload("res://scripts/ember_player.gd")
var actor:EmberPlayer
var errors:Array[String]=[]
var out:="D:/hoshi-ember-2026-10-27"
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("HOSHI_PLAYER_FAIL ",label)
func frames(n:int)->void:
	for i in n:await physics_frame
func shot(label:String)->void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(label+".png"))
func run()->void:
	Engine.max_fps=60
	var world:=Node3D.new();root.add_child(world);current_scene=world
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(0.22,0.23,0.26);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color(0.5,0.5,0.5);world.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-40,30,0);world.add_child(sun)
	var floor:=StaticBody3D.new();var col:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(320,2,320);col.shape=shape;floor.position.y=-1;floor.add_child(col);world.add_child(floor)
	actor=Player.new();actor.tile_size=16;world.add_child(actor)
	check(actor.install_hoshi_test_visual(),"original local avatar loads")
	var visual=actor._hoshi_visual
	check(visual.loaded and visual.height_m>1.4 and visual.height_m<1.6,"Hoshi native scale")
	check(not actor.get_node("Viz").visible,"placeholder replaced")
	check(absf(actor.get_node("Shape").shape.height-visual.height_m*16)<0.001,"capsule matches avatar height")
	check(visual.skeleton.get_bone_count()==136,"native skeleton retained")
	for mesh:MeshInstance3D in visual.avatar.find_children("*","MeshInstance3D",true,false):
		if mesh.skin!=null:check(mesh.get_node_or_null(mesh.skeleton)==visual.skeleton,"explicit skin skeleton binding across project compatibility settings")
	check(visual.toon.size()>0,"source toon materials actually bound")
	var rests:=[]
	for i in visual.skeleton.get_bone_count():rests.append(visual.skeleton.get_bone_rest(i))
	for mat in visual.toon:check(is_equal_approx(mat.get_shader_parameter("shadow_strength"),0.73),"saved soft shadow setting")
	var camera:=Camera3D.new();camera.fov=32;world.add_child(camera);camera.make_current()
	camera.look_at_from_position(Vector3(18,20,62),Vector3(0,13,0))
	await frames(20);await shot("hoshi-original-front")
	Input.action_press("move_north");var before:=actor.position
	await frames(45);Input.action_release("move_north")
	check(actor.position.distance_to(before)>20,"existing controller moves avatar")
	check(visual.current_motion=="run","fast motion follows actual movement")
	camera.look_at_from_position(actor.position+Vector3(42,18,48),actor.position+Vector3(0,13,0));await shot("hoshi-original-run")
	await frames(45);check(visual.current_motion=="idle","stop crossfades to idle")
	var key:=InputEventKey.new();key.physical_keycode=KEY_SHIFT;key.pressed=true;Input.parse_input_event(key);await frames(2)
	Input.action_press("move_north");before=actor.position
	await frames(40);Input.action_release("move_north")
	check(visual.current_motion=="walk","Shift selects walking")
	var distance:=actor.position.distance_to(before);check(distance>8 and distance<18,"walking speed uses existing collision movement")
	key=InputEventKey.new();key.physical_keycode=KEY_SHIFT;key.pressed=false;Input.parse_input_event(key)
	camera.look_at_from_position(actor.position+Vector3(42,18,48),actor.position+Vector3(0,13,0));await shot("hoshi-original-walk")
	actor.controlled_hero_id="mira";actor._refresh_active_visual()
	check(not visual.visible and actor.get_node("Viz").visible,"other hero keeps its placeholder")
	check(is_equal_approx(actor.get_node("Shape").shape.height,24.0),"other hero capsule restored")
	actor.controlled_hero_id="protagonist";actor._refresh_active_visual()
	check(visual.visible and not actor.get_node("Viz").visible,"Hoshi restored when returning to leader")
	for i in rests.size():check(visual.skeleton.get_bone_rest(i)==rests[i],"rest transform unchanged")
	check(absf(actor.position.y)<0.12,"controller retains floor contact")
	var f:=FileAccess.open(out.path_join("player-checks.json"),FileAccess.WRITE);f.store_string(JSON.stringify({"pass":errors.is_empty(),"errors":errors,"height_m":visual.height_m,"bones":rests.size(),"walking_distance":distance},"  "));f.close()
	print("HOSHI_PLAYER ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}));quit(0 if errors.is_empty() else 1)
