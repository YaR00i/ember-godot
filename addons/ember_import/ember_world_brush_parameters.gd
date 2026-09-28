extends RefCounted
## Editor-only catalogue: one control/value per parameter, reused by tool profiles.

const DEFINITIONS := {
	"edit_scale": {"kind":"choice", "items":["Основной · 2×2 на блок", "Средне · 8×8 на блок", "Детально · 16×16 на блок"]},
	"height_step": {"kind":"choice", "items":["Ступень · ¼ блока · 4 вокселя", "Ступень · ½ блока · 8 вокселей"]},
	"shape": {"kind":"choice", "items":["Форма · квадрат", "Форма · круг"]},
	"radius": {"kind":"slider", "title":"Радиус · блоки", "min":0.0625, "max":8.0, "initial":1.0, "step":0.0625},
	"strength_detail": {"kind":"slider", "title":"Глубина · vox", "min":1.0, "max":32.0, "initial":4.0},
	"strength_steps": {"kind":"slider", "title":"Сила · ступени", "min":1.0, "max":16.0, "initial":1.0},
	"plane_height": {"kind":"spin", "title":"Плоскость · мир", "min":-512.0, "max":512.0, "initial":0.0},
	"water_height": {"kind":"spin", "title":"Вода · мир", "min":-512.0, "max":512.0, "initial":-8.0},
	"shore_width": {"kind":"slider", "title":"Длина спуска · блоки", "min":0.25, "max":16.0, "initial":6.0, "step":0.25},
	"shore_direction": {"kind":"choice", "items":["Глубже · +X", "Глубже · −X", "Глубже · +Z", "Глубже · −Z"]},
	"softness": {"kind":"slider", "title":"Мягкость · %", "min":0.0, "max":100.0, "initial":75.0},
	"feature_scale": {"kind":"slider", "title":"Крупность неровностей · ячейки", "min":4.0, "max":64.0, "initial":16.0},
	"detail": {"kind":"slider", "title":"Детализация неровностей", "min":0.0, "max":5.0, "initial":0.0},
	"seed": {"kind":"spin", "title":"Вариант неровностей", "min":0.0, "max":2147483647.0, "initial":1.0},
	"direction": {"kind":"choice", "items":["Вверх и вниз", "Только вверх", "Только вниз"]},
	"level_from_point": {"kind":"toggle", "title":"Площадка · высота по точке"},
	"palette": {"kind":"palette", "title":"ЦВЕТ ПОВЕРХНОСТИ"},
	"sand_palette": {"kind":"palette", "title":"ЦВЕТ ПЕСКА"},
}

const COMPACT_TOOLS := {
	"raise":["strength_detail", "strength_steps"],
	"lower":["strength_detail", "strength_steps"],
	"smooth":["strength_detail", "strength_steps"],
	"level":["level_from_point", "plane_height"],
	"generator":["strength_detail", "strength_steps", "feature_scale", "detail", "seed", "direction"],
	"paint":["palette"],
	"water":["palette", "water_height"],
	"dry":[],
}

const LEGACY_TOOLS := {
	"raise":["strength_detail", "plane_height", "palette"],
	"lower":["strength_detail", "plane_height", "palette"],
	"add":["strength_detail", "plane_height", "palette"],
	"remove":["strength_detail", "plane_height", "palette"],
	"smooth":["plane_height", "palette"],
	"level":["strength_detail", "plane_height", "palette"],
	"shore":["strength_detail", "plane_height", "palette", "shore_width", "shore_direction"],
	"generator":["strength_detail", "plane_height", "palette"],
	"grab":["plane_height", "palette", "softness"],
	"paint":["plane_height", "palette"],
	"sand":["plane_height", "palette", "sand_palette"],
	"water":["plane_height", "palette", "water_height"],
	"dry":["plane_height", "palette", "water_height"],
	"objects":[],
}

static func definition(id: String) -> Dictionary:
	return DEFINITIONS.get(id, {})

static func active_for(mode: String, compact: bool, coarse: bool, level_from_point: bool) -> Array[String]:
	var tool_definitions: Dictionary = COMPACT_TOOLS if compact else LEGACY_TOOLS
	if not tool_definitions.has(mode): return []
	var active: Array[String] = []
	if mode != "objects":
		active.append("radius")
	if compact and mode != "objects":
		active.append("edit_scale")
		active.append("shape")
		if coarse and mode in ["raise", "lower", "smooth", "level", "generator"]:
			active.append("height_step")
	for id: String in tool_definitions[mode]:
		if id == "strength_detail" and compact and coarse: continue
		if id == "strength_steps" and (not compact or not coarse): continue
		if id == "plane_height" and compact and level_from_point: continue
		active.append(id)
	return active
