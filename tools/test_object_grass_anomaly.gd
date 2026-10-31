extends SceneTree
class FloorMap extends EmberMapLoader:
	var on_object:=true
	func _solid_floor_candidates(_bounds:AABB)->Array:return [self] if on_object else []
	func _solid_floor_sample(point:Vector3,_candidates:Variant=null)->Dictionary:
		return {"solid":true,"position":point,"object":self} if on_object else {"solid":true,"position":Vector3.ZERO}
func _initialize()->void:run.call_deferred()
func run()->void:
	var map:=FloorMap.new()
	var source:=EmberTerrainPilotResource.new();source.width=16;source.depth=16
	source.palette=PackedColorArray([Color.TRANSPARENT,Color.GREEN]);source.palette_surface_roles=PackedStringArray(["","grass"]);source.palette_material_ids=PackedStringArray(["","cartoon_grass"])
	for key in ["heights","top_materials","base_materials","cap_depths","water_levels","water_materials"]:source.get(key).resize(256)
	source.heights.fill(4);source.top_materials.fill(1);source.base_materials.fill(1);source.cap_depths.fill(1)
	map.compact_terrain=source;root.add_child(map)
	var sphere=load("res://scripts/ember_world_anomaly_3d.gd").new();sphere.enabled=false;map.add_child(sphere);sphere.set_process(false)
	sphere._map=map;sphere._projection=map._visual_surface_projection
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,BoxMesh.new().surface_get_arrays(0))
	var original:=MultiMesh.new();original.transform_format=MultiMesh.TRANSFORM_3D;original.mesh=mesh;original.instance_count=1
	var transform:=Transform3D(Basis(Vector3.RIGHT,Vector3(0.4,1,0),Vector3.BACK),Vector3(4,32,4));original.set_instance_transform(0,transform)
	var visual:=MultiMeshInstance3D.new();visual.multimesh=original;map.add_child(visual)
	var object_scatter:MultiMesh=await sphere._grass_scatter(original,visual,original.mesh)
	assert(object_scatter.get_instance_transform(0)==transform)
	assert(object_scatter.get_instance_custom_data(0)==Color(0,0,0,0))
	map.on_object=false
	var terrain_scatter:MultiMesh=await sphere._grass_scatter(original,visual,original.mesh)
	assert(terrain_scatter.get_instance_custom_data(0).r<-20 and terrain_scatter.get_instance_custom_data(0).g<-20)
	print("OBJECT_GRASS_ANOMALY PASS: cliff roots fixed; terrain endpoint deltas retained")
	# Let this bounded projection finish before disposal.
	for i in 8:await process_frame
	map.queue_free();await process_frame;quit()
