@tool
class_name EmberCraftRecipeResource
extends Resource
## Authored recipe only. Inventory and persistence remain in ExploreState.
@export var recipe_id := ""
@export var title := "Рецепт"
@export_enum("workbench", "kitchen") var station_kind := "workbench"
@export_multiline var description := ""
@export var ingredients: Dictionary = {}
@export var results: Dictionary = {}
@export var completion_dialogue: EmberDialogueResource

func validation_errors(items: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if recipe_id.strip_edges().is_empty(): errors.append("Не задан ID рецепта")
	if title.strip_edges().is_empty(): errors.append("Не задано название рецепта")
	if station_kind not in ["workbench", "kitchen"]: errors.append("Неизвестное рабочее место")
	for quantities in [ingredients, results]:
		if quantities.is_empty(): errors.append("Ингредиенты и результат не могут быть пустыми")
		for id in quantities:
			if typeof(id) != TYPE_STRING or not items.has(id):
				errors.append("Неизвестный предмет: " + str(id))
			var count: Variant = quantities[id]
			if typeof(count) != TYPE_INT or count < 1 or count > 999:
				errors.append("Количество должно быть целым от1до999: " + str(id))
	return errors
