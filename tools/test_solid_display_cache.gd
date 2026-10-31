extends SceneTree
const Solid=preload("res://scripts/ember_voxel_solid_surface.gd")
const Fixture=preload("res://tools/test_solid_volume.gd")
var errors:Array[String]=[]
func check(ok:bool,label:String):
	if not ok:errors.append(label);printerr("DISPLAY_CACHE_FAIL ",label)
func _initialize():run.call_deferred()
func run():
	var fixture:=Fixture.new();var source:EmberVoxelModelResource=fixture.fixture();fixture.free()
	var before:=source.voxels.duplicate()
	source.solid_surface.topology="volume"
	var model:Dictionary=EmberVoxelPrefab.model_of(source.to_definition())
	var boundary:=Solid.volume_mesh(model)
	var flat:Array=boundary.surface_get_arrays(0)
	var detailed:=Solid.detailed_volume_from_boundary(boundary)
	var expected:Array=Solid.volume_mesh(model,true).surface_get_arrays(0)
	var actual:Array=detailed.surface_get_arrays(0)
	for channel in Mesh.ARRAY_MAX:
		if channel==Mesh.ARRAY_NORMAL:
			var a:PackedVector3Array=actual[channel];var b:PackedVector3Array=expected[channel]
			check(a.size()==b.size(),"normal count")
			for i in mini(a.size(),b.size()):
				if a[i].distance_to(b[i])>0.0002:check(false,"smooth normals");break
		else:check(actual[channel]==expected[channel],"volume channel %d"%channel)
	check(boundary.surface_get_arrays(0)==flat,"canonical boundary unchanged")
	check(Solid.detailed_volume_from_boundary(boundary)==detailed,"bounded display reuse")
	source.solid_surface.erase("topology");model=EmberVoxelPrefab.model_of(source.to_definition())
	var pulls:=PackedFloat32Array([0,0.002,0.001,0])
	Solid.clear_living_cache();var first:=Solid.living_mesh(model,1.0,pulls)
	var hits:int=Solid.living_disk_hits
	Solid.clear_living_cache();var second:=Solid.living_mesh(model,1.0,pulls)
	check(Solid.living_disk_hits==hits+1,"persistent cache hit")
	check(first.surface_get_arrays(0)==second.surface_get_arrays(0),"disk geometry parity")
	pulls[1]=0.00317
	var changed:=Solid.living_mesh(model,1.0,pulls)
	check(changed.get_meta("solid_living_pulls")==pulls,"changed material pull")
	check(source.voxels==before,"immutable Source")
	print("SOLID_DISPLAY_CACHE ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}))
	quit(0 if errors.is_empty() else 1)
