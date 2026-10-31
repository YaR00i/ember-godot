extends SceneTree
## The animated shore needs bounded triangle spans; open water keeps its budget.
const Terrain=preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Builder=preload("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")
var failures: Array[String]=[]
func _initialize() -> void: run.call_deferred()
func check(ok: bool,text: String) -> void:
	if not ok: failures.append(text);printerr("SHORE_GRID FAIL ",text)
func run() -> void:
	var source:=Terrain.new();source.width=64;source.depth=32
	source.palette=PackedColorArray([Color.TRANSPARENT,Color.BROWN,Color.CYAN])
	for key in ["heights","water_levels","water_materials","top_materials","base_materials","cap_depths"]:
		var channel=source.get(key);channel.resize(2048);source.set(key,channel)
	for z in 32:
		for x in 64:
			var i:=x+z*64
			source.heights[i]=4 if x<32 else 8
			source.top_materials[i]=1;source.base_materials[i]=1
			if x<32:source.water_levels[i]=8;source.water_materials[i]=2
	var before:=source.heights.duplicate();var levels:=source.water_levels.duplicate()
	var cells:=PackedVector4Array()
	for z in 32:
		for x in range(32,40):cells.append(Vector4(x,z,8,8))
	var built: Dictionary=Builder.build_tile(source,0,0,64,8,true,cells,{},false,true,true)
	var arrays: Array=built.water.surface_get_arrays(0)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	var uvs: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
	var near_max:=0.0;var far_max:=0.0
	for i in range(0,indices.size(),3):
		var a:=vertices[indices[i]];var b:=vertices[indices[i+1]];var c:=vertices[indices[i+2]]
		if uvs[indices[i]].y!=0.0:continue
		var center: Vector3=(a+b+c)/3.0
		var span:=maxf(a.distance_to(b),maxf(b.distance_to(c),c.distance_to(a)))
		if center.x>=24:near_max=maxf(near_max,span)
		if center.x<16:far_max=maxf(far_max,span)
	check(near_max<=1.5,"coast still samples moving waves on coarse triangles")
	check(far_max>4,"open water was unnecessarily refined")
	var reference: Dictionary=Builder.build_tile(source,0,0,64,8,true,PackedVector4Array(),{},false,true,true)
	check(built.collision_faces==reference.collision_faces,"shore refinement changed physical ground")
	check(source.heights==before and source.water_levels==levels,"shore refinement changed source")
	print("SHORE_GRID ","PASS" if failures.is_empty() else "FAIL"," near_span=",near_max," far_span=",far_max," vertices=",vertices.size())
	quit(0 if failures.is_empty() else 1)
