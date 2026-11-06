extends SceneTree
## Real main-map capture and card/atlas binding regression. No authored writes.
const Fixture=preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
const Patch=preload("res://scripts/ember_grass_patch.gd")
var scene:Node3D
var map:EmberMapLoader
var camera:Camera3D
var output:="D:/aion2-grass-study-2026-10-26/main-map"
var errors:Array[String]=[]
var ordinary:Array[Node]=[]
func _init()->void:
	if not OS.get_environment("EMBER_GRASS_CAPTURE_DIR").is_empty():output=OS.get_environment("EMBER_GRASS_CAPTURE_DIR")
	DirAccess.make_dir_recursive_absolute(output)
	Fixture.prepare(self,"user://ember-tests/grass-cards-main-"+str(OS.get_process_id()))
	run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("GRASS_CARDS_FAIL ",label)
func settle()->bool:
	# Full cold source/scatter preparation exceeded 180s with continuous progress.
	var deadline:=Time.get_ticks_msec()+360000
	var last:=Time.get_ticks_msec()
	while Time.get_ticks_msec()<deadline:
		var projection=map._visual_surface_projection
		var busy:bool=projection==null
		if projection!=null:busy=projection.pending_tile_count()>0 or not projection._look_pending.is_empty()
		for p in ordinary:busy=busy or p.detail_preparation_pending()
		if not busy:return true
		if Time.get_ticks_msec()-last>20000:
			var ready:=0
			for p in ordinary:
				if not p.detail_preparation_pending():ready+=1
			print("GRASS_CARDS_WAIT ",scene._startup_status()," ready=",ready,"/",ordinary.size());last=Time.get_ticks_msec()
		await process_frame
	check(false,"main terrain and ordinary grass settle");return false
func capture(label:String)->void:
	for i in 20:await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label+".png"))==OK,"capture "+label)
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	DisplayServer.window_set_size(Vector2i(1440,900));Engine.max_fps=30
	scene=load("res://scenes/landscape_compact.tscn").instantiate()
	scene.sandbox_storage_root="user://ember-tests/grass-cards-main-"+str(OS.get_process_id())
	map=scene.get_node("Map")
	# The separately deferred 18m sphere preparation is unrelated to this gate.
	# Disable it only in this in-memory capture; never save the scene.
	map.get_node("WorldAnomaly").enabled=false
	root.add_child(scene);current_scene=scene
	for p in get_nodes_in_group(&"ember_grass_patches"):
		if map.is_ancestor_of(p) and p.detail_kind==0:ordinary.append(p)
	check(not ordinary.is_empty(),"main scene contains ordinary grass")
	if not await settle():quit(1);return
	var deadline:=Time.get_ticks_msec()+180000
	while not scene._startup_complete and Time.get_ticks_msec()<deadline:await process_frame
	check(scene._startup_complete,"actual main-map startup")
	if not scene._startup_complete:quit(1);return
	scene._player.set_physics_process(false);scene._party_followers.set_physics_process(false)
	scene.get_node("CanvasLayer").hide()
	await capture("main-game-camera")
	var total:=0;var populated:=0;var target:Node;var count:=0
	var buffers:Dictionary={}
	var authored:Dictionary={}
	for p in ordinary:
		authored[str(p.get_path())]=hash([p.density_mask,p.size_blocks,p.scatter_seed,p.tuft_size,p.tufts_per_block,p.global_transform])
		if p._visual==null:continue
		var mm:MultiMesh=p._visual.multimesh
		if mm==null:continue
		total+=mm.instance_count
		if mm.instance_count==0:continue
		populated+=1;buffers[str(p.get_path())]=mm.buffer
		if mm.instance_count>count:target=p;count=mm.instance_count
		var material:ShaderMaterial=p._visual.material_override
		check(material.get_shader_parameter("flower_atlas")==Patch.GRASS_CARD_ATLAS,"main patch binds accepted atlas")
		check(material.get_shader_parameter("flower_palette_slot")==float(map._visual_surface_projection.document.palette_surface_roles.find("grass")),"main palette slot")
		check(mm.mesh==Patch.grass_render_mesh(),"main detailed tuft uses shared native LOD contour")
		check(mm.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size()==24,"main detailed tuft has 8 triangles")
		var uv:PackedVector2Array=mm.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		check(uv==Patch.GRASS_CARD_MESH.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV],"local artwork UV survives palette binding")
	check(total>1000 and populated>0,"real map has substantial grass coverage")
	if target==null:quit(1);return
	print("GRASS_CARDS_MAIN_READY patches=",ordinary.size()," populated=",populated," tufts=",total)
	var gameplay_camera:=root.get_camera_3d()
	camera=Camera3D.new();camera.far=4000;camera.fov=58;scene.add_child(camera);camera.make_current()
	var mm:MultiMesh=target._visual.multimesh
	var focus:=Vector3.ZERO
	for i in mm.instance_count:focus+=target._visual.to_global(mm.get_instance_transform(i).origin)
	focus/=mm.instance_count
	camera.look_at_from_position(focus+Vector3(110,90,150),focus);await capture("main-grass-overview")
	camera.look_at_from_position(focus+Vector3(25,12,40),focus);await capture("main-grass-close")
	for i in 30:
		camera.position.x+=0.18;await process_frame
	await capture("main-grass-motion")
	var harvest:Node3D=map.get_node("Props/CuttableGrass")
	check(harvest.get_node("PileVisual").cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON,"main high grass keeps shadows")
	var harvest_focus:=harvest.global_position+Vector3.UP*8.0
	camera.look_at_from_position(harvest_focus+Vector3(-54,40,30),harvest_focus)
	await capture("main-cuttable-contour")
	# Capturing other areas changes residency. Compare return buffers at the
	# original gameplay view, rather than treating newly resident patches as loss.
	gameplay_camera.make_current()
	if not await settle():quit(1);return
	for look in [1,2,0]:
		for p in ordinary:p.set_world_look(look)
		if not await settle():break
		for p in ordinary:
			if p._visual==null or p._visual.multimesh==null or p._visual.multimesh.instance_count==0:continue
			var mat:ShaderMaterial=p._visual.material_override
			if look==0:
				check(mat.get_shader_parameter("flower_atlas")==Patch.GRASS_CARD_ATLAS,"detailed material restored")
				if buffers.has(str(p.get_path())):
					check(p._visual.multimesh.buffer==buffers[str(p.get_path())],"scatter return exact "+str(p.get_path()))
			else:check(not mat.shader.code.contains("#define EMBER_FLOWER_COVER"),"other looks retain opaque grass")
	for p in ordinary:
		check(authored[str(p.get_path())]==hash([p.density_mask,p.size_blocks,p.scatter_seed,p.tuft_size,p.tufts_per_block,p.global_transform]),"authored density and placement retained")
	var result={"pass":errors.is_empty(),"errors":errors,"ordinary_patches":ordinary.size(),"populated_patches":populated,"grass_instances":total,"scene":"landscape_compact","card_triangles":8,"author_visual_acceptance":"OPEN","anomaly":"disabled only in this capture; saved scene unchanged"}
	var f:=FileAccess.open(output.path_join("main-checks.json"),FileAccess.WRITE);f.store_string(JSON.stringify(result,"  "));f.close()
	print("GRASS_CARDS_MAIN ",JSON.stringify(result));quit(0 if errors.is_empty() else 1)
