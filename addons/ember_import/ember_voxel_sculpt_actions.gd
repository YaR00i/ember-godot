@tool
class_name EmberVoxelSculptActions
extends RefCounted
## Common Godot/headless Undo owner for one sculpt stroke.

signal source_changed(indices: PackedInt32Array)

var _undo_redo: Object
var active_part := 0

func _record_parts(resource: EmberVoxelModelResource, before: PackedByteArray, after: PackedByteArray, indices: PackedInt32Array, applied := false) -> void:
	if resource.voxel_part_ids.is_empty():
		return
	var owners := preload("res://addons/ember_import/ember_voxel_parts.gd").stroke(resource,before,after,active_part,indices)
	_add_undo_property(resource, &"voxel_part_ids", resource.voxel_part_ids.duplicate())
	_add_do_property(resource, &"voxel_part_ids", owners)
	if applied:
		resource.voxel_part_ids = owners

func apply_fragment(resource: EmberVoxelModelResource, plan: Dictionary) -> bool:
	if _undo_redo == null or plan.has("error") or not plan.has("properties"):
		return false
	for key in plan.before:
		if resource.get(key) != plan.before[key]:
			return false
	_create_action("Voxel · " + str(plan.label), resource)
	for key in plan.properties:
		_add_do_property(resource, key, plan.properties[key])
		_add_undo_property(resource, key, plan.before[key])
	_add_do_method_with_args(self, &"_notify_source_changed", [resource, PackedInt32Array()])
	_add_undo_method_with_args(self, &"_notify_source_changed", [resource, PackedInt32Array()])
	_commit_action()
	return true


func configure(undo_redo: Object) -> void:
	_undo_redo = undo_redo


func grow_canvas(resource: EmberVoxelModelResource, size: Vector3i) -> Dictionary:
	var result := preload("res://addons/ember_import/ember_voxel_canvas_growth.gd").plan(resource, size)
	if result.has("error"):
		return result
	if _undo_redo == null:
		return {"error": "История Undo недоступна"}
	_create_action("Voxel · расширить холст", resource)
	for key in result.properties:
		_add_do_property(resource, key, result.properties[key])
		_add_undo_property(resource, key, resource.get(key))
	_add_do_method_with_args(self, &"_notify_source_changed", [resource, PackedInt32Array()])
	_add_undo_method_with_args(self, &"_notify_source_changed", [resource, PackedInt32Array()])
	_commit_action()
	return result


func apply_palette(resource: EmberVoxelModelResource, operation: Dictionary) -> Dictionary:
	if _undo_redo == null:
		return {"error": "История Undo недоступна"}
	var result := preload("res://addons/ember_import/ember_voxel_palette_model.gd").plan(resource, operation)
	if result.has("error"):
		return result
	var properties: Dictionary = result["properties"]
	var changed := false
	for property_name in properties:
		changed = changed or resource.get(property_name) != properties[property_name]
	if not changed:
		return {"error": "Цвет уже имеет эти значения"}
	_create_action("Voxel Surface · " + str(result["label"]), resource)
	for property_name in properties:
		_add_do_property(resource, property_name, properties[property_name])
		_add_undo_property(resource, property_name, resource.get(property_name))
	_add_do_method_with_args(self, &"_notify_source_changed", [resource, PackedInt32Array()])
	_add_undo_method_with_args(self, &"_notify_source_changed", [resource, PackedInt32Array()])
	_commit_action()
	return result


func apply_groups(resource: EmberVoxelModelResource, operation: Dictionary) -> Dictionary:
	if resource == null or _undo_redo == null:
		return {"error": "История Undo недоступна"}
	var result := preload("res://addons/ember_import/ember_voxel_groups.gd").apply(
		resource.voxel_groups, operation, resource.voxels.size()
	)
	if result.has("error"):
		return result
	_create_action("Voxel Surface · " + str(result["label"]), resource)
	_add_do_property(resource, &"voxel_groups", result["groups"])
	_add_undo_property(resource, &"voxel_groups", resource.voxel_groups.duplicate(true))
	_add_do_property(resource, &"schema_version", EmberVoxelModelResource.SCHEMA_VERSION)
	_add_undo_property(resource, &"schema_version", resource.schema_version)
	_add_do_method_with_args(self, &"_notify_source_changed", [resource, PackedInt32Array()])
	_add_undo_method_with_args(self, &"_notify_source_changed", [resource, PackedInt32Array()])
	_commit_action()
	return result


func apply_stroke(resource: EmberVoxelModelResource, changes: Dictionary) -> bool:
	if resource == null or _undo_redo == null or changes.is_empty():
		return false
	var before := resource.voxels.duplicate()
	var after := EmberVoxelSculptModel.values_with_changes(before, changes, true)
	if before == after:
		return false
	_create_action("Voxel Surface · мазок (%d voxels)" % changes.size(), resource)
	_record_parts(resource,before,after,PackedInt32Array(changes.keys()))
	_add_do_property(resource, &"voxels", after)
	_add_undo_property(resource, &"voxels", before)
	var indices := PackedInt32Array()
	for raw_index in changes:
		indices.append(int(raw_index))
	_add_do_method_with_args(self, &"_notify_source_changed", [resource, indices])
	_add_undo_method_with_args(self, &"_notify_source_changed", [resource, indices])
	_commit_action()
	return true


func commit_applied_stroke(
	resource: EmberVoxelModelResource,
	before: PackedByteArray,
	after: PackedByteArray,
	indices: PackedInt32Array,
) -> bool:
	if resource == null or _undo_redo == null or before == after:
		return false
	_create_action("Voxel Surface · непрерывный мазок (%d voxels)" % indices.size(), resource)
	_record_parts(resource,before,after,indices,true)
	_add_do_property(resource, &"voxels", after)
	_add_undo_property(resource, &"voxels", before)
	_add_do_method_with_args(self, &"_notify_source_changed", [resource, indices])
	_add_undo_method_with_args(self, &"_notify_source_changed", [resource, indices])
	# The editor already shows `after` while the pointer is held. Register the
	# gesture without applying the do-state a second time on pointer-up.
	_commit_action(false)
	return true


func commit_applied_transparency_stroke(
	resource: EmberVoxelModelResource,
	before: PackedByteArray,
	after: PackedByteArray,
	indices: PackedInt32Array,
) -> bool:
	if resource == null or _undo_redo == null or before == after:
		return false
	_create_action("Voxel Surface · материал (%d voxels)" % indices.size(), resource)
	_add_do_property(resource, &"transparency", after)
	_add_undo_property(resource, &"transparency", before)
	_add_do_method_with_args(self, &"_notify_source_changed", [resource, indices])
	_add_undo_method_with_args(self, &"_notify_source_changed", [resource, indices])
	# The live preview already owns `after`; only register this gesture in history.
	_commit_action(false)
	return true


func apply_surface_fill(
	resource: EmberVoxelModelResource,
	after_levels: PackedInt32Array,
	after_materials: PackedByteArray,
	after_palette: PackedByteArray,
	indices: PackedInt32Array,
) -> bool:
	if resource == null or _undo_redo == null or indices.is_empty():
		return false
	var before_levels := resource.surface_fill_levels.duplicate()
	var before_materials := resource.surface_fill_materials.duplicate()
	var before_palette := resource.surface_fill_palette.duplicate()
	if (
		before_levels == after_levels
		and before_materials == after_materials
		and before_palette == after_palette
	):
		return false
	var before_schema := resource.schema_version
	_create_action("Voxel Surface · заливка уровня (%d columns)" % indices.size(), resource)
	_add_do_property(resource, &"surface_fill_levels", after_levels)
	_add_undo_property(resource, &"surface_fill_levels", before_levels)
	_add_do_property(resource, &"surface_fill_materials", after_materials)
	_add_undo_property(resource, &"surface_fill_materials", before_materials)
	_add_do_property(resource, &"surface_fill_palette", after_palette)
	_add_undo_property(resource, &"surface_fill_palette", before_palette)
	_add_do_property(resource, &"schema_version", EmberVoxelModelResource.SCHEMA_VERSION)
	_add_undo_property(resource, &"schema_version", before_schema)
	_add_do_method_with_args(self, &"_notify_source_changed", [resource, indices])
	_add_undo_method_with_args(self, &"_notify_source_changed", [resource, indices])
	_commit_action()
	return true


func reset_pilot(resource: EmberVoxelModelResource) -> bool:
	if resource == null or _undo_redo == null:
		return false
	var fresh := EmberVoxelSculptModel.make_pilot()
	if (
		resource.voxels == fresh.voxels
		and resource.palette == fresh.palette
		and resource.material == fresh.material
		and resource.emissive == fresh.emissive
		and resource.shine == fresh.shine
		and resource.transparency == fresh.transparency
		and resource.transmittance == fresh.transmittance
		and resource.surface_fill_levels == fresh.surface_fill_levels
		and resource.surface_fill_materials == fresh.surface_fill_materials
		and resource.surface_fill_palette == fresh.surface_fill_palette
		and resource.voxel_groups == fresh.voxel_groups
	):
		return false
	_create_action("Voxel Surface · сбросить пилот", resource)
	for property_name in [
		&"palette", &"voxels", &"material", &"emissive", &"shine",
		&"transparency", &"transmittance",
		&"surface_fill_levels", &"surface_fill_materials", &"surface_fill_palette",
		&"voxel_groups", &"merge_parts", &"voxel_part_ids",
	]:
		_add_do_property(resource, property_name, fresh.get(property_name))
		_add_undo_property(resource, property_name, resource.get(property_name))
	_add_do_method_with_args(self, &"_notify_source_changed", [resource, PackedInt32Array()])
	_add_undo_method_with_args(self, &"_notify_source_changed", [resource, PackedInt32Array()])
	_commit_action()
	return true


func _create_action(title: String, context: Object) -> void:
	if _undo_redo is EditorUndoRedoManager:
		(_undo_redo as EditorUndoRedoManager).create_action(title, UndoRedo.MERGE_DISABLE, context)
	else:
		(_undo_redo as UndoRedo).create_action(title, UndoRedo.MERGE_DISABLE)


func _add_do_property(object: Object, property_name: StringName, value: Variant) -> void:
	if _undo_redo is EditorUndoRedoManager:
		(_undo_redo as EditorUndoRedoManager).add_do_property(object, property_name, value)
	else:
		(_undo_redo as UndoRedo).add_do_property(object, property_name, value)


func _add_undo_property(object: Object, property_name: StringName, value: Variant) -> void:
	if _undo_redo is EditorUndoRedoManager:
		(_undo_redo as EditorUndoRedoManager).add_undo_property(object, property_name, value)
	else:
		(_undo_redo as UndoRedo).add_undo_property(object, property_name, value)


func _add_do_method(object: Object, method: StringName) -> void:
	if _undo_redo is EditorUndoRedoManager:
		(_undo_redo as EditorUndoRedoManager).add_do_method(object, method)
	else:
		(_undo_redo as UndoRedo).add_do_method(Callable(object, method))


func _add_do_method_with_args(object: Object, method: StringName, args: Array) -> void:
	if _undo_redo is EditorUndoRedoManager:
		(_undo_redo as EditorUndoRedoManager).add_do_method(object, method, args[0], args[1])
	else:
		(_undo_redo as UndoRedo).add_do_method(Callable(object, method).bindv(args))


func _add_undo_method(object: Object, method: StringName) -> void:
	if _undo_redo is EditorUndoRedoManager:
		(_undo_redo as EditorUndoRedoManager).add_undo_method(object, method)
	else:
		(_undo_redo as UndoRedo).add_undo_method(Callable(object, method))


func _add_undo_method_with_args(object: Object, method: StringName, args: Array) -> void:
	if _undo_redo is EditorUndoRedoManager:
		(_undo_redo as EditorUndoRedoManager).add_undo_method(object, method, args[0], args[1])
	else:
		(_undo_redo as UndoRedo).add_undo_method(Callable(object, method).bindv(args))


func _notify_source_changed(
	resource: EmberVoxelModelResource,
	indices: PackedInt32Array,
) -> void:
	resource.emit_changed()
	source_changed.emit(indices)


func _commit_action(execute := true) -> void:
	if _undo_redo is EditorUndoRedoManager:
		(_undo_redo as EditorUndoRedoManager).commit_action(execute)
	else:
		(_undo_redo as UndoRedo).commit_action(execute)
