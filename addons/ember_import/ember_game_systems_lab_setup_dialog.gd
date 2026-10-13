@tool
extends ConfirmationDialog
## Local test setup and named editor presets. Gameplay Resources stay unchanged.
const Setup = preload("res://scripts/prototypes/ember_combat_lab_setup.gd")
const Units = preload("res://scripts/prototypes/ember_combat_unit_catalog.gd")
const Items = preload("res://scripts/ember_item_catalog.gd")
const Presets = preload("res://addons/ember_import/ember_game_systems_lab_preset_store.gd")
signal launch_requested(setup: Dictionary)
var _encounter: EmberEncounterResource
var _setup := {}
var _hero_id := ""
var _items := {}
var _units := {}
var _history: Array[Dictionary] = []
var _cursor := 0
var _body: VBoxContainer
var _feedback: Label
var _undo: Button
var _redo: Button
var _stats: Label
var _stats_note: Label
var _scroll: ScrollContainer
var _layout: VBoxContainer
var preset_store = Presets.new()
var _preset_picker: OptionButton
var _preset_name: LineEdit
var _preset_note: Label
var _preset_load: Button
var _preset_save: Button
var _preset_update: Button
var _preset_delete: Button
var _preset_restore: Button
var _preset_rows: Array = []
var _preset_hash := ""
var _preset_id := ""
var _preset_error := ""
var _deleted_hash := ""
var _deleted_id := ""

func _ready() -> void:
	name = "GameSystemsLabSetup"
	wrap_controls = false
	min_size = Vector2i(800, 580)
	title = "Тестовый отряд и сумка"
	ok_button_text = "Запустить тест"
	cancel_button_text = "Отмена"
	dialog_hide_on_ok = false
	var root := VBoxContainer.new()
	_layout = root
	add_child(root)
	root.add_child(_label("Настройки действуют только в тесте. Состав встречи сохраняется. Отключённые герои используют сохранённые карточки без пересчёта."))
	_build_presets(root)
	var toolbar := HBoxContainer.new()
	root.add_child(toolbar)
	_undo = _button("Отменить", "LabSetupUndo", undo, toolbar)
	_redo = _button("Повторить", "LabSetupRedo", redo, toolbar)
	_button("По карточкам · пустая сумка", "LabSetupReset", func() -> void: _commit({}), toolbar)
	var scroll := ScrollContainer.new()
	_scroll = scroll
	scroll.custom_minimum_size = Vector2(760, 460)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_FILL
	root.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	_feedback = _label("")
	_feedback.name = "LabSetupFeedback"
	root.add_child(_feedback)
	confirmed.connect(func() -> void: launch_requested.emit(snapshot()))
	size_changed.connect(func() -> void: _fit_setup_scroll.call_deferred())

func open_setup(encounter: EmberEncounterResource, remembered: Dictionary = {}) -> void:
	_encounter = encounter
	_setup = remembered.duplicate(true)
	_history = [_setup.duplicate(true)]
	_cursor = 0
	_items = Items.definitions()
	_units.clear()
	for unit in Units.resources("hero"): _units[unit.unit_id] = unit
	_hero_id = encounter.party_unit_ids[0] if not encounter.party_unit_ids.is_empty() else ""
	_refresh_presets("")
	_rebuild()
	var height := mini(720, floori(float(get_tree().root.size.y) * 0.92))
	_scroll.custom_minimum_size.y = 120
	popup_centered_clamped(Vector2i(860, height), 0.92)
	_fit_setup_scroll.call_deferred()

func snapshot() -> Dictionary:
	return _setup.duplicate(true)

func feedback(message: String) -> void:
	_feedback.text = message

func undo() -> void:
	if _cursor <= 0: return
	_cursor -= 1
	_setup = _history[_cursor].duplicate(true)
	_rebuild()

func redo() -> void:
	if _cursor + 1 >= _history.size(): return
	_cursor += 1
	_setup = _history[_cursor].duplicate(true)
	_rebuild()

func _commit(next: Dictionary, rebuild := true) -> void:
	if next == _setup: return
	_history.resize(_cursor + 1)
	_history.append(next.duplicate(true))
	_cursor += 1
	_setup = next.duplicate(true)
	if rebuild: _rebuild()
	else: _refresh_summary()

func _rebuild() -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_undo.disabled = _cursor == 0
	_redo.disabled = _cursor + 1 == _history.size()
	_body.add_child(_label("Встреча: " + _encounter.display_name))
	var hero := OptionButton.new()
	hero.name = "LabSetupHero"
	hero.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in _encounter.party_unit_ids:
		var unit: EmberCombatUnitResource = _units.get(id)
		hero.add_item(unit.display_name if unit != null else id)
		hero.set_item_metadata(hero.item_count - 1, id)
		if id == _hero_id: hero.select(hero.item_count - 1)
	hero.item_selected.connect(func(index: int) -> void:
		_hero_id = str(hero.get_item_metadata(index))
		_rebuild()
	)
	_body.add_child(hero)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	_body.add_child(columns)
	var left := VBoxContainer.new()
	var right := VBoxContainer.new()
	for column in [left, right]:
		column.custom_minimum_size.x = 340
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		columns.add_child(column)
	var party: Dictionary = _setup.get("party", {})
	var custom := CheckBox.new()
	custom.name = "LabSetupCustom"
	custom.text = "Использовать уровень и экипировку"
	custom.button_pressed = party.has(_hero_id)
	custom.toggled.connect(_toggle_custom)
	left.add_child(custom)
	var member: Dictionary = party.get(_hero_id, {"level": 1, "equipment": EmberEquipment.empty()})
	var level_row := _field_row(left, "Уровень")
	var level := SpinBox.new()
	level.name = "LabSetupLevel"
	level.min_value = 1
	level.max_value = EmberPartyState.MAX_LEVEL
	level.value = int(member.get("level", 1))
	level.editable = custom.button_pressed
	level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level.value_changed.connect(_set_level)
	level_row.add_child(level)
	for slot in EmberEquipment.SLOTS:
		var row := _field_row(left, EmberEquipment.SLOT_LABELS[slot])
		var picker := OptionButton.new()
		picker.name = "LabSetupSlot_" + slot
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		picker.disabled = not custom.button_pressed
		picker.add_item("Пусто")
		picker.set_item_metadata(0, null)
		var current: Variant = member.get("equipment", {}).get(slot)
		var found := current == null
		var ids := _items.keys()
		ids.sort()
		for id in ids:
			var item: Dictionary = _items[id]
			if slot not in EmberEquipment.slots_for_item(item) or not EmberPartyState.equipment_allowed(item, _hero_id): continue
			picker.add_item(str(item.get("nameRu", id)))
			picker.set_item_metadata(picker.item_count - 1, id)
			if current == id:
				picker.select(picker.item_count - 1)
				found = true
		if not found:
			picker.add_item("Недоступно: " + str(current))
			picker.set_item_metadata(picker.item_count - 1, current)
			picker.select(picker.item_count - 1)
		picker.item_selected.connect(func(index: int) -> void: _set_equipment(slot, picker.get_item_metadata(index)))
		row.add_child(picker)
	right.add_child(_label("Характеристики в тесте"))
	_stats = _label("")
	_stats.name = "LabSetupStats"
	right.add_child(_stats)
	_stats_note = _label("")
	right.add_child(_stats_note)
	right.add_child(_label("Общая сумка расходников"))
	var bag: Dictionary = _setup.get("inventory", {})
	var bag_ids := _items.keys()
	for id in bag:
		if id not in bag_ids: bag_ids.append(id)
	bag_ids.sort()
	for id in bag_ids:
		var item: Dictionary = _items.get(id, {})
		if str(item.get("kind", "")) != "consumable" and not bag.has(id): continue
		var row := HBoxContainer.new()
		var label := _label(str(item.get("nameRu", "Недоступно: " + str(id))))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var count := SpinBox.new()
		count.name = "LabSetupCount_" + str(id)
		count.min_value = 0
		count.max_value = maxi(int(item.get("stackMax", 1)), int(bag.get(id, 0)))
		count.value = int(bag.get(id, 0))
		count.value_changed.connect(_set_count.bind(str(id)))
		row.add_child(count)
		right.add_child(row)
	_refresh_summary()

func _refresh_summary() -> void:
	# Numeric and picker edits keep their controls/focus; only the preview changes.
	_undo.disabled = _cursor == 0
	_redo.disabled = _cursor + 1 == _history.size()
	var prepared := Setup.prepare(_encounter, _setup, _items, _units)
	_stats.text = ""
	if prepared.get("ok", false) and _units.has(_hero_id):
		var stats: Dictionary = prepared.derived.get(_hero_id, (_units[_hero_id] as EmberCombatUnitResource).to_definition())
		var lines := PackedStringArray()
		for pair in [["maxHp", "HP"], ["maxMp", "MP"], ["str", "Сила"], ["mag", "Магия"], ["def", "Защита"], ["res", "Сопротивление"], ["speed", "Скорость"], ["acc", "Точность"], ["luck", "Удача"]]:
			lines.append("%s: %d" % [pair[1], int(stats.get(pair[0], 0))])
		_stats.text = " · ".join(lines)
	_stats_note.text = "Уровень и бонусы снаряжения рассчитаны по правилам отряда. HP/MP полные." if _setup.get("party", {}).has(_hero_id) else "По сохранённой карточке героя, без бонусов уровня и экипировки."
	get_ok_button().disabled = not prepared.get("ok", false)
	_update_preset_buttons(prepared.get("ok", false))
	feedback(str(prepared.get("error", "Настройки не меняют карточки и игровые сохранения. Отмена отбрасывает правки этого окна.")))
	_fit_setup_scroll.call_deferred()

func _fit_setup_scroll() -> void:
	if not visible or _scroll == null: return
	# Measure the actual native button row/theme/wrapped labels, rather than
	# reserving a fixed estimate which lets the body cover OK/Cancel.
	var fixed := _layout.get_combined_minimum_size().y - _scroll.get_combined_minimum_size().y
	var bottom := get_ok_button().global_position.y - _layout.global_position.y
	var gap := 2 * _layout.get_theme_constant("separation")
	_scroll.custom_minimum_size.y = maxf(80.0, floorf(bottom - fixed - gap))

func _build_presets(parent: VBoxContainer) -> void:
	parent.add_child(_label("Именованные наборы · для текущего состава героев"))
	var row := HBoxContainer.new()
	parent.add_child(row)
	_preset_picker = OptionButton.new()
	_preset_picker.name = "LabPresetPicker"
	_preset_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preset_picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(_preset_picker)
	_preset_load = _button("Загрузить", "LabPresetLoad", _load_preset, row)
	_button("Обновить список", "LabPresetRefresh", _refresh_presets, row)
	_preset_picker.item_selected.connect(_select_preset)
	row = HBoxContainer.new()
	parent.add_child(row)
	_preset_name = LineEdit.new()
	_preset_name.name = "LabPresetName"
	_preset_name.placeholder_text = "Название набора"
	_preset_name.max_length = 80
	_preset_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preset_name.custom_minimum_size.x = 200
	row.add_child(_preset_name)
	_preset_name.text_changed.connect(func(_value: String) -> void: _update_preset_buttons(not get_ok_button().disabled))
	_preset_save = _button("Сохранить новый", "LabPresetSave", _save_preset.bind(false), row)
	_preset_update = _button("Обновить выбранный", "LabPresetUpdate", _save_preset.bind(true), row)
	row = HBoxContainer.new()
	parent.add_child(row)
	_preset_delete = _button("Удалить…", "LabPresetDelete", _confirm_preset_delete, row)
	_preset_restore = _button("Отменить удаление", "LabPresetRestore", _restore_preset, row)
	_preset_note = _label("Наборы сохраняются на этом компьютере. Загрузка отменяется через Undo; сохранённые наборы остаются после закрытия окна.")
	parent.add_child(_preset_note)
	_preset_note.minimum_size_changed.connect(func() -> void: _fit_setup_scroll.call_deferred())

func _refresh_presets(preferred: Variant = null) -> void:
	if preferred == null: preferred = _preset_id
	var result: Dictionary = preset_store.read()
	_preset_error = "" if result.get("ok", false) else str(result.error)
	_preset_hash = str(result.get("hash", ""))
	_preset_rows = result.get("records", []).duplicate(true)
	_preset_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.name.naturalnocasecmp_to(b.name) < 0)
	_preset_picker.clear()
	_preset_picker.add_item("— выберите набор —")
	_preset_picker.set_item_metadata(0, "")
	var heroes := Presets.roster(_encounter)
	for record in _preset_rows:
		if record.heroes != heroes: continue
		_preset_picker.add_item(record.name)
		_preset_picker.set_item_metadata(_preset_picker.item_count - 1, record.id)
		if record.id == preferred: _preset_picker.select(_preset_picker.item_count - 1)
	_select_preset(_preset_picker.selected)
	if not _preset_error.is_empty(): _preset_note.text = _preset_error + " Текущий отряд можно настроить и проверить без наборов."
	elif result.get("recovered", false): _preset_note.text = "Восстановлена резервная версия наборов. Следующее сохранение запишет её в основной файл."
	else: _preset_note.text = "Наборы сохраняются на этом компьютере. Загрузка отменяется через Undo; сохранённые наборы остаются после закрытия окна."

func _select_preset(index: int) -> void:
	_preset_id = str(_preset_picker.get_item_metadata(index))
	_preset_name.text = ""
	for record in _preset_rows:
		if record.id == _preset_id: _preset_name.text = record.name
	_update_preset_buttons(not get_ok_button().disabled)

func _update_preset_buttons(valid: bool) -> void:
	if _preset_picker == null: return
	var available := _preset_error.is_empty()
	_preset_load.disabled = not available or _preset_id.is_empty()
	_preset_delete.disabled = _preset_load.disabled
	_preset_save.disabled = not available or not valid or _preset_name.text.strip_edges().is_empty()
	_preset_update.disabled = _preset_save.disabled or _preset_id.is_empty()
	_preset_restore.disabled = not available or _deleted_hash.is_empty() or _deleted_hash != _preset_hash

func _load_preset() -> void:
	var fresh: Dictionary = preset_store.read()
	if not fresh.get("ok", false) or fresh.hash != _preset_hash:
		_preset_note.text = str(fresh.get("error", "Набор изменился. Обновите список перед загрузкой."))
		return
	for record in fresh.records:
		if record.id != _preset_id: continue
		_items = Items.definitions()
		_units.clear()
		for unit in Units.resources("hero"): _units[unit.unit_id] = unit
		if not record.setup.get("party", {}).has(_hero_id):
			for hero in _encounter.party_unit_ids:
				if record.setup.get("party", {}).has(hero):
					_hero_id = hero
					break
		_commit(record.setup, false)
		_rebuild()
		_preset_note.text = "Загружен «%s». Изменения отряда можно отменить; сам набор пока не изменён." % record.name
		return

func _save_preset(update: bool) -> void:
	var result: Dictionary = preset_store.save(_encounter, _preset_name.text, snapshot(), _preset_hash, _preset_id if update else "")
	if not result.get("ok", false):
		_preset_note.text = str(result.error)
		return
	_deleted_hash = ""
	_refresh_presets(str(result.id))
	_preset_note.text = "Набор «%s» сохранён. Он останется после перезапуска редактора." % _preset_name.text

func _confirm_preset_delete() -> void:
	var id := _preset_id
	var expected := _preset_hash
	var saved_name := ""
	for record in _preset_rows:
		if record.id == id: saved_name = record.name
	var confirmation := ConfirmationDialog.new()
	confirmation.name = "LabPresetDeleteConfirmation"
	confirmation.title = "Удалить набор"
	confirmation.dialog_text = "Удалить «%s»? Текущий отряд останется. Удаление можно отменить до следующего сохранения набора." % saved_name
	confirmation.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirmation.ok_button_text = "Удалить"
	confirmation.cancel_button_text = "Отмена"
	add_child(confirmation)
	confirmation.confirmed.connect(func() -> void:
		var result: Dictionary = preset_store.remove(id, expected)
		if result.get("ok", false):
			_deleted_hash = str(result.hash)
			_deleted_id = id
			_refresh_presets("")
			_preset_note.text = "Набор удалён. Можно вернуть его кнопкой «Отменить удаление»."
		else: _preset_note.text = str(result.error)
	)
	confirmation.visibility_changed.connect(func() -> void:
		if not confirmation.visible: confirmation.queue_free()
	)
	confirmation.popup_centered_clamped(Vector2i(560, 160), 0.85)

func _restore_preset() -> void:
	var result: Dictionary = preset_store.undo_delete(_deleted_hash)
	if not result.get("ok", false):
		_preset_note.text = str(result.error)
		return
	_deleted_hash = ""
	_refresh_presets(_deleted_id)
	_preset_note.text = "Удалённый набор восстановлен; текущий отряд не изменён."

func _toggle_custom(enabled: bool) -> void:
	var next := snapshot()
	var party: Dictionary = next.get("party", {})
	if enabled: party[_hero_id] = {"level": 1, "equipment": EmberEquipment.empty()}
	else: party.erase(_hero_id)
	next["party"] = party
	_commit(next)

func _set_level(value: float) -> void:
	if not _setup.get("party", {}).has(_hero_id): return
	var next := snapshot()
	next.party[_hero_id]["level"] = int(value)
	_commit(next, false)

func _set_equipment(slot: String, item_id: Variant) -> void:
	if not _setup.get("party", {}).has(_hero_id): return
	var next := snapshot()
	next.party[_hero_id].equipment[slot] = item_id
	_commit(next, false)

func _set_count(value: float, item_id: String) -> void:
	var next := snapshot()
	var bag: Dictionary = next.get("inventory", {})
	if value == 0: bag.erase(item_id)
	else: bag[item_id] = int(value)
	next["inventory"] = bag
	_commit(next, false)

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _field_row(parent: Node, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := _label(text)
	label.custom_minimum_size.x = 124
	label.size_flags_horizontal = Control.SIZE_FILL
	row.add_child(label)
	parent.add_child(row)
	return row

func _button(text: String, node_name: String, action: Callable, parent: Node) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button
