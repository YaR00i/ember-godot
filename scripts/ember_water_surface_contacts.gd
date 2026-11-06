extends RefCounted
## Packs the shared water shader contact uniforms for terrain and local surfaces.
var texture: ImageTexture
var _distance_image: Image
var _distance_ids := PackedInt64Array()


func update(contacts: Array[EmberWaterContact3D], units_per_metre: float, wave_field: bool,
		footprint_for: Callable, wakes_for: Callable, set_parameter: Callable) -> void:
	var shapes := PackedVector4Array()
	var metadata := PackedVector2Array()
	var wakes := PackedVector4Array()
	var wake_details := PackedVector4Array()
	shapes.resize(8)
	metadata.resize(8)
	wakes.resize(12)
	wake_details.resize(12)
	var count := 0
	var wake_count := 0
	var distance_images: Array[Image] = []
	distance_images.resize(8)
	var distance_ids := PackedInt64Array()
	distance_ids.resize(8)
	var visible_contacts := 0
	for contact in contacts:
		if is_instance_valid(contact) and is_instance_valid(contact.get_parent()) and contact.get_parent().is_visible_in_tree():
			visible_contacts += 1
	var wake_budget := maxi(1, 12 / maxi(1, visible_contacts))
	for contact in contacts:
		if not is_instance_valid(contact): continue
		if not is_instance_valid(contact.get_parent()) or not contact.get_parent().is_visible_in_tree(): continue
		var footprint: Dictionary = footprint_for.call(contact)
		if not footprint.is_empty() and count < 8:
			var center: Vector2 = footprint["center"] / units_per_metre
			var half: Vector2 = footprint.get("half", Vector2.ONE * float(footprint.get("radius", 0.0))) / units_per_metre
			var kind := 1.0 if footprint["kind"] == "circle" else 0.0
			if footprint["kind"] == "mesh":
				kind = 2.0
				half = Vector2(footprint.distance_half) / units_per_metre
				distance_images[count] = footprint.distance
				distance_ids[count] = footprint.distance.get_instance_id()
			shapes[count] = Vector4(center.x, center.y, half.x, half.y)
			metadata[count] = Vector2(kind, float(footprint.get("angle", 0.0)))
			count += 1
		if not wakes_for.call(contact): continue
		# Reserve a share for every contact so a long leader trail cannot
		# consume all shader slots before the companions are visited.
		for sample in contact.surface_wake_samples(wake_budget):
			if wake_count >= 12: break
			var point: Vector3 = sample["position"]
			var forward: Vector2 = sample["forward"]
			wakes[wake_count] = Vector4(point.x / units_per_metre, point.z / units_per_metre, float(sample["age"]), float(sample.get("strength", 1.0)))
			wake_details[wake_count] = Vector4(forward.x, forward.y, float(sample["life"]), float(sample["radius"]))
			wake_count += 1
	if texture == null or distance_ids != _distance_ids:
		_distance_ids = distance_ids
		if _distance_image == null:
			_distance_image = Image.create_empty(64, 64 * 8, false, Image.FORMAT_RF)
		_distance_image.fill(Color(1000,0,0,1))
		for i in range(8):
			if distance_images[i] != null:
				_distance_image.blit_rect(distance_images[i], Rect2i(0,0,64,64), Vector2i(0,i*64))
		if texture == null: texture = ImageTexture.create_from_image(_distance_image)
		else: texture.update(_distance_image)
	set_parameter.call("object_contact_distance_map", texture)
	set_parameter.call("object_shapes", shapes)
	set_parameter.call("object_shape_meta", metadata)
	set_parameter.call("object_shape_count", count)
	set_parameter.call("object_contact_available", 1.0 if visible_contacts > 0 else 0.0)
	set_parameter.call("object_wave_interaction", 1.0 if wave_field else 0.0)
	set_parameter.call("reaction_samples", wakes)
	set_parameter.call("reaction_details", wake_details)
	set_parameter.call("reaction_count", wake_count)


