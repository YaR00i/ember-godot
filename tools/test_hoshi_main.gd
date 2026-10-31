extends SceneTree
const Fixture=preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
var out:="D:/hoshi-ember-2026-10-27"
var errors:Array[String]=[]
func _init()->void:
	Fixture.prepare(self,"user://ember-tests/hoshi-main-"+str(OS.get_process_id()))
	run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("HOSHI_MAIN_FAIL ",label)
func frames(n:int)->void:
	for i in n:await physics_frame
func shot(label:String)->void:
	for i in 15:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(label+".png"))
func run()->void:
	Engine.max_fps=30
	var scene=load("res://scenes/landscape_compact.tscn").instantiate()
	scene.sandbox_storage_root="user://ember-tests/hoshi-main-"+str(OS.get_process_id())
	check(scene.hoshi_test_character,"saved main enables original Hoshi")
	var map:EmberMapLoader=scene.get_node("Map");map.get_node("WorldAnomaly").enabled=false
	root.add_child(scene);current_scene=scene
	var deadline:=Time.get_ticks_msec()+360000;var last:=Time.get_ticks_msec()
	while not scene._startup_complete and Time.get_ticks_msec()<deadline:
		if Time.get_ticks_msec()-last>25000:print("HOSHI_MAIN_WAIT ",scene._startup_status());last=Time.get_ticks_msec()
		await process_frame
	check(scene._startup_complete,"normal main map startup")
	if not scene._startup_complete:quit(1);return
	var actor:EmberPlayer=scene._player
	check(is_instance_valid(actor._hoshi_visual) and actor._hoshi_visual.loaded,"Hoshi installed through main startup")
	var grass_ready:=false
	while not grass_ready and Time.get_ticks_msec()<deadline:
		grass_ready=true
		for p in get_nodes_in_group(&"ember_grass_patches"):
			if map.is_ancestor_of(p):grass_ready=grass_ready and not p._dirty and not p._rebuilding
		await process_frame
	check(grass_ready,"full authored detail coverage prepared")
	scene.get_node("CanvasLayer").hide();await shot("hoshi-main-gameplay")
	var camera:=Camera3D.new();camera.far=4000;camera.fov=38;scene.add_child(camera);camera.make_current()
	camera.look_at_from_position(actor.global_position+Vector3(-38,22,68),actor.global_position+Vector3(0,13,0));await shot("hoshi-main-front")
	if "--portrait-only" in OS.get_cmdline_user_args():quit();return
	Input.action_press("move_east");var start:=actor.global_position
	await frames(35);Input.action_release("move_east")
	check(actor.global_position.distance_to(start)>8,"walking controller moves real map avatar")
	camera.look_at_from_position(actor.global_position+Vector3(42,22,68),actor.global_position+Vector3(0,13,0));await shot("hoshi-main-moving")
	await frames(30)
	actor.inventory_ui.toggle();await frames(3);start=actor.global_position
	Input.action_press("move_east");await frames(12);Input.action_release("move_east")
	check(actor.global_position.distance_to(start)<0.5,"existing inventory blocks movement")
	actor.inventory_ui.toggle();await frames(3)
	actor.cycle_controlled_hero();await frames(5);check(not actor._hoshi_visual.visible,"party switch keeps other hero view")
	actor.cycle_controlled_hero();await frames(5);check(actor._hoshi_visual.visible,"party switch restores Hoshi test view")
	var f:=FileAccess.open(out.path_join("main-checks.json"),FileAccess.WRITE);f.store_string(JSON.stringify({"pass":errors.is_empty(),"errors":errors,"main":"landscape_compact","original_source":"Hoshi Companion Hoshi_v1.vrm","sphere":"disabled in capture RAM only","manual_motion_acceptance":"OPEN"},"  "));f.close()
	print("HOSHI_MAIN ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}));quit(0 if errors.is_empty() else 1)
