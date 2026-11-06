@tool
extends "res://scripts/ember_interact.gd"
## Movable interact adapter; recipes are authored Resources, UI is shared.
const Recipe = preload("res://scripts/ember_craft_recipe_resource.gd")
@export var station_title := "Верстак"
@export_enum("workbench", "kitchen") var station_kind := "workbench"
@export var recipes: Array[Resource] = []

func _ready() -> void:
	kind = "custom"
	super._ready()

func refresh_runtime_binding() -> void:
	_bind_progress()
	if runtime_available(): add_to_group("ember_interact")
	else: remove_from_group("ember_interact")
	collision_layer = 0
	collision_mask = 0
	set_deferred("monitoring", false)

func prompt() -> String:
	return station_title

func activate_from(actor: Node3D) -> String:
	if not is_instance_valid(actor) or not runtime_available(): return "Рабочее место недоступно"
	var ui := actor.get("interaction_ui") as EmberInteractionUi
	return ui.open_crafting(self) if ui != null else "Состояние игры недоступно"

func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	var seen := {}
	var items := EmberItemCatalog.definitions()
	if station_kind not in ["workbench", "kitchen"]: errors.append("Неизвестный тип рабочего места")
	if recipes.is_empty(): errors.append("Не назначены рецепты")
	for recipe in recipes:
		if not recipe is Recipe:
			errors.append("Нужен Resource рецепта")
			continue
		errors.append_array(recipe.validation_errors(items))
		if recipe.station_kind != station_kind: errors.append("Рецепт другого рабочего места")
		if seen.has(recipe.recipe_id): errors.append("Повторный ID рецепта")
		seen[recipe.recipe_id] = true
	return errors

func _get_configuration_warnings() -> PackedStringArray:
	return PackedStringArray(validation_errors())
