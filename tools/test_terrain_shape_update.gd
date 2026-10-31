extends SceneTree
## Height-only rebuild must preserve the complete observable surface/paint.
const Surface=preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")
const BrushMath=preload("res://scripts/prototypes/ember_terrain_pilot_brush_math.gd")
const Look=preload("res://scripts/prototypes/ember_terrain_look_bake.gd")
const Fixture=preload("res://tools/fixtures/ember_smooth_tools_fixture.gd")
var failures: Array[String]=[]
func _initialize() -> void: run.call_deferred()
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func reference_faceted(mesh: ArrayMesh,field: Dictionary) -> ArrayMesh:
	# Pre-optimization observable behavior, with no sample/plane reuse.
	var arrays:=mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	for i in range(0,vertices.size(),3):
		var top:=normals[i].y>0.0
		var centre:=(vertices[i]+vertices[i+1]+vertices[i+2])/3.0
		var flat: Vector3=Look.plane(field,Vector2(centre.x,centre.z)).normal if top else normals[i]
		for j in 3:
			var p:=vertices[i+j]
			if top or is_equal_approx(p.y,Surface.corner(field,roundi(p.x),roundi(p.z))):
				p.y=Look.plane(field,Vector2(p.x,p.z)).height
				vertices[i+j]=p;normals[i+j]=flat
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
	var result:=ArrayMesh.new();result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return result
func run() -> void:
	var source=Fixture.base()
	for cell in [Vector2i(0,0),Vector2i(53,60),Vector2i(source.width-1,source.depth-1)]:
		var total:=0;var count:=0
		for z in range(maxi(0,cell.y-1),mini(source.depth,cell.y+2)):
			for x in range(maxi(0,cell.x-1),mini(source.width,cell.x+2)):
				total+=source.heights[x+z*source.width];count+=1
		var original_height:int=source.heights[cell.x+cell.y*source.width]
		for influence in [0.0,0.5,1.0]:
			var limit:=maxi(1,ceili(4.0*influence))
			var expected_height:=original_height+clampi(roundi(float(total)/count)-original_height,-limit,limit)
			check(BrushMath.smooth_height(source.heights,source.width,source.depth,cell.x,cell.y,4,influence)==expected_height,"smooth math retains edge/interior result")
	# Include outer walls and a hole, with a high origin that defeats approximate
	# y==origin classification of thin wall vertices.
	source.origin_y=10000
	var initial_heights: PackedInt32Array=source.heights
	initial_heights[source.column_index(20,20)]=0
	source.heights=initial_heights
	var bounds:=Rect2i(0,0,96,96)
	var reference_field:=Surface.FieldJob.new(source,bounds)
	reference_field._dense_heights=PackedInt32Array() # Existing generic sampling path.
	while not reference_field.finished:reference_field.step(1000000)
	check(Surface.field(source,bounds)==reference_field.result,"dense field equals generic sampling at edges, holes and high origin")
	var original: Dictionary=Surface.build(source,bounds,true,true,{},true)
	var key: PackedByteArray=original.layout.key
	var legacy_cache: Dictionary={}
	for p in [Vector2i(0,0),Vector2i(53,60),Vector2i(94,90)]:
		var weights: Dictionary={}
		for z in 8:
			for x in 8:
				var slot:=Surface.palette_at(source,p.x+x-4,p.y+z-4,0)
				if slot>0:weights[slot]=float(weights.get(slot,0.0))+Surface.MATERIAL_KERNEL[x]*Surface.MATERIAL_KERNEL[z]/16384.0
		check(weights==Surface.material_weights(source,p,legacy_cache),"separable paint kernel equals original")
	var heights: PackedInt32Array=source.heights
	for z in range(0,82):
		for x in range(0,88):
			var i:int=source.column_index(x,z)
			if heights[i]>0:heights[i]+=4
	source.heights=heights
	check(Surface.layout_key(source,bounds,true)==key,"height edit retains paint/topology key")
	var job:=Surface.height_update_job(source,bounds,original.layout)
	var task:=WorkerThreadPool.add_task(job.run.bind(func():return false))
	WorkerThreadPool.wait_for_task_completion(task)
	check(not job.result.is_empty(),"CPU worker produces shape")
	var rebuilt: Dictionary=Surface.build(source,bounds,true)
	var expected: Array=rebuilt.terrain.surface_get_arrays(0)
	var published:=ArrayMesh.new()
	published.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,job.result.arrays)
	var actual: Array=published.surface_get_arrays(0)
	for channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2]:
		check(actual[channel]==expected[channel],"same surface channel "+str(channel))
	check(job.result.collision_faces==rebuilt.collision_faces,"same collision faces")
	check(job.result.smooth_field==rebuilt.smooth_field,"same floor/picking field")
	var faceted: ArrayMesh=Look.faceted(published,job.result.smooth_field).mesh
	check(faceted.surface_get_arrays(0)==reference_faceted(published,job.result.smooth_field).surface_get_arrays(0),"low-poly cache retains exact surface")
	var tops: PackedByteArray=source.top_materials
	tops[source.column_index(70,70)]=1 if tops[source.column_index(70,70)]!=1 else 2
	source.top_materials=tops
	check(Surface.layout_key(source,bounds,true)!=key,"paint invalidates cached attributes")
	var painted_key:=Surface.layout_key(source,bounds,true)
	heights=source.heights;heights[source.column_index(70,70)]=0;source.heights=heights
	check(Surface.layout_key(source,bounds,true)!=painted_key,"hole independently invalidates cached topology")
	var cancelled:=Surface.height_update_job(source,bounds,original.layout)
	cancelled.run(func():return true)
	check(cancelled.result.is_empty(),"cancelled work cannot publish")
	print("TERRAIN_SHAPE_UPDATE ",JSON.stringify({"pass":failures.is_empty(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
