extends SceneTree
const Smooth=preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")
const Mesher=preload("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")
const Brush=preload("res://addons/ember_import/ember_compact_terrain_brush.gd")
const Cache=preload("res://scripts/prototypes/ember_terrain_geometry_cache.gd")
var errors: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(ok: bool,message: String) -> void:
	if not ok:errors.append(message);printerr("FAIL ",message)
func settle(map: EmberMapLoader) -> void:
	var projection=map._visual_surface_projection
	var deadline:=Time.get_ticks_msec()+60000
	while projection.pending_tile_count()>0 and Time.get_ticks_msec()<deadline:await process_frame
	check(projection.pending_tile_count()==0,"tile build completed")
	await physics_frame;await physics_frame;await process_frame
func border_materials(mesh: ArrayMesh) -> Dictionary:
	var arrays:=mesh.surface_get_arrays(0);var result: Dictionary={}
	for i in arrays[Mesh.ARRAY_VERTEX].size():
		var p: Vector3=arrays[Mesh.ARRAY_VERTEX][i]
		var normal: Vector3=arrays[Mesh.ARRAY_NORMAL][i]
		if p.x!=64.0 or normal.y<0.1:continue
		var colour: Color=arrays[Mesh.ARRAY_COLOR][i]
		var uv: Vector2=arrays[Mesh.ARRAY_TEX_UV][i];var uv2: Vector2=arrays[Mesh.ARRAY_TEX_UV2][i]
		var slots: Array[int]=[roundi(uv.x*255.0),roundi(uv.y*255.0),roundi(uv2.x*255.0)]
		var weights:=Vector3.ZERO;var sum:=colour.r+colour.g+colour.b
		for j in 3:
			if slots[j]>=1 and slots[j]<=3:weights[slots[j]-1]+=colour[j]/sum
		result[Vector2(p.x,p.z)]=weights
	return result
func run() -> void:
	var base=load("res://content/world_terrains/cartoon_relief_base.res")
	var detail=load("res://content/world_terrains/cartoon_relief_detail.res")
	check(base!=null and detail!=null,"saved sources present")
	if base==null or detail==null:quit(1);return
	check(base.validation_errors().is_empty() and detail.validation_errors().is_empty(),"source validation")
	check(base.top_materials==detail.top_materials and base.palette_material_ids==detail.palette_material_ids,"same material distribution")
	var before: PackedInt32Array=detail.heights.duplicate()
	var a:=Smooth.field(base,Rect2i(0,0,192,128));var b:=Smooth.field(detail,Rect2i(0,0,192,128))
	var maxima: Array[float]=[0.0,0.0,0.0,0.0]
	var core_maxima: Array[float]=[0.0,0.0,0.0,0.0]
	var non_strip_rows:=0
	for z in range(12,116):
		var transitions:=0
		for x in range(1,detail.width):
			if detail.top_materials[x+z*detail.width]!=detail.top_materials[x-1+z*detail.width]:transitions+=1
		if transitions>2:non_strip_rows+=1
		for x in range(12,180):
			var role: int=detail.top_materials[x+z*detail.width]
			var delta:=absf(Smooth.corner(b,x,z)-Smooth.corner(a,x,z))/16.0
			maxima[role]=maxf(maxima[role],delta)
			var core:=true
			for oz in [-8,0,8]:
				for ox in [-8,0,8]:
					if detail.top_materials[x+ox+(z+oz)*detail.width]!=role:core=false
			if core:core_maxima[role]=maxf(core_maxima[role],delta)
	check(non_strip_rows>15,"material layout includes pockets and outcrops")
	check(maxima[3]>0.5,"stone changes physical silhouette")
	check(core_maxima[2]>0.04 and core_maxima[2]<0.3,"sand core has restrained physical crests")
	check(core_maxima[1]>0.03 and core_maxima[1]<0.2,"soil core relief remains quiet")
	var rock=load("res://content/terrain_materials/cartoon_relief_stone.tres")
	check(rock!=null and rock.albedo_texture!=null and rock.pixel_relief>0.0,"rock artwork supports optical relief")
	var left:=Smooth.field(detail,Rect2i(0,0,64,64));var right:=Smooth.field(detail,Rect2i(64,0,64,64))
	for z in range(2,62):
		check(absf(Smooth.corner(left,64,z)-Smooth.corner(right,64,z))<0.00001,"relief tile height seam")
		check(Smooth.normal(left,64,z).distance_to(Smooth.normal(right,64,z))<0.00001,"relief tile normal seam")
	var geometry:=Mesher.build_tile(detail,0,0,64,0,false,PackedVector4Array(),{},false,false,true,true)
	check(geometry.collision_faces==geometry.terrain.surface_get_arrays(0)[Mesh.ARRAY_VERTEX],"relief mesh/collider exact triangles")
	var joined:=Mesher.build_tile(detail,64,0,64,0,false,PackedVector4Array(),{},false,false,true,true)
	var sectioned:=Mesher.build_tile(detail.sectioned_copy(),64,0,64,0,false,PackedVector4Array(),{},false,false,true,true)
	var joined_arrays: Array=joined.terrain.surface_get_arrays(0)
	var edge_a:=border_materials(geometry.terrain);var edge_b:=border_materials(joined.terrain)
	var seam_error:=0.0
	for p: Vector2 in edge_a:
		check(edge_b.has(p),"same border nodes")
		if edge_b.has(p):seam_error=maxf(seam_error,(edge_a[p] as Vector3).distance_to(edge_b[p]))
	check(edge_a.size()>40 and seam_error<0.01,"shared material weights across tile seam")
	var section_arrays: Array=sectioned.terrain.surface_get_arrays(0)
	for channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2]:
		check(joined_arrays[channel]==section_arrays[channel],"dense/sectioned blend data equality")
	var blended_vertices:=0
	var maximum_weight_error:=0.0
	for colour: Color in joined_arrays[Mesh.ARRAY_COLOR]:
		maximum_weight_error=maxf(maximum_weight_error,absf(colour.r+colour.g+colour.b-1.0))
		if maxf(colour.r,maxf(colour.g,colour.b))<0.95:blended_vertices+=1
	# ArrayMesh quantizes vertex COLOR to 8 bits; the shader renormalizes RGB.
	check(maximum_weight_error<=1.5/255.0,"blend weights normalized within GPU colour precision")
	check(blended_vertices>100,"material border has actual mixed weights")
	var cache:=Cache.new();cache.directory="user://cartoon-relief-blend-cache"
	cache.write_geometry("blended-fixture",joined)
	var cached:=cache.read_geometry("blended-fixture")
	check(not cached.is_empty() and cached.terrain.surface_get_arrays(0)[Mesh.ARRAY_COLOR]==joined_arrays[Mesh.ARRAY_COLOR],"cache retains feathered colour weights")
	check(detail.heights==before,"projection does not mutate fixture")
	check(ResourceSaver.save(detail,"user://cartoon-relief-reopen.res")==OK,"Resource save")
	var saved=ResourceLoader.load("user://cartoon-relief-reopen.res","",ResourceLoader.CACHE_MODE_IGNORE)
	check(saved!=null and saved.same_terrain_data(detail),"Resource reopen exact")
	var scene=load("res://scenes/compact_cartoon_relief_study.tscn").instantiate()
	root.add_child(scene);current_scene=scene
	var map:=scene.get_node("Map") as EmberMapLoader
	check(map.compact_smooth_material_blend,"scene opts into feathered materials")
	var with_blend: Array=map._visual_surface_projection._geometry_policy()
	map.compact_smooth_material_blend=false
	check(with_blend!=map._visual_surface_projection._geometry_policy(),"blend cache policy distinct")
	map.compact_smooth_material_blend=true
	var scene_save:=PackedScene.new();check(scene_save.pack(scene)==OK,"scene pack")
	check(ResourceSaver.save(scene_save,"user://cartoon-relief-scene-reopen.tscn")==OK,"scene save")
	var reopened=load("user://cartoon-relief-scene-reopen.tscn").instantiate()
	check(reopened.get_node("Map").compact_smooth_material_blend,"scene blend flag reopens")
	reopened.free()
	var keyboard:=InputEventKey.new();keyboard.keycode=KEY_B;keyboard.pressed=true
	for version in 3:
		await settle(map)
		var expected_source=base if version==1 else detail
		check(map.compact_terrain==expected_source,"B switches existing terrain owner")
		var projection=map._visual_surface_projection
		for x in [2.1,5.6,9.7]:
			for z in [2.1,4.2,6.3]:
				var ray:=PhysicsRayQueryParameters3D.create(Vector3(x,20,z),Vector3(x,-2,z))
				var hit:=root.world_3d.direct_space_state.intersect_ray(ray)
				var floor=projection.floor_surface_sample(Vector3(x,0,z))
				check(not hit.is_empty() and hit.position.distance_to(floor.position)<0.001,"physics/sampler same relief")
				var pick=projection.pick_ground_top(ray.from,ray.to)
				check(not pick.is_empty() and pick.world.distance_to(floor.position)<0.001,"brush pick same relief")
		if version<2:scene._unhandled_input(keyboard)
	check(base.top_materials==detail.top_materials and detail.heights==before,"comparison leaves source unchanged")
	# Edits stay in a private fixture, including neighbouring material feathering.
	var draft=detail.working_copy();map.compact_terrain=draft;await settle(map)
	var tile=map._visual_surface_projection.get_node("TerrainTile_1_0/Ground")
	var colours_before: PackedColorArray=tile.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var saved_tops: PackedByteArray=draft.top_materials.duplicate()
	var history:=UndoRedo.new();var brush:=Brush.new()
	brush.configure({"resource":draft,"target":weakref(map)},history,map)
	check(brush.begin("paint",0.0625,1,1,0,1,0,7,0),"blend material brush begin")
	brush.stamp(Vector2i(62,44));brush.end();await settle(map)
	check(tile.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]!=colours_before,"paint feathers into neighbour tile")
	history.undo();await settle(map)
	check(draft.top_materials==saved_tops and tile.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]==colours_before,"Undo restores source and feathered neighbour")
	history.redo();await settle(map);check(draft.top_materials!=saved_tops,"paint Redo")
	history.undo();await settle(map)
	check(detail.heights==before and detail.top_materials==base.top_materials,"author fixture unchanged by edit checks")
	history.free()
	scene.queue_free();await process_frame
	print("CARTOON_RELIEF ","PASS" if errors.is_empty() else "FAIL"," displacement_m=",maxima," core_m=",core_maxima," mixed_vertices=",blended_vertices," pocket_rows=",non_strip_rows," ",errors)
	quit(0 if errors.is_empty() else 1)
