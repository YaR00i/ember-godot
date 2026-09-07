@tool
class_name EmberBattlefieldEditorActions
extends RefCounted
## Single Undo/Redo mutation owner for the Battlefield Inspector paint palette.

const Palette := preload("res://addons/ember_import/ember_battlefield_editor_palette.gd")

var _undo_redo: Object


func configure(undo_redo: Object) -> void:
	_undo_redo = undo_redo


func paint_cell(
	field: EmberBattlefieldResource,
	cell: Vector2i,
	tool: int,
	group_id := "",
) -> bool:
	return paint_cells(field, [cell], tool, group_id)


func paint_cells(
	field: EmberBattlefieldResource,
	cells: Array[Vector2i],
	tool: int,
	group_id := "",
) -> bool:
	if field == null or _undo_redo == null:
		return false
	var before := field.authoring_snapshot()
	var after := field.edited_cells_snapshot(cells, tool, group_id)
	if after.is_empty() or after == before:
		return false
	var target_label := (
		_cell_label(cells[0])
		if cells.size() == 1
		else "%d клеток" % cells.size()
	)
	_create_action("Поле боя · %s · %s" % [_tool_label(tool), target_label], field)
	for property_name in [
		"terrain_kinds", "elevations", "blocked", "groups", "focus_cell",
		"party_deployment_cells", "enemy_deployment_cells",
	]:
		_add_do_property(field, property_name, after[property_name])
		_add_undo_property(field, property_name, before[property_name])
	_add_do_method(field, "notify_authoring_changed")
	_add_undo_method(field, "notify_authoring_changed")
	_commit_action()
	return true


func resize_field(
	field: EmberBattlefieldResource,
	new_width: int,
	new_height: int,
	anchor: int,
) -> bool:
	if field == null or _undo_redo == null:
		return false
	var report := field.resize_preview(new_width, new_height, anchor)
	if not bool(report.get("ok", false)):
		return false
	var before := field.authoring_snapshot()
	var after: Dictionary = report.get("snapshot", {})
	if after.is_empty() or after == before:
		return false
	_create_action(
		"Поле боя · размер %dx%d → %dx%d" % [field.width, field.height, new_width, new_height],
		field,
	)
	for property_name in [
		"width", "height", "terrain_kinds", "elevations", "blocked", "groups",
		"focus_cell", "party_deployment_cells", "enemy_deployment_cells",
	]:
		_add_do_property(field, property_name, after[property_name])
		_add_undo_property(field, property_name, before[property_name])
	_add_do_method(field, "notify_authoring_changed")
	_add_undo_method(field, "notify_authoring_changed")
	_commit_action()
	return true


func assign_visual_surface(
	field: EmberBattlefieldResource,
	surface: EmberVoxelModelResource,
) -> bool:
	if field == null or surface == null or _undo_redo == null or field.visual_surface == surface:
		return false
	_create_action("Поле боя · назначить визуальную поверхность", field)
	_add_do_property(field, "visual_surface", surface)
	_add_undo_property(field, "visual_surface", field.visual_surface)
	_add_do_method(field, "notify_authoring_changed")
	_add_undo_method(field, "notify_authoring_changed")
	_commit_action()
	return true


func sync_surface_water(field: EmberBattlefieldResource, minimum_coverage := 0.25) -> bool:
	if field == null or _undo_redo == null:
		return false
	var report := field.surface_water_sync_preview(minimum_coverage)
	if not bool(report.get("ok", false)):
		return false
	var before := field.authoring_snapshot()
	var after: Dictionary = report.get("snapshot", {})
	var changed: Array = report.get("changed_cells", [])
	if after.is_empty() or changed.is_empty() or after == before:
		return false
	_create_action("Поле боя · вода Surface → Wet · %d клеток" % changed.size(), field)
	for property_name in ["terrain_kinds", "groups"]:
		_add_do_property(field, property_name, after[property_name])
		_add_undo_property(field, property_name, before[property_name])
	_add_do_method(field, "notify_authoring_changed")
	_add_undo_method(field, "notify_authoring_changed")
	_commit_action()
	return true


func sync_surface_heights(field: EmberBattlefieldResource) -> bool:
	if field == null or _undo_redo == null:
		return false
	var report := field.surface_height_sync_preview()
	if not bool(report.get("ok", false)):
		return false
	var before := field.authoring_snapshot()
	var after: Dictionary = report.get("snapshot", {})
	var changed: Array = report.get("changed_cells", [])
	if after.is_empty() or changed.is_empty() or after == before:
		return false
	_create_action("Поле боя · высота Surface → бой · %d клеток" % changed.size(), field)
	_add_do_property(field, "elevations", after["elevations"])
	_add_undo_property(field, "elevations", before["elevations"])
	_add_do_method(field, "notify_authoring_changed")
	_add_undo_method(field, "notify_authoring_changed")
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


func _add_undo_method(object: Object, method: StringName) -> void:
	if _undo_redo is EditorUndoRedoManager:
		(_undo_redo as EditorUndoRedoManager).add_undo_method(object, method)
	else:
		(_undo_redo as UndoRedo).add_undo_method(Callable(object, method))


func _commit_action() -> void:
	if _undo_redo is EditorUndoRedoManager:
		(_undo_redo as EditorUndoRedoManager).commit_action()
	else:
		(_undo_redo as UndoRedo).commit_action()


func _tool_label(tool: int) -> String:
	return Palette.tool_label(tool)


func _cell_label(cell: Vector2i) -> String:
	return "%s%d" % [String.chr(65 + cell.x), cell.y + 1]
