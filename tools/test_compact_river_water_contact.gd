extends SceneTree
## The existing contact owner must find wet and dry cells on a compact map.

const CompactProjection = preload("res://scripts/prototypes/ember_terrain_pilot_projection.gd")
const Contact = preload("res://scripts/ember_water_contact_3d.gd")
const TERRAIN := "res://content/world_terrains/compact_river_water_study.res"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var terrain := load(TERRAIN) as EmberTerrainPilotResource
	assert(terrain != null and terrain.validation_errors().is_empty())
	var shore_wet := Vector2i(-1, -1)
	var shore_dry := Vector2i(-1, -1)
	for z in range(410, 680):
		if shore_wet.x >= 0:
			break
		for x in range(300, 460):
			var index := terrain.column_index(x, z)
			if terrain.water_materials[index] == 0 or terrain.water_levels[index] <= terrain.heights[index]:
				continue
			var next := terrain.column_index(x + 1, z)
			if terrain.water_materials[next] == 0 or terrain.water_levels[next] <= terrain.heights[next]:
				shore_wet = Vector2i(x, z)
				shore_dry = Vector2i(x + 1, z)
				break
	assert(shore_wet.x >= 0)
	var projection := CompactProjection.new()
	projection.source = terrain
	root.add_child(projection)
	projection.set_process(false)
	assert(projection.is_in_group(&"ember_water_surface_projection"))
	var actor := Node3D.new()
	root.add_child(actor)
	actor.global_position = Vector3(shore_wet.x + 0.5,
		terrain.origin_y + terrain.water_levels[terrain.column_index(shore_wet.x, shore_wet.y)],
		shore_wet.y + 0.5)
	var contact := Contact.new()
	contact.radius_blocks = 0.30
	# The authored trial props keep this visual component top-level.
	contact.top_level = true
	actor.add_child(contact)
	contact.set_process(false)
	assert(contact.get("_target") == actor)
	contact.refresh_now()
	assert(contact.is_contact_visible())
	assert(contact.get("_projection") == projection)
	var mask: Image = contact.get("_contact_mask_image")
	var wet_pixels := 0
	for z in mask.get_height():
		for x in mask.get_width():
			wet_pixels += int(mask.get_pixel(x, z).r > 0.5)
	assert(wet_pixels > 0 and wet_pixels < mask.get_width() * mask.get_height())
	var flowing := Vector2i(-1, -1)
	for z in range(450, 620):
		if flowing.x >= 0:
			break
		for x in range(340, 430):
			var index := terrain.column_index(x, z)
			if terrain.water_materials[index] > 0 and terrain.water_levels[index] - terrain.heights[index] >= 12 and terrain.flow_at_cell(x, z).length() > 0.4:
				flowing = Vector2i(x, z)
				break
	assert(flowing.x >= 0)
	actor.global_position = Vector3(flowing.x + 0.5,
		terrain.origin_y + terrain.water_levels[terrain.column_index(flowing.x, flowing.y)],
		flowing.y + 0.5)
	contact.sample_motion(0.1)
	contact.refresh_now()
	actor.global_position.z -= 2.0
	contact.sample_motion(0.1)
	contact.refresh_now()
	contact.call("_advance_wake", 0.1)
	assert(contact.wake_sample_count() > 0)
	actor.global_position.x = shore_dry.x + 2.5
	actor.global_position.z = shore_dry.y + 0.5
	contact.refresh_now()
	assert(not contact.is_contact_visible())
	actor.global_position = Vector3(flowing.x + 0.5,
		terrain.origin_y + terrain.water_levels[terrain.column_index(flowing.x, flowing.y)],
		flowing.y + 0.5)
	contact.refresh_now()
	var box_visual := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(10.0, 13.0, 6.0)
	box_visual.mesh = box
	box_visual.position.y = 6.5
	actor.add_child(box_visual)
	var water_y := actor.global_position.y + 0.02
	var footprint := contact.foam_footprint_shape(water_y)
	assert(footprint.get("kind") == "box")
	var center: Vector2 = footprint["center"]
	assert(EmberWaterContact3D.footprint_signed_distance(center, footprint) < -2.5)
	assert(EmberWaterContact3D.footprint_signed_distance(center + Vector2(6.0, 0.0), footprint) > 0.5)
	box_visual.rotation.y = PI * 0.25
	footprint = contact.foam_footprint_shape(water_y)
	center = footprint["center"]
	var box_axis := Vector2.RIGHT.rotated(float(footprint["angle"]))
	assert(EmberWaterContact3D.footprint_signed_distance(center + box_axis * 6.0, footprint) > 0.5)
	actor.remove_child(box_visual)
	box_visual.free()
	var cylinder_visual := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 3.5
	cylinder.bottom_radius = 3.5
	cylinder.height = 12.0
	cylinder_visual.mesh = cylinder
	cylinder_visual.position.y = 6.0
	actor.add_child(cylinder_visual)
	footprint = contact.foam_footprint_shape(water_y)
	assert(footprint.get("kind") == "circle")
	center = footprint["center"]
	assert(EmberWaterContact3D.footprint_signed_distance(center, footprint) < -3.0)
	assert(EmberWaterContact3D.footprint_signed_distance(center + Vector2(5.0, 0.0), footprint) > 1.0)
	contact.set_surface_integrated(true)
	assert(contact.is_contact_visible())
	assert(not (contact.get("_visual") as MeshInstance3D).visible)
	print("PASS compact river contact: wet mask, flow wake, dry hiding, box/cylinder footprint")
	quit()
