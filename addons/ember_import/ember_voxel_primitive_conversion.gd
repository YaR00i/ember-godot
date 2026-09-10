@tool
extends RefCounted
## Conversion transaction using the existing shape generator and asset store.
const Creation = preload("res://addons/ember_import/ember_voxel_shape_creation.gd")
const Store = preload("res://addons/ember_import/ember_voxel_model_store.gd")
var source_directory := EmberVoxelCatalog.NATIVE_DIR
var prefab_directory := EmberVoxelPrefab.PREFAB_DIR
var source: EmberVoxelModelResource
var packed: PackedScene
var report := {}
var error := ""
var fit := Transform3D.IDENTITY
var world_size := 16.0
var _mesh: MeshInstance3D
var _scene: Node
var _state := {}

static func inspect(selected: Node, scene: Node, allow_alignment := false) -> Dictionary:
	var mesh := selected as MeshInstance3D
	if mesh == null and selected is Node3D:
		for child in selected.get_children():
			if child is MeshInstance3D:
				if mesh != null:
					return {"error": "Выберите одну простую форму, не составной объект."}
				mesh = child
	if mesh == null or mesh.mesh == null or scene == null or not scene.is_inside_tree() or not scene.is_ancestor_of(mesh):
		return {"error": "Выберите BoxMesh, обычный CylinderMesh или полную SphereMesh в сцене."}
	if mesh.get_script() != null or mesh.get_child_count() != 0 or mesh.owner != scene or not mesh.scene_file_path.is_empty():
		return {"error": "Форма содержит скрипт, детей или принадлежит prefab. Сначала сделайте её обычным самостоятельным узлом сцены."}
	if mesh.get_parent() is EmberVoxelProp or mesh.is_set_as_top_level() or absf(mesh.global_basis.determinant()) < 0.000001:
		return {"error": "Voxel-объект, top-level или нулевой масштаб не преобразуются этой командой."}
	var ancestor := mesh.get_parent()
	while ancestor != scene:
		if ancestor is EmberVoxelProp or not ancestor.scene_file_path.is_empty():
			return {"error": "Деталь внутри prefab не заменяется автоматически. Сначала сделайте её локальной."}
		ancestor = ancestor.get_parent()
	for connection in mesh.get_incoming_connections():
		if int(connection.get("flags",0)) & Object.CONNECT_PERSIST:
			return {"error": "К узлу подключены сохраняемые сигналы. Автоматическая замена остановлена."}
	var kind := ""
	var extent := Vector3.ZERO
	if mesh.mesh is BoxMesh:
		kind = "block"
		extent = (mesh.mesh as BoxMesh).size
	elif mesh.mesh is CylinderMesh:
		var cylinder := mesh.mesh as CylinderMesh
		if not is_equal_approx(cylinder.top_radius,cylinder.bottom_radius) or not cylinder.cap_top or not cylinder.cap_bottom:
			return {"error": "Поддерживается закрытый цилиндр с одинаковыми верхним и нижним радиусами."}
		kind = "cylinder"
		extent = Vector3(cylinder.top_radius * 2,cylinder.height,cylinder.top_radius * 2)
	elif mesh.mesh is SphereMesh:
		var sphere := mesh.mesh as SphereMesh
		if sphere.is_hemisphere or not is_equal_approx(sphere.height,sphere.radius * 2):
			return {"error": "Поддерживается полная сфера: высота равна двум радиусам."}
		kind = "sphere"
		extent = Vector3.ONE * sphere.radius * 2
	else:
		return {"error": "Произвольные Mesh/GLB пока не преобразуются в воксели."}
	if extent.x <= 0 or extent.y <= 0 or extent.z <= 0:
		return {"error": "Размеры формы должны быть положительными."}
	var material := mesh.get_active_material(0)
	if material != null and (not material is StandardMaterial3D or material.albedo_texture != null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED):
		return {"error": "В этом этапе поддерживается одноцветный непрозрачный StandardMaterial3D без текстуры."}
	if mesh.material_overlay != null:
		return {"error": "Материал-overlay не переносится. Сначала уберите его явно."}
	if mesh.transparency > 0.0 or (mesh.mesh as PrimitiveMesh).flip_faces:
		return {"error": "Полупрозрачные и вывернутые формы пока не преобразуются."}
	for signal_info in mesh.get_signal_list():
		for connection in mesh.get_signal_connection_list(signal_info.name):
			if int(connection.get("flags",0)) & Object.CONNECT_PERSIST:
				return {"error": "Форма отправляет сохраняемые сигналы. Автоматическая замена остановлена."}
	var collider: CollisionShape3D
	var body := mesh.get_parent() as CollisionObject3D
	if body == null:
		for sibling in mesh.get_parent().get_children():
			if sibling is CollisionShape3D or sibling is CollisionObject3D:
				return {"error": "Рядом с моделью есть отдельная физика. Выберите простую форму внутри её StaticBody3D, чтобы не оставить старую коллизию."}
	if body != null:
		if not body is StaticBody3D or body.get_script() != null or body.get_child_count() != 2:
			return {"error": "Коллизия должна принадлежать простому StaticBody3D с одной моделью и одной CollisionShape3D."}
		for child in body.get_children():
			if child is CollisionShape3D:
				collider = child
		if collider == null or collider.shape == null or collider.disabled or collider.owner != scene or collider.get_script() != null or collider.get_child_count() > 0:
			return {"error": "Коллизия отключена, имеет отдельное поведение или не совмещена с моделью."}
		var matching: bool = (kind == "block" and collider.shape is BoxShape3D and collider.shape.size.is_equal_approx(extent)) or (kind == "cylinder" and collider.shape is CylinderShape3D and is_equal_approx(collider.shape.radius * 2,extent.x) and is_equal_approx(collider.shape.height,extent.y)) or (kind == "sphere" and collider.shape is SphereShape3D and is_equal_approx(collider.shape.radius * 2,extent.x))
		if not matching or body.constant_linear_velocity != Vector3.ZERO or body.constant_angular_velocity != Vector3.ZERO or not body.get_collision_exceptions().is_empty():
			return {"error": "Коллизия отличается от формы или задаёт движение поверхности. Автоматическая замена небезопасна."}
		if not allow_alignment and not collider.transform.is_equal_approx(mesh.transform):
			var offset := mesh.position - collider.position
			return {"alignable": true, "error": "Коллизия не совмещена с моделью.\nСмещение XYZ: %.6f; %.6f; %.6f (локальные единицы).\nСовмещение перенесёт положение, поворот и масштаб модели на коллизию. Сама модель не изменится. Можно отменить через Undo." % [offset.x,offset.y,offset.z]}
	return {"mesh":mesh,"shape":mesh.mesh,"kind":kind,"extent":extent,"color":material.albedo_color if material != null else Color.WHITE,"collider":collider,"transform":mesh.transform,"global_transform":mesh.global_transform,"parent":mesh.get_parent(),"name":mesh.name,"index":mesh.get_index(),"collision_index":collider.get_index() if collider != null else -1,"collision_shape":collider.shape if collider != null else null,"layer":body.collision_layer if body != null else 0,"mask":body.collision_mask if body != null else 0,"physics_material":body.physics_material_override if body != null else null}

static func align_collision(selected: Node, scene: Node, undo: Object) -> bool:
	if not is_instance_valid(selected) or not is_instance_valid(scene):
		return false
	if Engine.is_editor_hint() and EditorInterface.get_edited_scene_root() != scene:
		return false
	var data := inspect(selected,scene,true)
	if data.has("error") or data.collider == null:
		return false
	var collider: CollisionShape3D = data.collider
	var mesh: MeshInstance3D = data.mesh
	if collider.transform.is_equal_approx(mesh.transform):
		return true
	if undo is EditorUndoRedoManager:
		undo.create_action("Совместить коллизию с моделью",UndoRedo.MERGE_DISABLE,scene)
	else:
		undo.create_action("Совместить коллизию с моделью")
	undo.add_do_property(collider,"transform",mesh.transform)
	undo.add_undo_property(collider,"transform",collider.transform)
	undo.commit_action()
	return true

func prepare(mesh: MeshInstance3D, scene: Node, dimensions: Vector3i, density: int, color: Color, title: String, block_size := 16.0) -> bool:
	_state = inspect(mesh,scene)
	if _state.has("error"):
		error = _state.error
		return false
	_mesh = mesh
	_scene = scene
	world_size = block_size
	var creation := Creation.new()
	creation.source_directory = source_directory
	creation.prefab_directory = prefab_directory
	if not creation.prepare(_state.kind,dimensions,density,color,title):
		error = creation.error
		return false
	source = creation.source
	source.physical = _state.collider != null
	packed = EmberVoxelPrefab.prepare_resource(source)
	report = creation.report
	# Exact original bounds: expose the fitted voxel step instead of silently
	# moving a thin/decorative shape onto a rounded world grid.
	var step := world_size / density
	var ratio: Vector3 = _state.extent / (Vector3(dimensions) * step)
	var center := (Vector3(report.origin) + Vector3(dimensions) * 0.5) * step
	center -= Vector3(report.grid.x,0,report.grid.z) * step * 0.5
	fit = Transform3D(Basis.from_scale(ratio),-center * ratio)
	error = "" if packed != null else "Не удалось построить voxel preview."
	return packed != null

func commit(undo: Object) -> EmberVoxelProp:
	if not is_instance_valid(_mesh) or not is_instance_valid(_scene) or (Engine.is_editor_hint() and EditorInterface.get_edited_scene_root() != _scene):
		error = "Сцена или объект изменились. Откройте предпросмотр заново."
		return null
	var current := inspect(_mesh,_scene)
	if current != _state or packed == null:
		error = "Форма, материал, коллизия или положение изменились после preview. Обновите предпросмотр."
		return null
	var path := source_directory.path_join(source.model_id + ".tres")
	var prefab := prefab_directory.path_join(source.model_id + ".tscn")
	if FileAccess.file_exists(path) or FileAccess.file_exists(prefab):
		error = "ID уже сохранён. Обновите предпросмотр."
		return null
	var saved := Store.install_prepared_asset(source,packed,path,prefab)
	if not saved.ok:
		error = saved.error
		return null
	var prop := EmberSceneAuthoring.make_model_instance(_scene,saved.packed,source.model_id,Vector3.ZERO)
	prop.configure_voxel_scale(source.normalized_density(),world_size)
	prop.name = _mesh.name
	prop.transform = _mesh.transform * fit
	prop.visible = _mesh.visible
	for group in _mesh.get_groups():
		if not str(group).begins_with("_"):
			prop.add_to_group(group,_mesh.is_in_group(group))
	for key in _mesh.get_meta_list():
		if not str(key).begins_with("ember_"):
			prop.set_meta(key,_mesh.get_meta(key))
	if source.physical:
		var body := prop.get_node("Collision") as StaticBody3D
		body.collision_layer = _state.layer
		body.collision_mask = _state.mask
		body.physics_material_override = _state.physics_material
	if undo is EditorUndoRedoManager:
		undo.create_action("Преобразовать форму в voxel",UndoRedo.MERGE_DISABLE,_scene)
		undo.add_do_method(self,"_swap",prop,true)
		undo.add_undo_method(self,"_swap",prop,false)
	else:
		undo.create_action("Преобразовать форму в voxel")
		undo.add_do_method(_swap.bind(prop,true))
		undo.add_undo_method(_swap.bind(prop,false))
	undo.add_do_reference(prop)
	undo.add_undo_reference(_mesh)
	if _state.collider != null:
		undo.add_undo_reference(_state.collider)
	undo.add_do_reference(self)
	undo.commit_action()
	return prop

func _swap(prop: EmberVoxelProp, forward: bool) -> void:
	var parent: Node = _state.parent
	var removed: Node = _mesh if forward else prop
	var added: Node = prop if forward else _mesh
	parent.remove_child(removed)
	if forward and _state.collider != null:
		parent.remove_child(_state.collider)
	parent.add_child(added)
	parent.move_child(added,mini(_state.index,parent.get_child_count()-1))
	added.owner = _scene
	if not forward and _state.collider != null:
		parent.add_child(_state.collider)
		parent.move_child(_state.collider,mini(_state.collision_index,parent.get_child_count()-1))
		_state.collider.owner = _scene
	if Engine.is_editor_hint():
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(added)
		EditorInterface.mark_scene_as_unsaved()
		EditorInterface.get_resource_filesystem().scan()
