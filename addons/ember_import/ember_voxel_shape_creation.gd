@tool
extends RefCounted
## One prepared preview -> one scene creation action; no new asset store.
const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
const Store = preload("res://addons/ember_import/ember_voxel_model_store.gd")
var source_directory := EmberVoxelCatalog.NATIVE_DIR
var prefab_directory := EmberVoxelPrefab.PREFAB_DIR
var source: EmberVoxelModelResource
var packed: PackedScene
var report := {}
var error := ""
var world_size := 16.0

func prepare(kind: String, dimensions: Vector3i, density: int, color: Color, title: String) -> bool:
	packed = null
	source = null
	var id := "vox_shape_%s_%d" % [kind, Time.get_ticks_usec()]
	while FileAccess.file_exists(source_directory.path_join(id + ".tres")) or FileAccess.file_exists(prefab_directory.path_join(id + ".tscn")):
		id += "x"
	report = Shapes.build(kind, dimensions, density, color, id, title)
	if not report.ok:
		error = report.error
		return false
	source = report.source
	packed = EmberVoxelPrefab.prepare_resource(source)
	error = "" if packed != null else "Не удалось подготовить preview модели."
	return packed != null

func commit(root: Node, parent: Node3D, undo: Object, position: Vector3) -> EmberVoxelProp:
	if Engine.is_editor_hint() and EditorInterface.get_edited_scene_root() != root:
		error = "Активная сцена изменилась. Откройте создание объекта заново."
		return null
	if source == null or packed == null or not is_instance_valid(root) or not is_instance_valid(parent) or (root != parent and not root.is_ancestor_of(parent)):
		error = "Сцена или подготовленный preview больше недоступны."
		return null
	var source_path := source_directory.path_join(source.model_id + ".tres")
	var prefab_path := prefab_directory.path_join(source.model_id + ".tscn")
	if FileAccess.file_exists(source_path) or FileAccess.file_exists(prefab_path):
		error = "Этот ID уже сохранён. Подготовьте новый preview."
		return null
	var saved := Store.install_prepared_asset(source, packed, source_path, prefab_path)
	if not saved.ok:
		error = saved.error
		return null
	var prop := EmberSceneAuthoring.make_model_instance(root, saved.packed as PackedScene, source.model_id, position)
	prop.configure_voxel_scale(source.normalized_density(), world_size)
	prop.scene_file_path = prefab_path
	prop.set_meta(EmberVoxelPrefab.SOURCE_SIGNATURE_META, saved.signature)
	if undo is EditorUndoRedoManager:
		undo.create_action("Создать voxel-форму", UndoRedo.MERGE_DISABLE, root)
		undo.add_do_method(self, "_attach", root, parent, prop)
		undo.add_undo_method(self, "_detach", parent, prop)
	else:
		undo.create_action("Создать voxel-форму")
		undo.add_do_method(_attach.bind(root, parent, prop))
		undo.add_undo_method(_detach.bind(parent, prop))
	undo.add_do_reference(prop)
	undo.add_do_reference(self)
	undo.commit_action()
	return prop

func _attach(root: Node, parent: Node3D, prop: EmberVoxelProp) -> void:
	if not is_instance_valid(root) or not is_instance_valid(parent):
		return
	EmberSceneAuthoring.attach_model_instance(root, parent, prop)
	if Engine.is_editor_hint():
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(prop)
		EditorInterface.mark_scene_as_unsaved()
		EditorInterface.get_resource_filesystem().scan()

func _detach(parent: Node3D, prop: EmberVoxelProp) -> void:
	if is_instance_valid(parent) and prop.get_parent() == parent:
		parent.remove_child(prop)
	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()
