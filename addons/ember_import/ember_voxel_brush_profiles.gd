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

const MAX_RADIUS_VOXELS:=256
const DEFAULT_RADIUS := 4
const DEFAULT_DEPTH := 1
const DIRECTION_BEHAVIOR_VERSION := 2
const TOOLS := {
	Model.TOOL_ADD:{"title":"Лепка · объём","mask":MASK_COLUMNS},
	Model.TOOL_GRAB:{"title":"Тянуть","mask":MASK_NONE},
	Model.TOOL_PAINT:{"title":"Покраска","mask":MASK_VOXELS},
	Model.TOOL_MATERIAL:{"title":"Материал / вода","mask":MASK_VOXELS},
	Model.TOOL_SURFACE_FILL:{"title":"Заливка уровня","mask":MASK_NONE},
	Model.TOOL_RAISE:{"title":"Рельеф","mask":MASK_COLUMNS},
	Model.TOOL_LEVEL:{"title":"Площадка","mask":MASK_COLUMNS},
	Model.TOOL_SMOOTH:{"title":"Сгладить","mask":MASK_COLUMNS},
	Model.TOOL_RAMP:{"title":"Склон A → B","mask":MASK_COLUMNS},
}
const WORLD_TOOLS := {
	"raise":Model.TOOL_RAISE,"lower":Model.TOOL_LOWER,"add":Model.TOOL_ADD,
	"remove":Model.TOOL_REMOVE,"smooth":Model.TOOL_SMOOTH,"level":Model.TOOL_LEVEL,
	"grab":Model.TOOL_GRAB,"paint":Model.TOOL_PAINT,
}

static func title(tool_id:int,volume_smooth:=false)->String:
	var label:=str(TOOLS.get(base_tool(tool_id),{}).get("title",""))
	return label+(" · объём" if volume_smooth else " · высоты") if tool_id==Model.TOOL_SMOOTH else label

static func world_modes(category:int,heightfield:bool)->Array:
	return ([
		["raise","lower","smooth","level","generator"],["paint"],["water","dry"],["objects"],
	] if heightfield else [
		["raise","lower","add","remove","smooth","level","shore","generator","grab"],["paint","sand"],["water","dry"],["objects"],
	])[category]

static func world_title(mode:String,volume_smooth:=false)->String:
	if mode.begins_with("canvas:"):return title(int(mode.trim_prefix("canvas:")))+" → Canvas"
	if mode in ["raise","lower"]:return title(Model.TOOL_RAISE)+(" · поднять" if mode=="raise" else " · опустить")
	if mode in ["add","remove"]:return "Лепка · добавить" if mode=="add" else "Лепка · убрать"
	return title(WORLD_TOOLS[mode],volume_smooth) if WORLD_TOOLS.has(mode) else {"shore":"Берег и дно","generator":"Неровности","sand":"Песок · пятна","water":"Вода · уровень","dry":"Убрать воду","objects":"Объекты"}.get(mode,mode)

static func world_mode_for_tool(tool_id:int)->String:
	for mode in WORLD_TOOLS:
		if WORLD_TOOLS[mode]==tool_id:return mode
	return "canvas:%d"%tool_id

static func is_relief(tool_id:int)->bool:
	return base_tool(tool_id)==Model.TOOL_RAISE

static func is_oriented(tool_id:int)->bool:
	return tool_id in [Model.TOOL_ADD,Model.TOOL_REMOVE,Model.TOOL_PAINT,Model.TOOL_MATERIAL]

static func mask_help(kind:String)->String:
	return {MASK_NONE:"Этот инструмент не ограничивается выделением. Маска сохранена, но не действует.",MASK_VOXELS:"Только выбранные объёмные ячейки; маска сохраняется после мазка.",MASK_COLUMNS:"Отпечаток выбранной грани, включая глубину. Направление кисти фиксируется этой гранью."}.get(kind,"")


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
		"radius": clampi(int(profile.get("radius", DEFAULT_RADIUS)), 1, MAX_RADIUS_VOXELS),
		"smooth_strength":clampi(int(profile.get("smooth_strength",2)),1,8),
		"grab_softness": clampf(float(profile.get("grab_softness", 75)), 0, 100),
		"depth": clampi(int(profile.get("depth", DEFAULT_DEPTH)), 1, 32),
		"surface_plane_mode":clampi(int(profile.get("surface_plane_mode",1)),0,2),
		"surface_plane_offset":clampf(float(profile.get("surface_plane_offset",0)),-32,32),
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


static func mask_kind(tool_id: int, volume_smooth:=false) -> String:
	if tool_id in [Model.TOOL_SMOOTH,Model.TOOL_LEVEL] and volume_smooth:return MASK_VOXELS
	return str(TOOLS.get(base_tool(tool_id),{}).get("mask",MASK_NONE))
