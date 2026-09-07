@tool
class_name EmberCombatActionInspectorPanel
extends VBoxContainer
## Visual summary for the canonical action Resource. Native Inspector fields
## remain the writer; this panel also composes shared effect Resources.

const EffectCatalog := preload("res://scripts/prototypes/ember_combat_effect_catalog.gd")
const VisualPopup := preload("res://addons/ember_import/ember_visual_library_popup.gd")

var _action: EmberCombatActionResource
var _editor_interface: EditorInterface
var _undo_redo: Object
var _portrait: TextureRect
var _swatch: ColorRect
var _summary: Label
var _validation: Label
var _effects: VBoxContainer
var _effect_popup: EmberVisualLibraryPopup


func setup(
	action: EmberCombatActionResource,
	editor_interface: EditorInterface = null,
	undo_redo: Object = null,
) -> void:
	_action = action
	_editor_interface = editor_interface
	_undo_redo = undo_redo
	name = "CombatActionOverview"
	add_theme_constant_override("separation", 7)
	var title := Label.new()
	title.text = "БОЕВОЕ ДЕЙСТВИЕ"
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
	_portrait.name = "CombatActionIcon"
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visual.add_child(_portrait)
	_swatch = ColorRect.new()
	_swatch.name = "CombatActionSwatch"
	_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.add_child(_swatch)
	_summary = Label.new()
	_summary.name = "CombatActionSummary"
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_summary)
	_validation = Label.new()
	_validation.name = "CombatActionValidation"
	_validation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_validation)
	_effects = VBoxContainer.new()
	_effects.name = "CombatActionEffectEditor"
	_effects.add_theme_constant_override("separation", 4)
	add_child(_effects)
	var hint_label := Label.new()
	hint_label.text = "Готовый preset сохраняет старые приёмы, а библиотечные эффекты добавляются по порядку и исполняются тем же resolver."
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.modulate = Color(0.62, 0.72, 0.82)
	hint_label.add_theme_font_size_override("font_size", 12)
	add_child(hint_label)
	if not _action.changed.is_connected(_refresh):
		_action.changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	if _action != null and _action.changed.is_connected(_refresh):
		_action.changed.disconnect(_refresh)


func _refresh() -> void:
	if _action == null:
		return
	_portrait.texture = _action.icon
	_swatch.color = _action.ui_color
	_swatch.visible = _action.icon == null
	var throw_copy := (
		" · бросок %d · вес ≤%d" % [_action.throw_range_cells, _action.max_lift_weight]
		if _action.effect == EmberCombatActionResource.Effect.LIFT_THROW
		else ""
	)
	var force_copy := " · толчок %d" % _action.force if _action.force > 0 else ""
	var partner_copy := (
		"\nПартнёр: %s · радиус %d · MP %d · задержка %d" % [
			_action.partner_unit_id, _action.partner_range_cells,
			_action.partner_mp_cost, _action.partner_delay,
		]
		if not _action.partner_unit_id.is_empty()
		else ""
	)
	var steps_copy: Array[String] = []
	for step in _action.effect_steps:
		if step != null:
			steps_copy.append(str(step.get("display_name")))
	_summary.text = "%s\n%s · %s · %s\n%s → %s\nСила %d · %s · MP %d · точность %+d%%\nДальность %d%s%s · задержка %d%s\n%s\nУсловия: %s" % [
		_action.display_name,
		_action.action_id,
		_action.menu_group_label(),
		_action.element_label(),
		_action.effect_label(),
		_action.target_label(),
		_action.power,
		_action.scaling_label(),
		_action.mp_cost,
		_action.accuracy_modifier,
		_action.range_cells,
		throw_copy,
		force_copy,
		_action.delay,
		partner_copy,
		_action.hint,
		_action.requirements_text,
	]
	if not steps_copy.is_empty():
		_summary.text += "\nЦепочка: %s" % " → ".join(steps_copy)
	var errors := _action.validation_errors()
	_validation.text = "✓ Действие готово" if errors.is_empty() else "⚠ " + "\n⚠ ".join(errors)
	_validation.modulate = Color("79d99a") if errors.is_empty() else Color("ff8d78")
	_rebuild_effect_editor()


func _rebuild_effect_editor() -> void:
	if _effects == null or _action == null:
		return
	for child in _effects.get_children():
		_effects.remove_child(child)
		child.free()
	var heading := Label.new()
	heading.text = "ЭФФЕКТЫ ПО ПОРЯДКУ"
	heading.modulate = Color(0.70, 0.76, 0.86)
	heading.add_theme_font_size_override("font_size", 12)
	_effects.add_child(heading)
	if _action.effect_steps.is_empty():
		var empty := Label.new()
		empty.text = "Нет дополнительных шагов; работает выбранный готовый preset."
		empty.modulate = Color(0.62, 0.68, 0.76)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_effects.add_child(empty)
	for index in _action.effect_steps.size():
		var effect := _action.effect_steps[index]
		var row := HBoxContainer.new()
		row.name = "CombatActionEffect_%d" % index
		row.add_theme_constant_override("separation", 4)
		_effects.add_child(row)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(18, 34)
		swatch.color = effect.get("ui_color") if effect != null else Color("8a3f4d")
		row.add_child(swatch)
		var open := Button.new()
		open.text = (
			"%s · %s" % [str(effect.get("display_name")), str(effect.call("operation_label"))]
			if effect != null
			else "⚠ Пустая ссылка"
		)
		open.tooltip_text = str(effect.get("description")) if effect != null else "Удалите пустую ссылку."
		open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		open.disabled = effect == null or _editor_interface == null
		open.pressed.connect(_open_effect.bind(effect))
		row.add_child(open)
		for direction in [-1, 1]:
			var move := Button.new()
			move.text = "↑" if direction < 0 else "↓"
			move.tooltip_text = "Изменить порядок выполнения. Ctrl+Z отменяет."
			move.disabled = _undo_redo == null or index + direction < 0 or index + direction >= _action.effect_steps.size()
			move.pressed.connect(_move_effect.bind(index, direction))
			row.add_child(move)
		var remove := Button.new()
		remove.text = "×"
		remove.tooltip_text = "Убрать эффект из действия. Ctrl+Z отменяет."
		remove.disabled = _undo_redo == null
		remove.modulate = Color(1.0, 0.56, 0.52)
		remove.pressed.connect(_remove_effect.bind(index))
		row.add_child(remove)
	var add := Button.new()
	add.name = "CombatActionAddEffect"
	add.text = "+ Добавить эффект из библиотеки…"
	add.disabled = _undo_redo == null or _available_effects().is_empty()
	add.pressed.connect(_open_effect_library)
	_effects.add_child(add)


func _open_effect(effect: Resource) -> void:
	if _editor_interface != null and effect != null:
		_editor_interface.edit_resource(effect)


func _open_effect_library() -> void:
	EffectCatalog.refresh()
	if _effect_popup == null:
		_effect_popup = VisualPopup.new() as EmberVisualLibraryPopup
		_effect_popup.name = "CombatEffectLibraryPopup"
		_effect_popup.value_chosen.connect(_add_effect)
		add_child(_effect_popup)
	var entries: Array[Dictionary] = []
	for effect in _available_effects():
		entries.append({
			"id": str(effect.get("effect_id")),
			"label": "%s\n%s" % [str(effect.get("display_name")), str(effect.get("effect_id"))],
			"tooltip": "%s\n%s" % [str(effect.call("operation_label")), str(effect.get("description"))],
			"texture": _effect_texture(effect),
		})
	_effect_popup.open_library("БИБЛИОТЕКА ЭФФЕКТОВ", entries, "", Vector2i(64, 64), 155)


func _available_effects() -> Array[Resource]:
	var result: Array[Resource] = []
	var assigned := {}
	for effect in _action.effect_steps:
		if effect != null:
			assigned[str(effect.get("effect_id"))] = true
	for effect in EffectCatalog.resources():
		if not assigned.has(str(effect.get("effect_id"))):
			result.append(effect)
	return result


func _effect_texture(effect: Resource) -> Texture2D:
	if effect == null:
		return null
	var icon := effect.get("icon") as Texture2D
	if icon != null:
		return icon
	var image := Image.create_empty(48, 48, false, Image.FORMAT_RGBA8)
	image.fill(effect.get("ui_color") as Color)
	return ImageTexture.create_from_image(image)


func _add_effect(effect_id: String) -> void:
	var effect := EffectCatalog.resource(effect_id)
	if effect == null:
		return
	var next := _action.effect_steps.duplicate()
	for assigned in next:
		if assigned != null and str(assigned.get("effect_id")) == effect_id:
			return
	next.append(effect)
	_commit_effects(next, "Добавить эффект действию")


func _remove_effect(index: int) -> void:
	if index < 0 or index >= _action.effect_steps.size():
		return
	var next := _action.effect_steps.duplicate()
	next.remove_at(index)
	_commit_effects(next, "Убрать эффект из действия")


func _move_effect(index: int, direction: int) -> void:
	var next := _action.effect_steps.duplicate()
	var target := index + direction
	if index < 0 or index >= next.size() or target < 0 or target >= next.size():
		return
	var value = next[index]
	next[index] = next[target]
	next[target] = value
	_commit_effects(next, "Изменить порядок эффектов")


func _commit_effects(next: Array[Resource], title: String) -> void:
	if _action == null or _undo_redo == null or _action.effect_steps == next:
		return
	var previous := _action.effect_steps.duplicate()
	if _undo_redo is EditorUndoRedoManager:
		(_undo_redo as EditorUndoRedoManager).create_action(title, UndoRedo.MERGE_DISABLE, _action)
		(_undo_redo as EditorUndoRedoManager).add_do_property(_action, "effect_steps", next)
		Callable(_undo_redo, "add_do_method").call(_action, "emit_changed")
		Callable(_undo_redo, "add_do_method").call(_action, "notify_property_list_changed")
		(_undo_redo as EditorUndoRedoManager).add_undo_property(_action, "effect_steps", previous)
		Callable(_undo_redo, "add_undo_method").call(_action, "emit_changed")
		Callable(_undo_redo, "add_undo_method").call(_action, "notify_property_list_changed")
		(_undo_redo as EditorUndoRedoManager).commit_action()
	else:
		(_undo_redo as UndoRedo).create_action(title, UndoRedo.MERGE_DISABLE)
		(_undo_redo as UndoRedo).add_do_property(_action, "effect_steps", next)
		(_undo_redo as UndoRedo).add_do_method(Callable(_action, "emit_changed"))
		(_undo_redo as UndoRedo).add_do_method(Callable(_action, "notify_property_list_changed"))
		(_undo_redo as UndoRedo).add_undo_property(_action, "effect_steps", previous)
		(_undo_redo as UndoRedo).add_undo_method(Callable(_action, "emit_changed"))
		(_undo_redo as UndoRedo).add_undo_method(Callable(_action, "notify_property_list_changed"))
		(_undo_redo as UndoRedo).commit_action()
