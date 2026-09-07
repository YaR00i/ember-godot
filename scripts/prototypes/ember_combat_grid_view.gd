class_name EmberCombatGridView
extends GridContainer
## Visual-only projection of EmberCombatGrid. It emits a cell choice and never
## mutates combat state, so the lab controller keeps staged movement ownership.

signal cell_chosen(cell: Vector2i, unit_id: String)

const Combat = preload("res://scripts/prototypes/ember_combat_prototype.gd")
const Grid = preload("res://scripts/prototypes/ember_combat_grid.gd")

const COLOR_HERO := Color("65cfe1")
const COLOR_ENEMY := Color("f07883")
const COLOR_WET := Color("245b73")
const COLOR_FROZEN := Color("4b71a1")
const COLOR_EMBER := Color("80513b")
const COLOR_NEUTRAL := Color("293244")

var _state: Dictionary = {}
var _selected_action := ""
var _selected_target := ""
var _pending_cell := Vector2i(-1, -1)
var _move_mode := false
var _preview: Dictionary = {}
var _secondary_cell := Combat.INVALID_CELL
var _target_cell := Combat.INVALID_CELL


func configure(
	state: Dictionary,
	selected_action: String,
	selected_target: String,
	pending_cell: Vector2i,
	move_mode: bool,
	preview: Dictionary = {},
	secondary_cell: Vector2i = Combat.INVALID_CELL,
	target_cell: Vector2i = Combat.INVALID_CELL,
) -> void:
	_state = state
	_selected_action = selected_action
	_selected_target = selected_target
	_pending_cell = pending_cell
	_move_mode = move_mode
	_preview = preview
	_secondary_cell = secondary_cell
	_target_cell = target_cell
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var grid: Dictionary = _state.get("grid", {})
	columns = maxi(1, int(grid.get("width", Grid.WIDTH)))
	add_theme_constant_override("h_separation", 5)
	add_theme_constant_override("v_separation", 5)
	var active_id := Combat.current_unit_id(_state)
	var active := Combat.unit_definition(_state, active_id)
	var active_cell: Vector2i = active.get("cell", Vector2i(-1, -1))
	var reachable := Grid.reachable_cells(_state, active_id)
	var has_staged_move := (
		_pending_cell != Vector2i(-1, -1)
		and _pending_cell != active_cell
		and _pending_cell in reachable
	)
	var valid_targets := _valid_targets_from_staged_state()
	var valid_target_cells := _valid_target_cells_from_staged_state()
	var secondary_cells := _valid_secondary_cells_from_staged_state()
	var approach_destination: Vector2i = _preview.get(
		"approachDestination", Combat.INVALID_CELL
	)
	var approach_fallback := bool(_preview.get("approachFallbackDefend", false))
	var approach_path: Array[Vector2i] = []
	for raw_cell in _preview.get("approachPath", []):
		if raw_cell is Vector2i:
			approach_path.append(raw_cell)
	for y in int(grid.get("height", Grid.HEIGHT)):
		for x in int(grid.get("width", Grid.WIDTH)):
			var cell := Vector2i(x, y)
			var actual_occupant := Grid.occupant_id(_state, cell)
			var staged_origin := has_staged_move and cell == active_cell
			var staged_destination := has_staged_move and cell == _pending_cell
			var display_occupant := active_id if staged_destination else actual_occupant
			if staged_origin:
				display_occupant = ""
			var button := Button.new()
			button.name = "CombatCell_%d_%d" % [x, y]
			button.custom_minimum_size = Vector2(105, 69)
			button.add_theme_font_size_override("font_size", 12)
			button.text = _cell_text(
				cell, display_occupant, staged_origin, staged_destination, active_id
			)
			if cell == approach_destination:
				button.text += "\n%s · СТОП" % ("◆ ЗАЩИТА" if approach_fallback else "⚔ АТАКА")
			elif cell in approach_path:
				button.text += "\n· маршрут"
			button.tooltip_text = _cell_tooltip(
				cell, display_occupant, staged_origin, staged_destination
			)
			var background := _cell_color(cell)
			var border := background.lightened(0.28)
			if cell == approach_destination:
				border = Color("b5a5ff") if approach_fallback else Color("79d8a3")
			elif staged_destination:
				border = Color("ffd76d")
			elif _is_changed_cell(cell):
				border = Color("bceaff")
			elif display_occupant == _selected_target:
				border = Color.WHITE
			elif cell == _target_cell:
				border = Color("f4d06f")
			elif cell in valid_target_cells:
				border = Color("cfad55")
			elif cell == _secondary_cell:
				border = Color("ffc85a")
			elif cell in secondary_cells:
				border = Color("b98232")
			elif display_occupant == active_id:
				border = COLOR_HERO
			elif _move_mode and cell in reachable and actual_occupant.is_empty() and not Grid.is_focus_cell(_state, cell):
				border = Color("82e6a3")
			button.add_theme_stylebox_override("normal", _style(background.darkened(0.26), border, 2))
			button.add_theme_stylebox_override("hover", _style(background.darkened(0.05), Color.WHITE, 2))
			button.add_theme_stylebox_override("pressed", _style(background.lightened(0.08), Color.WHITE, 3))
			button.add_theme_stylebox_override("disabled", _style(background.darkened(0.16), border.darkened(0.12), 1))
			button.add_theme_color_override("font_color", Color("e7edf7"))
			button.add_theme_color_override("font_hover_color", Color.WHITE)
			button.add_theme_color_override("font_disabled_color", Color("aeb9cb"))
			if _move_mode:
				button.disabled = (
					cell not in reachable
					or (not actual_occupant.is_empty() and actual_occupant != active_id)
					or Grid.is_focus_cell(_state, cell)
				)
			elif not valid_target_cells.is_empty():
				button.disabled = cell not in valid_target_cells
			elif not secondary_cells.is_empty():
				button.disabled = cell not in secondary_cells
			else:
				button.disabled = display_occupant.is_empty() or display_occupant not in valid_targets
			button.pressed.connect(_emit_cell.bind(cell, display_occupant))
			add_child(button)


func _valid_targets_from_staged_state() -> Array[String]:
	if _selected_action.is_empty():
		return []
	if _preview.has("validTargetIds"):
		var preview_targets: Array[String] = []
		for raw_id in _preview.get("validTargetIds", []):
			preview_targets.append(str(raw_id))
		return preview_targets
	return Grid.approach_target_ids(_state, _selected_action, _pending_cell)


func _valid_secondary_cells_from_staged_state() -> Array[Vector2i]:
	if _selected_target.is_empty():
		return []
	var staged := Grid.stage_move(_state, _pending_cell)
	if staged.is_empty():
		return []
	return Combat.valid_secondary_cells(staged, _selected_action, _selected_target)


func _valid_target_cells_from_staged_state() -> Array[Vector2i]:
	if _selected_action.is_empty():
		return []
	var staged := Grid.stage_move(_state, _pending_cell)
	if staged.is_empty():
		return []
	return Combat.valid_target_cells(staged, _selected_action)


func _cell_text(
	cell: Vector2i,
	occupant_id: String,
	staged_origin: bool,
	staged_destination: bool,
	active_id: String,
) -> String:
	var lines: Array[String] = [Grid.cell_label(cell)]
	var cell_def := _projected_cell_definition(cell)
	var elevation := int(cell_def.get("elevation", 0))
	if elevation > 0:
		lines.append("Высота +%d" % elevation)
	if bool(cell_def.get("blocked", false)):
		lines.append("▲ преграда")
	elif Grid.is_focus_cell(_state, cell):
		lines.append("◆ Жар-фокус")
	if not occupant_id.is_empty():
		var unit := Combat.unit_definition(_state, occupant_id)
		lines.append("▶ %s · план" % str(unit.get("name", occupant_id)) if staged_destination else str(unit.get("name", occupant_id)))
		lines.append("HP %d/%d%s" % [
			int(unit.get("hp", 0)), int(unit.get("maxHp", 0)), " · ждёт F" if staged_destination else "",
		])
	else:
		if "frozen" in cell_def.get("tags", []):
			lines.append("Frozen%s" % (" · прогноз" if _is_changed_cell(cell) else ""))
		elif "wet" in cell_def.get("tags", []):
			lines.append("Wet")
		elif str(cell_def.get("group", "")) == Grid.active_focus_group(_state):
			lines.append("Жар +2")
	if staged_origin:
		var active := Combat.unit_definition(_state, active_id)
		lines.append("↗ %s → %s" % [
			str(active.get("name", active_id)), Grid.cell_label(_pending_cell),
		])
	return "\n".join(lines)


func _cell_tooltip(
	cell: Vector2i,
	occupant_id: String,
	staged_origin: bool,
	staged_destination: bool,
) -> String:
	var cell_def := _projected_cell_definition(cell)
	var parts: Array[String] = ["Клетка %s" % Grid.cell_label(cell)]
	parts.append("Высота: +%d" % int(cell_def.get("elevation", 0)))
	if bool(cell_def.get("blocked", false)):
		parts.append("Непроходимая")
	var group := str(cell_def.get("group", ""))
	if group == "tide":
		parts.append("Связанная синяя панель: Wet проводит молнию")
	elif group == "ember":
		parts.append("Связанная янтарная панель: Жар-фокус усиливает огонь")
	if Grid.is_focus_cell(_state, cell):
		parts.append("Жар-фокус · источник общего правила панели")
	if _is_changed_cell(cell):
		parts.append("Это состояние поверхности будет применено только после F.")
	if not occupant_id.is_empty():
		var unit := Combat.unit_definition(_state, occupant_id)
		parts.append("%s · HP %d/%d" % [
			str(unit.get("name", occupant_id)),
			int(unit.get("hp", 0)), int(unit.get("maxHp", 0)),
		])
	if staged_origin:
		parts.append("Исходная позиция до подтверждения.")
	elif staged_destination:
		parts.append("Предпросмотр новой позиции; состояние изменится после F.")
	return "\n".join(parts)


func _cell_color(cell: Vector2i) -> Color:
	var definition := _projected_cell_definition(cell)
	if bool(definition.get("blocked", false)):
		return Color("34343d")
	var color := COLOR_NEUTRAL
	if "frozen" in definition.get("tags", []):
		color = COLOR_FROZEN
	else:
		match str(definition.get("group", "")):
			"tide": color = COLOR_WET
			"ember": color = COLOR_EMBER
			_: color = COLOR_NEUTRAL
	return color.lightened(0.08 * float(int(definition.get("elevation", 0))))


func _projected_cell_definition(cell: Vector2i) -> Dictionary:
	var definition := Grid.cell_definition(_state, cell)
	var changes: Dictionary = _preview.get("cellChanges", {})
	var patch: Dictionary = changes.get(Grid.cell_key(cell), {})
	for raw_field in patch:
		var field := str(raw_field)
		if field != "cell":
			definition[field] = patch[raw_field]
	return definition


func _is_changed_cell(cell: Vector2i) -> bool:
	return (_preview.get("cellChanges", {}) as Dictionary).has(Grid.cell_key(cell))


func _emit_cell(cell: Vector2i, occupant_id: String) -> void:
	cell_chosen.emit(cell, occupant_id)


func _style(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.border_width_left = width
	style.border_width_top = width
	style.border_width_right = width
	style.border_width_bottom = width
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	return style
