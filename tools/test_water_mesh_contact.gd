extends SceneTree
## Observable waterline: two separate mesh islands must not become one solid disc.
const Contact := preload("res://scripts/ember_water_contact_3d.gd")
const MeshSection := preload("res://scripts/ember_water_mesh_section.gd")
const Field := preload("res://scripts/prototypes/ember_compact_wave_obstacles.gd")
const Terrain := preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Water := preload("res://scripts/prototypes/ember_compact_planar_reflection_study.gd")
var errors: Array[String] = []
func _init() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok: errors.append(label)
func run() -> void:
	var legs: Array[Vector4] = [
		Vector4(-2, -2, 0, 0.8), Vector4(-2, 5, 0, 0.8),
		Vector4(2, -2, 0, 0.8), Vector4(2, 5, 0, 0.8),
	]
	var rig_section := MeshSection.build_rig(legs, 0.0, Vector2.ZERO)
	check(not rig_section.is_empty(), "both legs cross the waterline")
	if not rig_section.is_empty():
		rig_section.center = rig_section.center_offset
		rig_section.angle = 0.0
		for x in [-2.0, 2.0]:
			check(MeshSection.sample(Vector2(x, 0), rig_section) < -0.4, "each leg occupies the waterline")
		check(MeshSection.sample(Vector2.ZERO, rig_section) > 0.8, "open water stays between the legs")
		check(MeshSection.build_rig(legs, 8.0, Vector2.ZERO).is_empty(), "submerged rig has no waterline")
	var host := Node3D.new()
	root.add_child(host)
	var mesh := MeshInstance3D.new()
	var joined := ArrayMesh.new()
	for center in [-5.0, 5.0]:
		var box := BoxMesh.new()
		box.size = Vector3(2, 4, 2)
		var arrays := box.get_mesh_arrays()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in vertices.size(): vertices[i].x += center
		arrays[Mesh.ARRAY_VERTEX] = vertices
		joined.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.mesh = joined
	host.add_child(mesh)
	var contact := Contact.new()
	host.add_child(contact)
	contact.set_process(false)
	contact._contact_active = true
	contact._motion_block_world_size = 16.0
	var shape := contact.water_interaction_shape(0.0)
	check(not shape.is_empty(), "mesh waterline must exist")
	if not shape.is_empty():
		for x in [-6.0, -4.0, 4.0, 6.0]:
			check(absf(Contact.footprint_signed_distance(Vector2(x,0), shape)) < 0.5, "waterline follows mesh edge x=" + str(x))
		check(Contact.footprint_signed_distance(Vector2.ZERO, shape) > 3.0, "open water between disconnected rocks stays open")
		check(Contact.footprint_signed_distance(Vector2(-5,0), shape) < -0.5, "rock interior stays solid")
		var image: Variant = shape.get("distance")
		host.position = Vector3(60,0,12)
		host.rotation.y = 0.7
		var moved := contact.water_interaction_shape(0.0)
		for point in [Vector3(-6,0,0), Vector3(6,0,0)]:
			var world: Vector3 = host.global_transform * point
			check(absf(Contact.footprint_signed_distance(Vector2(world.x,world.z),moved)) < 0.5, "moving/yawing mesh retains waterline")
		check(image != null and image == moved.get("distance"), "horizontal movement reuses derived contour instead of rebuilding it")
		check(contact.water_interaction_shape(8.0).is_empty(), "fully submerged mesh has no surface intersection")
		host.position = Vector3(80,0,80)
		host.rotation = Vector3.ZERO
		var physics_shape := contact.water_interaction_shape(0.0)
		var document := Terrain.new()
		document.width = 160
		document.depth = 160
		for channel in ["heights","water_levels","water_materials"]:
			var values: Variant = document.get(channel)
			values.resize(160*160)
			values.fill(4 if channel == "heights" else 12 if channel == "water_levels" else 2)
			document.set(channel,values)
		var shore := Image.create_empty(160,160,false,Image.FORMAT_R8)
		shore.fill(Color.WHITE)
		var field := Field.new()
		var settings := {"wave_speed":0.42,"river_speed":0.0,"wave_height":2.0,"river_mix":0.8,"spacing":4.0,"opening":0.3,"sea_period":9.0,"sea_height":0.0,"sea_reach":10.0}
		field.build(document,[physics_shape],null,shore,null,settings,true)
		var same_pixels := physics_shape.duplicate()
		var original_image: Image = physics_shape.distance
		same_pixels.distance = Image.create_from_data(64,64,false,Image.FORMAT_RF,original_image.get_data())
		var equal_field := Field.new()
		equal_field.build(document,[same_pixels],null,shore,null,settings,true)
		check(equal_field.signature == field.signature, "cache key uses contour pixels rather than process-local image identity")
		same_pixels.distance.set_pixel(1,1,Color(123,0,0,1))
		var changed_field := Field.new()
		changed_field.build(document,[same_pixels],null,shore,null,settings,true)
		check(changed_field.signature != field.signature, "changed contour data invalidates the derived wave cache")
		check(field.ready and field.patches.size() == 1, "mesh contact uses the existing live field")
		if not field.patches.is_empty():
			var patch: Dictionary = field.patches[0]
			var cell := Vector2i(((Vector2(80,80) - Vector2(patch.origin)) / Field.CELL).round())
			check(patch.fluid[cell.x + cell.y*Field.GRID] == 1, "solver keeps the channel between rocks fluid")
			for i in range(120): field.advance(float(i)*0.05,2,1.0)
			var energy := 0.0
			for value in patch.h: energy += absf(value)
			check(energy > 0.01, "incoming wave scatters from mesh islands in the existing solver")
		# Water can be ready before actors exist. No eligible contact must not
		# deadlock world startup waiting for a patch that cannot be allocated.
		var startup := Node3D.new()
		root.add_child(startup)
		var map := EmberMapLoader.new()
		map.name = "Map"
		map.hydrate_legacy_regions = false
		startup.add_child(map)
		map.compact_terrain = document
		var projection := EmberTerrainPilotProjection.new()
		map.add_child(projection)
		map._visual_surface_projection = projection
		var controller := Water.new()
		startup.add_child(controller)
		controller.set_process(false)
		controller._prepared = true
		controller.obstacle_wave_mode = 2
		controller._surface_contacts.clear()
		check(controller.startup_preparation_status().ready, "ready water without contacts does not wait forever for an empty patch")
		startup.free()
		joined.clear_surfaces()
		for center in [-7.0,7.0]:
			var box := BoxMesh.new()
			box.size = Vector3(2,4,2)
			var arrays := box.get_mesh_arrays()
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for i in vertices.size(): vertices[i].x += center
			arrays[Mesh.ARRAY_VERTEX] = vertices
			joined.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		joined.emit_changed()
		var revised := contact.water_interaction_shape(0.0)
		check(Contact.footprint_signed_distance(Vector2(85,80),revised) > 0.5, "editing the same mesh resource replaces its old waterline")
	host.free()
	for error in errors: printerr("MESH_CONTACT FAIL ",error)
	print("MESH_CONTACT ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}))
	quit(0 if errors.is_empty() else 1)
