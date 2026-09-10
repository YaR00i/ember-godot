@tool
extends RefCounted
const Surface = preload("res://addons/ember_import/ember_walk_surface.gd")
var error := ""
var initial_size := Vector2(16, 16)
var initial_pose := Transform3D.IDENTITY
var scene: Node
var parent: Node3D
var target: StaticBody3D
var context_target: Node3D
var planned_pose := Transform3D.IDENTITY
var planned_size := Vector2.ZERO
var warnings: Array[AABB] = []
var _parent_world := Transform3D.IDENTITY
var _has_plan := false
var _target_shape: Shape3D

func open(selected: Node3D, root: Node) -> bool:
	_has_plan = false
	if root == null or selected == null or not root.is_inside_tree() or (selected != root and (not root.is_ancestor_of(selected) or selected.owner != root)):
		return _fail("Выберите объект или группу в открытой 3D-сцене.")
	scene = root
	context_target = selected
	if Surface.is_surface(selected):
		target = selected
		parent = target.get_parent() as Node3D
		initial_pose = target.transform
		initial_size = Surface.dimensions(target)
		var collider := Surface.shape_node(target)
		if not _standard(target):
			return _fail("Поверхность имеет нестандартное устройство. Редактирование остановлено.")
		_target_shape = collider.shape
	else:
		# A prop must remain the existing prefab shape. Attach alongside it; a
		# plain assembly receives the helper as its child and moves it as a unit.
		parent = selected.get_parent() as Node3D if selected is EmberVoxelProp else selected
		if parent == null:
			return _fail("Нужен 3D-родитель площадки.")
		var box := _bounds(selected, parent.global_transform.affine_inverse())
		if box.size != Vector3.ZERO:
			initial_size = Vector2(maxf(0.1, box.size.x), maxf(0.1, box.size.z))
			initial_pose.origin = Vector3(box.get_center().x, box.end.y, box.get_center().z)
	if parent == null or not Surface.orthogonal(parent.global_transform) or not Surface.orthogonal(initial_pose):
		return _fail("У родителя вырожденный или скошенный масштаб. Выберите обычную группу.")
	_parent_world = parent.global_transform
	return true

func plan(size: Vector2, pose: Transform3D) -> bool:
	_has_plan = false
	if not size.is_finite() or size.x < 0.1 or size.y < 0.1 or size.x > 4096 or size.y > 4096:
		return _fail("Размер площадки: от 0.1 до 4096 единиц по каждой оси.")
	var world := _parent_world * pose
	if not Surface.orthogonal(world):
		return _fail("Наклон при этом масштабе создаёт скос. Площадка не будет тайно выравниваться.")
	if world.basis.y.normalized().dot(Vector3.UP) < cos(deg_to_rad(44.0)):
		return _fail("Наклон поверхности превышает 44°: герой сочтёт её стеной.")
	planned_pose = pose
	planned_size = size
	warnings.clear()
	# Conservative visual bounds, explicitly not a proof of physical clearance.
	var inverse := world.affine_inverse()
	var nodes: Array[Node] = [scene]
	nodes.append_array(scene.find_children("*", "MeshInstance3D", true, false))
	for node in nodes:
		if node is MeshInstance3D and node.mesh != null and node.is_visible_in_tree():
			var box: AABB = inverse * node.global_transform * node.get_aabb()
			if box.end.y > 0.05 and box.position.y < 12 and box.position.x < size.x * 0.5 and box.end.x > -size.x * 0.5 and box.position.z < size.y * 0.5 and box.end.z > -size.y * 0.5:
				warnings.append(box)
	_has_plan = true
	return true

func world_pose() -> Transform3D:
	return _parent_world * planned_pose

func commit(undo: Object) -> StaticBody3D:
	if not _has_plan or not is_instance_valid(scene) or not is_instance_valid(parent) or not scene.is_inside_tree() or (scene != parent and not scene.is_ancestor_of(parent)) or not parent.global_transform.is_equal_approx(_parent_world):
		_fail("Сцена или родитель изменились. Откройте поверхность заново.")
		return null
	if Engine.is_editor_hint() and EditorInterface.get_edited_scene_root() != scene:
		_fail("Активная сцена изменилась.")
		return null
	if target != null:
		if not is_instance_valid(target) or not _standard(target) or target.get_parent() != parent or target.owner != scene or not target.transform.is_equal_approx(initial_pose) or Surface.shape_node(target).shape != _target_shape or Surface.dimensions(target) != initial_size:
			_fail("Поверхность изменена после открытия. Обновите предпросмотр.")
			return null
		_action(undo, "Изменить поверхность прохода", _edit.bind(planned_size, planned_pose), _edit.bind(initial_size, initial_pose))
	else:
		target = Surface.make_node(planned_size)
		target.transform = planned_pose
		var unique := "WalkSurface"
		while parent.has_node(NodePath(unique)):
			unique += "_new"
		target.name = unique
		_action(undo, "Создать поверхность прохода", _attach, _detach, true)
	_has_plan = false
	return target

func _action(undo: Object, title: String, forward: Callable, backward: Callable, creation := false) -> void:
	if undo is EditorUndoRedoManager:
		undo.create_action(title, UndoRedo.MERGE_DISABLE, scene)
		undo.add_do_method(self, "_invoke", forward)
		undo.add_undo_method(self, "_invoke", backward)
	else:
		undo.create_action(title)
		undo.add_do_method(forward)
		undo.add_undo_method(backward)
	if creation:
		undo.add_do_reference(target)
	undo.add_do_reference(self)
	undo.commit_action()

func _invoke(command: Callable) -> void:
	command.call()

func _edit(size: Vector2, pose: Transform3D) -> void:
	Surface.set_size(target, size)
	target.transform = pose
	_notify()

func _attach() -> void:
	parent.add_child(target)
	target.owner = scene
	Surface.shape_node(target).owner = scene
	_notify()

func _detach() -> void:
	parent.remove_child(target)
	_notify()

func _notify() -> void:
	if Engine.is_editor_hint() and EditorInterface.get_edited_scene_root() == scene:
		EditorInterface.mark_scene_as_unsaved()
		if target.is_inside_tree():
			EditorInterface.get_selection().clear()
			EditorInterface.get_selection().add_node(target)

func _bounds(node: Node3D, inverse: Transform3D) -> AABB:
	var result := AABB()
	var first := true
	var nodes: Array[Node] = [node]
	nodes.append_array(node.find_children("*", "MeshInstance3D", true, false))
	for visual in nodes:
		if visual is MeshInstance3D and visual.mesh != null:
			var bounds: AABB = inverse * visual.global_transform * visual.get_aabb()
			result = bounds if first else result.merge(bounds)
			first = false
	return result

func _fail(message: String) -> bool:
	error = message
	return false

func _standard(body: StaticBody3D) -> bool:
	var collider := Surface.shape_node(body)
	return collider != null and collider.shape is BoxShape3D and not collider.disabled and body.get_child_count() == 1 and body.get_script() == null and body.collision_layer == 1 and body.collision_mask == 0 and is_equal_approx(collider.shape.size.y, Surface.THICKNESS) and collider.transform.is_equal_approx(Transform3D(Basis.IDENTITY, Vector3(0, -Surface.THICKNESS * 0.5, 0)))
