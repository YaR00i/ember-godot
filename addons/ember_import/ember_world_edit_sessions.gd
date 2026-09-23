@tool
extends RefCounted
## Detached editor drafts shared by the 3D adapter and the existing Canvas.
## Canonical publication remains in ModelStore/ObjectSession and scene Save.
signal changed
const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const ObjectSession = preload("res://addons/ember_import/ember_voxel_object_session.gd")
const Store = preload("res://addons/ember_import/ember_voxel_model_store.gd")
const SurfaceProjection = preload("res://scripts/ember_voxel_surface_projection.gd")
const FIELDS := ["schema_version","model_id","display_name","tags","voxels_per_block","size_blocks","height_voxels","palette","voxels","emissive","shine","transparency","transmittance","surface_fill_levels","surface_fill_materials","surface_fill_palette","voxel_groups","voxel_part_ids","merge_parts","collision_voxels","material","physical","emissive_casts_light","emissive_light_range","emissive_light_shadows","emissive_light_soft_rings","emissive_light_soft_shadows","emissive_strength","emissive_suppress_host_shadow","emissive_torch_flicker","emissive_light_offset","emissive_lights","imported_from","imported_source_hash"]
const RECOVERY := "user://ember_world_drafts"
var entries: Dictionary = {}
var recovery_directory := RECOVERY
var undo: Object
var save_scene: Callable
var error := ""
var saving := false
var last_save_profile := {}
var pending_native_save := {}
var source_directory := EmberVoxelCatalog.NATIVE_DIR
var prefab_directory := EmberVoxelPrefab.PREFAB_DIR

func configure(history: Object, scene_save := Callable()) -> void:
	undo = history
	save_scene = scene_save

static func same_data(a: EmberVoxelModelResource, b: EmberVoxelModelResource) -> bool:
	if a == null or b == null: return false
	for field in FIELDS:
		if a.get(field) != b.get(field): return false
	return true

func _key(target: Node) -> int:
	return target.get_instance_id()

func _entry(target: Node, scene: Node, resource: EmberVoxelModelResource, path: String, object_session: RefCounted = null) -> Dictionary:
	var draft: EmberVoxelModelResource = object_session.draft if object_session != null else resource.duplicate_model()
	var next := {"target":weakref(target),"scene":weakref(scene),"resource":draft,"baseline":resource.duplicate_model(),"path":path,"hash":FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "","object_session":object_session,"origin":target.surface_origin if target is EmberMapLoader else Vector3.ZERO,"scene_path":scene.scene_file_path,"target_path":str(scene.get_path_to(target)),"source_resource":resource,"originals":[],"preview":null}
	entries[_key(target)] = next
	if object_session != null: next.source_resource = object_session._source
	next.on_changed = func(_indices): changed.emit()
	draft.geometry_changed.connect(next.on_changed)
	return next

func open_map(map: EmberMapLoader, scene: Node) -> Dictionary:
	error = ""
	if entries.has(_key(map)): return entries[_key(map)]
	var source := map.resolved_visual_surface()
	if source == null:
		error = "У карты ещё нет общей земли. Выделите место и нажмите «Создать землю»."
		return {}
	var next := _entry(map,scene,source,Model.surface_save_path(source,source.resource_path))
	preview(next)
	return next

func create_ground(map: EmberMapLoader, scene: Node) -> Dictionary:
	if entries.has(_key(map)) or map.resolved_visual_surface() != null:
		return open_map(map,scene)
	var resource := Model.make_native_world_surface(map.map_id,map.authored_size_blocks)
	if resource == null:
		error = "Размер карты неизвестен или превышает безопасный dense-бюджет32MiB. Земля не создана."
		return {}
	var path := EmberVoxelModelResource.world_surface_path(map.map_id)
	if FileAccess.file_exists(path):
		# An unbound/orphan source is still author data, not an empty slot.
		resource.model_id += "_"+str(Time.get_ticks_usec())
		path = path.get_base_dir().path_join(resource.model_id+".tres")
	var next := _entry(map,scene,resource,path)
	next.origin = Vector3(0,-32,0)
	preview(next)
	changed.emit()
	return next

func open_object(prop: EmberVoxelProp, scene: Node) -> Dictionary:
	error = ""
	if entries.has(_key(prop)): return entries[_key(prop)]
	var edit := ObjectSession.new()
	edit.source_directory = source_directory
	edit.prefab_directory = prefab_directory
	if not edit.open(prop,scene,undo):
		error = edit.error
		return {}
	var next := _entry(prop,scene,edit.draft,edit._source_path,edit)
	preview(next)
	return next

func dirty(entry: Dictionary) -> bool:
	return not same_data(entry.resource,entry.baseline)

func dirty_count(scene: Node = null) -> int:
	var count := 0
	for entry in entries.values():
		if (scene == null or entry.scene.get_ref() == scene) and dirty(entry): count += 1
	return count

func frame(entry: Dictionary) -> Transform3D:
	var target: Node3D = entry.target.get_ref()
	if not is_instance_valid(target): return Transform3D.IDENTITY
	if target is EmberMapLoader:
		return target.global_transform * Transform3D(Basis.IDENTITY * target.imported_tile_size,entry.origin)
	var context: Dictionary = entry.object_session.context_projection(entry.resource)
	return context.get("frame",Transform3D.IDENTITY)

func preview(entry: Dictionary) -> void:
	var target: Node3D = entry.target.get_ref()
	if not is_instance_valid(target) or not target.is_inside_tree(): return
	if target is EmberMapLoader:
		target.set_editor_surface_preview(entry.resource,entry.origin)
		return
	if not is_instance_valid(entry.preview):
		var projection := SurfaceProjection.new()
		projection.name = "EmberWorldObjectDraft"
		target.add_child(projection,false,Node.INTERNAL_MODE_BACK)
		projection.configure(entry.resource,1.0,Vector2i(entry.resource.size_blocks.x,entry.resource.size_blocks.z),null)
		entry.preview = projection
		for child in target.get_children():
			if child is MeshInstance3D:
				entry.originals.append({"node":weakref(child),"visible":child.visible})
	entry.preview.global_transform = frame(entry)
	_show_originals(entry,false)

func _show_originals(entry: Dictionary, restore: bool) -> void:
	for original in entry.originals:
		var node: Node3D = original.node.get_ref()
		if is_instance_valid(node): RenderingServer.instance_set_visible(node.get_instance(),bool(original.visible) and node.is_visible_in_tree() if restore else false)

func set_water_hidden(hidden: bool) -> void:
	for entry in entries.values():
		var target: Node = entry.target.get_ref()
		if not is_instance_valid(target): continue
		var projection: Node = target._visual_surface_projection if target is EmberMapLoader else entry.preview if is_instance_valid(entry.preview) else null
		if is_instance_valid(projection): projection.set_editor_water_hidden(hidden)

func discard(scene: Node = null) -> void:
	for entry in entries.values():
		if scene != null and entry.scene.get_ref() != scene: continue
		for field in FIELDS: entry.resource.set(field,EmberVoxelModelResource.copy_authoring_value(entry.baseline.get(field)))
		entry.resource.notify_geometry_changed(PackedInt32Array())
		preview(entry)
	changed.emit()

func save_all(scene: Node, defer_scene_save := false) -> bool:
	if saving: return false
	var profile_start := Time.get_ticks_usec()
	last_save_profile = {}
	saving = true
	error = ""
	var prepared: Array[Dictionary] = []
	var scene_path: String = scene.scene_file_path if is_instance_valid(scene) else ""
	var scene_snapshot := Store._snapshot_file(scene_path) if FileAccess.file_exists(scene_path) else {}
	if scene_path.is_empty(): error = "Сначала сохраните новую сцену через «Сохранить как…». Черновики остались."
	elif not defer_scene_save and not save_scene.is_valid(): error = "Сохранение сцены не настроено. Черновики не опубликованы."
	for entry in entries.values():
		if not error.is_empty(): break
		if entry.scene.get_ref() != scene or not dirty(entry): continue
		var target: Node = entry.target.get_ref()
		if not is_instance_valid(target) or not is_instance_valid(scene) or not scene.is_ancestor_of(target):
			error = "Цель удалена или сцена закрыта. Черновики не потеряны."
			break
		if not same_data(entry.source_resource,entry.baseline):
			error = "Исходный Resource изменён вне редактора мира. Черновик не опубликован."
			break
		var errors: Array[String] = entry.resource.validation_errors()
		if not errors.is_empty():
			error = errors[0]
			break
		if (FileAccess.get_sha256(entry.path) if FileAccess.file_exists(entry.path) else "") != entry.hash:
			error = "Файл изменён вне редактора мира. Чужие правки не перезаписаны: " + entry.path
			break
		_show_originals(entry,true)
		if entry.object_session != null:
			var plan: Dictionary = entry.object_session.save(entry.resource,true)
			if not plan.get("ok",false):
				error = str(plan.get("error","Не удалось подготовить объект"))
				break
			prepared.append({"entry":entry,"plan":plan,"old_source":Store._snapshot_file(plan.path) if FileAccess.file_exists(plan.path) else {},"old_prefab":Store._snapshot_file(plan.prefab) if FileAccess.file_exists(plan.prefab) else {},"published":false})
		else:
			prepared.append({"entry":entry,"old_source":Store._snapshot_file(entry.path) if FileAccess.file_exists(entry.path) else {},"old_map_source":target.visual_surface,"old_origin":target.surface_origin,"old_physical":target.use_visual_surface_physics,"published":false})
	last_save_profile.preflight_usec = Time.get_ticks_usec()-profile_start
	var publication_start := Time.get_ticks_usec()
	if error.is_empty():
		for item in prepared:
			var entry: Dictionary = item.entry
			var result: Dictionary = Store.install_prepared_asset(item.plan.next,item.plan.packed,item.plan.path,item.plan.prefab,true) if item.has("plan") else Store.install_surface_resource(entry.resource,entry.path)
			if not result.get("ok",false):
				error = str(result.get("error","Публикация не завершена"))
				break
			item.published = true
			if item.has("plan"):
				for state in item.plan.new_states: state.signature = result.signature
				entry.object_session._apply(item.plan.new_states,{})
			else:
				var map: EmberMapLoader = entry.target.get_ref()
				map.surface_origin = entry.origin
				map.visual_surface = ResourceLoader.load(entry.path)
				map.use_visual_surface_physics = true
	last_save_profile.publication_usec = Time.get_ticks_usec()-publication_start
	var scene_start := Time.get_ticks_usec()
	if defer_scene_save and error.is_empty():
		var packed := PackedScene.new()
		var pack_error := packed.pack(scene)
		if pack_error == OK:
			pending_native_save = {"prepared":prepared,"snapshot":scene_snapshot,"path":scene_path,"profile_start":profile_start,"scene_start":scene_start,"packed":packed,"root":weakref(scene)}
			return true
		error = "Не удалось подготовить сцену: " + error_string(pack_error)
	if error.is_empty() and save_scene.is_valid():
		var result: int = save_scene.call()
		if result != OK: error = "Сцена не сохранена: " + error_string(result)
	last_save_profile.scene_usec = Time.get_ticks_usec()-scene_start
	return _complete_save(prepared,scene_snapshot,scene_path,profile_start)

func finish_native_save(result: int) -> bool:
	if pending_native_save.is_empty(): return false
	var pending := pending_native_save
	pending_native_save = {}
	last_save_profile.scene_usec = Time.get_ticks_usec()-int(pending.scene_start)
	if result != OK: error = "Сцена не сохранена: " + error_string(result)
	return _complete_save(pending.prepared,pending.snapshot,pending.path,int(pending.profile_start))

func _complete_save(prepared: Array[Dictionary], scene_snapshot: Dictionary, scene_path: String, profile_start: int) -> bool:
	if not error.is_empty():
		var rollback_errors := PackedStringArray()
		for item in prepared:
			if not item.published: continue
			var entry: Dictionary = item.entry
			if item.has("plan"):
				_restore_checked(item.old_source,item.plan.path,rollback_errors)
				_restore_checked(item.old_prefab,item.plan.prefab,rollback_errors)
				entry.object_session._apply(item.plan.old_states,{})
			else:
				_restore_checked(item.old_source,entry.path,rollback_errors)
				var map: EmberMapLoader = entry.target.get_ref()
				if is_instance_valid(map):
					map.visual_surface = item.old_map_source
					map.surface_origin = item.old_origin
					map.use_visual_surface_physics = item.old_physical
		if not scene_snapshot.is_empty(): _restore_checked(scene_snapshot,scene_path,rollback_errors)
		if not rollback_errors.is_empty(): error += " Откат файлов не завершён: " + "; ".join(rollback_errors) + ". Резервные снимки сохранены рядом с аварийными черновиками."
		write_recovery()
	else:
		var paths := PackedStringArray()
		for item in prepared:
			var entry: Dictionary = item.entry
			if item.has("plan"):
				entry.resource.model_id = item.plan.next.model_id
				entry.path = item.plan.path
				entry.object_session.accept_prepared_save(item.plan.next,item.plan.path)
				paths.append(item.plan.prefab)
			entry.baseline = entry.resource.duplicate_model()
			entry.hash = FileAccess.get_sha256(entry.path)
			entry.source_resource = ResourceLoader.load(entry.path)
			paths.append(entry.path)
		if not paths.is_empty(): Store.asset_events.assets_published.emit(paths)
	for entry in entries.values(): preview(entry)
	last_save_profile.total_usec = Time.get_ticks_usec()-profile_start
	saving = false
	changed.emit()
	return error.is_empty()

func _restore_checked(snapshot: Dictionary, path: String, errors: PackedStringArray) -> void:
	var result: int = Store.restore_surface_snapshot(snapshot,path)
	if result == OK: return
	errors.append(path + ": " + error_string(result))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(recovery_directory))
	var backup := ConfigFile.new()
	backup.set_value("rollback","target",path)
	backup.set_value("rollback","snapshot",snapshot)
	backup.save(recovery_directory.path_join("rollback_"+path.sha256_text()+".cfg"))

func write_recovery() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(recovery_directory))
	var manifest := ConfigFile.new()
	for key in entries:
		var entry: Dictionary = entries[key]
		var scene: Node = entry.scene.get_ref()
		var target: Node = entry.target.get_ref()
		if not dirty(entry): continue
		var path := recovery_directory.path_join("draft_%s.tres" % key)
		if ResourceSaver.save(entry.resource,path) == OK:
			manifest.set_value(str(key),"draft",path)
			manifest.set_value(str(key),"scene",scene.scene_file_path if is_instance_valid(scene) else entry.scene_path)
			manifest.set_value(str(key),"target",str(scene.get_path_to(target)) if is_instance_valid(scene) and is_instance_valid(target) else entry.target_path)
			manifest.set_value(str(key),"source",entry.path)
			manifest.set_value(str(key),"hash",entry.hash)
			manifest.set_value(str(key),"origin",entry.origin)
	manifest.save(recovery_directory.path_join("manifest.cfg"))

func restore_recovery(scene: Node) -> int:
	error = ""
	var manifest := ConfigFile.new()
	if manifest.load(recovery_directory.path_join("manifest.cfg")) != OK: return 0
	var restored := 0
	for section in manifest.get_sections():
		if manifest.get_value(section,"scene","") != scene.scene_file_path: continue
		var path: String = manifest.get_value(section,"source","")
		if (FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "") != manifest.get_value(section,"hash",""):
			error = "Recovery не применён: исходник изменён. Копия черновика сохранена в user://ember_world_drafts."
			continue
		var target := scene.get_node_or_null(NodePath(manifest.get_value(section,"target","")))
		if target != null and entries.has(_key(target)) and dirty(entries[_key(target)]):
			error = "Восстановление не заменило текущий несохранённый черновик. Сначала сохраните или отмените его."
			continue
		var draft := ResourceLoader.load(manifest.get_value(section,"draft",""),"",ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource
		if draft == null or not draft.validation_errors().is_empty(): continue
		var entry := open_map(target,scene) if target is EmberMapLoader else open_object(target,scene) if target is EmberVoxelProp else {}
		var new_ground := entry.is_empty() and target is EmberMapLoader
		if new_ground: entry = create_ground(target,scene)
		if entry.is_empty(): continue
		if not new_ground and entry.path != path:
			error = "Recovery не применён: цель связана с другим исходником. Копия черновика сохранена."
			continue
		entry.path = path
		entry.hash = manifest.get_value(section,"hash","")
		for field in FIELDS: entry.resource.set(field,EmberVoxelModelResource.copy_authoring_value(draft.get(field)))
		entry.origin = manifest.get_value(section,"origin",entry.origin)
		entry.resource.notify_geometry_changed(PackedInt32Array())
		preview(entry)
		restored += 1
	return restored

func release() -> void:
	if not pending_native_save.is_empty(): finish_native_save(ERR_CANT_CREATE)
	write_recovery()
	for entry in entries.values():
		if entry.resource.geometry_changed.is_connected(entry.on_changed): entry.resource.geometry_changed.disconnect(entry.on_changed)
		_show_originals(entry,true)
		var target: Node = entry.target.get_ref()
		if target is EmberMapLoader: target.set_editor_surface_preview(null)
		if is_instance_valid(entry.preview): entry.preview.free()
	entries.clear()
