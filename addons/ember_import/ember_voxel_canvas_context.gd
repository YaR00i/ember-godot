@tool
extends Node3D
## Read-only visual snapshot in the existing Canvas world.
##
## v1.1 can operate in two modes:
## - legacy: reproduce the previous all-visible copy path for A/B profiling;
## - optimized: bounds-aware radius culling + safe opaque MultiMesh batching.

const LEGACY_MAX_VISUALS := 4096
const OPTIMIZED_MAX_SOURCES := 2048

var visuals: Array[GeometryInstance3D] = []
var original_transparency: Array[float] = []
var world_transforms: Array[Transform3D] = []
var _batched_flags: Array[bool] = []
var _last_frame := Transform3D.IDENTITY
var _last_report := {}


func rebuild(
	scene: Node,
	target: Node3D,
	canvas_to_world: Transform3D,
	exclude_target := true,
	radius_world := 0.0,
	optimized := false,
	context_opacity := 1.0,
) -> Dictionary:
	if (
		not is_instance_valid(scene)
		or not is_instance_valid(target)
		or not scene.is_inside_tree()
		or (scene != target and not scene.is_ancestor_of(target))
	):
		return {"error": "Исходная сцена или объект уже закрыты."}
	if absf(canvas_to_world.basis.determinant()) < 0.000001:
		return {"error": "Нулевой масштаб объекта: окружение нельзя совместить с Canvas."}

	var started := Time.get_ticks_usec()
	var sources: Array[GeometryInstance3D] = []
	var pending: Array[Node] = [scene]
	var culled := 0
	var target_bounds := _target_world_aabb(target)

	while not pending.is_empty():
		var node := pending.pop_back() as Node
		if node == target and exclude_target:
			continue
		if node is MeshInstance3D or node is MultiMeshInstance3D:
			var geometry := node as GeometryInstance3D
			if (
				geometry.is_visible_in_tree()
				and geometry.cast_shadow
					!= GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			):
				if (
					optimized
					and radius_world > 0.0
					and _aabb_distance_squared(
						_world_aabb(geometry),
						target_bounds,
					) > radius_world * radius_world
				):
					culled += 1
				else:
					sources.append(geometry)
					var source_limit := (
						OPTIMIZED_MAX_SOURCES
						if optimized
						else LEGACY_MAX_VISUALS
					)
					if sources.size() > source_limit:
						return {
							"error":
								"Более %d визуальных объектов в контексте. "
								% source_limit
								+ (
									"Уменьшите «Радиус фона»."
									if optimized
									else "Включите оптимизированный фон или уменьшите сцену."
								)
						}
		for child in node.get_children():
			pending.append(child)

	clear()
	_last_frame = canvas_to_world
	var world_to_canvas := canvas_to_world.affine_inverse()
	var batched_instances := 0
	var opacity := clampf(context_opacity, 0.0, 1.0)
	# GeometryInstance3D.transparency turns even opaque source meshes into a
	# transparent context pass. MultiMesh does not sort its instances like
	# separate GeometryInstance3D nodes, so exact visual parity requires full
	# context opacity before batching.
	var batching_allowed := optimized and opacity >= 0.999
	var batching_reason := (
		"enabled"
		if batching_allowed
		else ("context_opacity" if optimized else "legacy")
	)

	if optimized and batching_allowed:
		var batches := {}
		var singles: Array[GeometryInstance3D] = []
		for source in sources:
			var key := _batch_key(source)
			if key.is_empty():
				singles.append(source)
			else:
				if not batches.has(key):
					batches[key] = []
				(batches[key] as Array).append(source)

		for key in batches:
			var members: Array = batches[key]
			if members.size() < 2:
				singles.append(members[0] as GeometryInstance3D)
				continue
			_add_batch(members, world_to_canvas)
			batched_instances += members.size()

		for source in singles:
			_add_single(source, world_to_canvas, scene)
	else:
		# Optimized-at-60% still gets correct AABB culling, but deliberately
		# preserves individual GeometryInstance3D transparency/sorting.
		for source in sources:
			_add_single(source, world_to_canvas, scene)

	_last_report = {
		"count": visuals.size(),
		"source_count": sources.size(),
		"visual_count": visuals.size(),
		"batched_instances": batched_instances,
		"culled_count": culled,
		"optimized": optimized,
		"batching_allowed": batching_allowed,
		"batching_reason": batching_reason,
		"context_opacity": opacity,
		"milliseconds": (Time.get_ticks_usec() - started) / 1000.0,
	}
	return _last_report.duplicate(true)


func report() -> Dictionary:
	return _last_report.duplicate(true)


func set_opacity(opacity: float) -> void:
	var alpha := clampf(opacity, 0.0, 1.0)
	for index in visuals.size():
		visuals[index].transparency = (
			1.0 - alpha * (1.0 - original_transparency[index])
		)


func set_frame(canvas_to_world: Transform3D) -> void:
	if canvas_to_world.is_equal_approx(_last_frame):
		return
	_last_frame = canvas_to_world
	var inverse := canvas_to_world.affine_inverse()
	for index in visuals.size():
		if _batched_flags[index]:
			visuals[index].transform = inverse
		else:
			visuals[index].transform = inverse * world_transforms[index]


func clear() -> void:
	for visual in visuals:
		visual.free()
	visuals.clear()
	original_transparency.clear()
	world_transforms.clear()
	_batched_flags.clear()
	_last_report = {}


func _add_single(
	source: GeometryInstance3D,
	world_to_canvas: Transform3D,
	scene: Node,
) -> void:
	var visual: GeometryInstance3D
	if source is MeshInstance3D:
		var mesh_source := source as MeshInstance3D
		if mesh_source.mesh == null:
			return
		var copy := MeshInstance3D.new()
		copy.mesh = mesh_source.mesh
		for surface in mesh_source.mesh.get_surface_count():
			copy.set_surface_override_material(
				surface,
				mesh_source.get_surface_override_material(surface),
			)
		visual = copy
	else:
		var copy := MultiMeshInstance3D.new()
		copy.multimesh = (source as MultiMeshInstance3D).multimesh
		visual = copy

	visual.material_override = source.material_override
	visual.material_overlay = source.material_overlay
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.transform = world_to_canvas * source.global_transform
	visual.set_meta("context_source", str(scene.get_path_to(source)))
	add_child(visual)
	visuals.append(visual)
	original_transparency.append(source.transparency)
	world_transforms.append(source.global_transform)
	_batched_flags.append(false)


func _add_batch(members: Array, world_to_canvas: Transform3D) -> void:
	var first := members[0] as MeshInstance3D
	if first == null or first.mesh == null:
		return
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = first.mesh
	multi.instance_count = members.size()

	var bounds := AABB()
	var has_bounds := false
	for index in members.size():
		var source := members[index] as MeshInstance3D
		multi.set_instance_transform(index, source.global_transform)
		var source_bounds := _world_aabb(source)
		if not has_bounds:
			bounds = source_bounds
			has_bounds = true
		else:
			bounds = bounds.merge(source_bounds)
	if has_bounds:
		# Instance transforms are stored in world-like coordinates and the batch
		# root maps that coordinate space into Canvas, so custom_aabb uses the
		# same world-like coordinates.
		multi.custom_aabb = bounds

	var visual := MultiMeshInstance3D.new()
	visual.name = "ContextBatch_%d" % visuals.size()
	visual.multimesh = multi
	visual.material_override = first.material_override
	visual.material_overlay = first.material_overlay
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.transform = world_to_canvas
	add_child(visual)
	visuals.append(visual)
	original_transparency.append(first.transparency)
	world_transforms.append(Transform3D.IDENTITY)
	_batched_flags.append(true)


func _batch_key(source: GeometryInstance3D) -> String:
	if not source is MeshInstance3D:
		return ""
	if source.transparency > 0.0001:
		return ""
	if not _material_batch_safe(source.material_override):
		return ""
	if not _material_batch_safe(source.material_overlay):
		return ""

	var mesh_source := source as MeshInstance3D
	if mesh_source.mesh == null:
		return ""
	for surface in mesh_source.mesh.get_surface_count():
		if mesh_source.get_surface_override_material(surface) != null:
			return ""
	# material_override replaces surface presentation, but checking the original
	# surfaces too is intentionally conservative for this exact-parity pass.
	if not _mesh_batch_safe(mesh_source.mesh):
		return ""

	var override_id := (
		source.material_override.get_instance_id()
		if source.material_override != null
		else 0
	)
	var overlay_id := (
		source.material_overlay.get_instance_id()
		if source.material_overlay != null
		else 0
	)
	return "%d|%d|%d" % [
		mesh_source.mesh.get_instance_id(),
		override_id,
		overlay_id,
	]


static func _material_batch_safe(material: Material) -> bool:
	if material == null:
		return true
	if material is StandardMaterial3D:
		var standard := material as StandardMaterial3D
		if int(standard.transparency) != 0:
			return false
		# Non-mix blend modes can change ordering/compositing even when the
		# transparency property itself is disabled.
		if int(standard.get("blend_mode")) != 0:
			return false
		return true
	if material is ShaderMaterial:
		var shader := (material as ShaderMaterial).shader
		if shader == null:
			return false
		var code := shader.code
		for marker in [
			"ALPHA",
			"blend_",
			"depth_prepass_alpha",
			"depth_draw_alpha_prepass",
			"alpha_to_coverage",
			"alpha_scissor",
		]:
			if marker in code:
				return false
		return true
	return false


func _mesh_batch_safe(mesh: Mesh) -> bool:
	# v1.2 requires every effective material source to be confidently opaque.
	for surface in mesh.get_surface_count():
		if not _material_batch_safe(mesh.surface_get_material(surface)):
			return false
	return true


func _target_world_aabb(target: Node3D) -> AABB:
	var found := false
	var result := AABB()
	var nodes: Array[Node] = [target]
	nodes.append_array(target.find_children("*", "", true, false))
	for node in nodes:
		if node is VisualInstance3D:
			var visual := node as VisualInstance3D
			if not visual.is_visible_in_tree():
				continue
			var bounds := _world_aabb(visual)
			if not found:
				result = bounds
				found = true
			else:
				result = result.merge(bounds)
	if found:
		return result
	var epsilon := Vector3.ONE * 0.05
	return AABB(target.global_position - epsilon, epsilon * 2.0)


static func _world_aabb(source: VisualInstance3D) -> AABB:
	var local := source.get_aabb()
	if local.size.is_zero_approx():
		var epsilon := Vector3.ONE * 0.01
		return AABB(source.global_position - epsilon, epsilon * 2.0)

	var p := local.position
	var s := local.size
	var corners: Array[Vector3] = [
		p,
		p + Vector3(s.x, 0, 0),
		p + Vector3(0, s.y, 0),
		p + Vector3(0, 0, s.z),
		p + Vector3(s.x, s.y, 0),
		p + Vector3(s.x, 0, s.z),
		p + Vector3(0, s.y, s.z),
		p + s,
	]
	var first: Vector3 = source.global_transform * corners[0]
	var minimum := first
	var maximum := first
	for index in range(1, corners.size()):
		var world: Vector3 = source.global_transform * corners[index]
		minimum = minimum.min(world)
		maximum = maximum.max(world)
	return AABB(minimum, maximum - minimum)


static func _aabb_distance_squared(first: AABB, second: AABB) -> float:
	var first_end := first.end
	var second_end := second.end
	var dx := maxf(
		0.0,
		maxf(first.position.x - second_end.x, second.position.x - first_end.x),
	)
	var dy := maxf(
		0.0,
		maxf(first.position.y - second_end.y, second.position.y - first_end.y),
	)
	var dz := maxf(
		0.0,
		maxf(first.position.z - second_end.z, second.position.z - first_end.z),
	)
	return dx * dx + dy * dy + dz * dz
