@tool
class_name EmberEncounterInspectorPanel
extends VBoxContainer
## Visual overview and safe navigation for an Encounter Resource. Field edits
## remain native Inspector properties, so Godot owns Undo/Redo and serialization.

const Visuals := preload("res://scripts/prototypes/ember_encounter_visuals.gd")
const CombatResult := preload("res://scripts/prototypes/ember_combat_result.gd")
const UnitCatalog := preload("res://scripts/prototypes/ember_combat_unit_catalog.gd")

var _encounter: EmberEncounterResource
var _editor_interface: EditorInterface
var _undo_redo: Object
var _preview: TextureRect
var _summary: Label
var _validation: Label
var _party_box: VBoxContainer
var _enemy_box: VBoxContainer


func setup(
	encounter: EmberEncounterResource,
	editor_interface: EditorInterface,
	undo_redo: Object = null,
) -> void:
	_encounter = encounter
	_editor_interface = editor_interface
	_undo_redo = undo_redo
	name = "EncounterOverview"
	add_theme_constant_override("separation", 7)
	var title := Label.new()
	title.text = "БОЕВАЯ ВСТРЕЧА"
	title.add_theme_font_size_override("font_size", 13)
	title.modulate = Color("ffc85a")
	add_child(title)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	add_child(body)
	_preview = TextureRect.new()
	_preview.name = "EncounterPreview"
	_preview.custom_minimum_size = Vector2(176, 132)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	body.add_child(_preview)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(copy)
	_summary = Label.new()
	_summary.name = "EncounterSummary"
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(_summary)
	var field_button := Button.new()
	field_button.name = "OpenEncounterBattlefield"
	field_button.text = "Открыть данные поля"
	field_button.pressed.connect(_open_field)
	copy.add_child(field_button)
	var arena_button := Button.new()
	arena_button.name = "OpenEncounterArena"
	arena_button.text = "Открыть арену в 3D"
	arena_button.pressed.connect(_open_arena)
	copy.add_child(arena_button)
	_party_box = _build_roster_section("ГЕРОИ")
	_enemy_box = _build_roster_section("ВРАГИ")
	add_child(_party_box)
	add_child(_enemy_box)
	_validation = Label.new()
	_validation.name = "EncounterValidation"
	_validation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_validation)
	var hint := Label.new()
	hint.text = "В цепочке действий добавьте финальный шаг «Начать бой». Продолжение после исхода задаётся ниже отдельными цепочками."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(0.62, 0.72, 0.82)
	hint.add_theme_font_size_override("font_size", 12)
	add_child(hint)
	if not _encounter.changed.is_connected(_refresh):
		_encounter.changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	if _encounter != null and _encounter.changed.is_connected(_refresh):
		_encounter.changed.disconnect(_refresh)


func _refresh() -> void:
	if _encounter == null:
		return
	_preview.texture = Visuals.texture(_encounter)
	var reward_parts: Array[String] = []
	for raw_reward in CombatResult.reward_preview(_encounter.victory_action_script_id):
		var reward: Dictionary = raw_reward
		reward_parts.append("%s ×%d" % [reward.get("nameRu", reward.get("itemId", "?")), reward.get("count", 1)])
	var loot_names: Array[String] = []
	for enemy_id in _encounter.enemy_unit_ids:
		var enemy := UnitCatalog.resource(str(enemy_id))
		if enemy != null and enemy.loot_table != null and enemy.loot_table.display_name not in loot_names:
			loot_names.append(enemy.loot_table.display_name)
	_summary.text = "%s\n%s\nГерои: %d · враги: %d\nОпыт: %d XP каждому\nФиксированная награда: %s\nТаблицы врагов: %s\nСобытие задания: %s" % [
		_encounter.display_name,
		_encounter.encounter_id,
		_encounter.party_unit_ids.size(),
		_encounter.enemy_unit_ids.size(),
		_encounter.victory_xp,
		", ".join(reward_parts) if not reward_parts.is_empty() else "—",
		", ".join(loot_names) if not loot_names.is_empty() else "—",
		CombatResult.encounter_victory_counter(_encounter.encounter_id),
	]
	_rebuild_roster(_party_box, _encounter.party_unit_ids, "hero")
	_rebuild_roster(_enemy_box, _encounter.enemy_unit_ids, "enemy")
	var errors := _encounter.validation_errors()
	_validation.text = (
		"✓ Встреча готова к запуску"
		if errors.is_empty()
		else "⚠ " + "\n⚠ ".join(errors)
	)
	_validation.modulate = Color("79d99a") if errors.is_empty() else Color("ff8d78")


func _open_field() -> void:
	if _editor_interface != null and _encounter != null and _encounter.battlefield != null:
		_editor_interface.edit_resource(_encounter.battlefield)


func _open_arena() -> void:
	if _editor_interface == null or _encounter == null or _encounter.arena_scene == null:
		return
	var path := _encounter.arena_scene.resource_path
	if not path.is_empty():
		_editor_interface.open_scene_from_path(path)


func _build_roster_section(title_text: String) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 4)
	var title := Label.new()
	title.text = title_text
	title.modulate = Color(0.70, 0.76, 0.86)
	title.add_theme_font_size_override("font_size", 12)
	section.add_child(title)
	return section


func _rebuild_roster(
	section: VBoxContainer,
	unit_ids: PackedStringArray,
	team_id: String,
) -> void:
	if section == null:
		return
	while section.get_child_count() > 1:
		var child := section.get_child(1)
		section.remove_child(child)
		child.queue_free()
	for index in unit_ids.size():
		var unit_id := str(unit_ids[index])
		var unit := UnitCatalog.resource(unit_id)
		var row := HBoxContainer.new()
		row.name = "EncounterRoster_%s_%d" % [team_id, index]
		row.add_theme_constant_override("separation", 4)
		section.add_child(row)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(18, 34)
		swatch.color = unit.battle_color if unit != null else Color("8a3f4d")
		swatch.tooltip_text = "Цвет бойца на текущем 3D graybox-поле."
		row.add_child(swatch)
		var open := Button.new()
		open.name = "OpenEncounterUnit_%s" % unit_id
		open.text = (
			"%s · %s  HP %d  SPD %d" % [
				unit.display_name, unit.unit_id, unit.max_hp, unit.speed,
			]
			if unit != null
			else "⚠ Не найден · %s" % unit_id
		)
		open.tooltip_text = "Открыть единый Resource бойца."
		open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		open.clip_text = true
		open.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		open.disabled = unit == null or _editor_interface == null
		open.pressed.connect(_open_unit.bind(unit_id))
		row.add_child(open)
		for direction in [-1, 1]:
			var move := Button.new()
			move.text = "↑" if direction < 0 else "↓"
			move.tooltip_text = "Изменить порядок расстановки и инициативной карточки."
			move.disabled = _undo_redo == null or index + direction < 0 or index + direction >= unit_ids.size()
			move.pressed.connect(_move_unit.bind(team_id, index, direction))
			row.add_child(move)
		var remove := Button.new()
		remove.text = "×"
		remove.tooltip_text = "Убрать бойца из этой встречи. Ctrl+Z отменяет."
		remove.disabled = _undo_redo == null or unit_ids.size() <= 1
		remove.modulate = Color(1.0, 0.56, 0.52)
		remove.pressed.connect(_remove_unit.bind(team_id, index))
		row.add_child(remove)
	var add_row := HBoxContainer.new()
	add_row.name = "EncounterAdd_%s" % team_id
	section.add_child(add_row)
	var picker := OptionButton.new()
	picker.name = "EncounterUnitPicker_%s" % team_id
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for unit in UnitCatalog.resources(team_id):
		if unit.unit_id in unit_ids:
			continue
		picker.add_item("%s · %s" % [unit.display_name, unit.unit_id])
		picker.set_item_metadata(picker.item_count - 1, unit.unit_id)
	add_row.add_child(picker)
	var add := Button.new()
	add.name = "EncounterAddUnit_%s" % team_id
	add.text = "+ Добавить"
	add.disabled = _undo_redo == null or picker.item_count == 0
	add.pressed.connect(_add_unit.bind(team_id, picker))
	add_row.add_child(add)


func _open_unit(unit_id: String) -> void:
	if _editor_interface == null:
		return
	var unit := UnitCatalog.resource(unit_id)
	if unit != null:
		_editor_interface.edit_resource(unit)


func _add_unit(team_id: String, picker: OptionButton) -> void:
	if picker == null or picker.item_count == 0:
		return
	var unit_id := str(picker.get_item_metadata(picker.selected))
	var next := _roster(team_id)
	if not unit_id.is_empty() and unit_id not in next:
		next.append(unit_id)
		_commit_roster(team_id, next, "Добавить бойца во встречу")


func _remove_unit(team_id: String, index: int) -> void:
	var next := _roster(team_id)
	if index < 0 or index >= next.size() or next.size() <= 1:
		return
	next.remove_at(index)
	_commit_roster(team_id, next, "Убрать бойца из встречи")


func _move_unit(team_id: String, index: int, direction: int) -> void:
	var next := _roster(team_id)
	var target := index + direction
	if index < 0 or index >= next.size() or target < 0 or target >= next.size():
		return
	var value := next[index]
	next[index] = next[target]
	next[target] = value
	_commit_roster(team_id, next, "Изменить порядок бойцов")


func _roster(team_id: String) -> PackedStringArray:
	return (
		_encounter.party_unit_ids.duplicate()
		if team_id == "hero"
		else _encounter.enemy_unit_ids.duplicate()
	)


func _commit_roster(
	team_id: String,
	next: PackedStringArray,
	title: String,
) -> void:
	if _encounter == null or _undo_redo == null:
		return
	var property := "party_unit_ids" if team_id == "hero" else "enemy_unit_ids"
	var previous: PackedStringArray = _encounter.get(property).duplicate()
	if previous == next:
		return
	_create_action(title)
	_add_do_property(property, next)
	_add_do_method("emit_changed")
	_add_do_method("notify_property_list_changed")
	_add_undo_property(property, previous)
	_add_undo_method("emit_changed")
	_add_undo_method("notify_property_list_changed")
	_commit_action()


func _create_action(title: String) -> void:
	if _undo_redo is EditorUndoRedoManager:
		(_undo_redo as EditorUndoRedoManager).create_action(
			title, UndoRedo.MERGE_DISABLE, _encounter
		)
	else:
		(_undo_redo as UndoRedo).create_action(title, UndoRedo.MERGE_DISABLE)


func _add_do_property(property: StringName, value: Variant) -> void:
	if _undo_redo is EditorUndoRedoManager:
		(_undo_redo as EditorUndoRedoManager).add_do_property(_encounter, property, value)
	else:
		(_undo_redo as UndoRedo).add_do_property(_encounter, property, value)


func _add_undo_property(property: StringName, value: Variant) -> void:
	if _undo_redo is EditorUndoRedoManager:
		(_undo_redo as EditorUndoRedoManager).add_undo_property(_encounter, property, value)
	else:
		(_undo_redo as UndoRedo).add_undo_property(_encounter, property, value)


func _add_do_method(method: StringName) -> void:
	if _undo_redo is EditorUndoRedoManager:
		Callable(_undo_redo, "add_do_method").call(_encounter, method)
	else:
		(_undo_redo as UndoRedo).add_do_method(Callable(_encounter, method))


func _add_undo_method(method: StringName) -> void:
	if _undo_redo is EditorUndoRedoManager:
		Callable(_undo_redo, "add_undo_method").call(_encounter, method)
	else:
		(_undo_redo as UndoRedo).add_undo_method(Callable(_encounter, method))


func _commit_action() -> void:
	if _undo_redo is EditorUndoRedoManager:
		(_undo_redo as EditorUndoRedoManager).commit_action()
	else:
		(_undo_redo as UndoRedo).commit_action()
