extends SceneTree
## A retreat during I/O must keep the authored hull and its collider.
var errors: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)
		printerr(message)

func _initialize() -> void:
	run.call_deferred()

func finish_read(map: EmberMapLoader) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while not map._packed_mesh_loading.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
		map._finish_packed_detail()
	check(map._packed_mesh_loading.is_empty(), "A threaded request did not finish")

func run() -> void:
	var prefab := load("res://prefabs/voxels/vox_earth_cliff_straight.tscn") as PackedScene
	var prop := prefab.instantiate() as EmberVoxelProp
	var map := EmberMapLoader.new()
	map.add_child(prop)
	var visual := prop.get_node("Mesh") as MeshInstance3D
	var shape := prop.get_node("Collision/Shape") as CollisionShape3D
	var hull := visual.mesh
	var collider := shape.shape
	var mesh := prop.bake_packed_detail_mesh()
	check(mesh != null and visual.mesh == hull and shape.shape == collider, "Baking altered the authored prop")
	var path := "user://test-ember-packed-cliff-%d.res" % OS.get_process_id()
	if mesh != null and ResourceSaver.save(mesh, path, ResourceSaver.FLAG_BUNDLE_RESOURCES) == OK:
		prop.packed_detail_path = path
		prop.packed_detail_wanted = true
		check(not map._request_packed_detail(prop), "A cold request should yield")
		prop.packed_detail_wanted = false
		await finish_read(map)
		check(prop.packed_detail_mesh == null and visual.mesh == hull, "Retreat published a stale result")
		prop.packed_detail_wanted = true
		map._request_packed_detail(prop)
		await finish_read(map)
		var loaded := prop.packed_detail_mesh
		check(loaded != null, "Returning did not obtain the prepared mesh")
		if loaded != null:
			check(loaded.surface_get_arrays(0) == mesh.surface_get_arrays(0), "Vertex channels changed")
			var original_faces := mesh.get_meta("solid_layer_faces") as Texture2D
			var loaded_faces := loaded.get_meta("solid_layer_faces") as Texture2D
			check(loaded_faces != null and original_faces != null and loaded_faces.get_image().get_data() == original_faces.get_image().get_data(), "Face texture changed")
			prop._hull_mesh = hull
			check(prop._living_for(null, "") == loaded and shape.shape == collider, "Native transition lost the mesh or collider")
		DirAccess.remove_absolute(path)
	else:
		check(false, "Cannot save fixture")
	map.free()
	print("PACKED_OBJECT_DETAIL ", JSON.stringify({"pass":errors.is_empty(), "errors":errors}))
	quit(0 if errors.is_empty() else 1)
