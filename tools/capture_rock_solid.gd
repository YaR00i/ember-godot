extends "res://tools/capture_tree_foliage21_study.gd"
## Visual-only LAB: six existing fixture masses -> closed, flat-faced solids.
## Not an object authoring/floor/navigation integration or a general voxel converter.
const Smooth=preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")
const Fixture=preload("res://scripts/prototypes/ember_painted_light_fixture.gd")
const SPECS=[
	[Vector2(1.52,1.60),Vector2(1.05,0.92),2.0,-0.12],
	[Vector2(1.96,2.80),Vector2(1.03,0.82),1.67,0.16],
	[Vector2(0.76,2.65),Vector2(0.40,0.55),0.92,-0.38],
	[Vector2(2.98,2.28),Vector2(0.31,0.59),1.03,-0.27],
	[Vector2(0.73,3.65),Vector2(0.32,0.30),0.50,-0.23],
	[Vector2(4.65,1.40),Vector2(0.40,0.35),0.56,-0.23]]

func base_height(p: Vector2) -> float:
	return 0.30+0.12*sin(p.y*0.7)+0.22*(1.0-smoothstep(0.0,2.4,p.x))

func side_slope(points: PackedVector3Array, horizontal: Vector3) -> float:
	# Sample the occupied columns at several heights. Their outer extent gives
	# the side slope directly, without smoothing or inventing a random lean.
	var bottom:=INF;var top:=-INF
	for p in points:bottom=minf(bottom,p.y);top=maxf(top,p.y)
	var levels:=PackedFloat32Array();var extents:=PackedFloat32Array()
	for fraction in [0.20,0.30,0.40,0.50,0.60,0.70]:
		var level:=lerpf(bottom,top,fraction);var extent:=-INF
		for p in points:
			if p.y>=level:extent=maxf(extent,horizontal.dot(p))
		levels.append(level);extents.append(extent)
	var mean_y:=0.0;var mean_extent:=0.0
	for i in levels.size():mean_y+=levels[i];mean_extent+=extents[i]
	mean_y/=levels.size();mean_extent/=levels.size()
	var covariance:=0.0;var variance:=0.0
	for i in levels.size():
		covariance+=(levels[i]-mean_y)*(extents[i]-mean_extent)
		variance+=pow(levels[i]-mean_y,2)
	return covariance/maxf(variance,0.000001)

func solid(points: PackedVector3Array, angle: float, fit_sides:=true, detailed:=false) -> Dictionary:
	# Six principal sides, four upper cuts, four corner cuts. Distances come
	# from the occupied Source columns; no filtered heightfield or normals.
	var directions: Array[Vector3]=[Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.FORWARD,Vector3.BACK,
		Vector3(1,1.2,0),Vector3(-1,1.7,0),Vector3(0,1.4,1),Vector3(0,1.1,-1),
		Vector3(1,0,1),Vector3(-1,0,1),Vector3(1,0,-1),Vector3(-1,0,-1)]
	if detailed:
		directions.append_array([Vector3(1,1,1),Vector3(-1,1,1),Vector3(1,1,-1),Vector3(-1,1,-1)])
	var planes: Array[Plane]=[]
	var side_angles: Array[float]=[]
	for direction in directions:
		var n:=direction.normalized().rotated(Vector3.UP,angle)
		if fit_sides and absf(n.y)<0.00001:
			var slope:=side_slope(points,n)
			n=Vector3(n.x,-slope,n.z).normalized()
			side_angles.append(rad_to_deg(atan(-slope)))
		var d:=-INF
		for p in points:d=maxf(d,n.dot(p))
		planes.append(Plane(n,d))
	# Coincident intersections of several clipping planes may repeat a corner.
	# Keep one copy, otherwise fan triangulation emits zero-area triangles.
	var corners:=PackedVector3Array()
	for candidate in Geometry3D.compute_convex_mesh_points(planes):
		var duplicate:=false
		for p in corners:
			if candidate.distance_squared_to(p)<0.000001:duplicate=true;break
		if not duplicate:corners.append(candidate)
	check(corners.size()>=4,"closed solid has vertices")
	for plane in planes:
		for p in points:check(plane.distance_to(p)<0.003,"support plane retains source points")
	var vertices:=PackedVector3Array();var normals:=PackedVector3Array()
	var colours:=PackedColorArray();var uv:=PackedVector2Array();var uv2:=PackedVector2Array()
	var face_count:=0
	for plane in planes:
		var face: Array[Vector3]=[];var centre:=Vector3.ZERO
		for p in corners:
			if absf(plane.distance_to(p))<0.002:
				face.append(p);centre+=p
		if face.size()<3:continue
		centre/=float(face.size())
		var axis:=(face[0]-centre).normalized()
		var across:=plane.normal.cross(axis)
		face.sort_custom(func(a: Vector3,b: Vector3):return atan2((a-centre).dot(across),(a-centre).dot(axis))<atan2((b-centre).dot(across),(b-centre).dot(axis)))
		face_count+=1
		for i in range(1,face.size()-1):
			if (face[i]-face[0]).cross(face[i+1]-face[0]).length_squared()<0.00000001:continue
			# Godot front faces are clockwise.
			for p: Vector3 in [face[0],face[i+1],face[i]]:
				vertices.append(p);normals.append(plane.normal)
				colours.append(Color(1,0,0,1.0/255.0));uv.append(Vector2.ONE/255.0);uv2.append(Vector2(1.0/255.0,0))
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_COLOR]=colours;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_TEX_UV2]=uv2
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return {"mesh":mesh,"faces":face_count,"triangles":vertices.size()/3,"source_points":points.size(),"side_angles_degrees":side_angles}

func capture_looks(_source, _clouds: Array[PackedVector3Array], _nodes: Array[MeshInstance3D]) -> Dictionary:
	return {}

func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	scene=load("res://scenes/compact_natural_rock_study.tscn").instantiate();root.add_child(scene);current_scene=scene
	while not scene.rock_ready:await process_frame
	scene.get_node("Instructions").hide();scene.walker.set_physics_process(false);scene.followers.hide();scene.followers.set_physics_process(false)
	scene.follow_camera.set_process(false);scene.follow_camera.set_physics_process(false);scene.reset_actors()
	scene.set_lighting_preset(1);scene.set_sun_pose(1);scene.set_rock_view(0)
	scene.follow_camera.set_process(false);scene.follow_camera.look_height=1.35
	scene.follow_camera.reset_follow_height();scene.follow_camera._process(0)
	scene.set_material_style(0);scene.set_plain_rock(true)
	var source=scene._projection.document
	var source_hash: int=hash(source.heights)
	var grass_hash: int=hash(scene.tuft_visual.multimesh.buffer)
	var grass_material: Material=scene.tuft_visual.material_override
	var depth_hash: int=hash(scene.height_texture.get_image().get_data())
	var camera_pose: Transform3D=scene.follow_camera._cam.global_transform
	var ground=source.working_copy()
	var clouds: Array[PackedVector3Array]=[]
	for spec in SPECS:clouds.append(PackedVector3Array())
	for z in source.depth:
		for x in source.width:
			var p:=Vector2((x+0.5)/16.0,(z+0.5)/16.0)
			var best:=-1;var height:=0.0
			for id in SPECS.size():
				var spec: Array=SPECS[id]
				var h:=Fixture.rock_height(p,spec[0],spec[1],spec[2],spec[3])
				if h>height:height=h;best=id
			if best<0 or height<=0.05:continue
			var column: int=source.column_index(x,z)
			# Interior columns describe the principal mass; exclude the low
			# terrain skirt that made the previous result look rooted in soil.
			if height>float(SPECS[best][2])*0.22:
				for offset: Vector2 in [Vector2.ZERO,Vector2.RIGHT,Vector2.DOWN,Vector2.ONE]:
					clouds[best].append(Vector3(x+offset.x,source.heights[column]+source.origin_y,z+offset.y))
					clouds[best].append(Vector3(x+offset.x,(base_height(p)-0.08)*16.0+source.origin_y,z+offset.y))
			ground.heights[column]=roundi(base_height(p)*16.0)
			ground.top_materials[column]=2;ground.base_materials[column]=2
	for key: Vector2i in scene._projection._tiles:
		var begin:=key*64
		var bounds:=Rect2i(begin,Vector2i(mini(64,source.width-begin.x),mini(64,source.depth-begin.y)))
		var built:=Smooth.build(ground,bounds,true,true,Smooth.field(ground,bounds))
		built.terrain.surface_set_material(0,scene.plain_materials[0])
		scene._projection._tiles[key].get_node("Ground").mesh=built.terrain
		await process_frame
	var stats: Array=[];var rock_nodes: Array[MeshInstance3D]=[]
	for id in clouds.size():
		check(not clouds[id].is_empty(),"rock source points")
		var result:=solid(clouds[id],SPECS[id][3],false)
		var node:=MeshInstance3D.new();node.name="ClosedRock%d"%id;node.mesh=result.mesh
		node.material_override=scene.plain_materials[0];scene._projection.add_child(node)
		rock_nodes.append(node)
	await capture("before")
	for id in clouds.size():
		var result:=solid(clouds[id],SPECS[id][3])
		rock_nodes[id].mesh=result.mesh
		check(result.faces>=6 and result.faces<=14,"bounded principal face count")
		stats.append({"rock":id,"faces":result.faces,"triangles":result.triangles,"source_points":result.source_points,"side_angles_degrees":result.side_angles_degrees})
	await capture("after")
	var looks:=await capture_looks(source,clouds,rock_nodes)
	check(source_hash==hash(source.heights),"authored source preserved")
	check(grass_hash==hash(scene.tuft_visual.multimesh.buffer) and grass_material==scene.tuft_visual.material_override,"grass preserved")
	check(depth_hash==hash(scene.height_texture.get_image().get_data()),"depth source preserved")
	check(camera_pose==scene.follow_camera._cam.global_transform,"camera preserved")
	var file:=FileAccess.open(output.path_join("native.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":errors.is_empty(),"errors":errors,"rocks":stats,"looks":looks,"scope":"static visual fixture only; physics/floor/navigation integration NOT implemented; original Source unchanged","art_acceptance":"OPEN"},"\t"));file.close()
	print("ROCK_SOLID_NATIVE ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)
