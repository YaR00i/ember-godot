extends SceneTree
const Solid=preload("res://scripts/ember_voxel_solid_surface.gd")
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
var errors: Array[String]=[]
var output: String
func _initialize() -> void:run.call_deferred()
func check(value: bool,message: String) -> void:
	if not value:errors.append(message);printerr("FAIL ",message)
func frames(count:=8) -> void:
	for i in count:await process_frame
	await RenderingServer.frame_post_draw
func capture(name: String) -> void:
	await frames();check(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"capture "+name)
func own(node: Node,holder: Node) -> void:
	for child in node.get_children():
		child.owner=holder
		if child.scene_file_path.is_empty():own(child,holder)
func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	var old=load("res://scenes/compact_material_shapes_study.tscn").instantiate();root.add_child(old);current_scene=old
	while not old.styles_ready:await process_frame
	old.get_node("Instructions").hide();old.door.hide();old.walker.set_physics_process(false);old.followers.hide();old.followers.set_physics_process(false)
	old.set_material_style(0);old.set_look_view(0);old.follow_camera.set_process(false);old.follow_camera.set_physics_process(false)
	old.set_lighting_preset(1);old.set_sun_pose(1);old.reset_actors();old.follow_camera._process(0)
	var map: EmberMapLoader=old.get_node("Map")
	var production: ShaderMaterial=old._projection._ground_material
	for tile in old._projection._tiles.values():tile.get_node("Ground").material_override=production
	old.depth_material=production;old._sync_tuft_material()
	var grass_buffer: PackedFloat32Array=old.tuft_visual.multimesh.buffer.duplicate()
	var pose: Transform3D=old.follow_camera._cam.global_transform
	await capture("before-game")
	var ground=old._projection.document.working_copy()
	var changed:=0
	for z in ground.depth:
		for x in ground.width:
			var index: int=ground.column_index(x,z)
			if ground.top_materials[index]!=1:continue
			var point:=Vector2(x+0.5,z+0.5)/16.0
			var base:=0.30+0.12*sin(point.y*0.7)+0.22*(1.0-smoothstep(0.0,2.4,point.x))
			ground.heights[index]=roundi(base*16.0);ground.top_materials[index]=2;ground.base_materials[index]=2;changed+=1
	check(changed>0,"remove old terrain rock heights, not just hide their mesh")
	check(ResourceSaver.save(ground,"res://content/world_terrains/material_review_ground.tres")==OK,"save ordinary ground Source")
	ground.take_over_path("res://content/world_terrains/material_review_ground.tres")
	var review:=Node3D.new();review.name="EnvironmentMaterialReview";review.set_script(load("res://scripts/prototypes/ember_environment_material_review.gd"))
	review.player_start=old.walker.position
	review.camera_distance=old.follow_camera.follow_distance;review.camera_polar=old.follow_camera.polar_angle;review.camera_yaw=old.follow_camera.yaw;review.camera_look=old.follow_camera.look_height;review.camera_fov=old.follow_camera.fov
	var authored_map:=map.duplicate() as EmberMapLoader
	for child in authored_map.get_children():
		if child.name!="Look":authored_map.remove_child(child);child.free()
	authored_map.name="Map";authored_map.compact_terrain=ground;authored_map.map_id="environment_material_review"
	review.add_child(authored_map)
	var props:=Node3D.new();props.name="Props";authored_map.add_child(props)
	var source: EmberVoxelModelResource=load("res://content/voxel_models/vox_painted_rock_group.tres")
	var rock_prefab:=EmberVoxelPrefab.ensure_saved(source.model_id,16.0,{})
	check(rock_prefab!=null,"ordinary library prefab publication")
	var rocks:=rock_prefab.instantiate() as EmberVoxelProp
	rocks.name="PaintedRockGroup";rocks.configure_voxel_scale(16,1.0);rocks.position=Vector3(3,0,2);props.add_child(rocks)
	var oak:=EmberVoxelPrefab.prepare_resource(old.look_source).instantiate() as EmberVoxelProp
	oak.name="PaintedOak";oak.configure_voxel_scale(16,1.0);oak.transform=old.look_prop.transform;props.add_child(oak)
	var grass:=old.tuft_visual.duplicate() as MultiMeshInstance3D;grass.name="GrassTufts";review.add_child(grass)
	check(grass.multimesh.buffer==grass_buffer,"accepted grass positions and density unchanged")
	# Store bulky derived buffers compressed, not tens of MB of inline image
	# bytes in an authored text scene. Canonical voxel Sources stay separate.
	for entry in [[oak,"oak"]]:
		var visual: MeshInstance3D=entry[0].get_node("Mesh")
		var path:="res://prefabs/voxels/meshes/environment_review_%s.res"%entry[1]
		check(ResourceSaver.save(visual.mesh,path,ResourceSaver.FLAG_COMPRESS)==OK,"save derived mesh "+entry[1]);visual.mesh.take_over_path(path)
		var shape: CollisionShape3D=entry[0].get_node("Collision/Shape")
		path="res://prefabs/voxels/meshes/environment_review_%s_collision.res"%entry[1]
		check(ResourceSaver.save(shape.shape,path,ResourceSaver.FLAG_COMPRESS)==OK,"save derived collider "+entry[1]);shape.shape.take_over_path(path)
	var grass_path:="res://prefabs/voxels/meshes/environment_review_grass.res"
	check(ResourceSaver.save(grass.multimesh,grass_path,ResourceSaver.FLAG_COMPRESS)==OK,"save accepted grass buffer");grass.multimesh.take_over_path(grass_path)
	var material_path:="res://prefabs/voxels/meshes/environment_review_grass_material.res"
	check(ResourceSaver.save(grass.material_override,material_path,ResourceSaver.FLAG_COMPRESS)==OK,"save derived grass material");grass.material_override.take_over_path(material_path)
	own(review,review)
	var packed:=PackedScene.new();check(packed.pack(review)==OK,"pack actual ordinary scene")
	check(ResourceSaver.save(packed,"res://scenes/compact_environment_material_review.tscn")==OK,"save ordinary editor/play scene")
	review.free();root.remove_child(old);old.free()
	var saved: PackedScene=load("res://scenes/compact_environment_material_review.tscn")
	review=saved.instantiate();root.add_child(review);current_scene=review
	while not review.ready_for_play:await process_frame
	review.player.set_physics_process(false);review.camera.set_process(false)
	review.camera._cam.global_transform=pose
	var camera: Camera3D=review.camera._cam
	var game_pose:=pose;var game_fov:=camera.fov
	var physics_checks: Array=[]
	await physics_frame;await physics_frame
	for point in [Vector2(1.52,1.6),Vector2(1.96,2.8),Vector2(0.76,2.65),Vector2(2.98,2.28),Vector2(0.73,3.65),Vector2(4.65,1.4)]:
		var sample: Dictionary=review.get_node("Map").surface_floor_sample(Vector3(point.x,8,point.y))
		var query:=PhysicsRayQueryParameters3D.create(Vector3(point.x,8,point.y),Vector3(point.x,-2,point.y),1)
		var hit: Dictionary=review.get_world_3d().direct_space_state.intersect_ray(query)
		check(sample.get("solid",false) and not hit.is_empty(),"rock has real floor and collision")
		if not hit.is_empty():
			check(absf(sample.position.y-hit.position.y)<0.0001,"floor query matches physics ray")
			check(hit.collider.get_parent().model_id=="vox_painted_rock_group","physics hits new rock instead of old ground bump")
			physics_checks.append({"point":str(point),"height":sample.position.y,"physics_height":hit.position.y})
	var records: Array=[]
	for preset in 3:
		for side in 2:
			review.set_lighting(preset,side)
			for view in 2:
				camera.fov=game_fov;camera.global_transform=game_pose
				if view==1:camera.fov=40;camera.global_position=Vector3(3.0,3.1,6.5);camera.look_at(Vector3(2,1.1,2.5))
				var name:="after-%d-%d-%d"%[preset,side,view]
				await capture(name);records.append({"preset":preset,"side":side,"view":view,"file":name+".png"})
	var route: PackedVector3Array=review.get_node("Map").surface_navigation_path(Vector3(3.5,0.5,5.5),Vector3(0.5,0.5,1.5))
	check(not route.is_empty(),"existing navigation finds a route around/over the real surface")
	for point in route:
		var floor: Dictionary=review.get_node("Map").surface_floor_sample(point)
		check(floor.get("solid",false) and point.y>=floor.position.y,"navigation points stay above the same physical surface")
	var file:=FileAccess.open(output.path_join("native.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":errors.is_empty(),"errors":errors,"frames":records,"physics":physics_checks,"terrain_columns_lowered":changed,"navigation_points":route.size(),"scene":"res://scenes/compact_environment_material_review.tscn","source":"res://content/voxel_models/vox_painted_rock_group.tres","scope":"ordinary saved scene reopened before all AFTER captures; no LAB recipe on reopen","depth":"no new optical depth enabled"},"\t"));file.close()
	current_scene=null;root.remove_child(review);review.free();EmberVoxelPrefab.begin_import()
	rock_prefab=null;packed=null;saved=null
	await process_frame;await process_frame
	Node.print_orphan_nodes()
	print("ROCK_SHAPE_NATIVE ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)
