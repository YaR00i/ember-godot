extends SceneTree
## Render-only dense regression: production tufts/leaves and actual terrain source.
## Not the gameplay/streaming stress route or an FPS acceptance test.
const Materials = preload("res://scripts/ember_voxel_surface_materials.gd")
const Surface = preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")
const Fixture = preload("res://scripts/prototypes/ember_painted_light_fixture.gd")
var output := OS.get_environment("EMBER_GRASS_CAPTURE_DIR")
var host: Node3D
var vertices: PackedVector3Array
var offset: Vector3
var targets: Array[ShaderMaterial] = []
var programs: Array[Shader] = []
var errors: Array[String] = []
var tall_visuals: Array[MeshInstance3D] = []

func _initialize() -> void:
	run.call_deferred()

func floor_at(x: float,z: float) -> Vector3:
	var best := INF
	var result := Vector3.ZERO
	for point in vertices:
		var p := point + offset
		var distance := Vector2(p.x-x,p.z-z).length_squared()
		if distance < best: best=distance;result=p
	return result

func visual(parent: Node3D,mesh: Mesh,material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new();node.mesh=mesh;node.material_override=material
	parent.add_child(node)
	return node

func track(material: ShaderMaterial) -> void:
	if material in targets: return
	Materials.refresh_terrain_features(material)
	targets.append(material);programs.append(material.shader)
	if not material.shader.has_meta("ember_feature_base"): errors.append("missing compiled grass program")

func sample(label: String) -> Dictionary:
	print("GRASS_SAMPLE_BEGIN ",label)
	for frame in 45: await process_frame
	var values: Array[float] = []
	var walls: Array[float] = []
	var cpu: Array[float] = []
	var previous:=Time.get_ticks_usec()
	var finish:=Time.get_ticks_usec()+2000000
	while Time.get_ticks_usec()<finish or values.size()<120:
		await process_frame;await RenderingServer.frame_post_draw
		values.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
		var now:=Time.get_ticks_usec();walls.append((now-previous)/1000.0);previous=now
	values.sort()
	walls.sort();cpu.sort()
	var mid:=values.size()/2
	var p95:=mini(values.size()-1,int(ceil(values.size()*0.95))-1)
	var p99:=mini(values.size()-1,int(ceil(values.size()*0.99))-1)
	if not output.is_empty(): root.get_texture().get_image().save_png(output.path_join(label+".png"))
	return {"frames":values.size(),"gpu_median_ms":values[mid],"gpu_p95_ms":values[p95],"gpu_p99_ms":values[p99],"wall_median_ms":walls[mid],"wall_p95_ms":walls[p95],"wall_p99_ms":walls[p99],"wall_max_ms":walls[-1],"render_cpu_median_ms":cpu[mid],"primitives":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),"shadow_primitives":root.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)}

func run() -> void:
	print("GRASS_RENDER_SETUP")
	if RenderingServer.get_current_rendering_method()!="forward_plus" or output.is_empty(): quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(2560,1440);root.scaling_3d_scale=1.0;root.use_taa=false
	Engine.max_fps=0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	host=Node3D.new();root.add_child(host);current_scene=host
	var path := "res://content/world_terrains/landscape_compact.res"
	var sha := FileAccess.get_sha256(path)
	var source: Resource=load(path)
	var bounds:=Rect2i(Vector2i(source.width/2-64,source.depth/2-64),Vector2i(128,128))
	var field:=Surface.field(source,bounds)
	var data:=Surface.build_arrays(source,bounds,true,true,field,true)
	var upload:=Surface.prepare_render_upload(data.arrays,data.render_detail)
	var mesh:=Surface.publish_render_mesh(upload.arrays,upload.detail)
	vertices=mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var center:=mesh.get_aabb().get_center();offset=-center
	var ground_material:=Materials.compact_terrain_material()
	Materials.set_compact_terrain_roles(ground_material,source.palette_surface_roles,source.palette_material_ids,source.palette)
	ground_material.set_shader_parameter("smooth_surface_enabled",true)
	visual(host,mesh,ground_material).position=offset
	var packed: PackedScene=load("res://prefabs/items/cuttable_grass.scn")
	print("GRASS_GROUND_READY")
	var template:=packed.instantiate()
	var grass_mesh: Mesh=template.get_node("PileVisual").mesh
	if "geometry" in OS.get_cmdline_user_args():
		# Production may already contain the candidate; keep the control original.
		var reference:=SurfaceTool.new();reference.begin(Mesh.PRIMITIVE_TRIANGLES)
		for index in 3:
			reference.append_from(Fixture.grass_card_mesh(),0,Transform3D(Basis(Vector3.UP,index*1.7).scaled(Vector3(60,120,60)),[Vector3(-6,0,0),Vector3(6,0,1),Vector3(0,0,-5)][index]))
		grass_mesh=reference.commit()
	var grass_material: ShaderMaterial=template.get_node("PileVisual").material_override
	track(grass_material)
	for index in 128:
		var tuft:=visual(host,grass_mesh,grass_material)
		tall_visuals.append(tuft)
		tuft.position=floor_at((index%16-7.5)*7.0,(index/16-3.5)*13.0)
		tuft.rotate_y(index*2.39996)
	var ordinary_material:=grass_material.duplicate() as ShaderMaterial
	ordinary_material.shader=grass_material.shader.get_meta("ember_feature_base")
	track(ordinary_material)
	var ordinary:=MultiMeshInstance3D.new();host.add_child(ordinary)
	ordinary.multimesh=MultiMesh.new();ordinary.multimesh.transform_format=MultiMesh.TRANSFORM_3D
	ordinary.multimesh.mesh=Fixture.grass_card_mesh();ordinary.multimesh.instance_count=4096
	ordinary.material_override=ordinary_material
	ordinary.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for index in 4096:
		var point:=floor_at((index%64-31.5)*1.9,(index/64-31.5)*1.9)
		ordinary.multimesh.set_instance_transform(index,Transform3D(Basis(Vector3.UP,index*2.39996).scaled(Vector3(20,32,20)),point))
	var pile:Node3D=load("res://prefabs/items/autumn_leaf_pile.scn").instantiate()
	for index in 16:
		var leaves:=pile.get_node("PileVisual") as MeshInstance3D
		visual(host,leaves.mesh,leaves.material_override).position=floor_at((index%4-1.5)*28,(index/4-1.5)*28)
	template.free();pile.free()
	print("GRASS_POPULATION_READY")
	var sun:=DirectionalLight3D.new();host.add_child(sun);sun.rotation_degrees=Vector3(-18,-55,0);sun.shadow_enabled=true;sun.directional_shadow_max_distance=1600
	var env:=WorldEnvironment.new();host.add_child(env);env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("879bb0")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_energy=0.4
	var camera:=Camera3D.new();host.add_child(camera);camera.position=Vector3(160,130,180);camera.look_at(Vector3.ZERO);camera.fov=40;camera.far=1000;camera.current=true
	var results:Dictionary={}
	if "lod-parity" in OS.get_cmdline_user_args():
		for i in targets.size():targets[i].shader=programs[i]
		for child in host.get_children():
			if child is MeshInstance3D:child.hide()
		root.mesh_lod_threshold=100000.0
		results.reference=await sample("reference")
		var reference_image:=root.get_texture().get_image()
		ordinary.multimesh.mesh=load("res://prefabs/voxels/meshes/grass_card_contour.res")
		results.native_far=await sample("native-far")
		var actual:=root.get_texture().get_image()
		var changed:=0
		for y in actual.get_height():
			for x in actual.get_width():
				var delta:=reference_image.get_pixel(x,y)-actual.get_pixel(x,y)
				if maxf(absf(delta.r),maxf(absf(delta.g),absf(delta.b)))>2.0/255.0:changed+=1
		if changed!=0:errors.append("native far LOD changes original foliage pixels")
		var parity:Dictionary={"errors":errors,"samples":results,"changed_pixels_over_2":changed,"instances":ordinary.multimesh.instance_count,"scope":"ordinary-only full image parity; render-info LOD primitive counter may omit instance multiplier"}
		FileAccess.open(output.path_join("lod-parity.json"),FileAccess.WRITE).store_string(JSON.stringify(parity,"  "))
		print("GRASS_LOD_PARITY ",JSON.stringify(parity))
		host.queue_free();await process_frame;await process_frame;quit(0 if errors.is_empty() else 1);return
	if "geometry" in OS.get_cmdline_user_args():
		for i in targets.size(): targets[i].shader=programs[i]
		var atlas:=Image.load_from_file("res://content/terrain_materials/textures/grass-cards-runtime.png")
		var contour: ArrayMesh=load("res://prefabs/voxels/meshes/grass_card_contour.res") if "native-lod" in OS.get_cmdline_user_args() else Fixture.grass_card_contour_mesh(atlas)
		print("GRASS_CONTOUR_READY ",contour.get_meta("card_area_fraction"))
		var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for index in 3:
			surface.append_from(contour,0,Transform3D(Basis(Vector3.UP,index*1.7).scaled(Vector3(60,120,60)),[Vector3(-6,0,0),Vector3(6,0,1),Vector3(0,0,-5)][index]))
		var high_contour:=surface.commit()
		var candidates: Array[Mesh] = [Fixture.grass_card_mesh(),contour]
		var views: Array = ["near"] if "near" in OS.get_cmdline_user_args() else ["near","wide","oblique"]
		for view in views:
			camera.position={"near":Vector3(65,45,75),"wide":Vector3(160,130,180),"oblique":Vector3(120,25,140)}[view]
			camera.look_at(Vector3.ZERO)
			for variant in [0,1,0]:
				ordinary.multimesh.mesh=candidates[variant]
				for tuft in tall_visuals: tuft.mesh=grass_mesh if variant==0 else high_contour
				var label:String=str(view)+("-cards" if variant==0 else "-contour")
				if results.has(label):label+="-return"
				results[label]=await sample(label)
				if results[label].shadow_primitives<=0:errors.append("high grass shadows absent "+label)
		var geometry_report:Dictionary={"errors":errors,"samples":results,"ordinary_tufts":4096,"harvest_tufts":128,"leaf_piles":16,"card_area_fraction":contour.get_meta("card_area_fraction"),"triangles_per_tuft":[8,contour.surface_get_array_index_len(0)/3],"native_resolution":"2560x1440","max_fps":0,"external_load":"Aion 2 closed; GPU timing only, not full gameplay acceptance","production_mesh_changed":false,"scope":"same material/placement/coverage; ordinary caster OFF, tall caster ON; render-only crop"}
		if FileAccess.get_sha256(path)!=sha:errors.append("terrain source changed")
		FileAccess.open(output.path_join("geometry-result.json"),FileAccess.WRITE).store_string(JSON.stringify(geometry_report,"  "))
		print("GRASS_GEOMETRY ",JSON.stringify(geometry_report))
		host.queue_free();await process_frame;await process_frame;quit(0 if errors.is_empty() else 1);return
	for mode in ["base","compiled","base-return"]:
		for i in targets.size(): targets[i].shader=programs[i] if mode=="compiled" else programs[i].get_meta("ember_feature_base")
		results[mode]=await sample(mode)
	for mode in results:
		if results[mode].primitives!=results.base.primitives: errors.append("render population changed "+mode)
	if FileAccess.get_sha256(path)!=sha: errors.append("terrain source changed")
	var report:Dictionary={"errors":errors,"samples":results,"ordinary_tufts":4096,"harvest_tufts":128,"leaf_piles":16,"native_resolution":"2560x1440","max_fps":60,"external_load":"Aion 2 running; no clean performance acceptance","scope":"render-only crop of real source, not main gameplay/stress acceptance"}
	FileAccess.open(output.path_join("render-result.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("GRASS_RENDER ",JSON.stringify(report))
	host.queue_free();await process_frame;await process_frame
	quit(0 if errors.is_empty() else 1)
