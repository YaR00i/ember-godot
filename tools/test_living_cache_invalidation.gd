extends SceneTree
const Solid=preload("res://scripts/ember_voxel_solid_surface.gd")
var errors:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);push_error(label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var voxels:=PackedByteArray();voxels.resize(4096);voxels.fill(1)
	var owners:=PackedInt32Array();owners.resize(4096);owners.fill(1)
	var model:Dictionary={"voxels":voxels,"voxelPartIds":owners,"palette":["#00000000","#808080"],"sizeBlocks":{"x":1,"y":1,"z":1},"heightVoxels":16,"solidSurface":{"version":1,"occupancy":Solid.occupancy_hash(voxels),"parts":[PackedVector3Array([Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.FORWARD,Vector3.BACK])],"roles":PackedStringArray(["","stone"]),"material_ids":PackedStringArray(["","cartoon_stone"])}}
	var pulls:=PackedFloat32Array([0,0.03])
	Solid.clear_living_cache()
	var original:=Solid.living_mesh(model,1.0,pulls)
	check(original.get_surface_count()>0 and not original.get_meta("solid_volume_boundary",false),"hull fixture prepares a living carrier")
	check(Solid.living_mesh(model,1.0,pulls)==original,"unchanged model reuses the existing carrier")
	var carved:=model.duplicate(true);carved.voxels[0]=0
	var added:=model.duplicate(true);added.voxelPartIds[0]=0
	var volume:=model.duplicate(true);volume.solidSurface.topology="volume"
	for changed:Dictionary in [carved,added,volume]:
		var result:=Solid.living_mesh(changed,1.0,pulls)
		check(result!=original and result.get_meta("solid_volume_boundary",false),"occupancy, Added ownership or explicit topology bypasses cached hull")
	check(model.voxels==voxels and model.voxelPartIds==owners and not model.solidSurface.has("topology"),"derived cache never mutates Source snapshot")
	print("LIVING_CACHE_INVALIDATION ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}))
	quit(0 if errors.is_empty() else 1)
