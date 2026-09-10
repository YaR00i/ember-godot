@tool
extends RefCounted
## One preview -> one .tscn transform action for a voxel prop or existing group.
## The selected root is the only owner changed; model/prefab files stay read-only.

const Math = preload("res://addons/ember_import/ember_voxel_placement_math.gd")
const NATIVE_PROP = preload("res://scripts/ember_voxel_prop.gd")
const MAX_MEMBERS := 32

var error := ""
var source_directory := EmberVoxelCatalog.NATIVE_DIR
var grids: Array[Dictionary] = []
var members: Array[EmberVoxelProp] = []
var bounds_local := AABB()
var _target: WeakRef
var _scene: WeakRef
var _parent: WeakRef
var _undo: Object
var _initial_local := Transform3D.IDENTITY
var _initial_world := Transform3D.IDENTITY
var _initial_parent_world := Transform3D.IDENTITY
var _member_stamps: Array[Dictionary] = []
var _node_stamps: Array[Dictionary] = []
var _planned_local := Transform3D.IDENTITY
var _planned_world := Transform3D.IDENTITY
var _planned_pivot_local := Vector3.ZERO
var _has_plan := false


func open(target: Node3D,scene: Node,undo: Object) -> bool:
	error = ""
	grids.clear()
	members.clear()
	_member_stamps.clear()
	_node_stamps.clear()
	_has_plan = false
	if not is_instance_valid(target) or not is_instance_valid(scene) or target == scene:
		return _fail("Выберите voxel-объект или существующую группу его частей.")
	if not scene.is_ancestor_of(target) or target.owner != scene or target.get_parent() == null:
		return _fail("Объект не принадлежит открытой сцене.")
	members = _find_members(target)
	if target is EmberVoxelProp and members.size() != 1:
		return _fail("Voxel-объект содержит вложенные voxel-объекты; выберите один уровень сборки.")
	if not target is EmberVoxelProp and (members.size() < 2 or members.size() > MAX_MEMBERS):
		return _fail("Сборка должна содержать от 2 до 32 voxel-объектов.")
	if members.is_empty():
		return _fail("В выбранном узле нет voxel-объекта.")
	for prop in members:
		if prop != target and prop.is_set_as_top_level():
			return _fail("В сборке есть независимая top-level часть; перемещение корня не сдвинет её вместе со сборкой.")
		if not _find_members_below(prop).is_empty():
			return _fail("В сборке есть вложенные voxel-объекты; выберите один уровень сборки.")
	_target = weakref(target)
	_scene = weakref(scene)
	_parent = weakref(target.get_parent())
	_undo = undo
	_initial_local = target.transform
	_initial_world = target.global_transform
	_initial_parent_world = _parent_world(target)
	if absf(_initial_world.basis.determinant()) < 0.000001:
		return _fail("У объекта нулевой масштаб; точное положение невозможно вычислить.")
	for node in _descendant_node3d(target):
		if node.is_set_as_top_level():
			return _fail("Внутри объекта есть независимый top-level узел; он не будет следовать за общей расстановкой.")
	_add_grid(null,Vector3.ONE,"Мировая · шаг 1 / 1 / 1")
	_capture_node_stamps(target,scene)
	for prop in members:
		if prop.owner != scene or prop.get_script() != NATIVE_PROP:
			return _fail("Сборка содержит объект с отдельным поведением; выберите обычные native voxel-части.")
		var mesh := prop.get_node_or_null("Mesh") as MeshInstance3D
		var source_path := source_directory.path_join(prop.model_id+".tres")
		var source := ResourceLoader.load(source_path,"",ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource if FileAccess.file_exists(source_path) else null
		if mesh == null or mesh.mesh == null or source == null:
			return _fail("%s: сначала сохраните объект как native voxel-модель." % prop.name)
		var density := source.normalized_density()
		var world_basis := mesh.global_transform.basis
		var steps := Vector3(
			world_basis.x.length()/density,
			world_basis.y.length()/density,
			world_basis.z.length()/density,
		)
		if steps.x < 0.000001 or steps.y < 0.000001 or steps.z < 0.000001:
			return _fail("%s: нулевой фактический размер voxel." % prop.name)
		_add_grid(prop,steps)
		_member_stamps.append({
			"target":weakref(prop),
			"path":scene.get_path_to(prop),
			"transform":prop.transform,
			"model_id":prop.model_id,
			"block_world_size":prop.block_world_size,
			"density":prop.voxels_per_block,
			"source_density":density,
			"mesh_transform":mesh.transform,
			"source_path":source_path,
			"source_hash":FileAccess.get_sha256(source_path),
			"source_grid":source.grid_size(),
		})
	if not _build_bounds(target):
		return _fail("У выбранного объекта нет видимой voxel-геометрии для опорной точки.")
	_planned_local = _initial_local
	_planned_world = _initial_world
	return true


func target() -> Node3D:
	return _target.get_ref() as Node3D if _target != null else null


func scene() -> Node:
	return _scene.get_ref() as Node if _scene != null else null


func initial_world() -> Transform3D:
	return _initial_world


func planned_world() -> Transform3D:
	return _planned_world


func grid_steps(index: int) -> Vector3:
	if index < 0 or index >= grids.size():
		return Vector3.ONE
	return grids[index].steps


func grid_label(index: int) -> String:
	return str(grids[index].label) if index >= 0 and index < grids.size() else "Мировая сетка"


func pivot_local(kind: int,custom_vox: Vector3,grid_index: int) -> Vector3:
	if kind == 0:
		return bounds_local.get_center()
	if kind == 1:
		return bounds_local.position
	var selected := target()
	if selected is EmberVoxelProp and not _member_stamps.is_empty():
		var mesh := selected.get_node_or_null("Mesh") as MeshInstance3D
		var density := int(_member_stamps[0].source_density)
		return mesh.transform*Vector3(custom_vox.x/density,custom_vox.y/density,custom_vox.z/density)
	# A group has no common source coordinates. Custom values are therefore
	# offsets from its local lower AABB corner measured on the selected world grid.
	var world_offset := custom_vox*grid_steps(grid_index)
	return bounds_local.position+_initial_world.basis.inverse()*world_offset


func custom_limit() -> Vector3:
	if target() is EmberVoxelProp and not _member_stamps.is_empty():
		return Vector3(_member_stamps[0].source_grid)
	var steps := grid_steps(0)
	var world_extent := Vector3(
		(_initial_world.basis*bounds_local.size).abs().x,
		(_initial_world.basis*bounds_local.size).abs().y,
		(_initial_world.basis*bounds_local.size).abs().z,
	)
	return Vector3(maxf(1,world_extent.x/steps.x),maxf(1,world_extent.y/steps.y),maxf(1,world_extent.z/steps.z))


func coordinate_for_world(point: Vector3,grid_index: int) -> Vector3:
	return Math.world_to_vox(point,grid_steps(grid_index))


func world_for_coordinate(coordinates: Vector3,grid_index: int) -> Vector3:
	return Math.vox_to_world(coordinates,grid_steps(grid_index))


func plan(pivot: Vector3,desired_coordinates: Vector3,rotation_degrees: Vector3,grid_index: int) -> Dictionary:
	_has_plan = false
	var selected := target()
	var parent := _parent.get_ref() if _parent != null else null
	if not is_instance_valid(selected) or not is_instance_valid(parent):
		return {"ok":false,"error":"Объект или его родитель удалён."}
	if grid_index < 0 or grid_index >= grids.size() or not _finite_vector(pivot) or not _finite_vector(desired_coordinates) or not _finite_vector(rotation_degrees):
		return {"ok":false,"error":"Координаты, pivot или поворот содержат недопустимое значение."}
	var desired := world_for_coordinate(desired_coordinates,grid_index)
	_planned_pivot_local = pivot
	_planned_world = Math.place_world(_initial_world,pivot,desired,rotation_degrees)
	_planned_local = _planned_world if selected.is_set_as_top_level() or not parent is Node3D else _initial_parent_world.affine_inverse()*_planned_world
	if not _finite_transform(_planned_local) or absf(_planned_local.basis.determinant()) < 0.000001:
		return {"ok":false,"error":"Получился недопустимый transform. Проверьте значения."}
	_has_plan = true
	return {
		"ok":true,
		"world":_planned_world,
		"local":_planned_local,
		"pivot_world":_planned_world*pivot,
	}


func commit() -> bool:
	if not _has_plan:
		return _fail("Сначала подготовьте предпросмотр положения.")
	var selected := target()
	var current_scene := scene()
	var parent := _parent.get_ref() if _parent != null else null
	if not is_instance_valid(selected) or not is_instance_valid(current_scene) or not is_instance_valid(parent):
		return _fail("Объект, сцена или родитель уже закрыты.")
	if selected.get_parent() != parent or selected.owner != current_scene or not current_scene.is_ancestor_of(selected):
		return _fail("Объект перенесён в другое место дерева. Обновите предпросмотр.")
	if Engine.is_editor_hint() and EditorInterface.get_edited_scene_root() != current_scene:
		return _fail("Активная сцена изменилась. Откройте расстановку заново.")
	if not selected.transform.is_equal_approx(_initial_local) or not selected.global_transform.is_equal_approx(_initial_world) or not _parent_world(selected).is_equal_approx(_initial_parent_world):
		return _fail("Положение объекта или его родителя изменилось после preview. Обновите предпросмотр.")
	if not _members_unchanged(current_scene):
		return false
	if not _hierarchy_unchanged(current_scene):
		return false
	if _planned_local.is_equal_approx(_initial_local):
		return true
	if _undo == null:
		_set_transform(selected,_planned_local,current_scene)
		return true
	if _undo is EditorUndoRedoManager:
		_undo.create_action("Точная voxel-расстановка",UndoRedo.MERGE_DISABLE,current_scene)
		_undo.add_do_method(self,"_set_transform",selected,_planned_local,current_scene)
		_undo.add_undo_method(self,"_set_transform",selected,_initial_local,current_scene)
	else:
		_undo.create_action("Точная voxel-расстановка")
		_undo.add_do_method(_set_transform.bind(selected,_planned_local,current_scene))
		_undo.add_undo_method(_set_transform.bind(selected,_initial_local,current_scene))
	_undo.add_do_reference(self)
	_undo.commit_action()
	return true


func _set_transform(selected: Node3D,value: Transform3D,current_scene: Node) -> void:
	selected.transform = value
	selected.update_gizmos()
	if Engine.is_editor_hint() and EditorInterface.get_edited_scene_root() == current_scene:
		EditorInterface.mark_scene_as_unsaved()


func _append_members(node: Node,result: Array[EmberVoxelProp]) -> void:
	if node is EmberVoxelProp:
		result.append(node)
		return
	for child in node.get_children():
		_append_members(child,result)


func _find_members(node: Node) -> Array[EmberVoxelProp]:
	var result: Array[EmberVoxelProp] = []
	_append_members(node,result)
	return result


func _find_members_below(node: Node) -> Array[EmberVoxelProp]:
	var result: Array[EmberVoxelProp] = []
	for child in node.get_children():
		_append_members(child,result)
	return result


func _add_grid(prop: EmberVoxelProp,steps: Vector3,custom_label := "") -> void:
	for grid in grids:
		if (grid.steps as Vector3).is_equal_approx(steps):
			return
	grids.append({
		"steps":steps,
		"label":custom_label if not custom_label.is_empty() else "Мировая · %s · voxel XYZ %s / %s / %s" % [prop.name,_short(steps.x),_short(steps.y),_short(steps.z)],
	})


func _short(value: float) -> String:
	return str(snappedf(value,0.0001))


func _build_bounds(selected: Node3D) -> bool:
	var has_point := false
	for prop in members:
		var mesh := prop.get_node_or_null("Mesh") as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		var relative := _initial_world.affine_inverse()*mesh.global_transform
		var box := mesh.get_aabb()
		for x in [box.position.x,box.end.x]:
			for y in [box.position.y,box.end.y]:
				for z in [box.position.z,box.end.z]:
					var point := relative*Vector3(x,y,z)
					if not has_point:
						bounds_local = AABB(point,Vector3.ZERO)
						has_point = true
					else:
						bounds_local = bounds_local.expand(point)
	return has_point


func _members_unchanged(current_scene: Node) -> bool:
	var current_members := _find_members(target())
	if current_members.size() != _member_stamps.size():
		return _fail("Состав сборки изменился после preview.")
	for index in _member_stamps.size():
		var stamp := _member_stamps[index]
		var prop := stamp.target.get_ref() as EmberVoxelProp
		var mesh := prop.get_node_or_null("Mesh") as MeshInstance3D if prop != null else null
		if prop == null or mesh == null or current_members[index] != prop or current_scene.get_node_or_null(stamp.path) != prop:
			return _fail("Состав сборки изменился после preview.")
		if prop.model_id != stamp.model_id or prop.block_world_size != stamp.block_world_size or prop.voxels_per_block != stamp.density or not prop.transform.is_equal_approx(stamp.transform) or not mesh.transform.is_equal_approx(stamp.mesh_transform):
			return _fail("Voxel-часть изменилась после preview. Обновите предпросмотр.")
		if not FileAccess.file_exists(stamp.source_path) or FileAccess.get_sha256(stamp.source_path) != stamp.source_hash:
			return _fail("Voxel source изменился после preview. Обновите предпросмотр.")
	return true


func _capture_node_stamps(selected: Node3D,current_scene: Node) -> void:
	for spatial in _descendant_node3d(selected):
		_node_stamps.append({
			"target":weakref(spatial),
			"path":current_scene.get_path_to(spatial),
			"parent":current_scene.get_path_to(spatial.get_parent()),
			"transform":spatial.transform,
			"top_level":spatial.is_set_as_top_level(),
		})


func _descendant_node3d(selected: Node) -> Array[Node3D]:
	var result: Array[Node3D] = []
	var pending: Array[Node] = []
	for child in selected.get_children():
		pending.append(child)
	while not pending.is_empty():
		var node := pending.pop_front() as Node
		if node is Node3D:
			result.append(node)
		for child in node.get_children():
			pending.append(child)
	return result


func _hierarchy_unchanged(current_scene: Node) -> bool:
	var current := _descendant_node3d(target())
	if current.size() != _node_stamps.size():
		return _fail("Состав узлов изменился после preview. Обновите предпросмотр.")
	for index in _node_stamps.size():
		var stamp := _node_stamps[index]
		var node := stamp.target.get_ref() as Node3D
		if node == null or current[index] != node or current_scene.get_node_or_null(stamp.path) != node or current_scene.get_path_to(node.get_parent()) != stamp.parent:
			return _fail("Иерархия сборки изменилась после preview. Обновите предпросмотр.")
		if not node.transform.is_equal_approx(stamp.transform) or node.is_set_as_top_level() != stamp.top_level:
			return _fail("Часть сборки изменила положение после preview. Обновите предпросмотр.")
	return true


func _finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _finite_transform(value: Transform3D) -> bool:
	return _finite_vector(value.origin) and _finite_vector(value.basis.x) and _finite_vector(value.basis.y) and _finite_vector(value.basis.z)


func _parent_world(selected: Node3D) -> Transform3D:
	if selected.is_set_as_top_level() or not selected.get_parent() is Node3D:
		return Transform3D.IDENTITY
	return (selected.get_parent() as Node3D).global_transform


func _fail(message: String) -> bool:
	error = message
	return false
