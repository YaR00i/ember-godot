@tool
class_name EmberWaterContact3D
extends Node3D
## Derived footprint ripple. The target owns only radius/foot offset; water
## presence and exact plane height stay owned by EmberVoxelSurfaceProjection.

const CollisionFootprint := preload("res://scripts/ember_water_collision_footprint.gd")
const CONTACT_MATERIAL_PATH := "res://materials/ember_water_contact.tres"
const WAKE_MATERIAL_PATH := "res://materials/ember_water_wake.tres"
const WAKE_MESH_FPS := 15.0
const MASK_SIZE := 12
const MASK_INTERVAL := 0.10

enum FootprintMode {
	RADIUS,
	COLLISION_SHAPES,
}

@export var footprint_mode := FootprintMode.RADIUS
@export_range(0.05, 1.5, 0.01) var radius_blocks := 0.30
@export_range(-2.0, 2.0, 0.01) var feet_offset_blocks := 0.0
@export_range(0.05, 3.0, 0.05) var max_submerge_blocks := 1.10
@export_range(0.0, 1.0, 0.01) var dry_tolerance_blocks := 0.12
@export_range(0.25, 12.0, 0.25) var full_wake_speed_blocks := 2.5
@export_range(1.0, 24.0, 0.5) var motion_response := 9.0
@export_range(0.4, 3.0, 0.05) var wake_length_blocks := 1.20
@export_range(0.05, 0.30, 0.01) var wake_sample_spacing_blocks := 0.11
@export_range(0.2, 2.0, 0.05) var wake_lifetime_seconds := 1.10
@export_range(0.4, 1.2, 0.05) var wake_lane_offset_scale := 0.78
@export_group("Collision waterline")
@export var collision_root_path: NodePath
@export_range(0.02, 1.0, 0.01) var collision_reaction_distance_blocks := 0.22
@export_range(0.01, 0.5, 0.01) var collision_safety_padding_blocks := 0.10
@export_range(0.0, 1.0, 0.01) var collision_reaction_strength := 0.82
@export_range(0.005, 0.12, 0.001) var collision_contact_width_blocks := 0.025
@export_range(0.005, 0.12, 0.001) var collision_reaction_width_blocks := 0.025
@export_group("")

var _visual: MeshInstance3D
var _wake_visual: MeshInstance3D
var _wake_mesh: ImmediateMesh
var _projection: Node3D
var _projections: Array[Node3D] = []
var _projections_dirty := true
var _target: Node3D
var _last_block_world_size := -1.0
var _motion_block_world_size := 1.0
var _last_target_position := Vector3.ZERO
var _motion_initialized := false
var _motion_strength := 0.0
var _motion_yaw := 0.0
var _motion_direction := Vector2.UP
var _moved_this_frame := false
var _wake_origin := Vector3.ZERO
var _wake_origin_initialized := false
var _wake_samples: Array[Dictionary] = []
var _wake_redraw_accumulator := 0.0
var _contact_material: ShaderMaterial
var _water_mask: ImageTexture
var _contact_mask_image: Image
var _mask_elapsed := MASK_INTERVAL
var _mask_position := Vector3.INF
var _mask_yaw := INF
var _mask_radius := -1.0
var _mask_revision := -1
var _mask_projection: Node3D
var _collision_contacts: Array[Dictionary] = []
var _collision_visible_count := 0
var _wake_radius_blocks := 0.30
var _last_footprint_mode := -1


func _ready() -> void:
	get_tree().node_added.connect(_on_projection_tree_changed)
	get_tree().node_removed.connect(_on_projection_tree_changed)
	_target = get_parent_node_3d()
	if is_instance_valid(_target):
		_last_target_position = _target.global_position
		_motion_initialized = true
	set_as_top_level(true)
	_ensure_visual()
	_resolve_projection()
	refresh_now()


func _process(_delta: float) -> void:
	_mask_elapsed += maxf(_delta, 0.0)
	for record in _collision_contacts:
		record["mask_elapsed"] = float(record.get("mask_elapsed", MASK_INTERVAL)) + maxf(_delta, 0.0)
	sample_motion(_delta)
	refresh_now()
	_advance_wake(_delta)


func sample_motion(delta: float) -> void:
	## Parent position deltas keep this component reusable for CharacterBody3D,
	## combat preview nodes and teleported props without reading a second motion
	## contract. Only horizontal motion contributes to the wake.
	if not is_instance_valid(_target):
		_target = get_parent_node_3d()
	if not is_instance_valid(_target):
		return
	var current := _target.global_position
	if not _motion_initialized:
		_last_target_position = current
		_motion_initialized = true
		_apply_motion_visual()
		return
	var horizontal_delta := Vector2(
		current.x - _last_target_position.x,
		current.z - _last_target_position.z,
	)
	_moved_this_frame = horizontal_delta.length_squared() > 0.000001
	_last_target_position = current
	var safe_delta := maxf(delta, 0.0001)
	var block_size := maxf(_motion_block_world_size, 0.001)
	var speed_blocks := horizontal_delta.length() / block_size / safe_delta
	var target_strength := clampf(speed_blocks / maxf(full_wake_speed_blocks, 0.001), 0.0, 1.0)
	var response := 1.0 - exp(-maxf(0.01, motion_response) * safe_delta)
	_motion_strength = lerpf(_motion_strength, target_strength, response)
	if _moved_this_frame:
		var direction := horizontal_delta.normalized()
		_motion_direction = direction
		# Quad UV orientation is opposite its local geometry axis; this yaw keeps
		# the small attached bow wave ahead according to the user-facing visual gate.
		_motion_yaw = atan2(direction.x, direction.y)
	_apply_motion_visual()


func refresh_now() -> void:
	if not is_instance_valid(_target):
		_target = get_parent_node_3d()
	if not is_instance_valid(_target):
		_set_contact_visible(false)
		return
	if _projections_dirty:
		_resolve_projection()
	if footprint_mode != _last_footprint_mode:
		_last_footprint_mode = footprint_mode
		if footprint_mode == FootprintMode.COLLISION_SHAPES:
			_visual.visible = false
		else:
			_collision_visible_count = 0
			for record in _collision_contacts:
				_set_collision_record_visible(record, false)
	if footprint_mode == FootprintMode.COLLISION_SHAPES:
		_refresh_collision_contacts()
		return
	var sample := _select_water_sample()
	_motion_block_world_size = maxf(
		0.001, float(sample.get("block_world_size", _motion_block_world_size))
	)
	if not bool(sample.get("wet", false)):
		_wake_origin_initialized = false
		_set_contact_visible(false)
		return
	var block_world_size := maxf(0.001, float(sample.get("block_world_size", 1.0)))
	_wake_radius_blocks = radius_blocks
	var water_position: Vector3 = sample.get("position", _target.global_position)
	var feet_y := _target.global_position.y + feet_offset_blocks * block_world_size
	var submerge := water_position.y - feet_y
	if (
		submerge < -dry_tolerance_blocks * block_world_size
		or submerge > max_submerge_blocks * block_world_size
	):
		_set_contact_visible(false)
		return
	global_position = water_position + Vector3.UP * block_world_size * 0.002
	global_rotation = Vector3(0.0, _motion_yaw, 0.0)
	_resize_visual(block_world_size)
	_update_contact_mask(block_world_size)
	_apply_motion_visual()
	_set_contact_visible(true)
	_record_wake_sample(water_position, block_world_size)


func is_contact_visible() -> bool:
	if footprint_mode == FootprintMode.COLLISION_SHAPES:
		return _collision_visible_count > 0
	return is_instance_valid(_visual) and _visual.visible


func collision_contact_count() -> int:
	return _collision_visible_count


func interaction_materials() -> Array[ShaderMaterial]:
	var result: Array[ShaderMaterial] = []
	if footprint_mode == FootprintMode.COLLISION_SHAPES:
		for record in _collision_contacts:
			var material := record.get("material") as ShaderMaterial
			if material != null:
				result.append(material)
	elif _contact_material != null:
		result.append(_contact_material)
	return result


func motion_strength() -> float:
	return _motion_strength


func _resolve_projection() -> void:
	_projections.clear()
	_projections_dirty = false
	if get_tree() == null:
		return
	for candidate in get_tree().get_nodes_in_group(&"ember_water_surface_projection"):
		if (
			candidate is Node3D and candidate.has_method("water_surface_sample")
			and candidate.get_viewport() == get_viewport()
		):
			_projections.append(candidate)


func _select_water_sample() -> Dictionary:
	var best: Dictionary = {"wet": false}
	var best_distance := INF
	var chosen: Node3D
	for candidate in _projections:
		if not is_instance_valid(candidate) or not candidate.is_visible_in_tree():
			continue
		var sample: Dictionary = candidate.call("water_surface_sample", _target.global_position)
		if not bool(sample.get("wet", false)):
			continue
		var block_size := maxf(0.001, float(sample.get("block_world_size", 1.0)))
		var point: Vector3 = sample["position"]
		var depth := (point.y - _target.global_position.y) / block_size - feet_offset_blocks
		if depth < -dry_tolerance_blocks or depth > max_submerge_blocks:
			continue
		if absf(depth) < best_distance:
			best_distance = absf(depth)
			best = sample
			chosen = candidate
	if chosen != _projection:
		_wake_origin_initialized = false
		# A different projection may use another scale or even another lake.
		# Samples on the previous surface cannot be reinterpreted there.
		if chosen != null and is_instance_valid(_projection):
			_wake_samples.clear()
		if chosen != null:
			_projection = chosen
	return best


func _on_projection_tree_changed(node: Node) -> void:
	if node.has_method("water_surface_sample"):
		_projections_dirty = true


func _exit_tree() -> void:
	var tree := get_tree()
	if tree.node_added.is_connected(_on_projection_tree_changed):
		tree.node_added.disconnect(_on_projection_tree_changed)
	if tree.node_removed.is_connected(_on_projection_tree_changed):
		tree.node_removed.disconnect(_on_projection_tree_changed)


func _ensure_visual() -> void:
	if is_instance_valid(_visual):
		return
	_visual = MeshInstance3D.new()
	_visual.name = "ContactRipple"
	_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_contact_material = (load(CONTACT_MATERIAL_PATH) as ShaderMaterial).duplicate() as ShaderMaterial
	quad.material = _contact_material
	_visual.mesh = quad
	_visual.rotation_degrees.x = -90.0
	add_child(_visual)
	_wake_visual = MeshInstance3D.new()
	_wake_visual.name = "WakeTrail"
	_wake_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wake_mesh = ImmediateMesh.new()
	_wake_visual.mesh = _wake_mesh
	add_child(_wake_visual)
	_wake_visual.set_as_top_level(true)
	_wake_visual.global_transform = Transform3D.IDENTITY
	_wake_visual.visible = false
	_visual.visible = footprint_mode == FootprintMode.RADIUS


func _refresh_collision_contacts() -> void:
	_visual.visible = false
	var collision_root: Node = _target
	if not collision_root_path.is_empty():
		collision_root = _target.get_node_or_null(collision_root_path)
	var footprints := CollisionFootprint.collect(collision_root)
	_sync_collision_records(footprints)
	_collision_visible_count = 0
	var wake_sample: Dictionary = {}
	var wake_projection: Node3D
	var wake_distance := INF
	var widest_half_extent := 0.0
	for footprint in footprints:
		var record := _collision_record(int(footprint["id"]))
		if record.is_empty():
			continue
		var center: Vector3 = footprint["center"]
		var selected := _select_water_sample_for_footprint(footprint)
		var sample: Dictionary = selected.get("sample", {"wet": false})
		var projection := selected.get("projection") as Node3D
		var sampled_water_position: Vector3 = sample.get("position", center)
		var water_position := Vector3(center.x, sampled_water_position.y, center.z)
		if (
			not bool(sample.get("wet", false))
			or projection == null
			or not CollisionFootprint.intersects_height(
				footprint, water_position.y,
				maxf(0.001, float(sample.get("block_world_size", 1.0))) * 0.01
			)
		):
			_set_collision_record_visible(record, false)
			continue
		var block_size := maxf(0.001, float(sample.get("block_world_size", 1.0)))
		_configure_collision_record(record, footprint, water_position, projection, block_size)
		_set_collision_record_visible(record, true)
		_collision_visible_count += 1
		var half_extent: Vector2 = footprint["half_extent"]
		widest_half_extent = maxf(widest_half_extent, maxf(half_extent.x, half_extent.y))
		var target_distance := center.distance_squared_to(_target.global_position)
		if wake_sample.is_empty() or target_distance < wake_distance:
			wake_sample = sample
			wake_projection = projection
			wake_distance = target_distance
	if _collision_visible_count == 0:
		_wake_origin_initialized = false
		_wake_visual.visible = false
		return
	var wake_block_size := maxf(0.001, float(wake_sample.get("block_world_size", 1.0)))
	_motion_block_world_size = wake_block_size
	_wake_radius_blocks = maxf(0.05, widest_half_extent / wake_block_size)
	if wake_projection != _projection and is_instance_valid(_projection):
		_wake_samples.clear()
		_wake_origin_initialized = false
	_projection = wake_projection
	var target_sample := _select_water_sample_at(_target.global_position)
	var target_water: Dictionary = target_sample.get("sample", {})
	if bool(target_water.get("wet", false)):
		_record_wake_sample(target_water["position"], wake_block_size)


func _sync_collision_records(footprints: Array[Dictionary]) -> void:
	var active_ids := {}
	for footprint in footprints:
		var footprint_id := int(footprint["id"])
		active_ids[footprint_id] = true
		if _collision_record(footprint_id).is_empty():
			var collision := footprint.get("collision") as CollisionShape3D
			_collision_contacts.append(_create_collision_record(
				footprint_id, collision.name if collision != null else str(footprint_id)
			))
	for index in range(_collision_contacts.size() - 1, -1, -1):
		var record := _collision_contacts[index]
		if active_ids.has(int(record["id"])):
			continue
		var anchor := record.get("anchor") as Node3D
		if is_instance_valid(anchor):
			anchor.queue_free()
		_collision_contacts.remove_at(index)


func _collision_record(footprint_id: int) -> Dictionary:
	for record in _collision_contacts:
		if int(record.get("id", 0)) == footprint_id:
			return record
	return {}


func _create_collision_record(footprint_id: int, source_name: String) -> Dictionary:
	var anchor := Node3D.new()
	anchor.name = "CollisionWaterline_%s" % source_name
	add_child(anchor)
	anchor.set_as_top_level(true)
	var visual := MeshInstance3D.new()
	visual.name = "ContactRipple"
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.rotation_degrees.x = -90.0
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var material := (load(CONTACT_MATERIAL_PATH) as ShaderMaterial).duplicate() as ShaderMaterial
	material.resource_path = ""
	material.set_shader_parameter("flow_reaction_enabled", true)
	quad.material = material
	visual.mesh = quad
	anchor.add_child(visual)
	return {
		"id": footprint_id,
		"anchor": anchor,
		"visual": visual,
		"material": material,
		"mask_elapsed": MASK_INTERVAL,
		"mask_revision": -1,
		"mask_projection": null,
		"mask_position": Vector3.INF,
		"mask_yaw": INF,
		"mask_size": -1.0,
	}


func _configure_collision_record(
	record: Dictionary,
	footprint: Dictionary,
	water_position: Vector3,
	projection: Node3D,
	block_size: float,
) -> void:
	var half_extent: Vector2 = footprint["half_extent"]
	var reaction_world := collision_reaction_distance_blocks * block_size
	var padding_world := collision_safety_padding_blocks * block_size
	var quad_half := maxf(half_extent.x, half_extent.y) + reaction_world + padding_world
	quad_half = maxf(quad_half, block_size * 0.05)
	var anchor := record["anchor"] as Node3D
	anchor.global_position = Vector3(water_position.x, water_position.y + block_size * 0.002, water_position.z)
	anchor.global_rotation = Vector3(0.0, float(footprint["yaw"]), 0.0)
	var visual := record["visual"] as MeshInstance3D
	var quad := visual.mesh as QuadMesh
	quad.size = Vector2.ONE * quad_half * 2.0
	var material := record["material"] as ShaderMaterial
	material.set_shader_parameter("object_coordinate", Vector2(water_position.x, water_position.z))
	material.set_shader_parameter("object_half_extent", half_extent / quad_half)
	material.set_shader_parameter(
		"object_roundness", minf(float(footprint["roundness_world"]) / quad_half, 0.48)
	)
	material.set_shader_parameter("reaction_strength", collision_reaction_strength)
	material.set_shader_parameter("reaction_distance", reaction_world / quad_half)
	material.set_shader_parameter("contact_line_width", collision_contact_width_blocks * block_size / quad_half)
	material.set_shader_parameter("reaction_line_width", collision_reaction_width_blocks * block_size / quad_half)
	_update_collision_contact_mask(record, projection, block_size, quad_half)


func _select_water_sample_at(world_position: Vector3) -> Dictionary:
	var best_sample: Dictionary = {"wet": false}
	var best_projection: Node3D
	var best_distance := INF
	for candidate in _projections:
		if not is_instance_valid(candidate) or not candidate.is_visible_in_tree():
			continue
		var sample: Dictionary = candidate.call("water_surface_sample", world_position)
		if not bool(sample.get("wet", false)):
			continue
		var point: Vector3 = sample["position"]
		var distance := absf(point.y - world_position.y)
		if distance < best_distance:
			best_distance = distance
			best_sample = sample
			best_projection = candidate
	return {"sample": best_sample, "projection": best_projection}


func _select_water_sample_for_footprint(footprint: Dictionary) -> Dictionary:
	var center: Vector3 = footprint["center"]
	var half_extent: Vector2 = footprint["half_extent"]
	var yaw_basis := Basis(Vector3.UP, float(footprint["yaw"]))
	var probes := [Vector2.ZERO]
	for probe in [
		Vector2(0.78, 0.0), Vector2(-0.78, 0.0),
		Vector2(0.0, 0.78), Vector2(0.0, -0.78),
		Vector2(0.68, 0.68), Vector2(-0.68, 0.68),
		Vector2(0.68, -0.68), Vector2(-0.68, -0.68),
	]:
		probes.append(probe)
	var best: Dictionary = {"sample": {"wet": false}, "projection": null}
	var best_distance := INF
	for probe in probes:
		var offset := yaw_basis * Vector3(probe.x * half_extent.x, 0.0, probe.y * half_extent.y)
		var selected := _select_water_sample_at(center + offset)
		var sample: Dictionary = selected.get("sample", {"wet": false})
		if not bool(sample.get("wet", false)):
			continue
		var water_position: Vector3 = sample["position"]
		var distance := absf(water_position.y - center.y)
		if distance < best_distance:
			best_distance = distance
			best = selected
	return best


func _update_collision_contact_mask(
	record: Dictionary,
	projection: Node3D,
	block_size: float,
	quad_half: float,
) -> void:
	var revision := int(projection.call("water_revision"))
	var anchor := record["anchor"] as Node3D
	var source_changed: bool = record.get("mask_projection") != projection or int(record.get("mask_revision", -1)) != revision
	var size_changed: bool = not is_equal_approx(float(record.get("mask_size", -1.0)), quad_half)
	var moved: bool = not (record.get("mask_position", Vector3.INF) as Vector3).is_equal_approx(anchor.global_position)
	var turned: bool = not is_equal_approx(float(record.get("mask_yaw", INF)), anchor.global_rotation.y)
	if not source_changed and not size_changed and not moved and not turned:
		return
	if (
		not source_changed and not size_changed
		and float(record.get("mask_elapsed", MASK_INTERVAL)) < MASK_INTERVAL
		and (record.get("mask_position", Vector3.INF) as Vector3).distance_to(anchor.global_position) < block_size * 0.1
	):
		return
	var mask := record.get("mask_image") as Image
	if mask == null:
		mask = Image.create(MASK_SIZE, MASK_SIZE, false, Image.FORMAT_R8)
		record["mask_image"] = mask
	var yaw_basis := Basis(Vector3.UP, anchor.global_rotation.y)
	for z in MASK_SIZE:
		for x in MASK_SIZE:
			var local_offset := Vector3(
				((float(x) + 0.5) / float(MASK_SIZE) - 0.5) * quad_half * 2.0,
				0.0,
				((float(z) + 0.5) / float(MASK_SIZE) - 0.5) * quad_half * 2.0,
			)
			var point := anchor.global_position + yaw_basis * local_offset
			var sample: Dictionary = projection.call("water_surface_sample", point)
			var water: Vector3 = sample.get("position", point)
			var valid := bool(sample.get("wet", false)) and absf(water.y - anchor.global_position.y) < block_size * 0.02
			mask.set_pixel(x, z, Color(1.0 if valid else 0.0, 0.0, 0.0))
	var texture := record.get("mask_texture") as ImageTexture
	var material := record["material"] as ShaderMaterial
	if texture == null:
		texture = ImageTexture.create_from_image(mask)
		record["mask_texture"] = texture
		material.set_shader_parameter("water_mask", texture)
		material.set_shader_parameter("water_mask_enabled", true)
	else:
		texture.update(mask)
	record["mask_position"] = anchor.global_position
	record["mask_yaw"] = anchor.global_rotation.y
	record["mask_size"] = quad_half
	record["mask_projection"] = projection
	record["mask_revision"] = revision
	record["mask_elapsed"] = 0.0


func _set_collision_record_visible(record: Dictionary, next_visible: bool) -> void:
	var anchor := record.get("anchor") as Node3D
	if is_instance_valid(anchor):
		anchor.visible = next_visible


func _resize_visual(block_world_size: float) -> void:
	var diameter := radius_blocks * 2.0 * block_world_size
	var quad := _visual.mesh as QuadMesh
	if (
		is_equal_approx(_last_block_world_size, block_world_size)
		and quad != null and is_equal_approx(quad.size.x, diameter)
	):
		return
	_last_block_world_size = block_world_size
	if quad != null:
		quad.size = Vector2(diameter, diameter)


func _update_contact_mask(block_size: float) -> void:
	var revision := int(_projection.call("water_revision"))
	var source_changed := _mask_projection != _projection or _mask_revision != revision
	var radius_changed := not is_equal_approx(_mask_radius, radius_blocks * block_size)
	var moved := not _mask_position.is_equal_approx(global_position)
	var turned := not is_equal_approx(_mask_yaw, _motion_yaw)
	if not source_changed and not radius_changed:
		if not moved and not turned:
			return
		if _mask_elapsed < MASK_INTERVAL and _mask_position.distance_to(global_position) < block_size * radius_blocks * 0.5:
			return
	if _contact_mask_image == null:
		_contact_mask_image = Image.create(MASK_SIZE, MASK_SIZE, false, Image.FORMAT_R8)
	var mask := _contact_mask_image
	var diameter := radius_blocks * 2.0 * block_size
	for z in MASK_SIZE:
		for x in MASK_SIZE:
			var offset := Vector3(
				(float(x) + 0.5) / float(MASK_SIZE) - 0.5, 0.0,
				(float(z) + 0.5) / float(MASK_SIZE) - 0.5,
			) * diameter
			var point := global_transform * offset
			var sample: Dictionary = _projection.call("water_surface_sample", point)
			var water: Vector3 = sample.get("position", point)
			var valid := bool(sample.get("wet", false)) and absf(water.y - point.y) < block_size * 0.02
			mask.set_pixel(x, z, Color(1.0 if valid else 0.0, 0.0, 0.0))
	if _water_mask == null:
		_water_mask = ImageTexture.create_from_image(mask)
		_contact_material.set_shader_parameter("water_mask", _water_mask)
		_contact_material.set_shader_parameter("water_mask_enabled", true)
	else:
		_water_mask.update(mask)
	_mask_position = global_position
	_mask_yaw = _motion_yaw
	_mask_radius = radius_blocks * block_size
	_mask_projection = _projection
	_mask_revision = revision
	_mask_elapsed = 0.0


func _apply_motion_visual() -> void:
	if is_instance_valid(_visual):
		_visual.set_instance_shader_parameter(&"motion_strength", _motion_strength)


func _set_contact_visible(next_visible: bool) -> void:
	if not next_visible:
		_wake_origin_initialized = false
		_collision_visible_count = 0
		for record in _collision_contacts:
			_set_collision_record_visible(record, false)
	if is_instance_valid(_visual):
		_visual.visible = next_visible


func wake_sample_count() -> int:
	return _wake_samples.size()


func _record_wake_sample(water_position: Vector3, block_world_size: float) -> void:
	if not _wake_origin_initialized:
		_wake_origin = water_position
		_wake_origin_initialized = true
		return
	if not _moved_this_frame or _motion_strength < 0.08:
		return
	var spacing := maxf(0.01, wake_sample_spacing_blocks) * block_world_size
	var horizontal := Vector3(
		water_position.x - _wake_origin.x,
		0.0,
		water_position.z - _wake_origin.z
	)
	var distance := horizontal.length()
	if (
		distance > maxf(wake_length_blocks * 2.0, 1.0) * block_world_size
		or absf(water_position.y - _wake_origin.y) > block_world_size * 0.05
	):
		_wake_samples.clear()
		_wake_origin = water_position
		return
	if distance < spacing:
		return
	var forward3 := horizontal / distance
	while distance >= spacing:
		_wake_origin += forward3 * spacing
		_wake_origin.y = water_position.y + block_world_size * 0.003
		_wake_samples.append({
			"position": _wake_origin,
			"forward": Vector2(forward3.x, forward3.z),
			"age": 0.0,
			"block_size": block_world_size,
		})
		horizontal = Vector3(
			water_position.x - _wake_origin.x,
			0.0,
			water_position.z - _wake_origin.z
		)
		distance = horizontal.length()
	_prune_wake_by_length(block_world_size)


func _prune_wake_by_length(block_world_size: float) -> void:
	if _wake_samples.size() < 2:
		return
	var allowed := wake_length_blocks * block_world_size
	var travelled := 0.0
	var keep_from := _wake_samples.size() - 1
	for index in range(_wake_samples.size() - 2, -1, -1):
		var newer: Vector3 = _wake_samples[index + 1]["position"]
		var older: Vector3 = _wake_samples[index]["position"]
		travelled += Vector2(newer.x - older.x, newer.z - older.z).length()
		if travelled > allowed:
			break
		keep_from = index
	if keep_from > 0:
		_wake_samples = _wake_samples.slice(keep_from)


func _advance_wake(delta: float) -> void:
	var had_samples := not _wake_samples.is_empty()
	for sample in _wake_samples:
		sample["age"] = float(sample["age"]) + maxf(delta, 0.0)
	while (
		not _wake_samples.is_empty()
		and float(_wake_samples[0]["age"]) >= wake_lifetime_seconds
	):
		_wake_samples.pop_front()
	if _wake_samples.is_empty():
		if had_samples or _wake_visual.visible:
			_rebuild_wake_mesh()
		_wake_redraw_accumulator = 0.0
		return
	_wake_redraw_accumulator += maxf(delta, 0.0)
	if _wake_redraw_accumulator < 1.0 / WAKE_MESH_FPS:
		return
	_wake_redraw_accumulator = 0.0
	_rebuild_wake_mesh()


func _rebuild_wake_mesh() -> void:
	if not is_instance_valid(_wake_mesh) or not is_instance_valid(_wake_visual):
		return
	_wake_mesh.clear_surfaces()
	if _wake_samples.is_empty():
		_wake_visual.visible = false
		return
	var has_geometry := false
	for sample_index in range(_wake_samples.size()):
		var sample := _wake_samples[sample_index]
		var center: Vector3 = sample["position"]
		var forward_2d: Vector2 = sample["forward"]
		var forward := Vector3(forward_2d.x, 0.0, forward_2d.y).normalized()
		var side := Vector3(-forward.z, 0.0, forward.x)
		var block_size := float(sample["block_size"])
		var lane_offset := _wake_radius_blocks * wake_lane_offset_scale * block_size
		var half_length := wake_sample_spacing_blocks * 0.36 * block_size
		var half_width := maxf(0.025, radius_blocks * 0.11) * block_size
		var life := 1.0 - clampf(float(sample["age"]) / maxf(wake_lifetime_seconds, 0.01), 0.0, 1.0)
		var history := float(sample_index + 1) / float(_wake_samples.size())
		var alpha := life * lerpf(0.34, 0.88, history)
		for lane_sign in [-1.0, 1.0]:
			var lane_center: Vector3 = center + side * lane_offset * float(lane_sign)
			if not _wake_quad_on_water(lane_center, forward, side, half_length, half_width, block_size):
				continue
			if not has_geometry:
				_wake_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, load(WAKE_MATERIAL_PATH) as Material)
				has_geometry = true
			_add_wake_quad(lane_center, forward, side, half_length, half_width, alpha)
	if has_geometry:
		_wake_mesh.surface_end()
	_wake_visual.global_transform = Transform3D.IDENTITY
	_wake_visual.visible = has_geometry


func _wake_quad_on_water(
	center: Vector3, forward: Vector3, side: Vector3,
	half_length: float, half_width: float, block_size: float,
) -> bool:
	if not is_instance_valid(_projection) or not _projection.is_visible_in_tree():
		return false
	for point in [
		center,
		center - forward * half_length - side * half_width,
		center + forward * half_length - side * half_width,
		center + forward * half_length + side * half_width,
		center - forward * half_length + side * half_width,
	]:
		var sample: Dictionary = _projection.call("water_surface_sample", point)
		if not bool(sample.get("wet", false)):
			return false
		var water: Vector3 = sample["position"]
		if absf(water.y - center.y) > block_size * 0.02:
			return false
	return true


func _add_wake_quad(
	center: Vector3,
	forward: Vector3,
	side: Vector3,
	half_length: float,
	half_width: float,
	alpha: float
) -> void:
	var a := center - forward * half_length - side * half_width
	var b := center + forward * half_length - side * half_width
	var c := center + forward * half_length + side * half_width
	var d := center - forward * half_length + side * half_width
	var color := Color(0.88, 1.0, 0.93, alpha)
	for vertex in [a, b, c, a, c, d]:
		_wake_mesh.surface_set_color(color)
		_wake_mesh.surface_add_vertex(vertex)
