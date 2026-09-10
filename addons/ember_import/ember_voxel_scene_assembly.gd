@tool
extends RefCounted
## Scene-owned grouping and linked copies. No voxel source or prefab writes.
const Placement = preload("res://addons/ember_import/ember_voxel_placement_session.gd")
const NativeProp = preload("res://scripts/ember_voxel_prop.gd")
const Split = preload("res://addons/ember_import/ember_voxel_object_split.gd")
var error := ""
var source_directory := EmberVoxelCatalog.NATIVE_DIR
var positions: Array[Transform3D] = []
var _placement: RefCounted
var _step := Vector3.ZERO
var _count := 0

func _fail(message: String) -> bool:
	error = message
	return false

func _ordinary(prop: Node, scene: Node) -> bool:
	if not prop is EmberVoxelProp or prop.owner != scene or prop.get_script() != NativeProp:
		return _fail("Выберите обычные voxel-детали, принадлежащие открытой сцене.")
	if prop.water_contact_enabled or prop.is_set_as_top_level():
		return _fail("У детали есть отдельное поведение или независимое положение.")
	var signals_check := Split.new()
	var nodes: Array[Node] = [prop]
	nodes.append_array(prop.find_children("*", "", true, false))
	for node in nodes:
		if signals_check._has_persistent_signals(node):
			return _fail("У детали есть сохраняемые сигналы. Операция не будет разрывать связи.")
		if node != prop and (node.get_script() != null or str(prop.get_path_to(node)) not in ["Mesh", "ShadowBody", "Collision", "Collision/Shape", "Omni"]):
			return _fail("У детали есть дополнительные узлы или скрипты. Сначала выберите обычное окружение.")
		if node is Node3D and node.is_set_as_top_level():
			return _fail("Независимые дочерние узлы не могут двигаться вместе с деталью.")
	if not FileAccess.file_exists(source_directory.path_join(prop.model_id + ".tres")):
		return _fail("Сначала сохраните деталь как native voxel-модель через Canvas.")
	return true

func _scene_valid(scene: Node) -> bool:
	if not is_instance_valid(scene) or not scene.is_inside_tree():
		return _fail("Исходная сцена закрыта.")
	if Engine.is_editor_hint() and EditorInterface.get_edited_scene_root() != scene:
		return _fail("Активная сцена изменилась. Повторите команду.")
	return true

func _references_clear(scene: Node, targets: Array) -> bool:
	# Stored NodePaths and node references are observable dependencies. Arbitrary
	# script literals cannot be safely rewritten, so scripted parts are out of scope.
	var nodes: Array[Node] = [scene]
	nodes.append_array(scene.find_children("*", "", true, false))
	for node in nodes:
		for property in node.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_STORAGE == 0:
				continue
			var value: Variant = node.get(property.name)
			if _references_target(node, value, targets):
				return _fail("Узел «%s» ссылается на перемещаемую деталь (%s). Группировка не будет менять эту связь." % [node.name, property.name])
	return true

func _references_target(origin: Node, value: Variant, targets: Array, depth := 0) -> bool:
	if depth > 8:
		return false
	var referenced: Node
	if value is NodePath and not value.is_empty():
		referenced = origin.get_node_or_null(NodePath(value.get_concatenated_names()))
	elif value is Node:
		referenced = value
	elif value is Array or value is Dictionary:
		var values: Array = value.values() if value is Dictionary else value
		for item in values:
			if _references_target(origin, item, targets, depth + 1):
				return true
	if referenced != null:
		for target in targets:
			if referenced == target or target.is_ancestor_of(referenced):
				if (origin == target or target.is_ancestor_of(origin)) and (not value is NodePath or not value.is_absolute()):
					continue
				return true
	return false

func group(selection: Array, scene: Node, undo: Object) -> Node3D:
	if not _scene_valid(scene):
		return null
	if selection.size() < 2 or selection.size() > 32:
		_fail("Выберите от 2 до 32 отдельных voxel-деталей одного родителя.")
		return null
	var parent := (selection[0] as Node).get_parent() as Node3D
	if parent == null or absf(parent.global_basis.determinant()) < 0.000001:
		_fail("У деталей нет общего 3D-родителя с ненулевым масштабом.")
		return null
	var parts: Array = selection.duplicate()
	for part in parts:
		if not _ordinary(part, scene):
			return null
		if part.get_parent() != parent:
			_fail("Для этой команды детали должны лежать под одним родителем в дереве сцены.")
			return null
	if not _references_clear(scene, parts):
		return null
	parts.sort_custom(func(a: Node, b: Node): return a.get_index() < b.get_index())
	var group_node := Node3D.new()
	var group_name := "VoxelAssembly"
	while parent.has_node(NodePath(group_name)):
		group_name += "_group"
	group_node.name = group_name
	var center := Vector3.ZERO
	for part in parts:
		center += part.position
	group_node.position = center / parts.size()
	var slots: Array[Dictionary] = []
	for part in parts:
		slots.append(_slot(part, part.transform, group_node.transform.affine_inverse() * part.transform, part.get_index(), part.name))
	var at: int = parts[0].get_index()
	_action(undo, scene, "Собрать voxel-детали в группу", _group_state.bind(true, scene, parent, group_node, slots, at), _group_state.bind(false, scene, parent, group_node, slots, at), group_node, true)
	return group_node

func ungroup(group_node: Node3D, scene: Node, undo: Object) -> bool:
	if not _scene_valid(scene):
		return false
	if group_node == null or group_node.get_class() != "Node3D" or group_node.get_script() != null or group_node.owner != scene or not group_node.scene_file_path.is_empty():
		return _fail("Выберите обычную группу деталей, не сцену-prefab и не физический объект.")
	if group_node.unique_name_in_owner or group_node.get_groups().size() > 0 or not group_node.visible or group_node.process_mode != Node.PROCESS_MODE_INHERIT or group_node.is_set_as_top_level():
		return _fail("У группы есть собственные настройки или связи. Разбор не будет терять их.")
	if Split.new()._has_persistent_signals(group_node):
		return _fail("Группа участвует в сохраняемых сигналах.")
	var parts := group_node.get_children()
	if parts.size() < 1 or parts.size() > 32:
		return _fail("Группа должна содержать от 1 до 32 отдельных voxel-деталей.")
	for part in parts:
		if not _ordinary(part, scene):
			return false
	if not _references_clear(scene, [group_node]):
		return false
	var parent := group_node.get_parent() as Node3D
	if parent == null:
		return _fail("У группы нет 3D-родителя.")
	var slots: Array[Dictionary] = []
	var names := {}
	for child in parent.get_children():
		names[str(child.name)] = true
	for part in parts:
		var new_name := str(part.name)
		while names.has(new_name):
			new_name += "_part"
		names[new_name] = true
		slots.append(_slot(part, group_node.transform * part.transform, part.transform, group_node.get_index() + slots.size(), new_name))
	_action(undo, scene, "Разгруппировать voxel-детали", _group_state.bind(false, scene, parent, group_node, slots, group_node.get_index()), _group_state.bind(true, scene, parent, group_node, slots, group_node.get_index()), group_node, false)
	return true

func _slot(part: Node3D, outside: Transform3D, inside: Transform3D, index: int, outside_name: String) -> Dictionary:
	var owners: Array[Dictionary] = []
	var nodes: Array[Node] = [part]
	nodes.append_array(part.find_children("*", "", true, false))
	for node in nodes:
		owners.append({"node": node, "owner": node.owner})
	return {"part": part, "outside": outside, "inside": inside, "index": index, "outside_name": outside_name, "inside_name": str(part.name), "owners": owners}

func _group_state(grouped: bool, scene: Node, parent: Node3D, group_node: Node3D, slots: Array[Dictionary], at: int) -> void:
	# Detach every moved node first; restore owners explicitly after reparenting.
	for slot in slots:
		var part: Node = slot.part
		if part.get_parent() != null:
			part.get_parent().remove_child(part)
	if group_node.get_parent() != null:
		group_node.get_parent().remove_child(group_node)
	if grouped:
		parent.add_child(group_node)
		parent.move_child(group_node, mini(at, parent.get_child_count() - 1))
		group_node.owner = scene
	for slot in slots:
		var part: Node3D = slot.part
		part.name = slot.inside_name if grouped else slot.outside_name
		(group_node if grouped else parent).add_child(part)
		part.transform = slot.inside if grouped else slot.outside
		if not grouped:
			parent.move_child(part, mini(slot.index, parent.get_child_count() - 1))
		for entry in slot.owners:
			entry.node.owner = entry.owner
	var selected: Array = [group_node] if grouped else slots.map(func(slot): return slot.part)
	_select(scene, selected)

func prepare_copies(prop: EmberVoxelProp, scene: Node, world_step: Vector3, count: int) -> bool:
	positions.clear()
	if not _scene_valid(scene) or not _ordinary(prop, scene):
		return false
	if count < 1 or count > 32 or not world_step.is_finite() or world_step.is_zero_approx():
		return _fail("Задайте ненулевой конечный шаг и от 1 до 32 новых копий.")
	_placement = Placement.new()
	_placement.source_directory = source_directory
	if not _placement.open(prop, scene, null):
		return _fail(_placement.error)
	_step = world_step
	_count = count
	for index in count:
		var pose := prop.global_transform
		pose.origin += world_step * (index + 1)
		positions.append(pose)
	return true

func commit_copies(undo: Object) -> Array[EmberVoxelProp]:
	var result: Array[EmberVoxelProp] = []
	if _placement == null or positions.size() != _count:
		_fail("Сначала подготовьте ряд копий.")
		return result
	var source: EmberVoxelProp = _placement.target()
	var scene: Node = _placement.scene()
	if not _scene_valid(scene) or not is_instance_valid(source):
		return result
	# No-op placement commit performs the existing source/hierarchy stale checks.
	var initial: Transform3D = _placement.initial_world()
	_placement.plan(Vector3.ZERO, initial.origin, Vector3.ZERO, 0)
	if not _placement.commit() or not _ordinary(source, scene):
		_fail("Деталь изменилась после предпросмотра. Откройте дублирование заново.")
		return result
	var parent := source.get_parent() as Node3D
	var used := EmberSceneAuthoring.placement_ids(scene)
	for pose in positions:
		var copy := EmberSceneAuthoring.make_duplicate(scene, source, Vector3.ZERO)
		if copy == null:
			for earlier in result:
				earlier.free()
			_fail("Не удалось создать копию. Сцена не изменена.")
			return []
		while used.has(copy.placement_id):
			copy.placement_id += "_copy"
		used[copy.placement_id] = true
		copy.name = copy.placement_id
		copy.unique_name_in_owner = false
		if copy.has_meta("ember_canvas_unique_source"):
			copy.remove_meta("ember_canvas_unique_source")
		copy.transform = parent.global_transform.affine_inverse() * pose
		result.append(copy)
	_action(undo, scene, "Дублировать voxel-ряд", _copies_state.bind(true, scene, parent, source, result), _copies_state.bind(false, scene, parent, source, result), null, true, result)
	positions.clear()
	return result

func _copies_state(attached: bool, scene: Node, parent: Node, source: EmberVoxelProp, copies: Array[EmberVoxelProp]) -> void:
	for copy in copies:
		if attached:
			EmberSceneAuthoring.attach_duplicate(scene, source, parent, copy)
		elif copy.get_parent() == parent:
			parent.remove_child(copy)
	_select(scene, [copies.back()] if attached else [source])

func _action(undo: Object, scene: Node, title: String, forward: Callable, backward: Callable, retained: Node, retain_do: bool, copies: Array = []) -> void:
	if undo == null:
		forward.call()
		return
	if undo is EditorUndoRedoManager:
		undo.create_action(title, UndoRedo.MERGE_DISABLE, scene)
		undo.add_do_method(self, "_invoke", forward)
		undo.add_undo_method(self, "_invoke", backward)
	else:
		undo.create_action(title)
		undo.add_do_method(forward)
		undo.add_undo_method(backward)
	if retained != null:
		if retain_do:
			undo.add_do_reference(retained)
		else:
			undo.add_undo_reference(retained)
	for copy in copies:
		undo.add_do_reference(copy)
	undo.add_do_reference(self)
	undo.commit_action()

func _invoke(command: Callable) -> void:
	command.call()

func _select(scene: Node, nodes: Array) -> void:
	if Engine.is_editor_hint() and EditorInterface.get_edited_scene_root() == scene:
		var selection := EditorInterface.get_selection()
		selection.clear()
		for node in nodes:
			selection.add_node(node)
		EditorInterface.mark_scene_as_unsaved()
