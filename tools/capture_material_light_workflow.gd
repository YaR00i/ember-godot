extends SceneTree
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
const Look=preload("res://addons/ember_import/ember_world_look_panel.gd")
const Dialog=preload("res://addons/ember_import/ember_compact_material_pattern_dialog.gd")
var scene
var output: String
var errors: Array[String]=[]
var comparisons: Array=[]
func _initialize() -> void:run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok:errors.append(message);printerr("FAIL ",message)
func frames(count:=8) -> void:
	for i in count:await process_frame
	await RenderingServer.frame_post_draw
func capture(name: String) -> Image:
	await frames();var img:=root.get_texture().get_image();img.save_png(output.path_join(name+".png"));return img
func differences(a: Image,b: Image,region: Rect2i) -> Dictionary:
	var count:=0;var maximum:=0.0
	for y in range(region.position.y,region.end.y):
		for x in range(region.position.x,region.end.x):
			var ca:=a.get_pixel(x,y);var cb:=b.get_pixel(x,y)
			if ca!=cb:count+=1
			maximum=maxf(maximum,maxf(absf(ca.r-cb.r),maxf(absf(ca.g-cb.g),absf(ca.b-cb.b))))
	return {"changed_pixels":count,"max_rgb_error":maximum}
func geometry() -> int:
	var result: Array=[]
	for tile in scene._projection._tiles.values():
		result.append(hash(tile.get_node("Ground").mesh.surface_get_arrays(0)))
		result.append(hash(tile.get_node("GroundPhysics/Shape").shape.get_faces()))
	return hash(result)
func variant_probe() -> Dictionary:
	# Two real terrain-shader quads, one draw material, two palette variants.
	# The changed row must affect only its own half of the rendered fixture.
	var viewport:=SubViewport.new();viewport.size=Vector2i(400,240);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=4.2;viewport.add_child(camera);camera.look_at_from_position(Vector3(0,5,2),Vector3.ZERO);camera.make_current()
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-40,-65,0);viewport.add_child(sun)
	var material=Materials.compact_terrain_material();material.set_shader_parameter("material_light_mode",1)
	var p=Materials.load_compact_terrain_variant("grass_surface").duplicate(true);p.grass_light_enabled=true
	var q=p.duplicate(true);q.grass_light_low=0.75
	Materials.set_compact_terrain_roles(material,PackedStringArray(["","","grass","","","grass"]),PackedStringArray(["","","first","","","second"]),PackedColorArray(),{"first":p,"second":q})
	for slot in [2,5]:
		var mesh:=ArrayMesh.new();var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(-0.85,0,-0.85),Vector3(0.85,0,0.85),Vector3(0.85,0,-0.85),Vector3(-0.85,0,-0.85),Vector3(-0.85,0,0.85),Vector3(0.85,0,0.85)])
		var normals:=PackedVector3Array();normals.resize(6);normals.fill(Vector3.UP);arrays[Mesh.ARRAY_NORMAL]=normals
		# Godot front faces use clockwise winding viewed from above.
		var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		for i in [0,3]:
			var temp:=points[i+1];points[i+1]=points[i+2];points[i+2]=temp
		arrays[Mesh.ARRAY_VERTEX]=points
		var colors:=PackedColorArray();colors.resize(6);colors.fill(Color(1,0,0,slot/255.0));arrays[Mesh.ARRAY_COLOR]=colors
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var visual:=MeshInstance3D.new();visual.mesh=mesh;visual.material_override=material;visual.position.x=-1 if slot==2 else 1;viewport.add_child(visual)
	await frames();var before:=viewport.get_texture().get_image();before.save_png(output.path_join("two-variants-before.png"))
	p.grass_light_low=0.85;p.grass_light_warm=Color(1.3,0.85,0.8)
	Materials.update_grass_light_profile(material,2,p)
	await frames();var after:=viewport.get_texture().get_image();after.save_png(output.path_join("two-variants-after.png"))
	var left:=differences(before,after,Rect2i(15,30,170,170));var right:=differences(before,after,Rect2i(215,30,170,170))
	check(left.changed_pixels>100,"GPU changes first material profile")
	check(right.changed_pixels==0,"GPU preserves the second material profile")
	viewport.queue_free();await frames(2);return {"left":left,"right":right}
func run() -> void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	var variants:=await variant_probe()
	for scene_path in ["res://scenes/compact_grass_field_study.tscn","res://scenes/compact_bevel_light_study.tscn"]:
		scene=load(scene_path).instantiate();root.add_child(scene);current_scene=scene
		var grass: bool="grass_field" in scene_path
		var deadline:=Time.get_ticks_msec()+90000
		while not (scene.ready_for_painted if grass else scene.ready_for_bevel) and Time.get_ticks_msec()<deadline:await process_frame
		check(scene.ready_for_painted if grass else scene.ready_for_bevel,"fixture ready")
		scene.get_node("Instructions").hide();await frames(20)
		scene.follow_camera.set_process(false);scene.follow_camera.set_physics_process(false)
		var camera: Camera3D=scene.follow_camera._cam;camera.make_current();var camera_before:=camera.global_transform
		var source: Resource=scene._projection.document.working_copy();var geometry_before:=geometry()
		var panel=Look.new();root.add_child(panel);panel.hide();var history:=UndoRedo.new();panel.set_target(scene,scene.get_node("Map"),history)
		var sun: DirectionalLight3D=scene.get_node("Map/Look/Sun")
		for preset in 3:
			for pose in 2:
				panel.apply_material_light_preset(preset)
				var angle:=Vector3(-32,-145,0) if pose==0 else Vector3(-40,-65,0)
				if preset==1:angle.x=-62
				elif preset==2:angle.x=-38
				sun.rotation_degrees=angle;scene.depth_material.set_shader_parameter("material_depth_sun_direction",sun.global_basis.z)
				var label:=("grass" if grass else "bevel")+"-%d-%d"%[preset,pose]
				if grass:
					scene.depth_material.set_shader_parameter("grass_light_profiles_enabled",false);scene._sync_tuft_material()
					var before:=await capture(label+"-lab")
					scene.depth_material.set_shader_parameter("grass_light_profiles_enabled",true);scene._sync_tuft_material()
					var after:=await capture(label+"-editor")
					var d:=differences(before,after,Rect2i(Vector2i.ZERO,after.get_size()));d["label"]=label;comparisons.append(d)
					check(d.max_rgb_error<=3.0/255.0,"transferred profile retains accepted LAB light response "+label)
				else:await capture(label+"-editor")
				check(geometry()==geometry_before and scene._projection.document.same_terrain_data(source),"presets preserve Source and geometry")
				check(camera.global_transform.is_equal_approx(camera_before),"one fixed game camera per fixture")
				check(scene.depth_material.get_shader_parameter("material_depth_amplitude_m")==0.04,"POM retained")
		if grass:
			# Real shadow and zero-light controls: fill cannot turn into emission.
			var slot: int=scene._projection.document.palette_material_ids.find("cartoon_grass")
			var profile=scene._grass.duplicate(true);var original_fill: float=profile.grass_light_shadow_fill
			for mode in ["no-shadow","zero-light"]:
				if mode=="no-shadow":sun.shadow_enabled=false
				else:sun.shadow_enabled=true;sun.light_energy=0.0
				profile.grass_light_shadow_fill=original_fill;Materials.update_grass_light_profile(scene.depth_material,slot,profile);scene._sync_tuft_material()
				var on:=await capture(mode+"-fill")
				profile.grass_light_shadow_fill=0.0;Materials.update_grass_light_profile(scene.depth_material,slot,profile);scene._sync_tuft_material()
				var off:=await capture(mode+"-no-fill");check(on.get_data()==off.get_data(),"fill disappears with "+mode)
			profile.grass_light_shadow_fill=original_fill;Materials.update_grass_light_profile(scene.depth_material,slot,profile);scene._sync_tuft_material()
			sun.shadow_enabled=true;panel.apply_material_light_preset(0)
			# Native UI uses an isolated user:// Pattern. Preview/Undo/Discard
			# route through the same small table update as the editor projection.
			var path:="user://ember-tests/native-grass-light.tres";DirAccess.make_dir_recursive_absolute(path.get_base_dir());ResourceSaver.save(profile,path)
			var dialog=Dialog.new();var layer:=CanvasLayer.new();scene.add_child(layer)
			var host:=PanelContainer.new();host.position=Vector2(15,15);host.size=Vector2(355,850);layer.add_child(host)
			layer.add_child(dialog);host.add_child(dialog.parameters_panel);dialog.hide()
			dialog.pattern_path_override=path;dialog.light_profile_previewed.connect(func(pattern,id):Materials.update_grass_light_profile(scene.depth_material,slot,pattern);scene._sync_tuft_material())
			check(dialog.open_role("grass"),"native editor opens material");dialog.hide()
			dialog._parameter_scroll.scroll_vertical=280;await capture("material-editor")
			dialog._parameter_scroll.scroll_vertical=700;await capture("material-editor-tones")
			var previous: float=dialog._draft.grass_light_low;dialog._finish_sliders.grass_light_low.value=0.8
			check(is_equal_approx(scene.depth_material.get_meta("ember_grass_light_image").get_pixel(slot,0).r,0.8),"native draft preview updates material")
			dialog.undo_edit();check(is_equal_approx(scene.depth_material.get_meta("ember_grass_light_image").get_pixel(slot,0).r,previous),"native preview Undo")
			dialog._finish_sliders.grass_light_low.value=0.8;dialog.cancel_edit()
			check(is_equal_approx(scene.depth_material.get_meta("ember_grass_light_image").get_pixel(slot,0).r,previous),"native Discard restores profile")
			dialog.free();layer.queue_free();await frames(2)
			var look_host:=PanelContainer.new();look_host.position=Vector2(15,15);look_host.size=Vector2(390,850)
			var look_layer:=CanvasLayer.new();scene.add_child(look_layer);look_layer.add_child(look_host);panel.reparent(look_host);panel.show()
			await capture("world-look-editor")
			look_layer.queue_free()
			# A short real controller pass and camera motion after the fixed matrix.
			scene.follow_camera.set_process(true);scene.follow_camera.set_physics_process(true)
			Input.action_press("move_east",1.0)
			for i in 60:
				await physics_frame
				if i in [0,20,40]:await capture("walk-%02d"%i)
			Input.action_release("move_east");await frames(4)
		else:panel.queue_free()
		history.free();scene.queue_free();await frames(4)
	var report:={"variants":variants,"accepted_lab_comparisons":comparisons,"errors":errors,"matrix":"two existing LABs x 3 presets x side/back; fixed game cameras","POM":"original 4cm/32 steps","geometry_source_unchanged":errors.is_empty()}
	var file:=FileAccess.open(output.path_join("native.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("MATERIAL_LIGHT_WORKFLOW_NATIVE ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
