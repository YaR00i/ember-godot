extends SceneTree
## Fresh process: ordinary editor-published Sources/prefabs, no Recipe/LAB scene.
var errors: Array[String]=[]
func _initialize() -> void:run.call_deferred()
func check(value: bool,message: String) -> void:
	if not value:errors.append(message);push_error(message)
func run() -> void:
	var output:=OS.get_cmdline_user_args()[0]
	var ids: Array=[]
	if OS.get_cmdline_user_args().has("--bases"):ids.assign(preload("res://tools/build_painted_tree_library.gd").IDS)
	else:
		var file:=FileAccess.open(output.path_join("editor-library.var"),FileAccess.READ)
		check(file!=null,"native editor library manifest")
		if file==null:quit(1);return
		ids=file.get_var();file.close()
	var stage:=Node3D.new();stage.name="SavedTreesRuntime";root.add_child(stage);current_scene=stage
	var signatures: Array=[];var centres: Array[Vector3]=[]
	for kind in ids.size():
		var id: String=ids[kind]
		var source: EmberVoxelModelResource=load("res://content/voxel_models/"+id+".tres")
		var packed: PackedScene=EmberVoxelPrefab.ensure_saved(id,1.0,{}) if OS.get_cmdline_user_args().has("--bases") else load(EmberVoxelPrefab.PREFAB_DIR.path_join(id+".tscn"))
		check(source!=null and packed!=null,"published source/prefab exists")
		if source==null or packed==null:continue
		var accepted: Array[String]=["b2c04fd021ae17c0bc30387743ff6803e1ff84ebcdead5f5b5a94ba8eeac8497","b6009b88304c8f92621b2d7b88f524fba5512da83d64aad5cf5113cc2d6115bf","eb98aaa7043c412e3ecdf9fc611fb32bbc261230d2c42a2f29be6c74bd2fffde","fc3b1683cb56bd32f6248e7303c0f6479f07c47f092cd4f19762af5130a305d8","4d4733cf999f18c7734801bce185a7a82809eebd83eb8f0694c005e251140249"]
		check(source.voxels.hex_encode().sha256_text()==accepted[kind],"canonical library uses accepted Source "+str(kind))
		var prop:=packed.instantiate() as EmberVoxelProp;stage.add_child(prop);prop.owner=stage
		prop.configure_voxel_scale(16,1.0);prop.position=Vector3(kind*8,0,0)
		var mesh: ArrayMesh=prop.get_node("Mesh").mesh
		check(mesh.get_surface_count()==2 and mesh.surface_get_name(1)=="tree_leaves","runtime includes species foliage")
		if kind==1:
			var bark: ShaderMaterial=mesh.surface_get_material(0)
			var accepted_bark: Texture2D=load("res://scripts/ember_tree_bark_surface.gd").artwork("res://content/material_studies/trees/bark_species_v1/oak-v3-painted.png")
			check(bark.get_shader_parameter("painted_bark_albedo").get_image().get_data()==accepted_bark.get_image().get_data(),"fresh runtime oak uses accepted B and exact mipmaps")
			check(not bark.shader.code.contains("define EMBER_OBJECT_PAINTED_BARK_RELIEF_STUDY"),"bark relief stays in LAB")
		check(prop.get_node("Mesh").position==Vector3.ZERO,"support mesh uses the trunk-centred frame")
		var rebuilt:=EmberVoxelPrefab.prepare_resource(source).instantiate()
		for surface in 2:
			check(mesh.surface_get_arrays(surface)==rebuilt.get_node("Mesh").mesh.surface_get_arrays(surface),"cold Source rebuild agrees with editor prefab %d/%d"%[kind,surface])
		rebuilt.free();signatures.append(hash(mesh.surface_get_arrays(1)))
		for line: Dictionary in source.tree_surface.structure.lines:
			if line.physical and line.r0>1.0:
				centres.append(prop.position+(line.start.lerp(line.finish,0.5)+Vector3(source.tree_surface.pivot.x,0,source.tree_surface.pivot.y))/16.0);break
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-40,0);sun.shadow_enabled=true;stage.add_child(sun);sun.owner=stage
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color("648b9e");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color("b4cddc");environment.environment.ambient_light_energy=0.55
	stage.add_child(environment);environment.owner=stage
	var camera:=Camera3D.new();stage.add_child(camera);camera.owner=stage;camera.position=Vector3(16,10,39);camera.look_at(Vector3(16,3,0));camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=24;camera.current=true
	await physics_frame;await physics_frame
	check(centres.size()==5,"five physical trunk anchors")
	for centre in centres:
		var query:=PhysicsRayQueryParameters3D.create(centre-Vector3(2,0,0),centre+Vector3(2,0,0))
		check(not stage.get_world_3d().direct_space_state.intersect_ray(query).is_empty(),"visible trunk overlaps its wood collision")
	for frame in 8:await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join("runtime-library.png"))==OK,"fresh runtime gallery")
	var map:=PackedScene.new();check(map.pack(stage)==OK,"runtime fixture map pack")
	check(ResourceSaver.save(map,"user://painted-tree-runtime-map.tscn")==OK,"runtime fixture map save")
	stage.free()
	var reopened: PackedScene=ResourceLoader.load("user://painted-tree-runtime-map.tscn","",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var restored:=reopened.instantiate();root.add_child(restored);current_scene=restored
	for kind in 5:check(hash(restored.get_child(kind).get_node("Mesh").mesh.surface_get_arrays(1))==signatures[kind],"saved map preserves full tree appearance "+str(kind))
	var result:=FileAccess.open(output.path_join("runtime.json"),FileAccess.WRITE);result.store_string(JSON.stringify({"pass":errors.is_empty(),"errors":errors,"species":ids.size(),"recipes_evaluated":false},"\t"));result.close()
	print("PAINTED_TREE_RUNTIME ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)
