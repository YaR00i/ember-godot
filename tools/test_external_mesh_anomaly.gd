extends SceneTree
## One published external rock, real sphere preparation and Forward+ rendering.
## Uses an existing small terrain fixture in memory; never saves authored data.
const Correspondence = preload("res://scripts/ember_anomaly_correspondence.gd")
const External = preload("res://scripts/ember_external_mesh_surface.gd")
var errors: Array[String] = []
var output := "user://ember-tests/external-anomaly"
var scene: Node3D
var map: EmberMapLoader
var sphere: Node3D
var prop: EmberVoxelProp
var camera: Camera3D
var material_hash: int

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok: errors.append(label); printerr("FAIL ",label)
func frames(count: int) -> void:
	for frame in count: await process_frame
func capture(label: String) -> Image:
	await frames(8); await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(output.path_join(label+".png"))
	return image
func settle() -> void:
	var until := Time.get_ticks_msec()+90000
	while not sphere._prepared and Time.get_ticks_msec()<until:await process_frame
	check(sphere._prepared,"sphere prepared")

func image_error(a: Image, b: Image) -> float:
	var total:=0.0
	for y in a.get_height():
		for x in a.get_width():
			var p:=a.get_pixel(x,y);var q:=b.get_pixel(x,y)
			total+=absf(p.r-q.r)+absf(p.g-q.g)+absf(p.b-q.b)
	return total/(a.get_width()*a.get_height()*3.0)

func surface_light(binding: Dictionary) -> float:
	# Independently freeze the displayed geometry; lighting and cast shadows
	# must agree with the GPU morph. Isolate pigment and texel-light filtering.
	var display:MeshInstance3D=binding.visual
	var mesh:ArrayMesh=display.mesh;var material:ShaderMaterial=display.get_active_material(0)
	var test:ShaderMaterial=material.duplicate();test.set_shader_parameter("has_albedo_texture",false)
	test.set_shader_parameter("albedo",Color(0.5,0.5,0.5));test.set_shader_parameter("voxel_light_anomaly",false)
	var palette:=Image.create(256,1,false,Image.FORMAT_RGBAF);palette.fill(Color(0.214041,0.214041,0.214041))
	test.set_shader_parameter("palette_color_lookup",ImageTexture.create_from_image(palette))
	display.set_surface_override_material(0,test)
	var gpu:=await capture("light-gpu")
	var arrays:=mesh.surface_get_arrays(0)
	var positions:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var targets:Image=(test.get_shader_parameter("ember_anomaly_targets") as Texture2D).get_image()
	var radius:float=sphere.radius_m*map.imported_tile_size;var band:float=sphere.feather_m*map.imported_tile_size
	for i in positions.size():
		var weight:=1.0-smoothstep(radius-band*0.5,radius+band*0.5,(display.global_transform*positions[i]).distance_to(sphere.global_position))
		var index:=i*4+2;var p:=targets.get_pixel(index%Correspondence.WIDTH,index/Correspondence.WIDTH)
		var n:=targets.get_pixel((index+1)%Correspondence.WIDTH,(index+1)/Correspondence.WIDTH)
		positions[i]=positions[i].lerp(Vector3(p.r,p.g,p.b),weight)
		normals[i]=normals[i].lerp(Vector3(n.r,n.g,n.b),weight).normalized()
	arrays[Mesh.ARRAY_VERTEX]=positions;arrays[Mesh.ARRAY_NORMAL]=normals
	var baked:=ArrayMesh.new();baked.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},mesh.surface_get_format(0))
	display.mesh=baked
	# Constant pigment removes dependence on the pre-morph reference position.
	test.set_shader_parameter("ember_anomaly_prepared",false)
	var cpu:=await capture("light-baked")
	var difference:=image_error(gpu,cpu)
	display.mesh=mesh;display.set_surface_override_material(0,material)
	check(difference<0.0003,"GPU morph and frozen surface share lighting/shadows")
	return difference

func run() -> void:
	if DisplayServer.get_name()=="headless":printerr("Forward+ required");quit(2);return
	if not OS.get_cmdline_user_args().is_empty():output=OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	Engine.max_fps=30; DisplayServer.window_set_size(Vector2i(1100,800)); root.size=Vector2i(1100,800)
	scene=Node3D.new();root.add_child(scene);current_scene=scene
	map=EmberMapLoader.new();map.name="Map";map.world_look=0;map.compact_ground_style=1
	var terrain:=EmberTerrainPilotResource.new();terrain.width=4;terrain.depth=4
	terrain.palette=PackedColorArray([Color.TRANSPARENT,Color(0.4,0.35,0.25)])
	terrain.palette_surface_roles=PackedStringArray(["",""]);terrain.palette_material_ids=PackedStringArray(["",""])
	for key in ["heights","top_materials","base_materials","cap_depths","water_levels","water_materials"]:terrain.get(key).resize(16)
	terrain.heights.fill(1);terrain.top_materials.fill(1);terrain.base_materials.fill(1);terrain.cap_depths.fill(1)
	map.compact_terrain=terrain
	prop=load("res://prefabs/voxels/vox_external_coastal_rock.tscn").instantiate()
	prop.position=Vector3(-40,15,862);map.add_child(prop)
	var main_text:=FileAccess.get_file_as_string("res://scenes/landscape_compact.tscn")
	check('name="ExternalCoastalRock"' in main_text and 'path="res://prefabs/voxels/vox_external_coastal_rock.tscn"' in main_text,"published rock on main map")
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-40,-40,0);sun.shadow_enabled=true;sun.directional_shadow_max_distance=600;sun.light_angular_distance=0;scene.add_child(sun)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(0.16,0.2,0.23)
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE
	environment.environment.ambient_light_energy=0.5;environment.environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR;scene.add_child(environment)
	sphere=load("res://scripts/ember_world_anomaly_3d.gd").new();sphere.enabled=false;sphere.name="WorldAnomaly";map.add_child(sphere)
	scene.add_child(map)
	var projection:Node=map._visual_surface_projection
	while projection.pending_tile_count()>0 or not projection._look_pending.is_empty() or projection.pending_runtime_lod_count()>0:await process_frame
	var visual:MeshInstance3D=prop.get_node("Mesh")
	var detailed:ArrayMesh=visual.mesh
	var original:StandardMaterial3D=visual.get_active_material(0)
	var original_hash:=FileAccess.get_sha256("res://content/mesh_models/coastal_rock/source.glb")
	var original_texture:Texture2D=original.albedo_texture
	var collider:Shape3D=prop.get_node("Collision/Shape").shape
	var centre:Vector3=visual.global_transform*detailed.get_aabb().get_center()
	var floor_plane:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(260,260);floor_plane.mesh=plane
	var floor_material:=StandardMaterial3D.new();floor_material.albedo_color=Color(0.32,0.37,0.2);floor_plane.material_override=floor_material
	floor_plane.position=Vector3(centre.x,prop.position.y-0.1,centre.z);scene.add_child(floor_plane)
	camera=Camera3D.new();scene.add_child(camera);camera.fov=40;camera.far=1500;camera.make_current()
	camera.look_at_from_position(centre+Vector3(88,52,95),centre)
	var original_image:=await capture("original")
	prop.set_world_look(2);var voxel_material:ShaderMaterial=visual.get_active_material(0);prop.set_world_look(0)
	visual.material_override=External.anomaly_material(original,voxel_material)
	var adapted_image:=await capture("material-adapter")
	var adapter_error:=image_error(original_image,adapted_image)
	check(adapter_error<0.001,"adapter retains StandardMaterial appearance on original geometry")
	visual.material_override=null
	sphere.global_position=centre+Vector3(20,0,0);sphere.radius_m=1.45;sphere.feather_m=0.35;sphere.enabled=true
	await settle()
	var binding:Dictionary={}
	for candidate in sphere._bindings:
		if candidate.source==visual:binding=candidate
	check(not binding.is_empty(),"external StandardMaterial participates in actual sphere preparation")
	if binding.is_empty():quit(1);return
	check(binding.materials[0].get_shader_parameter("texture_albedo")==original_texture,"original albedo texture retained")
	check(binding.visual.get_parent()==visual and binding.visual.owner==null,"adapter is disposable, not authored")
	var identity:Array=[binding.visual.get_instance_id(),binding.visual.mesh.get_rid(),binding.materials[0].get_rid()]
	var builds:=Correspondence.builds;var preparations:int=sphere.preparations
	for look in [1,2]:
		sphere.inner_look=look
		await capture("partial-%d"%look)
		if look==2:
			var difference:=await surface_light(binding)
			print("EXTERNAL_LIGHT_ERROR ",difference)
			camera.look_at_from_position(centre+Vector3(-70,32,80),centre);await capture("partial-2-side")
			camera.look_at_from_position(centre+Vector3(150,88,160),centre);await capture("partial-2-far")
			camera.look_at_from_position(centre+Vector3(88,52,95),centre)
		for frame in 30:
			sphere.global_position=centre+Vector3(lerpf(-20,20,float(frame)/29.0),0,0)
			await process_frame
		check(sphere.preparations==preparations and Correspondence.builds==builds,"moving sphere never rebuilds targets")
		check(identity==[binding.visual.get_instance_id(),binding.visual.mesh.get_rid(),binding.materials[0].get_rid()],"moving sphere retains mesh/material")
		sphere.global_position=centre;sphere.radius_m=5.0
		await capture("inside-%d"%look)
		sphere.global_position=centre+Vector3(20,0,0);sphere.radius_m=1.45
	# The changed shared binding lifecycle must still suspend/restore on world switch.
	for look in [1,2,0]:
		map.world_look=look;await frames(4)
		if look!=0:check(visual.layers!=0 and not binding.visual.visible,"global look restores original owner")
	await settle()
	map.voxel_light_levels=5;map.voxel_light_cell_m=0.125;await frames(2)
	for candidate in sphere._bindings:
		if candidate.source==visual:
			check(candidate.materials[0].get_shader_parameter("voxel_light_levels")==5.0,"existing light levels reach adapter")
			check(is_equal_approx(candidate.materials[0].get_shader_parameter("voxel_light_cell"),0.125),"existing cell size reaches adapter")
	sphere.enabled=false;await frames(3)
	check(visual.mesh==detailed and visual.get_active_material(0)==original and visual.layers!=0,"disabling sphere returns exact original mesh/material")
	check(prop.get_node("Collision/Shape").shape==collider,"collision unchanged")
	check(original.albedo_texture==original_texture and original.roughness>0.9,"shared original material unchanged")
	check(FileAccess.get_sha256("res://content/mesh_models/coastal_rock/source.glb")==original_hash,"GLB unchanged")
	await capture("restored")
	print("EXTERNAL_ANOMALY ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"bindings":sphere._bindings.size(),"motion_builds":Correspondence.builds-builds,"adapter_rgb_error":adapter_error}))
	scene.queue_free();await frames(3);quit(0 if errors.is_empty() else 1)
