@tool
extends RefCounted
## One explicit generation -> one canonical object asset and scene placement.

const Generator = preload("res://addons/ember_import/ember_voxel_generator.gd")
const Store = preload("res://addons/ember_import/ember_voxel_model_store.gd")
signal asset_changed(model_id: String)
signal library_state_changed(published: bool)

var source_directory := EmberVoxelCatalog.NATIVE_DIR
var prefab_directory := EmberVoxelPrefab.PREFAB_DIR
var recipe_directory := "res://content/editor/voxel_generators"
var source: EmberVoxelModelResource
var packed: PackedScene
var recipe: Resource
var report := {}
var error := ""
var world_size := 16.0
var _update_model_id := ""
var _update_source_hash := ""
var _update_recipe_hash := ""
var _library_bytes := {}
var _library_present := false
var _library_root: WeakRef


## Unloaded editor candidate: identity/recipe and publication bytes remain,
## but no geometry Resource or GPU mesh is retained by its library history.
func unload_prepared_geometry() -> void:
	if source == null: return
	var identity := EmberVoxelModelResource.new()
	identity.model_id = source.model_id
	identity.display_name = source.display_name
	identity.voxels_per_block = source.voxels_per_block
	identity.size_blocks = source.size_blocks
	identity.height_voxels = source.height_voxels
	source = identity
	packed = null
	report.erase("geometry")


## Publish a prepared candidate without creating a scene instance. History owns
## only these newly-created files and refuses to erase later external edits.
func save_to_library(root: Node, undo: Object) -> bool:
	error = ""
	if not is_instance_valid(root) or not is_instance_valid(undo) or (Engine.is_editor_hint() and EditorInterface.get_edited_scene_root() != root):
		error = "Активная сцена изменилась. Откройте генерацию заново."
		return false
	if source == null or packed == null or recipe == null or _library_present:
		error = "Вариант не подготовлен или уже сохранён."
		return false
	var paths: Array[String] = [source_directory.path_join(source.model_id + ".tres"),
		prefab_directory.path_join(source.model_id + ".tscn"), recipe_path(source.model_id, recipe_directory)]
	for path in paths:
		if FileAccess.file_exists(path):
			error = "Файл уже существует; он не перезаписан: " + path
			return false
	var result := Store.install_prepared_asset(source, packed, paths[0], paths[1])
	if not bool(result.get("ok", false)):
		error = str(result.error)
		return false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(recipe_directory))
	var saved := ResourceSaver.save(recipe, paths[2])
	if saved != OK:
		for path in paths.slice(0, 2):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		error = "Рецепт не сохранён; публикация отменена: " + error_string(saved)
		return false
	for path in paths:
		_library_bytes[path] = FileAccess.get_file_as_bytes(path)
	_library_present = true
	_library_root = weakref(root)
	if undo is EditorUndoRedoManager:
		undo.create_action("Сохранить вариант генератора", UndoRedo.MERGE_DISABLE, root)
		undo.add_do_method(self, "_set_library_present", true)
		undo.add_undo_method(self, "_set_library_present", false)
	else:
		undo.create_action("Сохранить вариант генератора")
		undo.add_do_method(_set_library_present.bind(true))
		undo.add_undo_method(_set_library_present.bind(false))
	undo.add_do_reference(self)
	undo.commit_action(false)
	library_state_changed.emit(true)
	asset_changed.emit(source.model_id)
	return true


func _set_library_present(present: bool) -> void:
	if present == _library_present: return
	if not present and _library_used():
		error = "Вариант уже используется в сцене. Сначала уберите его экземпляры и сохраните карту; файлы не удалены."
		push_warning(error)
		return
	for path in _library_bytes:
		if (present and FileAccess.file_exists(path)) or (not present and (not FileAccess.file_exists(path) or FileAccess.get_file_as_bytes(path) != _library_bytes[path])):
			error = "Файл изменён после сохранения; история его не перезаписывает: " + str(path)
			push_warning(error)
			return
	var changed: Array[String] = []
	for path in _library_bytes:
		var result := OK
		if present:
			var file := FileAccess.open(path, FileAccess.WRITE)
			result = FileAccess.get_open_error() if file == null else OK
			if file != null:
				file.store_buffer(_library_bytes[path])
				result = file.get_error()
				file.close()
		else:
			result = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if result != OK:
			if present and FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			# Restore the subset already changed, retaining exact published bytes.
			for previous in changed:
				if present:
					DirAccess.remove_absolute(ProjectSettings.globalize_path(previous))
				else:
					var restore := FileAccess.open(previous, FileAccess.WRITE)
					if restore != null: restore.store_buffer(_library_bytes[previous])
			error = "Не удалось изменить файлы истории: " + error_string(result)
			push_warning(error)
			return
		changed.append(path)
	_library_present = present
	library_state_changed.emit(present)
	asset_changed.emit(source.model_id)
	if Engine.is_editor_hint(): preload("res://addons/ember_import/ember_editor_filesystem.gd").request()


func _library_used() -> bool:
	# Library history must not invalidate an object subsequently placed in a map.
	var scene: Node = _library_root.get_ref() if _library_root != null else null
	if Engine.is_editor_hint(): scene = (Engine.get_main_loop() as SceneTree).root
	var queue: Array[Node] = []
	if is_instance_valid(scene): queue.append(scene)
	while not queue.is_empty():
		var node: Node = queue.pop_back()
		if node is EmberVoxelProp and node.owner != null and node.model_id == source.model_id: return true
		queue.append_array(node.get_children())
	if not Engine.is_editor_hint(): return false
	var directories: Array[String] = ["res://scenes"]
	while not directories.is_empty():
		var directory: String = directories.pop_back()
		for child in DirAccess.get_directories_at(directory): directories.append(directory.path_join(child))
		for file in DirAccess.get_files_at(directory):
			if file.get_extension() == "tscn" and source.model_id in FileAccess.get_file_as_string(directory.path_join(file)): return true
	return false


static func recipe_path(model_id: String, directory := "res://content/editor/voxel_generators") -> String:
	return directory.path_join(model_id + ".tres")


static func load_recipe(model_id: String, directory := "res://content/editor/voxel_generators") -> Resource:
	var path := recipe_path(model_id, directory)
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) if ResourceLoader.exists(path) else null


func prepare(settings: Dictionary, seed: int, title: String) -> bool:
	packed = null
	source = null
	recipe = Generator.default_recipe(Generator.LARGE_TREE)
	recipe.seed = maxi(0, seed)
	recipe.parameters = Generator.normalized_parameters(Generator.LARGE_TREE, settings)
	return prepare_recipe(recipe, title)


## Shared prepared-asset transaction for any supported object recipe.
func prepare_recipe(next_recipe: Resource, title: String, update_model_id := "", candidate_model_id := "") -> bool:
	packed = null
	source = null
	_update_model_id = update_model_id
	_update_source_hash = FileAccess.get_sha256(source_directory.path_join(update_model_id + ".tres")) if not update_model_id.is_empty() else ""
	_update_recipe_hash = FileAccess.get_sha256(recipe_path(update_model_id, recipe_directory)) if not update_model_id.is_empty() else ""
	var errors := Generator.validation_errors(next_recipe)
	if not errors.is_empty():
		error = errors[0]
		return false
	recipe = next_recipe.duplicate(true)
	var prefix := "tree" if recipe.generator_id == Generator.LARGE_TREE else str(recipe.generator_id)
	var id := "vox_%s_%d" % [prefix, Time.get_ticks_usec()]
	while (
		FileAccess.file_exists(source_directory.path_join(id + ".tres"))
		or FileAccess.file_exists(prefab_directory.path_join(id + ".tscn"))
		or FileAccess.file_exists(recipe_path(id, recipe_directory))
	):
		id += "x"
	# An unsaved studio revision retains candidate identity, never an asset update.
	if not candidate_model_id.is_empty(): id = candidate_model_id
	var started := Time.get_ticks_usec()
	report = Generator.build(recipe, Color.WHITE, {}, title, id)
	if report.has("error"):
		error = str(report.error)
		return false
	source = report.geometry
	if recipe.family_id.is_empty():
		recipe.family_id = source.model_id
		recipe.family_title = title
	if report.has("structure"):
		recipe.structure = report.structure.duplicate(true)
	packed = EmberVoxelPrefab.prepare_resource(source)
	report["elapsed_usec"] = Time.get_ticks_usec() - started
	error = "" if packed != null else "Не удалось собрать точный prefab-предпросмотр дерева."
	return packed != null


func commit(root: Node, parent: Node3D, undo: Object, position: Vector3) -> EmberVoxelProp:
	if Engine.is_editor_hint() and EditorInterface.get_edited_scene_root() != root:
		error = "Активная сцена изменилась. Откройте создание дерева заново."
		return null
	if source == null or packed == null or recipe == null or not is_instance_valid(root) or not is_instance_valid(parent):
		error = "Сцена или подготовленное дерево больше недоступны."
		return null
	var source_path := source_directory.path_join(source.model_id + ".tres")
	var prefab_path := prefab_directory.path_join(source.model_id + ".tscn")
	var saved := Store.install_prepared_asset(source, packed, source_path, prefab_path)
	if not bool(saved.get("ok", false)):
		error = str(saved.get("error", "Не удалось сохранить дерево."))
		return null
	var recipe_path_value := recipe_path(source.model_id, recipe_directory)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(recipe_directory))
	var recipe_error := ResourceSaver.save(recipe, recipe_path_value)
	if recipe_error != OK:
		error = "Геометрия сохранена, но рецепт не записан: %s" % error_string(recipe_error)
		return null
	var prop := EmberSceneAuthoring.make_model_instance(
		root, saved.packed as PackedScene, source.model_id, position
	)
	if prop == null:
		error = "Дерево сохранено в Объекты, но instance сцены создать не удалось."
		return null
	prop.configure_voxel_scale(source.normalized_density(), world_size)
	prop.scene_file_path = prefab_path
	prop.set_meta(EmberVoxelPrefab.SOURCE_SIGNATURE_META, saved.signature)
	if undo is EditorUndoRedoManager:
		undo.create_action("Создать большое voxel-дерево", UndoRedo.MERGE_DISABLE, root)
		undo.add_do_method(self, "_attach", root, parent, prop)
		undo.add_undo_method(self, "_detach", parent, prop)
	else:
		undo.create_action("Создать большое voxel-дерево")
		undo.add_do_method(_attach.bind(root, parent, prop))
		undo.add_undo_method(_detach.bind(parent, prop))
	undo.add_do_reference(prop)
	undo.add_do_reference(self)
	undo.commit_action()
	asset_changed.emit(source.model_id)
	return prop


## Group projection uses only explicit recipe metadata; no automatic grouping.
static func grouped_entries(entries: Array[Dictionary], directory := "res://content/editor/voxel_generators") -> Array[Dictionary]:
	var groups := {}
	var result: Array[Dictionary] = []
	for entry in entries:
		var id := str(entry.get("id", ""))
		var stored := load_recipe(id, directory)
		var family := id
		var title := str(entry.get("title", id))
		var name := "Основной"
		if stored != null and Generator.validation_errors(stored).is_empty():
			family = id if stored.family_id.is_empty() else str(stored.family_id)
			title = title if stored.family_title.is_empty() else str(stored.family_title)
			name = str(stored.variation_name)
		var member := entry.duplicate(true)
		member["variation_name"] = name
		member["family_id"] = family
		if not groups.has(family):
			var group := entry.duplicate(true)
			group["family_id"] = family
			group["title"] = title
			group["variations"] = []
			groups[family] = group
			result.append(group)
		groups[family].variations.append(member)
	for group in result:
		group.variations.sort_custom(func(a: Dictionary, b: Dictionary):
			if str(a.id) == str(group.family_id): return str(b.id) != str(a.id)
			if str(b.id) == str(group.family_id): return false
			return str(a.variation_name).naturalnocasecmp_to(str(b.variation_name)) < 0
		)
		var representative: Dictionary = group.variations[0]
		group["id"] = representative.id
		group["label"] = "%s%s\n%s" % ["" if group.ready else "◇ ", group.title,
			"%d вариаций" % group.variations.size() if group.variations.size() > 1 else representative.id]
		var names := PackedStringArray()
		for member in group.variations:
			names.append(str(member.variation_name) + " · " + str(member.id))
		group["tooltip"] = str(group.get("tooltip", group.title)) + "\nВариации: " + ", ".join(names)
	return result


static func variation_name_exists(family_id: String, name: String, exclude_id := "", directory := "res://content/editor/voxel_generators") -> bool:
	for file in DirAccess.get_files_at(directory):
		if file.get_extension() != "tres" or file.get_basename() == exclude_id:
			continue
		var stored := load_recipe(file.get_basename(), directory)
		if stored == null:
			continue
		var family := file.get_basename() if stored.family_id.is_empty() else str(stored.family_id)
		if family == family_id and str(stored.variation_name).strip_edges().nocasecmp_to(name.strip_edges()) == 0:
			return true
	return false


func update_variation(model_id: String, context: Dictionary) -> bool:
	error = ""
	if source == null or packed == null or recipe == null or not context.has("undo"):
		error = "Сначала соберите точный предпросмотр."
		return false
	var path := source_directory.path_join(model_id + ".tres")
	if bool(context.get("manual_dirty", false)):
		error = "Сначала сохраните или отмените ручную лепку. Она не перезаписана."
		return false
	if _update_model_id != model_id or _update_source_hash != FileAccess.get_sha256(path) or _update_recipe_hash != FileAccess.get_sha256(recipe_path(model_id, recipe_directory)):
		error = "Source или рецепт изменён после предпросмотра. Откройте вариацию заново."
		return false
	var old_source := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as EmberVoxelModelResource
	var old_recipe := load_recipe(model_id, recipe_directory)
	if old_source == null or old_recipe == null:
		error = "Исходная вариация больше недоступна."
		return false
	var expected := Generator.build(old_recipe, Color.WHITE, {}, old_source.display_name, model_id)
	if expected.has("error") or expected.geometry.to_definition().get("model") != old_source.to_definition().get("model"):
		error = "В исходнике есть ручные изменения или рецепт не совпадает. Сохраните новую вариацию; исходник не перезаписан."
		return false
	var scene: Node = context.root
	if not is_instance_valid(scene):
		error = "Сцена закрыта."
		return false
	var target: EmberVoxelProp = null
	var queue: Array[Node] = [scene]
	while not queue.is_empty():
		var node: Node = queue.pop_back()
		if node is EmberVoxelProp and node.model_id == model_id:
			target = node
			break
		queue.append_array(node.get_children())
	var temporary := false
	if target == null:
		var old_packed := EmberVoxelPrefab.prepare_resource(old_source)
		target = old_packed.instantiate() as EmberVoxelProp
		target.process_mode = Node.PROCESS_MODE_DISABLED
		scene.add_child(target)
		temporary = true
	var edit := preload("res://addons/ember_import/ember_voxel_object_session.gd").new()
	edit.source_directory = source_directory
	edit.prefab_directory = prefab_directory
	if not edit.open(target, scene, context.undo, true):
		error = edit.error
		if temporary: target.free()
		return false
	var prepared: Dictionary = edit.save(source, true)
	if temporary: target.free()
	if not bool(prepared.get("ok", false)):
		error = str(prepared.get("error", "Не удалось подготовить обновление."))
		return false
	var old_asset := {"source": old_source, "packed": EmberVoxelPrefab.prepare_resource(old_source), "path": path, "prefab": prefab_directory.path_join(model_id + ".tscn")}
	if not prepared.has("next"):
		prepared = {"next": old_source, "packed": old_asset.packed, "path": path,
			"prefab": old_asset.prefab, "new_states": [], "old_states": []}
	var new_asset := {"source": prepared.next, "packed": prepared.packed, "path": prepared.path, "prefab": prepared.prefab}
	if not _apply_variation_update(edit, prepared.new_states, new_asset, recipe, old_asset, old_recipe):
		return false
	var undo: Object = context.undo
	if undo is EditorUndoRedoManager:
		undo.create_action("Обновить вариацию «%s»" % recipe.variation_name, UndoRedo.MERGE_DISABLE, scene)
		undo.add_do_method(self, "_apply_variation_update", edit, prepared.new_states, new_asset, recipe, old_asset, old_recipe)
		undo.add_undo_method(self, "_apply_variation_update", edit, prepared.old_states, old_asset, old_recipe, new_asset, recipe)
	else:
		undo.create_action("Обновить вариацию «%s»" % recipe.variation_name)
		undo.add_do_method(_apply_variation_update.bind(edit, prepared.new_states, new_asset, recipe, old_asset, old_recipe))
		undo.add_undo_method(_apply_variation_update.bind(edit, prepared.old_states, old_asset, old_recipe, new_asset, recipe))
	undo.add_do_reference(self)
	undo.commit_action(false)
	return true


func _apply_variation_update(edit: RefCounted, states: Array, asset: Dictionary,
	next_recipe: Resource, rollback_asset: Dictionary, rollback_recipe: Resource) -> bool:
	var result := Store.install_prepared_asset(asset.source, asset.packed, asset.path, asset.prefab)
	if not bool(result.get("ok", false)):
		error = str(result.error)
		return false
	var recipe_path_value := recipe_path(asset.source.model_id, recipe_directory)
	var saved := ResourceSaver.save(next_recipe, recipe_path_value)
	if saved != OK:
		Store.install_prepared_asset(rollback_asset.source, rollback_asset.packed, rollback_asset.path, rollback_asset.prefab)
		ResourceSaver.save(rollback_recipe, recipe_path_value)
		error = "Рецепт не сохранён: " + error_string(saved)
		return false
	for state in states:
		state.signature = result.signature
	edit._apply(states, {})
	asset_changed.emit(asset.source.model_id)
	return true


func _attach(root: Node, parent: Node3D, prop: EmberVoxelProp) -> void:
	if not is_instance_valid(root) or not is_instance_valid(parent):
		return
	EmberSceneAuthoring.attach_model_instance(root, parent, prop)
	if Engine.is_editor_hint():
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(prop)
		EditorInterface.mark_scene_as_unsaved()
		preload("res://addons/ember_import/ember_editor_filesystem.gd").request()


func _detach(parent: Node3D, prop: EmberVoxelProp) -> void:
	if is_instance_valid(parent) and prop.get_parent() == parent:
		parent.remove_child(prop)
	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()
