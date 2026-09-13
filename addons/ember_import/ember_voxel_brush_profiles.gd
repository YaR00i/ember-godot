@tool
extends RefCounted
## Pure mapping between compact editor tool families and the existing concrete
## sculpt operations. Saved data and model algorithms stay unchanged.

const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")

const MASK_NONE := "none"
const MASK_VOXELS := "voxels"
const MASK_COLUMNS := "columns"

const APPLICATION_STROKE := "stroke"
const APPLICATION_POINT := "point"
const APPLICATION_LINE := "line"
const SHAPE_CIRCLE := "circle"
const SHAPE_SQUARE := "square"
const SMOOTH_LOCAL := "local"
const SMOOTH_COMMON := "common"
const RELIEF_BUILDUP := "buildup"
const RELIEF_GENERATOR := "generator"
const RELIEF_SOIL := "soil"
const RELIEF_RIDGES := "ridges"
const RELIEF_FACETS := "facets"
const RELIEF_SHORE := "shore"
const PAINT_PLAIN := "plain"
const PAINT_SAND := "sand"

const DEFAULT_RADIUS := 4
const DEFAULT_DEPTH := 1
const DIRECTION_BEHAVIOR_VERSION := 2


static func normalize_profile(profile: Dictionary) -> Dictionary:
	var application := str(profile.get("application", APPLICATION_STROKE))
	if application not in [APPLICATION_STROKE, APPLICATION_POINT, APPLICATION_LINE]:
		application = APPLICATION_STROKE
	var shape := str(profile.get("shape", SHAPE_CIRCLE))
	if shape not in [SHAPE_CIRCLE, SHAPE_SQUARE]:
		shape = SHAPE_CIRCLE
	var smooth_mode := str(profile.get("smooth_mode", SMOOTH_LOCAL))
	if smooth_mode not in [SMOOTH_LOCAL, SMOOTH_COMMON]:
		smooth_mode = SMOOTH_LOCAL
	var relief_mode := str(profile.get("relief_mode", RELIEF_BUILDUP))
	if relief_mode not in [RELIEF_BUILDUP, RELIEF_GENERATOR]:
		relief_mode = RELIEF_BUILDUP
	var relief_style := str(profile.get("relief_style", RELIEF_SOIL))
	if relief_style not in [RELIEF_SOIL, RELIEF_RIDGES, RELIEF_FACETS, RELIEF_SHORE]:
		relief_style = RELIEF_SOIL
	var follow_surface := bool(profile.get("follow_surface", true))
	# Profiles saved before the corner-safe behavior used the old first-face
	# default. Migrate them once so the repaired surface-following mode is the
	# default, while subsequent explicit "one face" choices remain persistent.
	if int(profile.get("direction_behavior_version", 0)) < DIRECTION_BEHAVIOR_VERSION:
		follow_surface = true
	return {
		"radius": clampi(int(profile.get("radius", DEFAULT_RADIUS)), 1, 32),
		"grab_softness": clampf(float(profile.get("grab_softness", 75)), 0, 100),
		"depth": clampi(int(profile.get("depth", DEFAULT_DEPTH)), 1, 32),
		"coarse": bool(profile.get("coarse", false)),
		"follow_surface": follow_surface,
		"direction_behavior_version": DIRECTION_BEHAVIOR_VERSION,
		"application": application,
		"shape": shape,
		"smooth_mode": smooth_mode,
		"smooth_fill_pits": bool(profile.get("smooth_fill_pits", true)),
		"relief_mode": relief_mode,
		"relief_direction": -1 if int(profile.get("relief_direction", 1)) < 0 else 1,
		"relief_geometry": (
			"shell" if str(profile.get("relief_geometry", "solid")) == "shell" else "solid"
		),
		"relief_style": relief_style,
		"relief_generator_direction": clampi(
			int(profile.get("relief_generator_direction", 0)), -1, 1
		),
		"relief_scale": clampi(int(profile.get("relief_scale", 16)), 4, 64),
		"relief_detail": clampi(int(profile.get("relief_detail", 3)), 0, 5),
		"relief_seed": maxi(0, int(profile.get("relief_seed", 0))),
		"relief_facet_tilt": clampi(int(profile.get("relief_facet_tilt", 60)), 0, 100),
		"relief_joint_width": clampi(int(profile.get("relief_joint_width", 1)), 0, 4),
		"relief_joint_depth": clampi(int(profile.get("relief_joint_depth", 3)), 0, 16),
		"shore_direction": clampi(int(profile.get("shore_direction", 0)), 0, 3),
		"shore_width": clampi(int(profile.get("shore_width", 96)), 4, 256),
		"shore_slope": clampi(int(profile.get("shore_slope", 3 if profile.has("shore_width") else 0)), 0, 3),
		"height_limit": clampi(int(profile.get("height_limit", 8)), 1, 24),
		"shore_roughness": clampi(int(profile.get("shore_roughness", 15)), 0, 40),
		"paint_mode": PAINT_SAND if str(profile.get("paint_mode", PAINT_PLAIN)) == PAINT_SAND else PAINT_PLAIN,
		"sand_palette": clampi(int(profile.get("sand_palette", 2)), 1, 255),
		"sand_scale": clampi(int(profile.get("sand_scale", 24)), 8, 64),
		"sand_coverage": clampi(int(profile.get("sand_coverage", 35)), 0, 100),
		"sand_seed": maxi(0, int(profile.get("sand_seed", 0))),
		"fill_mode": "open" if str(profile.get("fill_mode", "basin")) == "open" else "basin",
		"open_water_level": clampi(int(profile.get("open_water_level", 16)), 1, 256),
	}


static func normalize_profiles(profiles: Dictionary) -> Dictionary:
	var normalized := {}
	for raw_tool in profiles:
		var tool_id := int(raw_tool)
		var raw_profile: Variant = profiles[raw_tool]
		if raw_profile is Dictionary:
			normalized[tool_id] = normalize_profile(raw_profile as Dictionary)
	return normalized


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
