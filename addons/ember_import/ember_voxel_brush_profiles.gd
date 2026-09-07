@tool
extends RefCounted
## Pure mapping between compact editor tool families and the existing concrete
## sculpt operations. Saved data and model algorithms stay unchanged.

const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")

const MASK_NONE := "none"
const MASK_VOXELS := "voxels"
const MASK_COLUMNS := "columns"


static func resolved_tool(
	base_tool: int,
	volume_operation: int,
	relief_direction: int,
	relief_geometry: String,
) -> int:
	if base_tool == Model.TOOL_ADD:
		return Model.TOOL_REMOVE if volume_operation == Model.TOOL_REMOVE else Model.TOOL_ADD
	if base_tool != Model.TOOL_RAISE:
		return base_tool
	var lowering := relief_direction < 0
	var shell := relief_geometry == "shell"
	if shell:
		return Model.TOOL_SHELL_LOWER if lowering else Model.TOOL_SHELL_RAISE
	return Model.TOOL_LOWER if lowering else Model.TOOL_RAISE


static func base_tool(tool_id: int) -> int:
	if tool_id in [Model.TOOL_ADD, Model.TOOL_REMOVE]:
		return Model.TOOL_ADD
	if tool_id in [
		Model.TOOL_RAISE, Model.TOOL_LOWER,
		Model.TOOL_SHELL_RAISE, Model.TOOL_SHELL_LOWER,
	]:
		return Model.TOOL_RAISE
	return tool_id


static func mask_kind(tool_id: int) -> String:
	if tool_id in [Model.TOOL_PAINT, Model.TOOL_MATERIAL]:
		return MASK_VOXELS
	if tool_id in [
		Model.TOOL_ADD, Model.TOOL_REMOVE,
		Model.TOOL_RAISE, Model.TOOL_LOWER,
		Model.TOOL_SHELL_RAISE, Model.TOOL_SHELL_LOWER,
		Model.TOOL_LEVEL, Model.TOOL_SMOOTH, Model.TOOL_RAMP,
	]:
		return MASK_COLUMNS
	return MASK_NONE
