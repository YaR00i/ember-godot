extends "res://tools/capture_tree_foliage21_study.gd"
const Profiles=preload("res://scripts/ember_voxel_material_profiles.gd")
const Look=preload("res://addons/ember_import/ember_world_look_panel.gd")
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
const Dialog=preload("res://addons/ember_import/ember_compact_material_pattern_dialog.gd")
const PalettePanel=preload("res://addons/ember_import/ember_voxel_palette_panel.gd")
const Actions=preload("res://addons/ember_import/ember_voxel_sculpt_actions.gd")

func bind_tree(enabled: bool, wood:=0.45, leaves:=0.18) -> void:
	var source: EmberVoxelModelResource=scene.parametric_inputs.source
	source.material=Profiles.with_rim(source.material,"bark",enabled,wood)
	source.material=Profiles.with_rim(source.material,"foliage",enabled,leaves)
	scene.apply_tree_material_rim(source)

func difference(a: Image,b: Image) -> int:
	return 0 if a.get_data()==b.get_data() else 1

func baseline_matches(a: Image,b: Image) -> bool:
	var aa:=a.get_data();var bb:=b.get_data();var changed:=0;var maximum:=0
	if aa==bb:return true
	for i in aa.size():
		var delta:=absi(int(aa[i])-int(bb[i]))
		if delta>0:changed+=1;maximum=maxi(maximum,delta)
	return changed<=16 and maximum<=1

func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	var before:=OS.get_cmdline_user_args().has("--before")
	scene=load("res://scenes/compact_tree_foliage21_study.tscn").instantiate()
	root.add_child(scene);current_scene=scene
	while not scene.ready_for_foliage21:await process_frame
	scene.get_node("Instructions").hide()
	scene.walker.set_physics_process(false);scene.followers.set_physics_process(false)
	scene.follow_camera.set_process(false);scene.follow_camera.set_physics_process(false)
	scene.reset_actors();scene.show_tree_leaf_trial(0.4);scene.set_tree_leaf_shared_light(true)
	var camera: Camera3D=scene.follow_camera._cam
	scene.set_comparison(0);camera.fov=scene.follow_camera.fov
	var game_transform:=camera.global_transform;var game_fov:=camera.fov
	var mesh_hash:=hash(scene.foliage21_cards.mesh.surface_get_arrays(0))
	var wood_hash:=hash(scene.parametric_wood.mesh.surface_get_arrays(0))
	var source_hash: String=scene.parametric_inputs.source.voxels.hex_encode().sha256_text()
	var floor_hash:=floor_geometry();var grass_hash:=hash(scene.tuft_visual.multimesh.buffer)
	var terrain: Resource=scene._projection.document.working_copy()
	var matches:=0
	for preset in [1,0,2]:
		for pose in 2:
			scene.set_lighting_preset(preset);scene.set_sun_pose(pose)
			for view in ["tree","game"]:
				scene.set_network_view(1)
				if view=="game":camera.global_transform=game_transform;camera.fov=game_fov
				for enabled in [false,true]:
					scene.set_tree_rim(enabled)
					if not before:
						scene.tree_leaf_shared_material.set_shader_parameter("object_style_rim_profiles_enabled",false)
						if scene.tree_rim_wood_material!=null:scene.tree_rim_wood_material.set_shader_parameter("object_style_rim_profiles_enabled",false)
					var name:="%s-%d-%d-%s"%[view,preset,pose,"on" if enabled else "off"]
					var lab:=await capture(name)
					if before:continue
					check(baseline_matches(lab,Image.load_from_file(output.path_join("baseline").path_join(name+".png"))),"legacy baseline within 1 RGB8/16 channels "+name)
					bind_tree(enabled)
					var transferred:=await capture(name+"-saved")
					check(baseline_matches(lab,transferred),"saved profile equals LAB within 1 RGB8/16 channels "+name)
					matches+=1
	if before:print("STYLE_RIM_NATIVE BASELINE PASS");quit();return
	check(mesh_hash==hash(scene.foliage21_cards.mesh.surface_get_arrays(0)) and wood_hash==hash(scene.parametric_wood.mesh.surface_get_arrays(0)),"tree arrays exact")
	check(source_hash==scene.parametric_inputs.source.voxels.hex_encode().sha256_text(),"Source voxels exact")
	check(scene.tree_leaf_density_percent==45 and scene.tree_leaf_density_inputs.cards==885,"45%/885 cards")
	check(scene._projection.document.same_terrain_data(terrain) and floor_hash==floor_geometry() and grass_hash==hash(scene.tuft_visual.multimesh.buffer),"terrain paint physics grass exact")
	check(scene.depth_material.get_shader_parameter("material_depth_amplitude_m")==0.04,"POM 4cm")
	scene.set_lighting_preset(1);scene.set_sun_pose(0);scene.set_network_view(1);bind_tree(true)
	var accepted:=await capture("accepted")
	bind_tree(true,0.0,0.18);var leaves:=await capture("leaves-only")
	bind_tree(true,0.45,0.0);var wood:=await capture("wood-only")
	check(difference(accepted,leaves)>0 and difference(accepted,wood)>0,"independent wood and leaves")
	bind_tree(false);var off:=await capture("material-off")
	bind_tree(true,0.0,0.0);check(baseline_matches(off,await capture("strength-zero")),"zero strength equals local off within RGB8 precision")
	bind_tree(true)
	# Save/reopen the genuine Source Resource; a fresh material consumes its fields.
	var model_path:="user://style-rim-accepted-tree.res"
	check(ResourceSaver.save(scene.parametric_inputs.source,model_path,ResourceSaver.FLAG_COMPRESS)==OK,"Source save")
	var saved=ResourceLoader.load(model_path,"",ResourceLoader.CACHE_MODE_IGNORE)
	scene.apply_tree_material_rim(saved);check(baseline_matches(accepted,await capture("source-reopened")),"Source reopen within RGB8 precision")
	var palette=PalettePanel.new();root.add_child(palette);palette.hide()
	var material_history:=UndoRedo.new();var material_actions:=Actions.new();material_actions.configure(material_history)
	palette.rim_requested.connect(func(value,role,enabled,strength):material_actions.apply_style_rim(value,role,enabled,strength))
	material_actions.material_changed.connect(func(value):scene.apply_tree_material_rim(value);palette.sync(value,1))
	palette.sync(saved,1)
	var actions_before:=material_history.get_history_count()
	palette._rim_slider.drag_started.emit();palette._rim_slider.value=0.1;palette._rim_slider.value=0.25
	check(material_history.get_history_count()==actions_before,"native drag does not commit per input")
	palette._rim_slider.drag_ended.emit(true)
	check(material_history.get_history_count()==actions_before+1,"native release one history action")
	check(difference(accepted,await capture("object-material-edit"))>0,"native material UI changes bark")
	material_history.undo();check(baseline_matches(accepted,await capture("object-material-undo")),"native object Undo within RGB8 precision")
	var map: EmberMapLoader=scene.get_node("Map")
	var look=Look.new();var undo:=UndoRedo.new();root.add_child(look);look.set_target(scene,map,undo);look.hide()
	look._rim_switch.button_pressed=false;var master_off:=await capture("master-off")
	check(difference(accepted,master_off)>0,"map master changes real GPU")
	undo.undo();check(baseline_matches(accepted,await capture("master-undo")),"map Undo within RGB8 precision")
	undo.redo();check(baseline_matches(master_off,await capture("master-redo")),"map Redo within RGB8 precision")
	var added:=MeshInstance3D.new();added.mesh=BoxMesh.new();added.material_override=scene.tree_rim_wood_material
	scene.add_child(added);await frames()
	check(added.get_instance_shader_parameter("ember_style_rim_master")==false,"new instance inherits master")
	added.queue_free();look._rim_switch.button_pressed=true
	var sun: DirectionalLight3D=scene.get_node("Map/Look/Sun")
	var energy:=sun.light_energy;sun.light_energy=0;bind_tree(false)
	var zero:=await capture("zero-source-off");bind_tree(true)
	check(baseline_matches(zero,await capture("zero-source-on")),"zero Sun within 1 RGB8/16 channels")
	sun.light_energy=energy
	var blocker:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(100,100,0.2)
	blocker.mesh=box;blocker.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY;scene.add_child(blocker)
	blocker.global_transform=Transform3D(sun.global_basis,scene.smooth_tree.global_position+Vector3(0,4.3,0)+sun.global_basis.z*7)
	for preset in [1,0,2]:
		for pose in 2:
			scene.set_lighting_preset(preset);scene.set_sun_pose(pose)
			blocker.global_transform=Transform3D(sun.global_basis,scene.smooth_tree.global_position+Vector3(0,4.3,0)+sun.global_basis.z*7)
			bind_tree(false);var shadow:=await capture("shadow-%d-%d-off"%[preset,pose]);bind_tree(true)
			check(baseline_matches(shadow,await capture("shadow-%d-%d-on"%[preset,pose])),"shadow response within 1 RGB8/16 channels at all presets/poses")
	blocker.queue_free();await frames()
	# Actual terrain editor callbacks update one slot, preserving the other variants.
	scene.set_lighting_preset(1);scene.set_sun_pose(0)
	scene.set_comparison(0);camera.global_transform=game_transform;camera.fov=game_fov
	var before_ground:=await capture("ground-before")
	var image: Image=scene.depth_material.get_meta("ember_style_rim_image")
	var other:=image.get_pixel(2,0)
	var pattern=Materials.load_compact_terrain_variant("painted_light_stone").duplicate(true)
	var pattern_path:="user://style-rim-stone.tres";check(ResourceSaver.save(pattern,pattern_path)==OK,"terrain fixture save")
	var panel=Dialog.new();root.add_child(panel);root.add_child(panel.parameters_panel);panel.hide();panel.parameters_panel.hide()
	panel.pattern_path_override=pattern_path;check(panel.open_variant("painted_light_stone","stone"),"terrain dialog open")
	panel.hide();panel.parameters_panel.hide()
	panel.light_profile_previewed.connect(func(value,_id):Materials.update_style_rim_profile(scene.depth_material,1,value))
	panel._change_style_rim({"style_rim_enabled":true})
	check(baseline_matches(before_ground,await capture("ground-saved-on")),"explicit terrain 0.7 equals legacy/POM rim")
	panel._style_rim_slider.value=0.35
	check(difference(before_ground,await capture("ground-strength"))>0,"terrain strength produces GPU change")
	panel.undo_edit();panel.undo_edit()
	panel._style_rim_switch.button_pressed=false
	var after_ground:=await capture("ground-local-off")
	check(difference(before_ground,after_ground)>0,"terrain local GPU control")
	panel.undo_edit();check(baseline_matches(before_ground,await capture("ground-undo")),"terrain Undo within RGB8 precision")
	panel.redo_edit();panel.cancel_edit();check(baseline_matches(before_ground,await capture("ground-discard")),"terrain Discard within RGB8 precision")
	check(image.get_pixel(2,0)==other,"other palette slot unchanged")
	look.position=Vector2(16,16);look.size=Vector2(360,860);look._tabs.current_tab=2;look.show()
	await capture("controls-world-look")
	look.hide()
	palette.position=Vector2(1250,16);palette.size=Vector2(330,600);palette.show()
	await capture("controls-object-material");palette.hide()
	panel.open_variant("painted_light_stone","stone");panel.hide()
	panel.parameters_panel.position=Vector2(1100,16);panel.parameters_panel.size=Vector2(480,860)
	panel.parameters_panel.show();panel._parameter_scroll.scroll_vertical=300
	await capture("controls-material")
	panel.free();look.free();undo.free();palette.free();material_history.free()
	var file:=FileAccess.open(output.path_join("native.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":errors.is_empty(),"errors":errors,"baseline_pairs":matches,"source_sha256":source_hash,"cards":885,"wood_strength":0.45,"leaf_strength":0.18,"manual_acceptance":"OPEN"},"\t"));file.close()
	print("STYLE_RIM_NATIVE BASELINE PASS" if before else "STYLE_RIM_NATIVE PASS")
	quit(0 if errors.is_empty() else 1)
