extends SceneTree
const Visual=preload("res://scripts/ember_hoshi_visual.gd")
var out:="D:/hoshi-world-toon-2026-10-27"
func _init()->void:run.call_deferred()
func image_after()->Image:
	for i in 12:await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func luminance(image:Image)->float:
	var total:=0.0
	# Same fixed model/camera; black background and no visible blocker geometry.
	for y in range(180,850,3):
		for x in range(570,1030,3):total+=image.get_pixel(x,y).get_luminance()
	return total/(224.0*154.0)
func run()->void:
	DirAccess.make_dir_recursive_absolute(out);Engine.max_fps=30
	var world:=Node3D.new();root.add_child(world);current_scene=world
	var env:=WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color.BLACK
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color(0.58,0.67,0.85);env.environment.ambient_light_energy=0.45;world.add_child(env)
	var actor:=CharacterBody3D.new();world.add_child(actor)
	var visual:=Visual.new();actor.add_child(visual);assert(visual.setup(actor,16.0))
	visual.set_process(false);visual.motion.pause()
	var sun:=DirectionalLight3D.new();sun.rotation_degrees.x=-90;sun.light_energy=1.3
	sun.shadow_enabled=true;sun.directional_shadow_max_distance=200;world.add_child(sun)
	var blocker:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(50,2,50)
	blocker.mesh=box;blocker.position=Vector3(0,40,0);world.add_child(blocker)
	var camera:=Camera3D.new();camera.fov=32;camera.far=300;world.add_child(camera)
	camera.look_at_from_position(Vector3(18,20,62),Vector3(0,13,0));camera.make_current()
	blocker.visible=false;var lit:=await image_after();lit.save_png(out.path_join("fixture-lit.png"))
	blocker.visible=true;var shade:=await image_after();shade.save_png(out.path_join("fixture-shadow.png"))
	var bright:=luminance(lit);var dark:=luminance(shade)
	# Negative control must fail the same shadow-reception criterion.
	var bypass:=Shader.new();bypass.code=load("res://shaders/ember_hoshi_toon.gdshader").code.replace(" * ATTENUATION *"," * 1.0 *")
	for mat in visual.toon:mat.shader=bypass
	var negative_dark:=luminance(await image_after())
	blocker.visible=false;var negative_bright:=luminance(await image_after())
	var passed:=bright-dark>0.012 and absf(negative_bright-negative_dark)<0.003
	var report:={"pass":passed,"lit":bright,"shadow":dark,"drop":bright-dark,"negative_drop":negative_bright-negative_dark}
	var f:=FileAccess.open(out.path_join("checks.json"),FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "))
	print("HOSHI_WORLD_LIGHT ",JSON.stringify(report));quit(0 if passed else 1)
