@tool
class_name EmberCombatLootEntryResource
extends Resource
## One independently rolled item row inside a shared combat loot table.

@export var item_id := ""
@export_range(0.0, 100.0, 0.1, "suffix:%") var chance_percent := 100.0
@export_range(1, 999, 1) var minimum_count := 1
@export_range(1, 999, 1) var maximum_count := 1


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if EmberItemCatalog.definition(item_id).is_empty():
		errors.append("Предмет %s отсутствует в общей библиотеке." % item_id)
	if chance_percent <= 0.0 or chance_percent > 100.0:
		errors.append("Шанс должен быть больше 0 и не выше 100%.")
	if minimum_count <= 0 or maximum_count < minimum_count:
		errors.append("Количество: максимум не может быть меньше минимума.")
	return errors


func content_signature() -> String:
	return "%s|%.3f|%d|%d" % [item_id, chance_percent, minimum_count, maximum_count]


func duplicate_entry() -> EmberCombatLootEntryResource:
	var copy := EmberCombatLootEntryResource.new()
	copy.item_id = item_id
	copy.chance_percent = chance_percent
	copy.minimum_count = minimum_count
	copy.maximum_count = maximum_count
	return copy
