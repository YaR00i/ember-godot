extends SceneTree

const SurfaceProjection = preload("res://scripts/ember_voxel_surface_projection.gd")
const Contact = preload("res://scripts/ember_water_contact_3d.gd")
var errors: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var other_view := SubViewport.new()
	other_view.own_world_3d = true
	root.add_child(other_view)
	var unrelated := _projection(other_view, Vector3.ZERO)
	var host := Node3D.new()
	root.add_child(host)
	var distant := _projection(host, Vector3(80, 0, 0))
	var actor := Node3D.new()
	host.add_child(actor)
	actor.position = Vector3(8, 4, 8)
	var contact := Contact.new()
	contact.radius_blocks = 0.12
	actor.add_child(contact)
	contact.set_process(false)
	contact.refresh_now()
	_check(not contact.is_contact_visible(), "contact selected another viewport's pool")
	var nearby := _projection(host, Vector3.ZERO)
	contact.refresh_now()
	_check(contact.is_contact_visible(), "late-added local water was not discovered")
	_check(contact.get("_projection") == nearby, "contact selected distant water by tree order")
	actor.position.x = 88
	contact.refresh_now()
	_check(contact.get("_projection") == distant, "contact did not switch to a second pool")
	actor.position.x = 8
	contact.refresh_now()
	contact.sample_motion(0.1)
	actor.position.x += 2
	contact.sample_motion(0.1)
	contact.refresh_now()
	contact.call("_advance_wake", 0.1)
	_check(contact.wake_sample_count() > 0, "walking did not leave water history")
	var before := contact.wake_sample_count()
	actor.position.y = 60
	contact.refresh_now()
	_check(not contact.is_contact_visible(), "contact remained visible above the water")
	actor.position.y = 4
	actor.position.x += 1
	contact.sample_motion(0.1)
	contact.refresh_now()
	_check(contact.wake_sample_count() == before, "re-entry drew a trail across time spent in air")
	var surface = nearby.surface()
	for z in range(9, 16):
		for x in 16:
			surface.surface_fill_materials[x + z * 16] = 0
	surface.emit_changed()
	contact.refresh_now()
	var mask: Image = contact.get("_contact_mask_image")
	if mask != null:
		var wet_pixels := 0
		for z in mask.get_height():
			for x in mask.get_width():
				wet_pixels += int(mask.get_pixel(x, z).r > 0.5)
		_check(wet_pixels > 0 and wet_pixels < 144, "contact ring mask did not clip at the bank")
	contact.call("_rebuild_wake_mesh")
	var trail := contact.get_node("WakeTrail") as MeshInstance3D
	_check(trail.mesh.get_surface_count() == 1, "valid water-side wake was removed")
	if trail.mesh.get_surface_count() > 0:
		var vertices: PackedVector3Array = trail.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			_check(vertex.z < 9.0, "wake geometry crossed onto the dry bank")
	# Queries were already cached. Removing water must invalidate them and also
	# remove still-alive historical foam, without waiting for its lifetime.
	surface.surface_fill_materials.fill(0)
	surface.emit_changed()
	contact.refresh_now()
	contact.call("_rebuild_wake_mesh")
	_check(not contact.is_contact_visible(), "water cache stayed wet after fill deletion")
	_check(trail.mesh.get_surface_count() == 0, "deleted water retained wake geometry")
	nearby.free()
	contact.refresh_now()
	_check(not contact.is_contact_visible(), "freed projection retained a contact")
	_check(unrelated != null, "isolated preview fixture disappeared")
	host.free()
	other_view.free()
	if errors.is_empty():
		print("PASS water contact boundaries: viewport isolation, multiple pools, re-entry, bank clipping, deletion")
	else:
		for error in errors:
			printerr(error)
	quit(0 if errors.is_empty() else 1)


func _projection(parent: Node, at: Vector3) -> Node3D:
	var surface := EmberVoxelModelResource.new()
	surface.voxels_per_block = 16
	surface.size_blocks = Vector3i.ONE
	surface.height_voxels = 8
	surface.palette = PackedColorArray([Color.TRANSPARENT, Color.GREEN])
	surface.voxels.resize(16 * 16 * 8)
	for column in 256:
		surface.voxels[column] = 1
	surface.surface_fill_levels.resize(256)
	surface.surface_fill_levels.fill(4)
	surface.surface_fill_materials.resize(256)
	surface.surface_fill_materials.fill(1)
	var projection := SurfaceProjection.new()
	parent.add_child(projection)
	projection.position = at
	projection.configure(surface, 16.0, Vector2i.ONE, null)
	projection.set_process(false)
	return projection


func _check(condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)
