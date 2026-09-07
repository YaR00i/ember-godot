@tool
class_name EmberWaterContact3D
extends Node3D
## Derived footprint ripple. The target owns only radius/foot offset; water
## presence and exact plane height stay owned by EmberVoxelSurfaceProjection.

const SurfaceMaterials := preload("res://scripts/ember_voxel_surface_materials.gd")
const WAKE_MESH_FPS := 15.0
const MASK_SIZE := 12
const MASK_INTERVAL := 0.10

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
	var sample := _select_water_sample()
	_motion_block_world_size = maxf(
		0.001, float(sample.get("block_world_size", _motion_block_world_size))
	)
	if not bool(sample.get("wet", false)):
		_wake_origin_initialized = false
		_set_contact_visible(false)
		return
	var block_world_size := maxf(0.001, float(sample.get("block_world_size", 1.0)))
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
	return is_instance_valid(_visual) and _visual.visible


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
	_contact_material = SurfaceMaterials.contact_material().duplicate() as ShaderMaterial
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
		var lane_offset := radius_blocks * wake_lane_offset_scale * block_size
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
				_wake_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, SurfaceMaterials.wake_material())
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
