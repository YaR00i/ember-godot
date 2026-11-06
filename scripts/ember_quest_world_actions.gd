extends RefCounted
## Descriptions/validation only; progress and transactions belong to ExploreState.
const Recipe = preload("res://scripts/ember_craft_recipe_resource.gd")
const LABELS := {
	"destroy": "Разрушить объекты",
	"reveal_leaves": "Разгрести кучки листьев",
	"cut_grass": "Скосить пучки травы",
	"collect": "Собрать предметы в мире",
	"craft": "Изготовить по рецепту",
}

static func recipes() -> Dictionary:
	var result := {}
	var directory := "res://content/recipes"
	if not DirAccess.dir_exists_absolute(directory): return result
	for filename in DirAccess.get_files_at(directory):
		if filename.get_extension() != "tres": continue
		var recipe := ResourceLoader.load(directory.path_join(filename), "", ResourceLoader.CACHE_MODE_IGNORE) as Recipe
		if recipe != null and not recipe.recipe_id.is_empty():
			result[recipe.recipe_id] = recipe
	return result

static func targets(action: String) -> Dictionary:
	var result := {}
	if action == "craft":
		var available := recipes()
		for id in available: result[id] = available[id].title
	elif action in ["destroy", "collect"]:
		for id in EmberItemCatalog.ids():
			result[id] = str(EmberItemCatalog.definition(id).get("nameRu", id))
	return result

static func validation_error(action: String, target: String) -> String:
	if not LABELS.has(action): return "Выберите действие в мире"
	if action in ["reveal_leaves", "cut_grass"]:
		return "Для листьев и травы отдельный предмет не выбирается" if not target.is_empty() else ""
	if not targets(action).has(target): return "Выберите существующий рецепт" if action == "craft" else "Выберите существующий предмет"
	return ""
