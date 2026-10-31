extends SceneTree
## Derived paint band: continuous weights, exact geometry, no Source mutation.
const Solid=preload("res://scripts/ember_voxel_solid_surface.gd")
var errors:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("VOLUME_BLEND_FAIL ",label)
func _initialize()->void:
	var source:=EmberVoxelModelResource.new();source.model_id="volume_blend_fixture"
	source.palette=PackedColorArray([Color.TRANSPARENT,Color.BROWN,Color.GRAY,Color.GREEN])
	source.voxels.resize(4096);source.voxel_part_ids.resize(4096);source.voxel_part_ids.fill(1)
	source.merge_parts=PackedStringArray(["body"])
	for y in 16:
		for z in 16:
			for x in 16:source.voxels[x+z*16+y*256]=3 if y>=8 else 2 if x>=8 else 1
	source.solid_surface={"version":1,"occupancy":Solid.occupancy_hash(source.voxels),"parts":[PackedVector3Array([Vector3.UP,Vector3.DOWN,Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD,Vector3.BACK])],"roles":PackedStringArray(["","soil","stone","grass"]),"material_ids":PackedStringArray(["","soil_grain","stone_ochre","cartoon_grass"])}
	check(source.validation_errors().is_empty(),"valid Source")
	var before:=source.to_definition().duplicate(true)
	var model:=EmberVoxelPrefab.model_of(before)
	var arrays:=Solid.volume_geometry(model)
	var single:=model.duplicate(true);var voxels:PackedByteArray=single.voxels.duplicate();voxels.fill(1);single.voxels=voxels
	var plain:=Solid.volume_geometry(single)
	check(arrays[Mesh.ARRAY_VERTEX]==plain[Mesh.ARRAY_VERTEX] and arrays[Mesh.ARRAY_NORMAL]==plain[Mesh.ARRAY_NORMAL] and arrays[Mesh.ARRAY_CUSTOM0]==plain[Mesh.ARRAY_CUSTOM0],"paint leaves positions, normals and physical faces identical")
	var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var colours:PackedColorArray=arrays[Mesh.ARRAY_COLOR]
	var uv:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
	var uv2:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV2]
	var by_point:Dictionary={};var mixed:=0;var triples:=0;var far_pure:=0
	for i in vertices.size():
		var c:=colours[i];var weights:=Vector3(c.r,c.g,c.b)
		check(absf(weights.x+weights.y+weights.z-1.0)<0.00001 and weights.x>=0 and weights.y>=0 and weights.z>=0,"nonnegative normalised weights")
		var ids:=[roundi(uv[i].x*255),roundi(uv[i].y*255),roundi(uv2[i].x*255)]
		var mask:=Vector3.ZERO;var active:=0
		for j in 3:
			if weights[j]>0.00001:
				check(ids[j]>=1 and ids[j]<=3,"only painted nonempty palette slots")
				mask[ids[j]-1]+=weights[j];active+=1
		var point:=Vector3i((vertices[i]*100000).round())
		if by_point.has(point):check((by_point[point] as Vector3).is_equal_approx(mask),"same surface point has continuous paint across triangles")
		else:by_point[point]=mask
		if active>1:
			mixed+=1
			check(absf(vertices[i].y-0.5)<=1.1/16.0 or (vertices[i].y<0.5 and absf(vertices[i].x-0.5)<=1.1/16.0),"band stays within adjacent voxel rows")
		if active==3:triples+=1
		if vertices[i].y>0.7:
			check(mask.is_equal_approx(Vector3(0,0,1)),"distant grass stays pure");far_pure+=1
	check(mixed>0 and triples>0 and far_pure>0,"two-material band and three-material junction are exercised")
	check(source.to_definition()==before,"Source paint is byte-for-byte unchanged")
	var again:=Solid.volume_geometry(model)
	check(again[Mesh.ARRAY_COLOR]==colours and again[Mesh.ARRAY_TEX_UV]==uv and again[Mesh.ARRAY_TEX_UV2]==uv2,"deterministic derived channels")
	var voxel_arrays:=Solid.voxel_geometry(model)
	for c:Color in voxel_arrays[Mesh.ARRAY_COLOR]:
		if c.r!=1 or c.g!=0 or c.b!=0:check(false,"voxel paint stays stepped and unmixed");break
	print("VOLUME_MATERIAL_BLEND ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"mixed_vertices":mixed,"triple_vertices":triples}))
	quit(0 if errors.is_empty() else 1)
