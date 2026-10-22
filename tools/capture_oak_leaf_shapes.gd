extends "res://tools/capture_tree_foliage21_study.gd"
func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	var reference:=OS.get_cmdline_user_args()[1]
	var quick:=OS.get_cmdline_user_args().has("--quick")
	scene=load("res://scenes/compact_oak_looks_study.tscn").instantiate();root.add_child(scene);current_scene=scene
	while not scene.looks_ready:await process_frame
	scene.get_node("Instructions").hide();scene.walker.set_physics_process(false);scene.followers.hide();scene.followers.set_physics_process(false)
	scene.follow_camera.set_physics_process(false);scene.follow_camera.set_process(false);scene.reset_actors()
	var original:=hash(scene.look_source.to_definition());var ground:=floor_geometry();var grass:=hash(scene.tuft_visual.multimesh.buffer)
	var collider: Shape3D=scene.look_prop.get_node("Collision/Shape").shape;var collision:=hash(collider.get_faces())
	scene.set_alternate_look(1);scene.set_look_fraction(1)
	export_alpha_examples()
	var faceted:=hash(scene.faceted_visual.mesh.get_faces())
	for preset in [1,0,2]:
		for pose in [1,0]:
			if quick and (preset!=1 or pose!=1):continue
			scene.set_lighting_preset(preset);scene.set_sun_pose(pose)
			for view in [1,2,0]:
				scene.set_look_view(view);scene.follow_camera.set_process(false)
				var tail:="%d-%d-%d"%[preset,pose,view]
				scene.set_leaf_shape(0.0)
				var before:=await capture("before-"+tail)
				check(before.get_data()==Image.load_from_file(reference.path_join("faceted-"+tail+".png")).get_data(),"zero returns previous faceted exact "+tail)
				for kind in 3:
					scene.set_leaf_shape_kind(kind)
					for amount in [0.7,1.0]:
						scene.set_leaf_shape(amount);await capture("shape-%d-%d-"%[kind,roundi(amount*100)]+tail)
				scene.set_leaf_shape(0.0)
				check(before.get_data()==(await capture("return-"+tail)).get_data(),"original alpha restores exact "+tail)
				scene.set_look_fraction(0.0)
				check((await capture("smooth-"+tail)).get_data()==Image.load_from_file(reference.path_join("smooth-"+tail+".png")).get_data(),"smooth untouched "+tail)
				scene.set_alternate_look(0);scene.set_look_fraction(1.0)
				check((await capture("voxel-"+tail)).get_data()==Image.load_from_file(reference.path_join("voxel-"+tail+".png")).get_data(),"voxel untouched "+tail)
				scene.set_alternate_look(1)
	scene.set_leaf_shape_kind(0);scene.set_leaf_shape(0.7)
	scene.set_lighting_preset(0);scene.set_sun_pose(1);scene.set_look_view(2);scene.follow_camera.set_process(false)
	var camera: Camera3D=scene.follow_camera._cam;var initial:=camera.global_transform
	var target: Vector3=initial.origin-initial.basis.z*7.0
	for i in 12:
		camera.global_position=target+(initial.origin-target).rotated(Vector3.UP,(float(i)-5.5)*0.025);camera.look_at(target);await capture("motion-%02d"%i)
	camera.global_transform=initial
	scene.set_look_fraction(0.5);await capture("split")
	check(scene.bake_count==2 and hash(scene.faceted_visual.mesh.get_faces())==faceted,"no remesh when shape changes")
	check(hash(scene.look_source.to_definition())==original and floor_geometry()==ground and hash(scene.tuft_visual.multimesh.buffer)==grass,"Source ground grass unchanged")
	check(scene.look_prop.get_node("Collision/Shape").shape==collider and hash(collider.get_faces())==collision,"single collider retained")
	scene.get_node("Instructions").show();await capture("controls")
	var file:=FileAccess.open(output.path_join("native.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":errors.is_empty(),"errors":errors,"art_acceptance":"OPEN","source_and_physics_unchanged":true},"\t"));file.close()
	print("OAK_LEAF_SHAPES_NATIVE ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)

func export_alpha_examples() -> void:
	# A small explanatory atlas swatch. World captures above use the real shader.
	var material: ShaderMaterial=scene.faceted_visual.mesh.surface_get_material(1)
	var texture: Texture2D=material.get_shader_parameter("painted_leaf_card_albedo")
	var source:=texture.get_image();source.resize(512,512,Image.INTERPOLATE_BILINEAR)
	var mask: Image=material.get_shader_parameter("faceted_leaf_shape").get_image()
	var original:=source.get_region(Rect2i(0,0,256,256))
	for y in 256:
		for x in 256:
			var c:=original.get_pixel(x,y);c.a=1.0 if c.a>=0.4 else 0.0;original.set_pixel(x,y,c)
	original.save_png(output.path_join("atlas-before.png"))
	for kind in 3:
		for amount in [0.7,1.0]:
			var result:=original.duplicate() as Image
			var limit:=lerpf(2.25 if kind==1 else 1.65,1.0,amount)
			for y in 256:
				for x in 256:
					var c:=result.get_pixel(x,y)
					if mask.get_pixel(x,y)[kind]>limit:c.a=0.0
					result.set_pixel(x,y,c)
			result.save_png(output.path_join("atlas-%d-%d.png"%[kind,roundi(amount*100)]))
