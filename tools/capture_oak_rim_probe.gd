extends "res://tools/capture_tree_foliage21_study.gd"
func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	scene=load("res://scenes/compact_oak_looks_study.tscn").instantiate();root.add_child(scene);current_scene=scene
	while not scene.looks_ready:await process_frame
	scene.get_node("Instructions").hide();scene.walker.set_physics_process(false);scene.followers.hide();scene.followers.set_physics_process(false)
	scene.reset_actors();scene.set_look_view(1);scene.set_lighting_preset(0)
	for pose in [1,0]:
		scene.set_sun_pose(pose)
		for look in [0,1]:
			scene.set_look_fraction(float(look))
			var visual: MeshInstance3D=scene.smooth_visual if look==0 else scene.voxel_visual
			visual.set_instance_shader_parameter("ember_style_rim_master",false);await capture("rim-%d-%d-off"%[pose,look])
			visual.set_instance_shader_parameter("ember_style_rim_master",true);await capture("rim-%d-%d-on"%[pose,look])
			for i in visual.mesh.get_surface_count():
				var m: ShaderMaterial=visual.mesh.surface_get_material(i)
				print("RIM_PROBE ",look," ",i," enabled=",m.get_shader_parameter("object_style_rim_enabled")," strength=",m.get_shader_parameter("object_style_rim_strength")," profiles=",m.get_shader_parameter("object_style_rim_profiles"))
			if look==1:
				var leaf: ShaderMaterial=visual.mesh.surface_get_material(1)
				leaf.set_shader_parameter("voxel_leaf_rim_form_weight",0.0);await capture("rim-%d-faces"%pose)
				leaf.set_shader_parameter("voxel_leaf_rim_form_weight",1.0);await capture("rim-%d-form"%pose)
				visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;await capture("rim-%d-form-no-cast-diagnostic"%pose)
				visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	print("OAK_RIM_PROBE PASS");quit()
