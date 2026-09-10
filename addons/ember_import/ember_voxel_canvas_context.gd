@tool
extends Node3D
## Read-only visual snapshot in the existing Canvas world; never duplicate scripts.
const MAX_VISUALS := 4096
var visuals: Array[GeometryInstance3D] = []
var original_transparency: Array[float] = []
var world_transforms: Array[Transform3D] = []
var _last_frame := Transform3D.IDENTITY

func rebuild(scene: Node, target: Node3D, canvas_to_world: Transform3D, exclude_target := true) -> Dictionary:
	if not is_instance_valid(scene) or not is_instance_valid(target) or not scene.is_inside_tree() or (scene != target and not scene.is_ancestor_of(target)):
		return {"error": "Исходная сцена или объект уже закрыты."}
	if absf(canvas_to_world.basis.determinant()) < 0.000001:
		return {"error": "Нулевой масштаб объекта: окружение нельзя совместить с Canvas."}
	var started := Time.get_ticks_usec()
	var sources: Array[GeometryInstance3D] = []
	var pending: Array[Node] = [scene]
	while not pending.is_empty():
		var node := pending.pop_back() as Node
		if node == target and exclude_target:
			continue
		if node is MeshInstance3D or node is MultiMeshInstance3D:
			if node.is_visible_in_tree() and node.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
				sources.append(node)
				if sources.size() > MAX_VISUALS:
					return {"error": "Более 4096 визуальных объектов: фон не построен, чтобы не блокировать редактор."}
		for child in node.get_children():
			pending.append(child)
	clear()
	_last_frame = canvas_to_world
	var world_to_canvas := canvas_to_world.affine_inverse()
	for source in sources:
		var visual: GeometryInstance3D
		if source is MeshInstance3D:
			var mesh_source := source as MeshInstance3D
			if mesh_source.mesh == null:
				continue
			var copy := MeshInstance3D.new()
			copy.mesh = mesh_source.mesh
			for surface in mesh_source.mesh.get_surface_count():
				copy.set_surface_override_material(surface, mesh_source.get_surface_override_material(surface))
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
	return {"count": visuals.size(), "milliseconds": (Time.get_ticks_usec() - started) / 1000.0}

func set_opacity(opacity: float) -> void:
	for index in visuals.size():
		visuals[index].transparency = 1.0 - clampf(opacity, 0.0, 1.0) * (1.0 - original_transparency[index])

func set_frame(canvas_to_world: Transform3D) -> void:
	if canvas_to_world.is_equal_approx(_last_frame):
		return
	_last_frame = canvas_to_world
	var inverse := canvas_to_world.affine_inverse()
	for index in visuals.size():
		visuals[index].transform = inverse * world_transforms[index]

func clear() -> void:
	for visual in visuals:
		visual.free()
	visuals.clear()
	original_transparency.clear()
	world_transforms.clear()
