extends "res://tools/capture_tree_foliage21_study.gd"
## Production prefab/preview and existing derived looks; no LAB relief binding.
const Bake=preload("res://scripts/ember_tree_look_bake.gd")
const C_ART:="res://content/material_studies/trees/bark_species_v1/oak-v2-calm.png"
var records: Array=[]
var parity: Array=[]
var exact_returns:=0
func run() -> void:
	output=OS.get_cmdline_user_args()[0].replace("\\","/")
	scene=load("res://scenes/compact_oak_looks_study.tscn").instantiate();root.add_child(scene);current_scene=scene
	while not scene.looks_ready:await process_frame
	scene.get_node("Instructions").hide();scene.walker.set_physics_process(false);scene.followers.hide();scene.followers.set_physics_process(false)
	scene.follow_camera.set_process(false);scene.follow_camera.set_physics_process(false);scene.reset_actors()
	scene.set_alternate_look(1);scene.set_look_fraction(0)
	var source_hash:=hash(scene.look_source.to_definition().model)
	var floor_hash:=floor_geometry();var grass_hash:=hash(scene.tuft_visual.multimesh.buffer)
	var collider: Shape3D=scene.look_prop.get_node("Collision/Shape").shape;var collision_hash:=hash(collider.get_faces())
	var published:=EmberVoxelPrefab.ensure_saved("vox_painted_oak",1.0,{})
	check(EmberVoxelPrefab.validate_packed("vox_painted_oak",published).ok,"production prefab current")
	var prop:=published.instantiate() as EmberVoxelProp;scene.add_child(prop);prop.configure_voxel_scale(16,1.0);prop.transform=scene.look_prop.transform;prop.hide()
	var preview:=EmberVoxelPrefab.prepare_resource(scene.look_source).instantiate() as EmberVoxelProp;scene.add_child(preview);preview.configure_voxel_scale(16,1.0);preview.transform=prop.transform;preview.hide()
	var wood_materials: Array[ShaderMaterial]=[]
	for visual in [scene.smooth_visual,scene.faceted_visual,scene.voxel_visual]:
		wood_materials.append(visual.mesh.surface_get_material(0))
		var material: ShaderMaterial=visual.mesh.surface_get_material(0)
		check(not material.shader.code.contains("define EMBER_OBJECT_PAINTED_BARK_RELIEF_STUDY"),"no LAB depth in look shader")
	var b: Texture2D=wood_materials[0].get_shader_parameter("painted_bark_albedo")
	var c:=Bake.Bark.artwork(C_ART)
	check(b.get_image().get_data()==Bake.Bark.artwork(Bake.Species.BARK_ART[1]).get_image().get_data(),"production accepted artwork")
	for preset in [1,0,2]:
		for light in [1,0]:
			scene.set_lighting_preset(preset);scene.set_sun_pose(light)
			for view in [0,1,3]:
				scene.set_look_view(view);scene.follow_camera.set_process(false);scene.follow_camera.set_physics_process(false)
				if view==0:scene.follow_camera._process(0)
				for look in 3:
					choose_look(look)
					var label:="%d-%d-%d-%d"%[preset,light,view,look]
					for material in wood_materials:material.set_shader_parameter("painted_bark_albedo",c)
					await capture("C-"+label)
					for material in wood_materials:material.set_shader_parameter("painted_bark_albedo",b)
					var accepted:=await capture("B-"+label)
					check(accepted.get_data()==(await capture("return-"+label)).get_data(),"B return exact "+label);exact_returns+=1
					records.append({"preset":preset,"light":light,"view":view,"look":look})
					if look==0:
						scene.look_prop.hide();prop.show();var runtime:=await capture("runtime-"+label);prop.hide();preview.show()
						var prepared:=await capture("preview-"+label);preview.hide();scene.look_prop.show()
						check(delta(prepared,runtime,label),"ordinary preview/runtime parity "+label)
	# Real cast shadow, retaining the existing leaf receive and common light path.
	scene.set_lighting_preset(1);scene.set_sun_pose(1);scene.set_look_view(1)
	var blocker:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(12,12,0.5);blocker.mesh=box
	blocker.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY;scene.add_child(blocker)
	var sun: DirectionalLight3D=scene.get_node("Map/Look/Sun")
	blocker.global_basis=sun.global_basis;blocker.global_position=scene.look_prop.global_position+Vector3(0,3,0)+sun.global_basis.z*12
	for look in 3:choose_look(look);await capture("shade-%d"%look)
	blocker.free();choose_look(0)
	# Cold file reopen in this native process, compared with the current prefab.
	scene.look_prop.hide();prop.show();var saved_image:=await capture("saved-day")
	var reopened: PackedScene=ResourceLoader.load(EmberVoxelPrefab.prefab_path("vox_painted_oak"),"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var restored:=reopened.instantiate() as EmberVoxelProp;scene.add_child(restored);restored.configure_voxel_scale(16,1.0);restored.transform=prop.transform;prop.hide()
	check(delta(saved_image,await capture("reopened-day"),"reopen"),"saved prefab reopen parity")
	check(source_hash==hash(scene.look_source.to_definition().model),"Source unchanged")
	check(floor_hash==floor_geometry() and grass_hash==hash(scene.tuft_visual.multimesh.buffer),"floor and grass unchanged")
	check(scene.look_prop.get_node("Collision/Shape").shape==collider and collision_hash==hash(collider.get_faces()),"single original physical surface")
	var file:=FileAccess.open(output.path_join("native.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":errors.is_empty(),"errors":errors,"records":records,"exact_returns":exact_returns,"parity":parity,"production_scope":"smooth oak editor/runtime; faceted/voxel derivatives remain existing LAB checks","bark_depth":"LAB only; not bound"},"\t"));file.close()
	restored.free();preview.free();prop.free()
	print("OAK_BARK_TRANSFER_NATIVE ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)
func choose_look(look: int) -> void:
	scene.set_alternate_look(1 if look==1 else 0);scene.set_look_fraction(0 if look==0 else 1)
func delta(a: Image,b: Image,label: String) -> bool:
	var x:=a.get_data();var y:=b.get_data();var peak:=0;var total:=0;var changed:=0
	if x.size()!=y.size():return false
	var stride:=4 if x.size()==a.get_width()*a.get_height()*4 else 3
	for i in range(0,x.size(),stride):
		var difference:=0
		for channel in 3:
			var d:=absi(int(x[i+channel])-int(y[i+channel]));peak=maxi(peak,d);difference=maxi(difference,d);total+=d
		if difference>0:changed+=1
	var mean:=float(total)/(a.get_width()*a.get_height()*3)
	parity.append({"label":label,"changed_pixels":changed,"max_rgb8":peak,"mean_rgb8":mean})
	# Existing oak material-instance tolerance, separate from exact mesh/Source gates.
	return peak<=5 and mean<=0.15
