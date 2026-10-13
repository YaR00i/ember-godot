extends SceneTree
var scene
var output: String
var records: Array=[]
var errors: Array[String]=[]
func _initialize() -> void:run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok:errors.append(message);printerr("FAIL ",message)
func frames(count: int) -> void:
	for i in count:await process_frame
	await RenderingServer.frame_post_draw
func capture(name: String) -> Image:
	await frames(5)
	var image:=root.get_texture().get_image()
	check(image.save_png(output.path_join(name+".png"))==OK,"capture "+name)
	return image
func different_pixels(a: Image,b: Image,region: Rect2i) -> int:
	var count:=0
	for y in range(region.position.y,region.end.y):
		for x in range(region.position.x,region.end.x):
			if a.get_pixel(x,y)!=b.get_pixel(x,y):count+=1
	return count
func depth_delta(a: Image,b: Image,region: Rect2i) -> float:
	var maximum:=0.0
	for y in range(region.position.y,region.end.y):
		for x in range(region.position.x,region.end.x):
			var ca:=a.get_pixel(x,y);var cb:=b.get_pixel(x,y)
			var va:=roundi(ca.r*255)*65536+roundi(ca.g*255)*256+roundi(ca.b*255)
			var vb:=roundi(cb.r*255)*65536+roundi(cb.g*255)*256+roundi(cb.b*255)
			maximum=maxf(maximum,absf(va-vb)/100000.0)
	return maximum
func metrics(label: String,enabled: bool,amount: float) -> void:
	scene.amplitude_m=amount;scene.set_depth(enabled)
	await frames(45)
	var gpu: Array[float]=[];var cpu: Array[float]=[];var wall: Array[float]=[]
	for i in 120:
		var start:=Time.get_ticks_usec();await process_frame
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
		wall.append((Time.get_ticks_usec()-start)/1000.0)
	gpu.sort();cpu.sort();wall.sort()
	records.append({"label":label,"gpu_median_ms":gpu[60],"gpu_p95_ms":gpu[114],"cpu_median_ms":cpu[60],"wall_median_ms":wall[60],"samples":120,"vram_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"texture_builds":scene.texture_build_count})
func texture_probe(periodic: bool) -> float:
	# Run the actual shared height query on GPU. Top and new 16x taller side
	# must agree with direct periodic sampling at the current world position.
	var viewport:=SubViewport.new();viewport.size=Vector2i(256,64);viewport.disable_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var rect:=ColorRect.new();rect.size=Vector2(256,64);viewport.add_child(rect)
	var material:=ShaderMaterial.new();var shader:=Shader.new()
	shader.code="shader_type canvas_item; render_mode unshaded; uniform sampler2D png_lookup : filter_nearest, repeat_disable; vec3 slot_albedo_at(int slot,vec3 p,vec3 n){return vec3(0.0);}\n#include \"res://shaders/ember_material_texture_mapping.gdshaderinc\"\n#include \"res://shaders/ember_terrain_material_depth.gdshaderinc\"\nvoid fragment(){material_depth_lod=0.0; bool side=UV.y>0.5; vec3 p=side?vec3(0.0,UV.x*14.4,UV.y*0.9):vec3(UV.x*0.9,0.0,UV.y*0.9);vec3 n=ember_texture_surface_normal(p,vec3(0,1,0));vec2 uv=side?p.zy/0.9:p.xz/0.9;float actual=material_depth_height_at(p,n);float expected=textureLod(material_depth_height,uv,0.0).r;COLOR=vec4(abs(actual-expected)*100.0,0.0,0.0,1.0);}"
	material.shader=shader;rect.material=material
	var lookup:=Image.create(256,1,false,Image.FORMAT_RGBAF);lookup.set_pixel(1,0,Color(1,0.9,4,1 if periodic else 0))
	var coverage:=Image.create(1,1,false,Image.FORMAT_RF);coverage.fill(Color(1,0,0))
	material.set_shader_parameter("png_lookup",ImageTexture.create_from_image(lookup))
	material.set_shader_parameter("material_depth_height",scene.height_texture)
	material.set_shader_parameter("material_depth_coverage",ImageTexture.create_from_image(coverage))
	await frames(5)
	var image:=viewport.get_texture().get_image();var maximum:=0.0
	for y in image.get_height():
		for x in image.get_width():maximum=maxf(maximum,image.get_pixel(x,y).r)
	image.save_png(output.path_join("texture-probe-"+("periodic" if periodic else "legacy")+".png"))
	viewport.queue_free();await frames(2);return maximum
func run() -> void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	scene=load("res://scenes/compact_material_depth_study.tscn").instantiate();root.add_child(scene);current_scene=scene
	var deadline:=Time.get_ticks_msec()+60000
	while not scene.ready_for_depth and Time.get_ticks_msec()<deadline:await process_frame
	check(scene.ready_for_depth,"study ready");if not scene.ready_for_depth:quit(1);return
	var negative_texture_error:=await texture_probe(false)
	var periodic_texture_error:=await texture_probe(true)
	check(negative_texture_error>0.1,"texture probe detects the old seam defect")
	check(periodic_texture_error<0.001,"actual GPU height query preserves periodic top and current side scale")
	scene.get_node("Instructions").hide()
	scene._projection._water_material.set_shader_parameter("preview_time",0.0)
	var camera: Camera3D=scene.get_node("Camera3D");camera.make_current()
	var views:={
		"overview":[Vector3(6.5,5,7.5),Vector3(2.4,1.15,2)],
		"close":[Vector3(2.1,1.94,2.8),Vector3(1.85,1.49,1.85)],
		"transition":[Vector3(4.2,2.3,3.3),Vector3(2.75,1.22,2.0)],
		"seam":[Vector3(4.0,2.0,3.3),Vector3(4.0,1.02,2.0)],
		"edge":[Vector3(-1.45,1.25,2.8),Vector3(0.02,0.85,1.9)],
		"grazing":[Vector3(2.0,1.65,3.4),Vector3(1.75,1.48,1.25)],
		"shore":[Vector3(5.9,2.4,4.8),Vector3(4.3,1.1,3.45)],
		"distant":[Vector3(15.0,10.0,16.0),Vector3(2.4,1.1,2.0)]
	}
	var unchanged_shore:=false;var unchanged_zero:=false
	var water_differences:=-1;var depth_differences:=-1
	var maximum_depth_delta:=-1.0
	for name: String in views:
		camera.look_at_from_position(views[name][0],views[name][1])
		scene.set_depth(false);var a:=await capture(name+"-a")
		scene.set_depth(true);var b:=await capture(name+"-b")
		if name=="shore":
			unchanged_shore=a.get_data()==b.get_data()
			var point:=camera.unproject_position(Vector3(4.35,1.125,3.55))
			var region:=Rect2i(Vector2i(point)-Vector2i(28,18),Vector2i(56,36))
			water_differences=different_pixels(a,b,region)
			var probe:=MeshInstance3D.new();var quad:=QuadMesh.new();quad.size=Vector2(2,2);probe.mesh=quad;probe.extra_cull_margin=1024.0
			var material:=ShaderMaterial.new();var shader:=Shader.new()
			shader.code="shader_type spatial; render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled; uniform sampler2D depth_image : hint_depth_texture, filter_nearest; void vertex(){POSITION=vec4(VERTEX.xy,1.0,1.0);} void fragment(){float d=textureLod(depth_image,SCREEN_UV,0.0).r; vec4 p=INV_PROJECTION_MATRIX*vec4(SCREEN_UV*2.0-1.0,d,1.0); uint bits=uint(round(clamp(-p.z/p.w,0.0,160.0)*100000.0));vec3 c=vec3(float((bits>>16u)&255u),float((bits>>8u)&255u),float(bits&255u))/255.0; ALBEDO=mix(c/12.92,pow((c+0.055)/1.055,vec3(2.4)),step(vec3(0.04045),c));}"
			material.shader=shader;material.render_priority=127;probe.material_override=material;camera.add_child(probe)
			var environment: Environment=scene.get_node("Map/Look/WorldEnvironment").environment
			var previous_tonemap:=environment.tonemap_mode;environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR
			scene.set_depth(false);var depth_a:=await capture("shore-depth-a")
			scene.set_depth(true);var depth_b:=await capture("shore-depth-b")
			depth_differences=different_pixels(depth_a,depth_b,region)
			maximum_depth_delta=depth_delta(depth_a,depth_b,region)
			environment.tonemap_mode=previous_tonemap;probe.queue_free();await frames(3)
		if name=="close":
			scene.amplitude_m=0.0;scene.apply_depth();var zero:=await capture("close-zero")
			unchanged_zero=a.get_data()==zero.get_data();scene.amplitude_m=0.04;scene.apply_depth()
	for phase in [0.25,0.5,0.75,1.0]:
		scene.set_phase(phase);await frames(6)
		camera.look_at_from_position(views.overview[0],views.overview[1])
		for enabled in [false,true]:
			scene.set_depth(enabled);await capture("morph-%d-%s"%[roundi(phase*100),"b" if enabled else "a"])
			if phase==0.5 or phase==1.0:await capture("phase-%d-%s"%[roundi(phase*2),"b" if enabled else "a"])
	scene.set_phase(0.0)
	for enabled in [false,true]:
		scene.set_depth(enabled)
		for i in 12:
			var offset:=Vector3(0.6*sin(i*0.12-0.65),0.0,0.15*cos(i*0.12-0.65))
			camera.look_at_from_position(views.close[0]+offset,views.close[1]);await capture("motion-%s-%02d"%["b" if enabled else "a",i])
	# Separate timing run: GPU/CPU queries, 1080p, 120 FPS cap, VSync disabled.
	# Wall time is reported as pacing evidence, never substituted for GPU cost.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=120
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	for name in ["overview","close"]:
		camera.look_at_from_position(views[name][0],views[name][1])
		await metrics(name+"-a1",false,0.04)
		await metrics(name+"-b1",true,0.04)
		await metrics(name+"-a2",false,0.04)
		await metrics(name+"-b2",true,0.04)
		if name=="close":
			scene.steps=16;await metrics("close-b-16-steps",true,0.04);scene.steps=32
	Engine.max_fps=30
	check(water_differences==0,"test water pixels unchanged by material depth")
	check(maximum_depth_delta<=0.0001,"ground depth under test water stable within 0.1 mm")
	var report:={"resolution":"1920x1080","capture_cap":30,"measurement_cap":120,"measurement_vsync":false,"renderer":RenderingServer.get_rendering_device().get_device_name(),"measurements":records,"zero_matches_baseline":unchanged_zero,"shore_full_frame_matches":unchanged_shore,"water_roi_different_pixels":water_differences,"water_roi_pixels":2016,"ground_depth_roi_different_pixels":depth_differences,"ground_depth_max_difference_m":maximum_depth_delta,"source_immutable":scene.get_node("Map").compact_terrain.same_terrain_data(load("res://content/world_terrains/material_depth_study.res")),"height_bytes_with_mips":scene.height_texture.get_image().get_data_size(),"coverage_bytes":scene.coverage_image.get_data_size(),"reference_attribute_bytes":scene.reference_attribute_bytes,"errors":errors}
	report["texture_probe_legacy_max_error"]=negative_texture_error
	report["texture_probe_periodic_max_error"]=periodic_texture_error
	var file:=FileAccess.open(output.path_join("native.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	check(unchanged_zero,"native zero amplitude matches A exactly")
	print("MATERIAL_DEPTH_NATIVE ","PASS" if errors.is_empty() else errors," zero=",unchanged_zero," shore=",unchanged_shore)
	scene.queue_free();await process_frame;await process_frame;quit(0 if errors.is_empty() else 1)
