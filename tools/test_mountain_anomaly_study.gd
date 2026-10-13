extends SceneTree
const Smooth=preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")
var errors: Array[String]=[]
var capture:=false
var outputs:="C:/Users/novos/Documents/Codex/2026-10-12/new-chat-2/outputs"
var frames:="C:/Users/novos/Documents/Codex/2026-10-12/new-chat-2/work/mountain-frames"
func _initialize() -> void:run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok:errors.append(message);printerr("FAIL ",message)
func image_capture(name: String) -> void:
	await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	check(image.save_png(outputs.path_join(name))==OK,"capture "+name)
	print("CAPTURE ",name)
func run() -> void:
	capture="--capture-mountain" in OS.get_cmdline_user_args()
	var scene=load("res://scenes/compact_mountain_anomaly_study.tscn").instantiate();root.add_child(scene)
	var deadline:=Time.get_ticks_msec()+120000
	while not scene.ready_for_morph and Time.get_ticks_msec()<deadline:await process_frame
	check(scene.ready_for_morph,"study preparation completes")
	if not scene.ready_for_morph:quit(1);return
	var map=scene.get_node("Map");var source: Resource=map.compact_terrain;var original: Resource=source.working_copy()
	check(source.width==512 and source.depth==512 and source.width*source.depth==Smooth.MAX_COLUMNS,"32m detail grid")
	check(source.column_value("heights",source.column_index(256,256))>=280,"18m mountain")
	var projection=map._visual_surface_projection
	# Global alignment makes every shared edge identical, including mask feather.
	for key: Vector2i in scene.preparations:
		var entry: Dictionary=scene.preparations[key]
		for z in range(key.y*64,key.y*64+65):
			for x in range(key.x*64,key.x*64+65):
				var inside:=false
				for zone: Vector4 in scene.anomaly_zones:
					if Vector2(x/16.0-zone.x,z/16.0-zone.y).length()<zone.z:inside=true
				if not inside:
					check(Smooth.corner(entry.base,x,z)==Smooth.corner(entry.half,x,z) and Smooth.corner(entry.base,x,z)==Smooth.corner(entry.voxel,x,z),"outside mask stays exact")
		for delta in [Vector2i.RIGHT,Vector2i.DOWN]:
			var other_key: Vector2i=key+delta
			if not projection._tiles.has(other_key):continue
			var other_base: Dictionary=projection._smooth_field(other_key)
			var other_bounds:=Rect2i(other_key*64,Vector2i(64,64))
			var other_targets:=Smooth.anomaly_targets(other_base,other_bounds,scene.anomaly_zones,source.origin_y,Smooth.field(source,other_bounds.grow(8)))
			for t in 65:
				var p:=key*64+(Vector2i(64,t) if delta==Vector2i.RIGHT else Vector2i(t,64))
				check(absf(Smooth.corner(entry.half,p.x,p.y)-Smooth.corner(other_targets[0],p.x,p.y))<0.001,"half seam "+str(p))
				check(absf(Smooth.corner(entry.voxel,p.x,p.y)-Smooth.corner(other_targets[1],p.x,p.y))<0.001,"voxel seam "+str(p))
	if capture:await image_capture("mountain-overview.png")
	var camera:=scene.get_node("Camera3D") as Camera3D
	if capture:camera.look_at_from_position(Vector3(39,30,42),Vector3(18,9,20))
	for phase in [0.0,0.25,0.5,0.75,1.0,0.0]:
		scene.set_phase(phase);await physics_frame;await physics_frame
		for key: Vector2i in scene.preparations:
			var entry: Dictionary=scene.preparations[key]
			var mesh:=entry.ground.mesh as ArrayMesh
			check(mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]==entry.ground.bake_mesh_from_current_blend_shape_mix().surface_get_arrays(0)[Mesh.ARRAY_COLOR],"morph keeps coverage weights")
			var faces: PackedVector3Array=(projection._tiles[key].get_node("GroundPhysics/Shape").shape as ConcavePolygonShape3D).get_faces()
			for i in range(0,faces.size(),maxi(1,faces.size()/97)):
				check(absf(faces[i].y-Smooth.corner(entry.current,roundi(faces[i].x),roundi(faces[i].z)))<0.002,"mesh/collision/field match")
		for point in [Vector2(21.14,19.23),Vector2(13.31,23.12),Vector2(20.43,20.31),Vector2(8.2,7.6)]:
			var expected: Dictionary=map.surface_floor_sample(Vector3(point.x,30,point.y))
			var query:=PhysicsRayQueryParameters3D.create(Vector3(point.x,30,point.y),Vector3(point.x,-1,point.y))
			var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(query)
			check(not hit.is_empty(),"terrain ray hit")
			if not hit.is_empty():check(absf(hit.position.y-expected.position.y)<0.002,"ray agrees with shared floor phase="+str(phase))
		if capture:
			var names: Dictionary={0.0:"mountain-smooth.png",0.25:"mountain-transition.png",0.5:"mountain-half.png",0.75:"mountain-transition-voxel.png",1.0:"mountain-voxel.png"}
			await image_capture(names[phase])
	for entry: Dictionary in scene.preparations.values():check(entry.current.heights==entry.base.heights,"return to exact base")
	check(source.same_terrain_data(original),"morph never writes source, water, roles or overrides")
	# Exercise the actual runtime controls, rather than only the leaf math.
	var row:=scene._status.get_parent().get_child(2) as HBoxContainer
	for i in 3:
		row.get_child(i).pressed.emit();check(is_equal_approx(scene.phase,i*0.5),"state button "+str(i))
	scene._slider.value=0.37;check(is_equal_approx(scene.phase,0.37),"phase slider")
	scene._status.get_parent().get_child(3).pressed.emit()
	for i in 8:await process_frame
	check(scene.playing and scene.phase>0.37,"continuous playback advances")
	scene._status.get_parent().get_child(3).pressed.emit();check(not scene.playing,"playback pause")
	scene.set_phase(0.0)
	var packed:=PackedScene.new();check(packed.pack(scene)==OK,"study pack")
	var path:="user://mountain-anomaly-reopen.tscn";check(ResourceSaver.save(packed,path)==OK,"save study")
	var reopened=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP).instantiate()
	check(reopened.anomaly_zones==scene.anomaly_zones and reopened.get_node("Map").compact_terrain.same_terrain_data(source),"reopen source and zones");reopened.free()
	if capture and errors.is_empty():
		DirAccess.make_dir_recursive_absolute(frames)
		# Forward+ renders, sampled along the same continuous phase used by controls.
		for i in 64:
			scene.set_phase(float(i)/31.0 if i<32 else float(63-i)/31.0)
			await process_frame;await RenderingServer.frame_post_draw
			var image:=root.get_texture().get_image();image.resize(960,540,Image.INTERPOLATE_LANCZOS)
			image.save_png(frames.path_join("frame_%03d.png"%i))
		scene.set_phase(0.0)
	print("MOUNTAIN_METRIC phase_max_ms=",scene.worst_phase_us/1000.0," bake_ms=",scene.worst_bake_us/1000.0," field_ms=",scene.worst_field_us/1000.0," collision_ms=",scene.worst_collision_us/1000.0," affected_tiles=",scene.preparations.size())
	print("MOUNTAIN_ANOMALY ","PASS" if errors.is_empty() else errors)
	scene.queue_free();await process_frame;await process_frame
	quit(0 if errors.is_empty() else 1)
