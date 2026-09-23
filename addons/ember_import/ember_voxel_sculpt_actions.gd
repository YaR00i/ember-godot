@tool
class_name EmberVoxelSculptActions
extends RefCounted
## Common Godot/headless Undo owner for one sculpt stroke.

signal source_changed(indices: PackedInt32Array)

var _undo_redo: Object
var active_part := 0
var history_context: Object

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
	var changed_indices: PackedInt32Array = plan.get("changed_indices", PackedInt32Array())
	_add_do_method_with_args(self, &"_notify_source_changed", [resource, changed_indices])
	_add_undo_method_with_args(self, &"_notify_source_changed", [resource, changed_indices])
	_commit_action()
	return true


func configure(undo_redo: Object) -> void:
	_undo_redo = undo_redo


func record_editor_state(
	context: Object,
	target: Object,
	before: Dictionary,
	after: Dictionary,
	title: String,
) -> bool:
	## Transient editor state shares the canonical chronological Undo history,
	## but does not write into EmberVoxelModelResource or emit source_changed.
	if _undo_redo == null or context == null or target == null or before == after:
		return false
	_create_action(title, context)
	_add_do_method_with_state(target, &"apply_history_state", after.duplicate(true))
	_add_undo_method_with_state(target, &"apply_history_state", before.duplicate(true))
	_commit_action(false)
	return true


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
	_record_collision(resource, before, after, PackedInt32Array(changes.keys()))
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
	if is_instance_valid(history_context):
		var channels := {"voxels":{},"__sizes":{}}
		for index in indices: channels.voxels[index] = Vector2i(before[index],after[index])
		if not resource.voxel_part_ids.is_empty():
			var owners := preload("res://addons/ember_import/ember_voxel_parts.gd").stroke(resource,before,after,active_part,indices)
			channels.voxel_part_ids = {}
			for index in indices:
				if resource.voxel_part_ids[index] != owners[index]: channels.voxel_part_ids[index] = Vector2i(resource.voxel_part_ids[index],owners[index])
			resource.voxel_part_ids = owners
		if not resource.collision_voxels.is_empty():
			var collision := resource.collision_voxels.duplicate()
			channels.collision_voxels = {}
			for index in indices:
				var next := 0 if after[index] == 0 else 1 if before[index] == 0 else int(collision[index])
				if collision[index] != next: channels.collision_voxels[index] = Vector2i(collision[index],next)
				collision[index] = next
			resource.collision_voxels = collision
		return commit_applied_delta(resource,channels,indices,"Мир / Canvas · мазок")
	_create_action("Voxel Surface · непрерывный мазок (%d voxels)" % indices.size(), resource)
	_record_parts(resource,before,after,indices,true)
	_record_collision(resource, before, after, indices, true)
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
	if is_instance_valid(history_context):
		var channels := {"transparency":{},"__sizes":{"transparency":Vector2i(before.size(),after.size())}}
		for index in indices: channels.transparency[index] = Vector2i(before[index] if index < before.size() else 0,after[index])
		return commit_applied_delta(resource,channels,indices,"Мир / Canvas · материал")
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
		&"transparency", &"transmittance", &"collision_voxels",
		&"surface_fill_levels", &"surface_fill_materials", &"surface_fill_palette",
		&"voxel_groups", &"merge_parts", &"voxel_part_ids",
	]:
		_add_do_property(resource, property_name, fresh.get(property_name))
		_add_undo_property(resource, property_name, resource.get(property_name))
	_add_do_method_with_args(self, &"_notify_source_changed", [resource, PackedInt32Array()])
	_add_undo_method_with_args(self, &"_notify_source_changed", [resource, PackedInt32Array()])
	_commit_action()
	return true


func _record_collision(
	resource: EmberVoxelModelResource,
	before_voxels: PackedByteArray,
	after_voxels: PackedByteArray,
	indices: PackedInt32Array,
	applied := false,
) -> void:
	if resource.collision_voxels.is_empty():
		return
	var before := resource.collision_voxels.duplicate()
	var after := before.duplicate()
	for index in indices:
		if index < 0 or index >= after.size():
			continue
		if after_voxels[index] == 0:
			after[index] = 0
		elif before_voxels[index] == 0:
			# Hand-sculpted additions are physical by default. Existing generated
			# leaves keep their non-physical value when merely repainted.
			after[index] = 1
	if before == after:
		return
	_add_do_property(resource, &"collision_voxels", after)
	_add_undo_property(resource, &"collision_voxels", before)
	if applied:
		resource.collision_voxels = after


func _create_action(title: String, context: Object) -> void:
	if _undo_redo is EditorUndoRedoManager:
		(_undo_redo as EditorUndoRedoManager).create_action(title, UndoRedo.MERGE_DISABLE, history_context if is_instance_valid(history_context) else context)
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
		Callable(_undo_redo,&"add_do_method").callv([object,method]+args)
	else:
		(_undo_redo as UndoRedo).add_do_method(Callable(object, method).bindv(args))


func _add_undo_method(object: Object, method: StringName) -> void:
	if _undo_redo is EditorUndoRedoManager:
		(_undo_redo as EditorUndoRedoManager).add_undo_method(object, method)
	else:
		(_undo_redo as UndoRedo).add_undo_method(Callable(object, method))


func _add_undo_method_with_args(object: Object, method: StringName, args: Array) -> void:
	if _undo_redo is EditorUndoRedoManager:
		Callable(_undo_redo,&"add_undo_method").callv([object,method]+args)
	else:
		(_undo_redo as UndoRedo).add_undo_method(Callable(object, method).bindv(args))


func _add_do_method_with_state(object: Object, method: StringName, state: Dictionary) -> void:
	if _undo_redo is EditorUndoRedoManager:
		(_undo_redo as EditorUndoRedoManager).add_do_method(object, method, state)
	else:
		(_undo_redo as UndoRedo).add_do_method(Callable(object, method).bind(state))


func _add_undo_method_with_state(object: Object, method: StringName, state: Dictionary) -> void:
	if _undo_redo is EditorUndoRedoManager:
		(_undo_redo as EditorUndoRedoManager).add_undo_method(object, method, state)
	else:
		(_undo_redo as UndoRedo).add_undo_method(Callable(object, method).bind(state))


func _notify_source_changed(
	resource: EmberVoxelModelResource,
	indices: PackedInt32Array,
) -> void:
	resource.notify_geometry_changed(indices)
	source_changed.emit(indices)

func commit_applied_delta(resource: EmberVoxelModelResource, channels: Dictionary, indices: PackedInt32Array, title := "Мир · мазок") -> bool:
	if _undo_redo == null or channels.is_empty():
		return false
	channels = pack_delta(resource,channels)
	_create_action(title, resource)
	_add_do_method_with_args(self, &"_apply_delta", [resource, channels, true, indices])
	_add_undo_method_with_args(self, &"_apply_delta", [resource, channels, false, indices])
	_commit_action(false)
	return true

static func pack_delta(resource: EmberVoxelModelResource, channels: Dictionary) -> Dictionary:
	var packed := {"__sizes":channels.get("__sizes",{}).duplicate(true)}
	for channel in channels:
		if channel == "__sizes": continue
		var before: Variant = PackedByteArray() if resource.get(channel) is PackedByteArray else PackedInt32Array()
		var after: Variant = PackedByteArray() if resource.get(channel) is PackedByteArray else PackedInt32Array()
		var indices := PackedInt32Array()
		for index in channels[channel]:
			var pair: Vector2i = channels[channel][index]
			indices.append(index)
			before.append(pair.x)
			after.append(pair.y)
		packed[channel] = {"indices":indices,"before":before,"after":after}
	return packed

func _apply_delta(resource: EmberVoxelModelResource, channels: Dictionary, forward: bool, indices: PackedInt32Array) -> void:
	for channel in channels:
		if channel == "__sizes": continue
		var values: Variant = resource.get(channel)
		var sizes: Vector2i = channels.get("__sizes",{}).get(channel,Vector2i(values.size(),values.size()))
		if values.size() < sizes.y:
			values.resize(sizes.y)
			values.fill(0)
		if channels[channel].has("indices"):
			var indices_data: PackedInt32Array = channels[channel].indices
			var data: Variant = channels[channel].after if forward else channels[channel].before
			for i in indices_data.size(): values[indices_data[i]] = data[i]
		else:
			for raw_index in channels[channel]:
				var pair: Vector2i = channels[channel][raw_index]
				values[int(raw_index)] = pair.y if forward else pair.x
		if not forward: values.resize(sizes.x)
		resource.set(channel, values)
	_notify_source_changed(resource, indices)


func _commit_action(execute := true) -> void:
	if _undo_redo is EditorUndoRedoManager:
		(_undo_redo as EditorUndoRedoManager).commit_action(execute)
	else:
		(_undo_redo as UndoRedo).commit_action(execute)
