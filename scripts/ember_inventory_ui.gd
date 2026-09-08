class_name EmberInventoryUi
extends Control
## Keyboard inventory/equipment overlay. It owns presentation/selection only;
## EmberExploreState owns every item, slot mutation and save.

const MODE_BAG := "bag"
const MODE_EQUIPMENT := "equipment"
const PartyState := preload("res://scripts/ember_party_state.gd")

var progress_state: EmberExploreState
var _mode := MODE_BAG
var _bag_index := 0
var _slot_index := 0
var _hero_index := 0
var _strategy_index := 0
var _strategy_draft: Array[String] = []
var _strategy_signature := ""
var _feedback := ""
var _view: Dictionary = {}
var _title: Label
var _stats: Label
var _equipment: Label
var _bag: Label
var _detail: Label
var _help: Label
var _hero_buttons: Array[Button] = []
var _strategy_rows: VBoxContainer
var _strategy_save: Button


func _ready() -> void:
	if progress_state == null:
		progress_state = get_node_or_null("/root/EmberExploreProgress") as EmberExploreState
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_panel()
	if progress_state and not progress_state.progress_changed.is_connected(_on_progress_changed):
		progress_state.progress_changed.connect(_on_progress_changed)
	visible = false


func _exit_tree() -> void:
	if progress_state and progress_state.progress_changed.is_connected(_on_progress_changed):
		progress_state.progress_changed.disconnect(_on_progress_changed)


func open() -> void:
	if progress_state == null:
		return
	var active_index := PartyState.HERO_IDS.find(progress_state.exploration_leader_id)
	_hero_index = active_index if active_index >= 0 else 0
	_mode = MODE_BAG
	_bag_index = 0
	_slot_index = 0
	_strategy_index = 0
	_strategy_draft = progress_state.combat_strategy_snapshot()
	_feedback = ""
	visible = true
	_refresh()


func close() -> void:
	visible = false
	_feedback = ""


func toggle() -> void:
	if is_open():
		close()
	else:
		open()


func is_open() -> bool:
	return visible


func blocks_movement() -> bool:
	return is_open()


func confirm() -> void:
	if not is_open() or progress_state == null:
		return
	var result: Dictionary
	if _mode == MODE_EQUIPMENT:
		result = progress_state.unequip_slot_for_member(_hero_id(), EmberEquipment.SLOTS[_slot_index])
	else:
		var rows := _bag_rows()
		if rows.is_empty():
			_feedback = "Сумка пуста"
			_refresh()
			return
		var row: Dictionary = rows[_bag_index]
		if bool(row.get("canUse", false)):
			result = progress_state.use_item_on_member(_hero_id(), str(row.get("itemId", "")))
			if bool(result.get("ok", false)):
				var effects: Array[String] = []
				var gained := int(result.get("gained", 0))
				var gained_mp := int(result.get("gainedMp", 0))
				if gained > 0:
					effects.append("+%d HP" % gained)
				if gained_mp > 0:
					effects.append("+%d MP" % gained_mp)
				_feedback = " · ".join(effects) if not effects.is_empty() else "Нет эффекта"
			else:
				_feedback = EmberEquipment.failure_ru(str(result.get("reason", "")))
			_refresh()
			return
		if not bool(row.get("canEquip", false)):
			_feedback = "У предмета нет действия"
			_refresh()
			return
		result = progress_state.equip_item_for_member(_hero_id(), str(row.get("itemId", "")))
	_feedback = "Готово" if bool(result.get("ok", false)) else EmberEquipment.failure_ru(str(result.get("reason", "")))
	_refresh()


func select_item(item_id: String) -> bool:
	var rows := _bag_rows()
	for index in range(rows.size()):
		if str(rows[index].get("itemId", "")) == item_id:
			_mode = MODE_BAG
			_bag_index = index
			_refresh()
			return true
	return false


func view_state() -> Dictionary:
	return {
		"open": is_open(),
		"mode": _mode,
		"bagIndex": _bag_index,
		"slotIndex": _slot_index,
		"heroId": _hero_id(),
		"equipment": _equipment.text if _equipment else "",
		"bag": _bag.text if _bag else "",
		"detail": _detail.text if _detail else "",
		"feedback": _feedback,
		"strategyDraft": _strategy_draft.duplicate(),
		"strategyIndex": _strategy_index,
		"savedStrategy": progress_state.combat_strategy_snapshot() if progress_state else [],
	}


func _on_progress_changed() -> void:
	if is_open():
		_refresh()


func _refresh() -> void:
	if progress_state == null:
		return
	_view = progress_state.inventory_view_for_member(_hero_id())
	var rows := _bag_rows()
	_bag_index = clampi(_bag_index, 0, maxi(0, rows.size() - 1))
	_slot_index = clampi(_slot_index, 0, EmberEquipment.SLOTS.size() - 1)
	_title.text = "ИНВЕНТАРЬ · %s" % str(_view.get("nameRu", _hero_id()))
	_stats.text = "Ур. %d · XP %d  ·  HP %d/%d  ·  MP %d/%d  ·  atk %d  ·  def %d  ·  арена %d" % [
		int(_view.get("level", 1)),
		int(_view.get("xp", 0)),
		roundi(float(_view.get("hp", 0.0))),
		roundi(float(_view.get("maxHp", 0.0))),
		roundi(float(_view.get("mp", 0.0))),
		roundi(float(_view.get("maxMp", 0.0))),
		int(_view.get("atk", 4)),
		int(_view.get("def", 0)),
		int(_view.get("arenaAtk", 4)),
	]
	var party_views := progress_state.party_view()
	for index in _hero_buttons.size():
		var button := _hero_buttons[index]
		var hero_id := PartyState.HERO_IDS[index]
		var member: Dictionary = party_views[index] if index < party_views.size() else {}
		var selected := index == _hero_index
		button.text = "%s%s" % ["▶ " if selected else "", str(member.get("nameRu", hero_id))]
		button.button_pressed = selected
		button.add_theme_color_override("font_color", Color("182234") if selected else Color("e9eef8"))
	_refresh_equipment()
	_refresh_bag(rows)
	_refresh_strategy()
	_refresh_detail(rows)


func _refresh_strategy() -> void:
	if _strategy_rows == null:
		return
	var party_names := {}
	for member in progress_state.party_view():
		party_names[str(member.get("heroId", ""))] = str(member.get("nameRu", ""))
	_strategy_index = clampi(_strategy_index, 0, maxi(0, _strategy_draft.size() - 1))
	var signature := "%s|%d|%s" % [_strategy_draft, _strategy_index, party_names]
	_strategy_save.disabled = _strategy_draft == progress_state.combat_strategy_snapshot()
	if signature == _strategy_signature:
		return
	_strategy_signature = signature
	for child in _strategy_rows.get_children():
		child.queue_free()
	for index in _strategy_draft.size():
		var hero_id := _strategy_draft[index]
		var row := Button.new()
		row.name = "InventoryStrategyHero_%s" % hero_id
		row.text = "%s%d. %s" % ["▶ " if index == _strategy_index else "", index + 1, party_names.get(hero_id, hero_id)]
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.pressed.connect(_select_strategy_row.bind(index))
		_strategy_rows.add_child(row)


func _select_strategy_row(index: int) -> void:
	_strategy_index = clampi(index, 0, maxi(0, _strategy_draft.size() - 1))
	_refresh()


func move_strategy_hero(delta: int) -> bool:
	if _strategy_draft.is_empty() or delta == 0:
		return false
	var target := clampi(_strategy_index + delta, 0, _strategy_draft.size() - 1)
	if target == _strategy_index:
		return false
	var hero_id := _strategy_draft[_strategy_index]
	_strategy_draft.remove_at(_strategy_index)
	_strategy_draft.insert(target, hero_id)
	_strategy_index = target
	_feedback = "Порядок изменён — подтвердите сохранение."
	_refresh()
	return true


func save_strategy() -> bool:
	if progress_state == null:
		return false
	var previous := progress_state.combat_strategy_snapshot()
	progress_state.set_battle_strategy(_strategy_draft)
	if not progress_state.save_slot(progress_state.active_slot):
		progress_state.set_battle_strategy(previous)
		_feedback = "Не удалось сохранить стратегию."
		_refresh()
		return false
	_strategy_draft = progress_state.combat_strategy_snapshot()
	_feedback = "Стратегия сохранена."
	_refresh()
	return true


func _refresh_equipment() -> void:
	var eq: Dictionary = _view.get("equipment", {})
	var items := EmberInteractionContent.item_definitions()
	var lines: Array[String] = []
	for index in range(EmberEquipment.SLOTS.size()):
		var slot := EmberEquipment.SLOTS[index]
		var marker := "▶" if _mode == MODE_EQUIPMENT and index == _slot_index else " "
		var raw_id: Variant = eq.get(slot, null)
		var item_id := str(raw_id) if raw_id != null else ""
		var item: Dictionary = items.get(item_id, {})
		var name := str(item.get("nameRu", item_id)) if not item_id.is_empty() else "—"
		lines.append("%s %-10s  %s" % [marker, EmberEquipment.SLOT_LABELS[slot], name])
	_equipment.text = "ЭКИПИРОВКА%s\n\n%s" % [
		"  [выбрано]" if _mode == MODE_EQUIPMENT else "",
		"\n".join(lines),
	]


func _refresh_bag(rows: Array) -> void:
	var lines: Array[String] = []
	for index in range(rows.size()):
		var row: Dictionary = rows[index]
		var marker := "▶" if _mode == MODE_BAG and index == _bag_index else " "
		var tag := ""
		if bool(row.get("canEquip", false)):
			tag = " · надеть"
		elif int(row.get("hpRestore", 0)) > 0:
			tag = " · HP +%d" % int(row.get("hpRestore", 0))
		elif int(row.get("mpRestore", 0)) > 0:
			tag = " · MP +%d" % int(row.get("mpRestore", 0))
		elif int(row.get("reviveHp", 0)) > 0:
			tag = " · воскрешение"
		lines.append("%s %s ×%d%s" % [
			marker,
			str(row.get("nameRu", row.get("itemId", "?"))),
			int(row.get("count", 0)),
			tag,
		])
	if lines.is_empty():
		lines.append("Сумка пуста")
	_bag.text = "СУМКА%s\n\n%s" % [
		"  [выбрано]" if _mode == MODE_BAG else "",
		"\n".join(lines),
	]


func _refresh_detail(rows: Array) -> void:
	var text := _feedback
	if _mode == MODE_EQUIPMENT:
		text = "F — снять предмет из выбранного слота" if text.is_empty() else text
	elif not rows.is_empty():
		var row: Dictionary = rows[_bag_index]
		var stats: Array[String] = []
		if int(row.get("atk", 0)) != 0:
			stats.append("atk %d" % int(row.get("atk", 0)))
		if int(row.get("def", 0)) != 0:
			stats.append("def %d" % int(row.get("def", 0)))
		if int(row.get("hpRestore", 0)) > 0:
			stats.append("HP +%d" % int(row.get("hpRestore", 0)))
		if int(row.get("mpRestore", 0)) > 0:
			stats.append("MP +%d" % int(row.get("mpRestore", 0)))
		if int(row.get("reviveHp", 0)) > 0:
			stats.append("воскрешение: %d HP" % int(row.get("reviveHp", 0)))
		text = str(row.get("nameRu", ""))
		if not stats.is_empty():
			text += "  ·  %s" % "  ·  ".join(stats)
		if not _feedback.is_empty():
			text += "\n%s" % _feedback
	_detail.text = text
	_help.text = "Q/E — герой · A/D — экипировка/сумка · W/S — выбор · F — использовать/надеть/снять · Стратегия: строка, ↑/↓, Сохранить · I или Esc — закрыть"


func _bag_rows() -> Array:
	var raw: Variant = _view.get("items", [])
	return raw if typeof(raw) == TYPE_ARRAY else []


func _move_selection(delta: int) -> void:
	_feedback = ""
	if _mode == MODE_EQUIPMENT:
		_slot_index = posmod(_slot_index + delta, EmberEquipment.SLOTS.size())
	else:
		var rows := _bag_rows()
		if rows.is_empty():
			return
		_bag_index = posmod(_bag_index + delta, rows.size())
	_refresh()


func _set_mode(mode: String) -> void:
	if mode != MODE_BAG and mode != MODE_EQUIPMENT:
		return
	_mode = mode
	_feedback = ""
	_refresh()


func _hero_id() -> String:
	return PartyState.HERO_IDS[clampi(_hero_index, 0, PartyState.HERO_IDS.size() - 1)]


func _select_hero(index: int) -> void:
	_hero_index = posmod(index, PartyState.HERO_IDS.size())
	if progress_state != null:
		progress_state.set_exploration_leader(_hero_id())
	_feedback = ""
	_refresh()


func select_next_hero() -> String:
	if not is_open():
		return _hero_id()
	_select_hero(_hero_index + 1)
	return _hero_id()


func _input(event: InputEvent) -> void:
	# Q/E must work even while a hero Button owns GUI focus. `_unhandled_input`
	# runs too late for that case. In the world Q still belongs to the journal.
	if not is_open() or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if key.pressed and not key.echo and key.physical_keycode in [KEY_Q, KEY_E]:
		_select_hero(_hero_index + (1 if key.physical_keycode == KEY_E else -1))
		get_viewport().set_input_as_handled()


func _build_panel() -> void:
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0.025, 0.016, 0.045, 0.96)
	backdrop.anchor_left = 0.12
	backdrop.anchor_top = 0.12
	backdrop.anchor_right = 0.88
	backdrop.anchor_bottom = 0.88
	add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 26)
	backdrop.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	_title = Label.new()
	_title.text = "ИНВЕНТАРЬ"
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_color_override("font_color", Color(1.0, 0.78, 0.34))
	column.add_child(_title)
	var hero_row := HBoxContainer.new()
	hero_row.add_theme_constant_override("separation", 8)
	column.add_child(hero_row)
	var party_views := progress_state.party_view() if progress_state != null else []
	for index in PartyState.HERO_IDS.size():
		var hero_id := PartyState.HERO_IDS[index]
		var member: Dictionary = party_views[index] if index < party_views.size() else {}
		var hero_button := Button.new()
		hero_button.name = "InventoryHero_%s" % hero_id
		hero_button.text = str(member.get("nameRu", hero_id))
		hero_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hero_button.toggle_mode = true
		hero_button.tooltip_text = "Выбрать героя; Q/E переключают назад/вперёд"
		var selected_style := StyleBoxFlat.new()
		selected_style.bg_color = Color("ffc85a")
		selected_style.border_color = Color("fff0b0")
		selected_style.set_border_width_all(2)
		selected_style.set_corner_radius_all(7)
		hero_button.add_theme_stylebox_override("pressed", selected_style)
		hero_button.add_theme_stylebox_override("hover_pressed", selected_style)
		hero_button.pressed.connect(_select_hero.bind(index))
		hero_row.add_child(hero_button)
		_hero_buttons.append(hero_button)
	_stats = Label.new()
	_stats.add_theme_font_size_override("font_size", 18)
	column.add_child(_stats)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 30)
	column.add_child(columns)
	_equipment = Label.new()
	_equipment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_equipment.add_theme_font_size_override("font_size", 18)
	columns.add_child(_equipment)
	_bag = Label.new()
	_bag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bag.add_theme_font_size_override("font_size", 18)
	columns.add_child(_bag)
	var strategy_panel := VBoxContainer.new()
	strategy_panel.name = "InventoryStrategySection"
	strategy_panel.custom_minimum_size = Vector2(250, 0)
	strategy_panel.add_theme_constant_override("separation", 6)
	columns.add_child(strategy_panel)
	var strategy_title := Label.new()
	strategy_title.text = "СТРАТЕГИЯ"
	strategy_title.add_theme_font_size_override("font_size", 18)
	strategy_panel.add_child(strategy_title)
	_strategy_rows = VBoxContainer.new()
	_strategy_rows.add_theme_constant_override("separation", 3)
	strategy_panel.add_child(_strategy_rows)
	var strategy_controls := HBoxContainer.new()
	strategy_controls.add_theme_constant_override("separation", 5)
	strategy_panel.add_child(strategy_controls)
	var strategy_up := Button.new()
	strategy_up.name = "InventoryStrategyUp"
	strategy_up.text = "↑"
	strategy_up.tooltip_text = "Поднять выбранного героя"
	strategy_up.pressed.connect(move_strategy_hero.bind(-1))
	strategy_controls.add_child(strategy_up)
	var strategy_down := Button.new()
	strategy_down.name = "InventoryStrategyDown"
	strategy_down.text = "↓"
	strategy_down.tooltip_text = "Опустить выбранного героя"
	strategy_down.pressed.connect(move_strategy_hero.bind(1))
	strategy_controls.add_child(strategy_down)
	_strategy_save = Button.new()
	_strategy_save.name = "InventoryStrategySave"
	_strategy_save.text = "Сохранить"
	_strategy_save.tooltip_text = "Сохранить порядок в текущий слот"
	_strategy_save.pressed.connect(save_strategy)
	_strategy_save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strategy_controls.add_child(_strategy_save)
	_detail = Label.new()
	_detail.add_theme_font_size_override("font_size", 17)
	_detail.add_theme_color_override("font_color", Color(0.88, 0.91, 1.0))
	column.add_child(_detail)
	_help = Label.new()
	_help.add_theme_font_size_override("font_size", 15)
	_help.add_theme_color_override("font_color", Color(0.68, 0.66, 0.72))
	column.add_child(_help)


func _unhandled_input(event: InputEvent) -> void:
	if not is_open() or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()
		KEY_A, KEY_LEFT:
			_set_mode(MODE_EQUIPMENT)
			get_viewport().set_input_as_handled()
		KEY_D, KEY_RIGHT:
			_set_mode(MODE_BAG)
			get_viewport().set_input_as_handled()
		KEY_W, KEY_UP:
			_move_selection(-1)
			get_viewport().set_input_as_handled()
		KEY_S, KEY_DOWN:
			_move_selection(1)
			get_viewport().set_input_as_handled()
