@tool
extends RefCounted
const Surface = preload("res://addons/ember_import/ember_walk_surface.gd")
const Mask = preload("res://addons/ember_import/ember_walk_surface_mask.gd")
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
var initial_mask: Dictionary = {}
var planned_mask: Dictionary = {}
var voxel_cell := Vector2.ONE
var voxel_height := 1.0
var geometry_pose := Transform3D.IDENTITY
var geometry_count := Vector2i.ZERO
var geometry_error := ""
var _visuals: Array[MeshInstance3D] = []
var _visual_state: Array[Dictionary] = []
var _source_path := NodePath()
var _geometry_dirty := false
var _geometry_source: WeakRef
var _candidate_ids: Array[int] = []
var _initial_source_path := NodePath(".")

func open(selected: Node3D, root: Node) -> bool:
	_has_plan = false
	if root == null or selected == null or not root.is_inside_tree() or (selected != root and (not root.is_ancestor_of(selected) or selected.owner != root)):
		return _fail("Выберите объект или группу в открытой 3D-сцене.")
	scene = root
	context_target = selected
	var picked := selected
	if not Surface.is_surface(selected):
		var container := selected.get_parent() as Node3D if selected is EmberVoxelProp else selected
		var linked: Array[Node3D] = []
		if container != null:
			for node in container.get_children():
				if Surface.is_surface(node) and node.owner == root and (node.collision_layer & 1) != 0 and container.get_node_or_null(node.get_meta("ember_walk_source",NodePath("."))) == selected:
					linked.append(node)
		if linked.size() > 1:
			return _fail("Для настила найдены несколько активных опор. Выберите нужную WalkSurface и откройте её: «Оставить эту опору» отключит совпадающий дубликат.")
		if linked.size() == 1:
			picked = linked[0]
	if Surface.is_surface(picked):
		target = picked
		parent = target.get_parent() as Node3D
		initial_pose = target.transform
		initial_size = Surface.dimensions(target)
		initial_mask = target.get_meta(Surface.MASK_KEY, {}).duplicate(true)
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
	if target == null:
		_source_path = parent.get_path_to(selected)
		_capture_geometry(selected)
	else:
		_source_path = target.get_meta("ember_walk_source",NodePath("."))
		_initial_source_path = _source_path
		var source := parent.get_node_or_null(_source_path) as Node3D
		if source == null or Surface.is_surface(source):
			geometry_error = "Исходный настил не найден. Выберите доски для новой генерации. Сохранённую разметку можно править кистью."
		else:
			_capture_geometry(source)
	return true

func rebind_geometry(selected: Node3D) -> bool:
	if selected == null or Surface.is_surface(selected) or not selected.is_inside_tree() or (selected != parent and not parent.is_ancestor_of(selected)):
		return _fail("Выберите настил внутри родителя этой опоры.")
	for state in _visual_state:
		var mesh: Mesh = state.mesh
		if mesh.changed.is_connected(_geometry_changed):
			mesh.changed.disconnect(_geometry_changed)
	_visuals.clear()
	_visual_state.clear()
	_candidate_ids.clear()
	_geometry_dirty = false
	geometry_error = ""
	_source_path = parent.get_path_to(selected)
	_capture_geometry(selected)
	return geometry_error.is_empty()

func _capture_geometry(selected: Node3D) -> void:
	_geometry_source = weakref(selected)
	var nodes: Array[Node] = [selected]
	nodes.append_array(selected.find_children("*", "MeshInstance3D", true, false))
	for node in nodes:
		if node is MeshInstance3D:
			_candidate_ids.append(node.get_instance_id())
	var frame := Transform3D.IDENTITY
	var first := true
	for node in nodes:
		if not node is MeshInstance3D or node.mesh == null or not node.is_visible_in_tree():
			continue
		var ancestor: Node = node
		var skip := false
		var prop: EmberVoxelProp
		while ancestor != null:
			if Surface.is_surface(ancestor) or ancestor.name == &"ShadowBody":
				skip = true
			if ancestor is EmberVoxelProp:
				prop = ancestor
				break
			if ancestor == scene:
				break
			ancestor = ancestor.get_parent()
		if skip:
			continue
		var pose: Transform3D = _parent_world.affine_inverse()*node.global_transform
		var cell := Vector2.ONE
		var height_cell := 1.0
		if prop != null:
			cell = Vector2(pose.basis.x.length(),pose.basis.z.length())/prop.voxels_per_block
			height_cell = pose.basis.y.length()/prop.voxels_per_block
		if first:
			frame = Transform3D(pose.basis.orthonormalized(),pose.origin)
			voxel_cell = cell
			voxel_height = height_cell
			first = false
		elif prop != null and (not cell.is_equal_approx(voxel_cell) or not is_equal_approx(height_cell,voxel_height) or not pose.basis.orthonormalized().is_equal_approx(frame.basis)):
			geometry_error = "Детали имеют разные voxel-сетки. Сначала выровняйте их или выберите один объект."
		if prop != null:
			var offset := frame.affine_inverse()*pose.origin
			var lattice := Vector2(offset.x,offset.z)/voxel_cell
			if not lattice.is_equal_approx(lattice.round()):
				geometry_error = "Доски смещены между voxel-клетками. Выровняйте группу по общей сетке."
		_visuals.append(node)
		_visual_state.append({"node":weakref(node),"pose":node.global_transform,"mesh":node.mesh})
		if not node.mesh.changed.is_connected(_geometry_changed):
			node.mesh.changed.connect(_geometry_changed)
	if first:
		geometry_error = "Нет геометрии настила. Выберите доски или их группу."
		return
	var inverse := frame.affine_inverse()*_parent_world.affine_inverse()
	var box := _bounds(selected,inverse)
	var low := Vector2(box.position.x,box.position.z)/voxel_cell
	var high := Vector2(box.end.x,box.end.z)/voxel_cell
	low = (low+Vector2.ONE*0.0001).floor()
	high = (high-Vector2.ONE*0.0001).ceil()
	geometry_count = Vector2i(high-low)
	var center := (low+high)*0.5*voxel_cell
	geometry_pose = frame*Transform3D(Basis.IDENTITY,Vector3(center.x,box.end.y,center.y))
	if geometry_count.x < 1 or geometry_count.y < 1 or geometry_count.x*geometry_count.y > Mask.MAX_CELLS:
		geometry_error = "Настил превышает 65 536 voxel-клеток. Выберите меньшую группу."

func _geometry_changed() -> void:
	_geometry_dirty = true

func geometry_current(check_membership := false) -> bool:
	if _geometry_dirty:
		return false
	if check_membership and _geometry_source != null:
		var source: Node = _geometry_source.get_ref()
		if not is_instance_valid(source) or not source.is_inside_tree():
			return false
		var ids: Array[int] = []
		var nodes: Array[Node] = [source]
		nodes.append_array(source.find_children("*","MeshInstance3D",true,false))
		for node in nodes:
			if node is MeshInstance3D:
				ids.append(node.get_instance_id())
		if ids != _candidate_ids:
			return false
	for state in _visual_state:
		var node: MeshInstance3D = state.node.get_ref()
		if not is_instance_valid(node) or not node.is_inside_tree() or not node.is_visible_in_tree() or node.mesh != state.mesh or not node.global_transform.is_equal_approx(state.pose):
			return false
	return true

func generate(maximum_gap: int, tolerance_voxels: int) -> bool:
	_has_plan = false
	if not geometry_error.is_empty():
		return _fail(geometry_error)
	if not geometry_current(true):
		return _fail("Доски изменились. Откройте инструмент заново.")
	var triangles := PackedVector3Array()
	var inverse := (_parent_world*geometry_pose).affine_inverse()
	for visual in _visuals:
		var pose := inverse*visual.global_transform
		for surface_index in visual.mesh.get_surface_count():
			if visual.mesh is ArrayMesh and visual.mesh.surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arrays := visual.mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			for index in vertices.size() if indices.is_empty() else indices.size():
				triangles.append(pose*vertices[index if indices.is_empty() else indices[index]])
	var bits := Mask.rasterize(triangles,geometry_count,voxel_cell,tolerance_voxels*voxel_height)
	bits = Mask.close_gaps(bits,geometry_count,maximum_gap)
	var data := Mask.make(geometry_count,voxel_cell,bits)
	data["height_cell"] = voxel_height
	return plan_mask(data,geometry_pose)

func plan_mask(data: Dictionary, pose: Transform3D) -> bool:
	_has_plan = false
	if not Mask.valid(data):
		return _fail("Некорректная voxel-разметка.")
	var rects := Mask.rectangles(data)
	if rects.is_empty():
		planned_mask = data.duplicate(true)
		return _fail("Опора пуста. Верните клетки кистью или пересоздайте разметку.")
	if rects.size() > Mask.MAX_RECTS:
		return _fail("Слишком раздробленная опора: более 2048 участков. Уменьшите группу или число отверстий.")
	if not plan(Mask.size(data),pose):
		return false
	planned_mask = data.duplicate(true)
	return true

func plan(size: Vector2, pose: Transform3D) -> bool:
	_has_plan = false
	planned_mask = {}
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

func duplicates() -> Array[StaticBody3D]:
	var result: Array[StaticBody3D] = []
	if target == null or planned_mask.is_empty() or not is_instance_valid(parent):
		return result
	var source := parent.get_node_or_null(_source_path)
	if source == null:
		return result
	for node in parent.get_children():
		if node == target or not Surface.is_surface(node) or node.owner != scene or (node.collision_layer & 1) == 0 or not node.transform.is_equal_approx(planned_pose):
			continue
		if parent.get_node_or_null(node.get_meta("ember_walk_source",NodePath("."))) != source:
			continue
		var data: Dictionary = node.get_meta(Surface.MASK_KEY,{})
		if Mask.valid(data) and data.count == planned_mask.count and data.cell.is_equal_approx(planned_mask.cell) and data.allowed == planned_mask.allowed and _standard(node):
			result.append(node)
	return result

func commit(undo: Object, replace_duplicates := false) -> StaticBody3D:
	if not _has_plan or not is_instance_valid(scene) or not is_instance_valid(parent) or not scene.is_inside_tree() or (scene != parent and not scene.is_ancestor_of(parent)) or not parent.global_transform.is_equal_approx(_parent_world):
		_fail("Сцена или родитель изменились. Откройте поверхность заново.")
		return null
	var conflicts := duplicates()
	if not conflicts.is_empty() and not replace_duplicates:
		_fail("Другие опоры перекрывают эту разметку. Нажмите «Оставить эту опору», чтобы применить её и отключить совпадающие дубликаты.")
		return null
	if not planned_mask.is_empty() and not geometry_current(true):
		_fail("Геометрия изменилась. Откройте поверхность заново.")
		return null
	if Engine.is_editor_hint() and EditorInterface.get_edited_scene_root() != scene:
		_fail("Активная сцена изменилась.")
		return null
	if target != null:
		if not is_instance_valid(target) or not _standard(target) or target.get_parent() != parent or target.owner != scene or not target.transform.is_equal_approx(initial_pose) or Surface.shape_node(target).shape != _target_shape or Surface.dimensions(target) != initial_size or target.get_meta(Surface.MASK_KEY,{}) != initial_mask:
			_fail("Поверхность изменена после открытия. Обновите предпросмотр.")
			return null
		var others: Array[Dictionary] = []
		for node in conflicts:
			others.append({"node":node,"layer":node.collision_layer})
		var title := "Оставить одну поверхность прохода" if not others.is_empty() else "Изменить поверхность прохода"
		_action(undo,title,_edit_resolve.bind(planned_size,planned_pose,planned_mask.duplicate(true),_source_path,others,true),_edit_resolve.bind(initial_size,initial_pose,initial_mask.duplicate(true),_initial_source_path,others,false))
	else:
		target = Surface.make_node(planned_size)
		if not planned_mask.is_empty():
			Surface.set_mask(target,planned_mask)
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

func _edit(size: Vector2, pose: Transform3D, data: Dictionary, source_path: NodePath) -> void:
	if data.is_empty():
		Surface.set_size(target, size)
	else:
		Surface.set_mask(target,data)
	target.set_meta("ember_walk_source",source_path)
	target.transform = pose
	_notify()

func _edit_resolve(size: Vector2, pose: Transform3D, data: Dictionary, source_path: NodePath, others: Array[Dictionary], disable: bool) -> void:
	_edit(size,pose,data,source_path)
	for state in others:
		if is_instance_valid(state.node):
			state.node.collision_layer = 0 if disable else state.layer
			state.node.update_gizmos()

func _attach() -> void:
	parent.add_child(target)
	target.set_meta("ember_walk_source",_source_path)
	target.owner = scene
	for child in target.get_children():
		child.owner = scene
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
	if body.has_meta(Surface.MASK_KEY):
		var data: Dictionary = body.get_meta(Surface.MASK_KEY)
		if not Mask.valid(data) or body.get_script() != null or body.collision_layer != 1 or body.collision_mask != 0:
			return false
		var rects := Mask.rectangles(data)
		if rects.is_empty() or rects.size() > Mask.MAX_RECTS or body.get_child_count() != rects.size():
			return false
		for index in rects.size():
			var shape := body.get_child(index) as CollisionShape3D
			var extent: Vector2 = Vector2(rects[index].size)*data.cell
			if shape == null or not shape.shape is BoxShape3D or shape.disabled or not shape.shape.size.is_equal_approx(Vector3(extent.x,Surface.THICKNESS,extent.y)) or not shape.transform.is_equal_approx(Transform3D(Basis.IDENTITY,Mask.rect_pose(rects[index],data)+Vector3(0,-Surface.THICKNESS*0.5,0))):
				return false
		return collider != null
	return collider != null and collider.shape is BoxShape3D and not collider.disabled and body.get_child_count() == 1 and body.get_script() == null and body.collision_layer == 1 and body.collision_mask == 0 and is_equal_approx(collider.shape.size.y, Surface.THICKNESS) and collider.transform.is_equal_approx(Transform3D(Basis.IDENTITY, Vector3(0, -Surface.THICKNESS * 0.5, 0)))
