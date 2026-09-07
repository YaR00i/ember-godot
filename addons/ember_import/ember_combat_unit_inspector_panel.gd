@tool
class_name EmberCombatUnitInspectorPanel
extends VBoxContainer
## Compact visual summary for a canonical combatant Resource. Native Inspector
## fields remain the only writer, so this panel adds no parallel schema.

const Combat := preload("res://scripts/prototypes/ember_combat_prototype.gd")
const ActionCatalog := preload("res://scripts/prototypes/ember_combat_action_catalog.gd")
const AiProfileCatalog := preload("res://scripts/prototypes/ember_combat_ai_profile_catalog.gd")
const LootTableCatalog := preload("res://scripts/prototypes/ember_combat_loot_table_catalog.gd")
const ItemVisuals := preload("res://scripts/ember_item_visuals.gd")
const VisualPopup := preload("res://addons/ember_import/ember_visual_library_popup.gd")

var _unit: EmberCombatUnitResource
var _editor_interface: EditorInterface
var _undo_redo: Object
var _swatch: ColorRect
var _portrait: TextureRect
var _summary: Label
var _validation: Label
var _actions: VBoxContainer
var _action_popup: EmberVisualLibraryPopup


func setup(
	unit: EmberCombatUnitResource,
	editor_interface: EditorInterface = null,
	undo_redo: Object = null,
) -> void:
	_unit = unit
	_editor_interface = editor_interface
	_undo_redo = undo_redo
	if _unit != null and _unit.team_id() == "enemy":
		AiProfileCatalog.refresh()
	name = "CombatUnitOverview"
	add_theme_constant_override("separation", 7)
	var title := Label.new()
	title.text = "БОЕЦ"
	title.add_theme_font_size_override("font_size", 13)
	title.modulate = Color("ffc85a")
	add_child(title)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	add_child(body)
	var visual := PanelContainer.new()
	visual.custom_minimum_size = Vector2(88, 88)
	visual.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	visual.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(visual)
	_portrait = TextureRect.new()
	_portrait.name = "CombatUnitPortrait"
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	visual.add_child(_portrait)
	_swatch = ColorRect.new()
	_swatch.name = "CombatUnitSwatch"
	_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.add_child(_swatch)
	_summary = Label.new()
	_summary.name = "CombatUnitSummary"
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_summary)
	_validation = Label.new()
	_validation.name = "CombatUnitValidation"
	_validation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_validation)
	_actions = VBoxContainer.new()
	_actions.name = "CombatUnitActionEditor"
	_actions.add_theme_constant_override("separation", 4)
	add_child(_actions)
	var hint := Label.new()
	hint.text = "Encounter хранит только ID. Действия выбираются из общей визуальной библиотеки и исполняются единым resolver."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(0.62, 0.72, 0.82)
	hint.add_theme_font_size_override("font_size", 12)
	add_child(hint)
	if not _unit.changed.is_connected(_refresh):
		_unit.changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	if _unit != null and _unit.changed.is_connected(_refresh):
		_unit.changed.disconnect(_refresh)


func _refresh() -> void:
	if _unit == null:
		return
	_portrait.texture = _unit.portrait
	_swatch.color = _unit.battle_color
	_swatch.visible = _unit.portrait == null
	_summary.text = "%s\n%s · %s · уровень %d\nТип %s · размер %s · стойкость %d\nHP %d · MP %d\nSTR %d · MAG %d · DEF %d · RES %d\nSPD %d · ACC %d · LUCK %d · ход %d · Jump %d\nСтихии: Огонь %+d · Вода %+d · Холод %+d · Молния %+d · Воздух %+d · Земля %+d%%\nЭффекты: Wet −%d · Frozen −%d · Burning −%d ход\nДействия: %s\nЛут: %s\nТеги: %s" % [
		_unit.display_name,
		_unit.unit_id,
		"Герой" if _unit.team_id() == "hero" else "Враг",
		_unit.combat_level,
		_unit.creature_type_label(),
		_unit.size_label(),
		_unit.push_resistance,
		_unit.max_hp,
		_unit.max_mp,
		_unit.strength,
		_unit.magic,
		_unit.defense,
		_unit.resistance,
		_unit.speed,
		_unit.accuracy,
		_unit.luck,
		_unit.move_range,
		_unit.jump_height,
		_unit.fire_resistance,
		_unit.water_resistance,
		_unit.cold_resistance,
		_unit.lightning_resistance,
		_unit.air_resistance,
		_unit.earth_resistance,
		_unit.wet_resistance,
		_unit.frozen_resistance,
		_unit.burning_resistance,
		", ".join(_unit.action_ids),
		_unit.loot_table.display_name if _unit.loot_table != null else "—",
		", ".join(_unit.combat_tags) if not _unit.combat_tags.is_empty() else "—",
	]
	var errors := _unit.validation_errors(Combat.action_ids())
	_validation.text = "✓ Боец готов" if errors.is_empty() else "⚠ " + "\n⚠ ".join(errors)
	_validation.modulate = Color("79d99a") if errors.is_empty() else Color("ff8d78")
	_rebuild_action_editor()


func _rebuild_action_editor() -> void:
	if _actions == null or _unit == null:
		return
	for child in _actions.get_children():
		_actions.remove_child(child)
		child.free()
	var heading := Label.new()
	heading.text = "ДЕЙСТВИЯ"
	heading.modulate = Color(0.70, 0.76, 0.86)
	heading.add_theme_font_size_override("font_size", 12)
	_actions.add_child(heading)
	for index in _unit.action_ids.size():
		var action_id := str(_unit.action_ids[index])
		var action := ActionCatalog.resource(action_id)
		var row := HBoxContainer.new()
		row.name = "CombatUnitAction_%s" % action_id
		row.add_theme_constant_override("separation", 4)
		_actions.add_child(row)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(34, 34)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.texture = _action_texture(action)
		row.add_child(icon)
		var open := Button.new()
		open.name = "OpenCombatAction_%s" % action_id
		open.text = (
			"%s · %s  PWR %d  MP %d  RNG %d" % [
				action.display_name, action.action_id, action.power, action.mp_cost,
				action.range_cells,
			]
			if action != null
			else "⚠ Не найдено · %s" % action_id
		)
		open.tooltip_text = action.hint if action != null else "Действие отсутствует в каталоге."
		open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		open.clip_text = true
		open.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		open.disabled = action == null or _editor_interface == null
		open.pressed.connect(_open_action.bind(action_id))
		row.add_child(open)
		for direction in [-1, 1]:
			var move := Button.new()
			move.text = "↑" if direction < 0 else "↓"
			move.tooltip_text = "Изменить порядок в боевом кольце. Ctrl+Z отменяет."
			move.disabled = _undo_redo == null or index + direction < 0 or index + direction >= _unit.action_ids.size()
			move.pressed.connect(_move_action.bind(index, direction))
			row.add_child(move)
		var remove := Button.new()
		remove.text = "×"
		remove.tooltip_text = "Убрать действие у бойца. Ctrl+Z отменяет."
		remove.disabled = _undo_redo == null or _unit.action_ids.size() <= 1
		remove.modulate = Color(1.0, 0.56, 0.52)
		remove.pressed.connect(_remove_action.bind(index))
		row.add_child(remove)
	var add := Button.new()
	add.name = "CombatUnitAddAction"
	add.text = "+ Выбрать действие из библиотеки…"
	add.disabled = _undo_redo == null or _available_actions().is_empty()
	add.pressed.connect(_open_action_library)
	_actions.add_child(add)
	if _unit.team_id() == "enemy":
		var ai_row := HBoxContainer.new()
		ai_row.name = "CombatUnitAiProfileEditor"
		ai_row.add_theme_constant_override("separation", 4)
		_actions.add_child(ai_row)
		var profile := AiProfileCatalog.resource(_unit.ai_profile_id)
		var ai_swatch := ColorRect.new()
		ai_swatch.custom_minimum_size = Vector2(18, 34)
		ai_swatch.color = profile.accent_color if profile != null else Color("8a3f4d")
		ai_row.add_child(ai_swatch)
		var ai_label := Label.new()
		ai_label.text = "Профиль AI"
		ai_label.custom_minimum_size.x = 80
		ai_row.add_child(ai_label)
		var ai_picker := OptionButton.new()
		ai_picker.name = "CombatUnitAiProfilePicker"
		ai_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for candidate in AiProfileCatalog.resources():
			ai_picker.add_item("%s · %s" % [candidate.display_name, candidate.profile_id])
			ai_picker.set_item_metadata(ai_picker.item_count - 1, candidate.profile_id)
			ai_picker.set_item_tooltip(ai_picker.item_count - 1, candidate.description)
			if candidate.profile_id == _unit.ai_profile_id:
				ai_picker.select(ai_picker.item_count - 1)
		ai_picker.disabled = _undo_redo == null or ai_picker.item_count == 0
		ai_picker.item_selected.connect(_select_ai_profile.bind(ai_picker))
		ai_row.add_child(ai_picker)
		var open_profile := Button.new()
		open_profile.name = "OpenCombatAiProfile"
		open_profile.text = "Открыть"
		open_profile.disabled = profile == null or _editor_interface == null
		open_profile.pressed.connect(_open_ai_profile)
		ai_row.add_child(open_profile)
		var loot_row := HBoxContainer.new()
		loot_row.name = "CombatUnitLootTableEditor"
		loot_row.add_theme_constant_override("separation", 4)
		_actions.add_child(loot_row)
		var loot_icon := TextureRect.new()
		loot_icon.custom_minimum_size = Vector2(34, 34)
		loot_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		loot_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		loot_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if _unit.loot_table != null and not _unit.loot_table.entries.is_empty():
			loot_icon.texture = ItemVisuals.item_texture(_unit.loot_table.entries[0].item_id, 34)
		loot_row.add_child(loot_icon)
		var loot_label := Label.new()
		loot_label.text = "Лут"
		loot_label.custom_minimum_size.x = 50
		loot_row.add_child(loot_label)
		var loot_picker := OptionButton.new()
		loot_picker.name = "CombatUnitLootTablePicker"
		loot_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for candidate in LootTableCatalog.resources():
			loot_picker.add_item("%s · %s" % [candidate.display_name, candidate.table_id])
			loot_picker.set_item_metadata(loot_picker.item_count - 1, candidate.table_id)
			loot_picker.set_item_tooltip(loot_picker.item_count - 1, candidate.description)
			if _unit.loot_table != null and candidate.table_id == _unit.loot_table.table_id:
				loot_picker.select(loot_picker.item_count - 1)
		loot_picker.disabled = _undo_redo == null or loot_picker.item_count == 0
		loot_picker.item_selected.connect(_select_loot_table.bind(loot_picker))
		loot_row.add_child(loot_picker)
		var open_loot := Button.new()
		open_loot.name = "OpenCombatLootTable"
		open_loot.text = "Открыть"
		open_loot.disabled = _unit.loot_table == null or _editor_interface == null
		open_loot.pressed.connect(_open_loot_table)
		loot_row.add_child(open_loot)


func _open_action(action_id: String) -> void:
	if _editor_interface == null:
		return
	var action := ActionCatalog.resource(action_id)
	if action != null:
		_editor_interface.edit_resource(action)


func _open_action_library() -> void:
	ActionCatalog.refresh()
	if _action_popup == null:
		_action_popup = VisualPopup.new() as EmberVisualLibraryPopup
		_action_popup.name = "CombatActionLibraryPopup"
		_action_popup.value_chosen.connect(_add_action)
		add_child(_action_popup)
	var entries: Array[Dictionary] = []
	for action in _available_actions():
		entries.append({
			"id": action.action_id,
			"label": "%s\n%s" % [action.display_name, action.action_id],
			"tooltip": "%s · %s → %s\n%s" % [
				action.element_label(), action.effect_label(), action.target_label(), action.hint,
			],
			"texture": _action_texture(action),
		})
	_action_popup.open_library("БИБЛИОТЕКА БОЕВЫХ ДЕЙСТВИЙ", entries, "", Vector2i(64, 64), 150)


func _available_actions() -> Array[EmberCombatActionResource]:
	var result: Array[EmberCombatActionResource] = []
	if _unit == null:
		return result
	for action in ActionCatalog.resources():
		if action.action_id not in _unit.action_ids:
			result.append(action)
	return result


func _action_texture(action: EmberCombatActionResource) -> Texture2D:
	if action == null:
		return null
	if action.icon != null:
		return action.icon
	var image := Image.create_empty(48, 48, false, Image.FORMAT_RGBA8)
	image.fill(action.ui_color)
	return ImageTexture.create_from_image(image)


func _add_action(action_id: String) -> void:
	if action_id.is_empty() or action_id in _unit.action_ids:
		return
	var next := _unit.action_ids.duplicate()
	next.append(action_id)
	_commit_actions(next, "Добавить действие бойцу")


func _remove_action(index: int) -> void:
	if index < 0 or index >= _unit.action_ids.size() or _unit.action_ids.size() <= 1:
		return
	var next := _unit.action_ids.duplicate()
	next.remove_at(index)
	_commit_actions(next, "Убрать действие у бойца")


func _move_action(index: int, direction: int) -> void:
	var next := _unit.action_ids.duplicate()
	var target := index + direction
	if index < 0 or index >= next.size() or target < 0 or target >= next.size():
		return
	var value := next[index]
	next[index] = next[target]
	next[target] = value
	_commit_actions(next, "Изменить порядок действий")


func _select_ai_profile(index: int, picker: OptionButton) -> void:
	if picker == null or index < 0 or index >= picker.item_count:
		return
	var next_profile := str(picker.get_item_metadata(index))
	if next_profile == _unit.ai_profile_id:
		return
	_commit_profile(next_profile)


func _open_ai_profile() -> void:
	if _editor_interface == null:
		return
	var profile := AiProfileCatalog.resource(_unit.ai_profile_id)
	if profile != null:
		_editor_interface.edit_resource(profile)


func _select_loot_table(index: int, picker: OptionButton) -> void:
	if picker == null or index < 0 or index >= picker.item_count:
		return
	var table := LootTableCatalog.resource(str(picker.get_item_metadata(index)))
	if table != null and (_unit.loot_table == null or table.table_id != _unit.loot_table.table_id):
		_commit_loot_table(table)


func _open_loot_table() -> void:
	if _editor_interface != null and _unit != null and _unit.loot_table != null:
		_editor_interface.edit_resource(_unit.loot_table)


func _commit_loot_table(next: EmberCombatLootTableResource) -> void:
	if _unit == null or _undo_redo == null or next == _unit.loot_table:
		return
	var previous := _unit.loot_table
	_create_action("Изменить таблицу лута врага")
	_add_do_property("loot_table", next)
	_add_do_method("emit_changed")
	_add_do_method("notify_property_list_changed")
	_add_undo_property("loot_table", previous)
	_add_undo_method("emit_changed")
	_add_undo_method("notify_property_list_changed")
	_commit_action()


func _commit_profile(next_profile: String) -> void:
	if _unit == null or _undo_redo == null or next_profile == _unit.ai_profile_id:
		return
	var previous := _unit.ai_profile_id
	_create_action("Изменить профиль AI")
	_add_do_property("ai_profile_id", next_profile)
	_add_do_method("emit_changed")
	_add_do_method("notify_property_list_changed")
	_add_undo_property("ai_profile_id", previous)
	_add_undo_method("emit_changed")
	_add_undo_method("notify_property_list_changed")
	_commit_action()


func _commit_actions(next: PackedStringArray, title: String) -> void:
	if _unit == null or _undo_redo == null:
		return
	var previous := _unit.action_ids.duplicate()
	if previous == next:
		return
	_create_action(title)
	_add_do_property("action_ids", next)
	_add_do_method("emit_changed")
	_add_do_method("notify_property_list_changed")
	_add_undo_property("action_ids", previous)
	_add_undo_method("emit_changed")
	_add_undo_method("notify_property_list_changed")
	_commit_action()


func _create_action(title: String) -> void:
	if _undo_redo is EditorUndoRedoManager:
		(_undo_redo as EditorUndoRedoManager).create_action(title, UndoRedo.MERGE_DISABLE, _unit)
	else:
		(_undo_redo as UndoRedo).create_action(title, UndoRedo.MERGE_DISABLE)


func _add_do_property(property: StringName, value: Variant) -> void:
	if _undo_redo is EditorUndoRedoManager:
		(_undo_redo as EditorUndoRedoManager).add_do_property(_unit, property, value)
	else:
		(_undo_redo as UndoRedo).add_do_property(_unit, property, value)


func _add_undo_property(property: StringName, value: Variant) -> void:
	if _undo_redo is EditorUndoRedoManager:
		(_undo_redo as EditorUndoRedoManager).add_undo_property(_unit, property, value)
	else:
		(_undo_redo as UndoRedo).add_undo_property(_unit, property, value)


func _add_do_method(method: StringName) -> void:
	if _undo_redo is EditorUndoRedoManager:
		Callable(_undo_redo, "add_do_method").call(_unit, method)
	else:
		(_undo_redo as UndoRedo).add_do_method(Callable(_unit, method))


func _add_undo_method(method: StringName) -> void:
	if _undo_redo is EditorUndoRedoManager:
		Callable(_undo_redo, "add_undo_method").call(_unit, method)
	else:
		(_undo_redo as UndoRedo).add_undo_method(Callable(_unit, method))


func _commit_action() -> void:
	if _undo_redo is EditorUndoRedoManager:
		(_undo_redo as EditorUndoRedoManager).commit_action()
	else:
		(_undo_redo as UndoRedo).commit_action()
