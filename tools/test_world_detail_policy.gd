extends SceneTree
const Policy=preload("res://scripts/prototypes/ember_world_detail_policy.gd")
const Surface=preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")
const Fixture=preload("res://tools/fixtures/ember_smooth_tools_fixture.gd")
const Cache=preload("res://scripts/prototypes/ember_terrain_geometry_cache.gd")
var errors:Array[String]=[]
func check(ok:bool,why:String)->void:
	if not ok:errors.append(why);push_error(why)
func _initialize()->void:run.call_deferred()
func boundary(points:PackedVector3Array,bounds:Rect2i)->Dictionary:
	var result:Dictionary={}
	for p in points:
		if p.x==bounds.position.x or p.z==bounds.position.y or p.x==bounds.end.x or p.z==bounds.end.y:result[p]=true
	return result
func run()->void:
	var policy:=Policy.new()
	var near:=Rect2(Vector2(17*16,0),Vector2.ONE*16)
	check(policy.ground_full(near,false),"new near terrain is detailed")
	var band:=Rect2(Vector2(21*16,0),Vector2.ONE*16)
	check(not policy.ground_full(band,false) and policy.ground_full(band,true),"ground hysteresis")
	check(policy.ground_full(Rect2(Vector2.ONE*9999,Vector2.ONE),false,true),"editing protects a remote tile")
	check(policy.detail_resident(Rect2(Vector2(31*16,0),Vector2.ONE),true) and not policy.detail_resident(Rect2(Vector2(31*16,0),Vector2.ONE),false),"detail residency hysteresis")
	check(policy.detail_resident(Rect2(Vector2(29.5*16,0),Vector2.ONE),false),"cold scatter starts before the budgeted-resume deadline")
	check(policy.detail_fade_begin_m==16.0 and policy.detail_fade_end_m==24.0 and policy.detail_release_m==32.0,"preparation lead never changes visible coverage or release distance")
	var source=Fixture.base()
	source.heights.fill(24);source.top_materials.fill(2)
	var before:=source.working_copy()
	var bounds:=Rect2i(16,16,64,64)
	var full:=Surface.build_arrays(source,bounds,true)
	var far:=Surface.build_arrays(source,bounds,true,true,{},true,Callable(),8)
	check(Surface.publish_arrays(far).terrain.surface_get_array_len(0)==6,"planar render mesh has two triangles")
	check(boundary(full.collision_faces,bounds)==boundary(far.arrays[Mesh.ARRAY_VERTEX],bounds),"fine perimeter is exact")
	var points:PackedVector3Array=far.arrays[Mesh.ARRAY_VERTEX]
	for i in range(0,points.size(),3):
		check(is_equal_approx(points[i].y,24.0) and is_equal_approx(points[i+1].y,24.0) and is_equal_approx(points[i+2].y,24.0),"planar physical height preserved")
		check((points[i+1]-points[i]).cross(points[i+2]-points[i]).y<0,"far triangles preserve clockwise winding")
	# Mixed paint and cavities must not be swallowed by planar coalescing.
	source.top_materials[source.column_index(40,40)]=3
	source.heights[source.column_index(44,44)]=0
	var exact:=Surface.build_arrays(source,bounds,true)
	var protected:=Surface.build_arrays(source,bounds,true,true,{},true,Callable(),8)
	check(exact.collision_faces==protected.collision_faces,"mixed paint/holes keep the exact physical surface")
	check(boundary(exact.collision_faces,bounds)==boundary(protected.arrays[Mesh.ARRAY_VERTEX],bounds),"mixed paint/holes keep fine borders")
	check(before.heights[40+40*128]==24 and source.heights[40+40*128]==24,"derived build does not change authored heights")
	# Camera selection reuses one canonical base plus native LOD levels; cache preserves both.
	var cache:=Cache.new();cache.directory="user://world-detail-policy-test"
	var options:Dictionary={"far_stride":8}
	var first=cache.editor_job(before,Vector2i.ZERO,true,options);first.run(func():return false)
	var second=cache.editor_job(before,Vector2i.ZERO,true,options);second.run(func():return false)
	check(second.cache_hit and first.result.arrays==second.result.arrays and first.result.collision_faces==second.result.collision_faces,"far cached arrays roundtrip")
	var detailed=cache.editor_job(before,Vector2i.ZERO,true,{"far_stride":1});detailed.run(func():return false)
	check(detailed.result.arrays==second.result.arrays and detailed.result.render_detail==second.result.render_detail,"camera distance does not regenerate canonical geometry")
	var saved_key:String=cache.tile_key(before,Vector2i.ZERO,0,["editor-top-native-lod-v1",true],PackedVector4Array(),{})
	var broken:Dictionary=cache.disk.read(saved_key)
	check(broken.get("editor_version")==3,"cache explicitly transports native render detail")
	broken.render_detail.indices=PackedInt32Array([0,1,999999])
	cache.disk.write(saved_key,broken,func():return false)
	var repaired=cache.editor_job(before,Vector2i.ZERO,true,options);repaired.run(func():return false)
	check(not repaired.cache_hit and repaired.invalid>0 and repaired.result.collision_faces==detailed.result.collision_faces,"malformed render indices rebuild safely without altering collision")
	# Curved geometry on a mixed tile must now reduce beyond planar-only spans.
	source=before.working_copy()
	for z in source.depth:
		for x in range(48,source.width):source.top_materials[source.column_index(x,z)]=1
	var field:=Surface.field(source,bounds)
	for z in field.size.y:
		for x in field.size.x:
			var at:Vector2i=field.start+Vector2i(x,z)
			field.heights[x+z*field.size.x]=24.0+0.0005*at.x*at.x+0.02*at.y
	var curved_full:=Surface.build_arrays(source,bounds,true,true,field)
	var curved_far:=Surface.build_arrays(source,bounds,true,true,field,true,Callable(),32)
	check(not curved_far.render_detail.lods.is_empty() and curved_far.render_detail.lods.values()[0].size()<curved_full.collision_faces.size()*0.8,"curved mixed surface has a real native reduction")
	check(curved_far.collision_faces==curved_full.collision_faces and curved_far.smooth_field==curved_full.smooth_field,"far display leaves physical faces/height sampling exact")
	var material_cache:Dictionary={}
	var positions:PackedVector3Array=curved_far.arrays[Mesh.ARRAY_VERTEX]
	for i in positions.size():
		if curved_far.arrays[Mesh.ARRAY_NORMAL][i].y<=0:continue
		var color:Color=curved_far.arrays[Mesh.ARRAY_COLOR][i]
		var uv:Vector2=curved_far.arrays[Mesh.ARRAY_TEX_UV][i]
		var uv2:Vector2=curved_far.arrays[Mesh.ARRAY_TEX_UV2][i]
		var decoded:Dictionary={}
		for pair in [[roundi(uv.x*255),color.r],[roundi(uv.y*255),color.g],[roundi(uv2.x*255),color.b]]:decoded[pair[0]]=decoded.get(pair[0],0.0)+pair[1]
		var expected:Dictionary=Surface.material_weights(source,Vector2i(roundi(positions[i].x),roundi(positions[i].z)),material_cache)
		for slot in expected:check(absf(expected[slot]-decoded.get(slot,0.0))<0.00001,"actual far vertex preserves material weights")
	var first_error:float=curved_far.render_detail.lods.keys()[0]
	var render_points:=PackedVector3Array()
	for index in curved_far.render_detail.lods[first_error]:render_points.append(positions[index])
	var world:=Node3D.new();root.add_child(world)
	for spec in [[1,curved_full.collision_faces],[2,render_points]]:
		var body:=StaticBody3D.new();body.collision_layer=spec[0];body.collision_mask=0;world.add_child(body)
		var shape:=CollisionShape3D.new();var triangles:=ConcavePolygonShape3D.new();triangles.set_faces(spec[1]);shape.shape=triangles;body.add_child(shape)
	await physics_frame;await physics_frame
	var largest:=0.0
	for z in 15:
		for x in 15:
			var at:=Vector3(17.13+x*4.1,100,17.27+z*4.1)
			var hits:Array=[]
			for mask in [1,2]:hits.append(world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at,at-Vector3.UP*200,mask)))
			check(not hits[0].is_empty() and not hits[1].is_empty(),"real simplified mesh has no missing triangles")
			if not hits[0].is_empty() and not hits[1].is_empty():largest=maxf(largest,absf(hits[0].position.y-hits[1].position.y))
	check(largest<=first_error+0.0001,"rendered triangle interpolation stays within distance error budget")
	world.free()
	var sectioned=before.sectioned_copy()
	var section_job=cache.editor_job(sectioned,Vector2i(1,1),true,options);section_job.run(func():return false)
	check(section_job.tile_data.render_detail.planar or not section_job.tile_data.render_detail.lods.is_empty(),"section offset preserves separate render/physical topology")
	var detail_job=cache.editor_job(sectioned,Vector2i(1,1),true,{"far_stride":1});detail_job.run(func():return false)
	check(section_job.tile_data.collision_faces==detail_job.tile_data.collision_faces,"sectioned full/far collision positions are exact")
	# Indexed base publication retains the alternate-look contract and edit layout.
	var bake=load("res://scripts/prototypes/ember_terrain_look_bake.gd")
	var indexed:ArrayMesh=Surface.publish_arrays(curved_far).terrain
	var fine:ArrayMesh=Surface.publish_render_mesh(curved_far.arrays)
	var low=bake.faceted(indexed,curved_far.smooth_field,8,source)
	var fine_low=bake.faceted(fine,curved_far.smooth_field,8,source)
	check(low.mesh.surface_get_arrays(0)==fine_low.mesh.surface_get_arrays(0),"indexed low-poly appearance preserves every fine channel")
	var carrier=bake._anomaly_arrays(func():return false,indexed.surface_get_arrays(0),low.mesh.surface_get_arrays(0),source,curved_far.smooth_field,bounds)
	var fine_carrier=bake._anomaly_arrays(func():return false,fine.surface_get_arrays(0),fine_low.mesh.surface_get_arrays(0),source,curved_far.smooth_field,bounds)
	check(carrier==fine_carrier,"indexed third-look carrier preserves its existing topology")
	var edit=before.working_copy();edit.heights[edit.column_index(44,44)]+=4
	var job=Surface.height_update_job(edit,bounds,far.layout);job.run(func():return false)
	var rebuilt=Surface.build_arrays(edit,bounds,true,true,{},true)
	check(job.result.arrays==rebuilt.arrays and job.result.collision_faces==rebuilt.collision_faces and job.result.render_detail.lods==rebuilt.render_detail.lods,"height update keeps exact fine physics and regenerates native LOD")
	var mesher=load("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")
	var generated=mesher.build_tile(before,16,16,64,0,false,PackedVector4Array(),{},false,false,true,true)
	var runtime_key:=cache.tile_key(before,Vector2i(1,1),0,["runtime-native-lod"],PackedVector4Array(),{})
	cache.write_geometry(runtime_key,generated)
	var cached:=cache.read_geometry(runtime_key)
	check(not cached.is_empty() and cached.collision_faces==generated.collision_faces and cached.terrain.surface_get_arrays(0)==generated.terrain.surface_get_arrays(0),"runtime cache preserves planar display and separate exact collision")
	# Material blending must never switch geometric detail off. Nonblend keeps
	# its canonical barycentric colours; only simplifier weights may be equivalent.
	var unblended:=Surface.build_arrays(source,bounds,false,true,field,true)
	check(unblended.collision_faces==curved_full.collision_faces,"both paint modes share exact physical geometry")
	check(not unblended.render_detail.lods.is_empty(),"nonblend curved surface has native LOD")
	var canonical_colours:PackedColorArray=unblended.arrays[Mesh.ARRAY_COLOR]
	for i in canonical_colours.size():
		var weights:=Vector3(canonical_colours[i].r,canonical_colours[i].g,canonical_colours[i].b)
		check(weights==[Vector3.RIGHT,Vector3.UP,Vector3.BACK][i%3],"nonblend canonical barycentric weights untouched")
	for indices in unblended.render_detail.lods.values():
		check(Surface._render_palette_ids_valid(unblended.arrays,indices),"nonblend LOD retains original palette tuples")
	var unblended_flat:=Surface.build_arrays(before,bounds,false,true,{},true)
	check(unblended_flat.render_detail.planar and unblended_flat.render_detail.base_triangles==2,"nonblend flat surface collapses to two triangles")
	var flat_display:Array=Surface.publish_arrays(unblended_flat).terrain.surface_get_arrays(0)
	for i in flat_display[Mesh.ARRAY_VERTEX].size():
		var colour:Color=flat_display[Mesh.ARRAY_COLOR][i]
		check(is_equal_approx(colour.r+colour.g+colour.b,1.0) and Vector2i((flat_display[Mesh.ARRAY_TEX_UV][i]*255.0).round())==Vector2i(2,2) and roundi(flat_display[Mesh.ARRAY_TEX_UV2][i].x*255.0)==2,"collapsed nonblend plane retains decoded pigment")
	print("WORLD_DETAIL_POLICY ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"curved_full":curved_full.collision_faces.size(),"curved_far":positions.size(),"max_display_error":largest,"full_vertices":full.collision_faces.size(),"far_vertices":far.arrays[Mesh.ARRAY_VERTEX].size()}))
	quit(0 if errors.is_empty() else 1)
