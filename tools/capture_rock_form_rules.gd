extends "res://tools/capture_coherent_looks.gd"
## Ordinary-rock form probe. Existing source rules and smooth owner only.
## All working documents and derived geometry are private to this capture.
const Rules=preload("res://scripts/prototypes/ember_terrain_surface_rules.gd")
const Smooth=preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")
var variants: Array[Dictionary]=[]
var rule_cells: Dictionary={}
var checked_variants: Dictionary={}
var mesh_collision_error_m:=0.0

func setup_capture_view(view: int) -> void:
	scene.set_rock_view(view);scene.follow_camera.set_process(false)

func build_variant(source, code: int) -> Dictionary:
	var document=source.working_copy()
	var cells: Dictionary={}
	for cell: Vector2i in rule_cells:cells[cell]=code
	document.surface_rules=Rules.changed(document.surface_rules,cells)
	check(document.validation_errors().is_empty(),"private rule document validates")
	var tiles: Dictionary={}
	for key: Vector2i in scene._projection._tiles:
		var begin:=key*64
		var bounds:=Rect2i(begin,Vector2i(mini(64,source.width-begin.x),mini(64,source.depth-begin.y)))
		var field:=Smooth.field(document,bounds)
		var built:=Smooth.build(document,bounds,true,true,field)
		var current: ArrayMesh=scene._projection._tiles[key].get_node("Ground").mesh
		built.terrain.surface_set_material(0,current.surface_get_material(0))
		tiles[key]=built
		await process_frame
	return {"document":document,"tiles":tiles,"code":code}

func install_variant(index: int) -> void:
	var item:=variants[index]
	scene._projection.document=item.document
	for key: Vector2i in item.tiles:
		var built: Dictionary=item.tiles[key]
		scene._projection._tiles[key].get_node("Ground").mesh=built.terrain
		check(scene._projection.apply_study_smooth_tile(key,built.smooth_field,built.collision_faces),"install one physical field")
		if not checked_variants.has(index):
			# ArrayMesh.get_faces() rounds positions to 1e-4 source units;
			# the physics shape retains the original float32 coordinates.
			var mesh_faces: PackedVector3Array=built.terrain.get_faces()
			var physics_faces: PackedVector3Array=scene._projection._tiles[key].get_node("GroundPhysics/Shape").shape.get_faces()
			check(mesh_faces.size()==physics_faces.size(),"same mesh/collision triangle count")
			for i in mini(mesh_faces.size(),physics_faces.size()):mesh_collision_error_m=maxf(mesh_collision_error_m,mesh_faces[i].distance_to(physics_faces[i])/16.0)
			check(mesh_collision_error_m<0.00001,"mesh and collision match within 0.01mm")
		var begin:=key*64
		var p:=Vector2(begin)+Vector2(16.3,21.7)
		var floor_sample: Dictionary=scene.get_node("Map").surface_floor_sample(Vector3(p.x/16.0,12,p.y/16.0))
		check(absf(floor_sample.position.y-Smooth.sample(built.smooth_field,p)/16.0)<0.00001,"floor uses same field")
	checked_variants[index]=true

func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	scene=load("res://scenes/compact_natural_rock_study.tscn").instantiate();root.add_child(scene);current_scene=scene
	while not scene.rock_ready:await process_frame
	scene.get_node("Instructions").hide();scene.walker.set_physics_process(false);scene.followers.hide();scene.followers.set_physics_process(false)
	scene.follow_camera.set_physics_process(false);scene.follow_camera.set_process(false);scene.reset_actors()
	scene.set_material_style(0);scene.set_plain_rock(true)
	var source=scene._projection.document
	var source_heights: int=hash(source.heights)
	var source_rules: int=hash(source.surface_rules)
	var grass_hash: int=hash(scene.tuft_visual.multimesh.buffer)
	var grass_mesh: int=hash(scene.tuft_visual.multimesh.mesh.surface_get_arrays(0))
	var grass_material: Material=scene.tuft_visual.material_override
	var depth_bytes: PackedByteArray=scene.height_texture.get_image().get_data()
	for z in source.depth:
		for x in source.width:
			if Smooth.palette_at(source,x,z,0)==1:rule_cells[Vector2i(x,z)]=true
	var original_tiles: Dictionary={}
	for key: Vector2i in scene._projection._tiles:
		var ground: MeshInstance3D=scene._projection._tiles[key].get_node("Ground")
		original_tiles[key]={"terrain":ground.mesh,"smooth_field":scene._projection._smooth_field(key),"collision_faces":scene._projection._tiles[key].get_node("GroundPhysics/Shape").shape.get_faces()}
	variants.append({"document":source,"tiles":original_tiles,"code":0})
	variants.append(await build_variant(source,Rules.round_code(1.0,1)))
	variants.append(await build_variant(source,Rules.protect_code(0.75)))
	var max_displacements: Array[float]=[]
	for index in [1,2]:
		var largest:=0.0
		for key: Vector2i in original_tiles:
			var old: Dictionary=original_tiles[key].smooth_field
			var new: Dictionary=variants[index].tiles[key].smooth_field
			for i in old.heights.size():largest=maxf(largest,absf(old.heights[i]-new.heights[i])/16.0)
		max_displacements.append(largest)
	for preset in [1,0]:
		scene.set_lighting_preset(preset);scene.set_sun_pose(1)
		for view in [1,0]:
			setup_capture_view(view)
			# The inherited game-camera preset rebuilds its tuft material.
			# Restore the accepted ordinary-look bindings before this A/B pair.
			scene.set_material_style(0)
			var camera: Camera3D=scene.follow_camera._cam
			var camera_pose:=camera.global_transform
			var baseline: Image
			for index in variants.size():
				install_variant(index)
				var shot:=await capture("form-%d-%d-%d"%[index,preset,view])
				if index==0:baseline=shot
				check(camera.global_transform==camera_pose,"identical camera")
			install_variant(0)
			check(baseline.get_data()==(await capture("return-%d-%d"%[preset,view])).get_data(),"baseline restores exactly")
	check(hash(source.heights)==source_heights and hash(source.surface_rules)==source_rules,"original source untouched")
	check(hash(scene.tuft_visual.multimesh.buffer)==grass_hash and hash(scene.tuft_visual.multimesh.mesh.surface_get_arrays(0))==grass_mesh,"grass scatter and shape unchanged")
	check(scene.tuft_visual.material_override==grass_material,"grass material unchanged")
	check(scene.height_texture.get_image().get_data()==depth_bytes,"Sol depth source unchanged")
	var file:=FileAccess.open(output.path_join("native.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":errors.is_empty(),"errors":errors,"rule_cells":rule_cells.size(),"codes":variants.map(func(item):return item.code),"max_displacement_m":max_displacements,"mesh_collision_error_m":mesh_collision_error_m,"scope":"ordinary rock, plain material; private source rules; mesh/collision/floor together","art_acceptance":"OPEN"},"\t"));file.close()
	print("ROCK_FORM_RULES_NATIVE ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)
