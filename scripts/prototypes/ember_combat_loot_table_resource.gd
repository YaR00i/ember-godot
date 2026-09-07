@tool
class_name EmberCombatLootTableResource
extends Resource
## Shared authored drops for a combatant type. Rolling is pure and stable for
## the supplied battle key; inventory mutation remains owned by InteractionUI.

@export_group("Таблица")
@export var table_id := ""
@export var display_name := "Новая таблица лута"
@export_multiline var description := ""
@export var accent_color := Color("d6a85f")

@export_group("Предметы")
@export var entries: Array[EmberCombatLootEntryResource] = []


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if not _valid_id(table_id):
		errors.append("ID таблицы: используйте a-z, 0-9, _ или -.")
	if display_name.strip_edges().is_empty():
		errors.append("Укажите понятное название таблицы.")
	if entries.is_empty():
		errors.append("Добавьте хотя бы один предмет.")
	var seen := {}
	for index in entries.size():
		var entry := entries[index]
		if entry == null:
			errors.append("Строка %d пуста." % (index + 1))
			continue
		for entry_error in entry.validation_errors():
			errors.append("Строка %d: %s" % [index + 1, entry_error])
		if seen.has(entry.item_id):
			errors.append("Предмет %s добавлен дважды; объедините количество в одну строку." % entry.item_id)
		seen[entry.item_id] = true
	return errors


func roll(context_key: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not validation_errors().is_empty():
		return result
	for index in entries.size():
		var entry := entries[index]
		var roll_value := posmod(hash("%s|%s|%d|chance" % [context_key, table_id, index]), 100000)
		if roll_value >= roundi(entry.chance_percent * 1000.0):
			continue
		var span := entry.maximum_count - entry.minimum_count + 1
		var count := entry.minimum_count
		if span > 1:
			count += posmod(hash("%s|%s|%d|count" % [context_key, table_id, index]), span)
		var item := EmberItemCatalog.definition(entry.item_id)
		result.append({
			"itemId": entry.item_id,
			"nameRu": str(item.get("nameRu", item.get("name", entry.item_id))),
			"count": count,
			"lootTableId": table_id,
		})
	return result


func content_signature() -> String:
	var entry_signatures := PackedStringArray()
	for entry in entries:
		entry_signatures.append(entry.content_signature() if entry != null else "missing")
	return "|".join([
		table_id, display_name, description, accent_color.to_html(true),
		"||".join(entry_signatures),
	])


func _valid_id(value: String) -> bool:
	var expression := RegEx.new()
	return expression.compile("^[a-z0-9][a-z0-9_-]*$") == OK and expression.search(value.strip_edges()) != null
