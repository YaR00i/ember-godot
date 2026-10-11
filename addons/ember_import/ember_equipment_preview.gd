@tool
extends VBoxContainer
## Editor-only fitting context. Party/Equipment remain the sole stat/equip rules.
const Items = preload("res://scripts/ember_item_catalog.gd")
const Equipment = preload("res://scripts/ember_equipment.gd")
const Party = preload("res://scripts/ember_party_state.gd")
const Units = preload("res://scripts/prototypes/ember_combat_unit_catalog.gd")
const STATS := [["maxHp", "Максимум HP"], ["maxMp", "Максимум MP"], ["str", "Сила"], ["def", "Защита"], ["mag", "Магия"], ["res", "Сопротивление"], ["speed", "Скорость"], ["atk", "Атака оружия"]]
var _context: Dictionary
var _items: Dictionary
var _document: Dictionary
var _hero: OptionButton
var _level: SpinBox
var _choices := {}
var _numbers := {}
var _summary: Label
var _target_slot: OptionButton
var _comparison := {}

func setup(context: Dictionary) -> void:
	name = "ItemEquipmentPreview"
	_context = context
	_items = Items.definitions()
	add_theme_constant_override("separation", 8)
	add_child(_label("Результат замены текущим предметом. Примерка не меняет героя и сохранения."))
	var actor_row := HBoxContainer.new()
	add_child(actor_row)
	_hero = OptionButton.new()
	_hero.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero.name = "EquipmentPreviewHero"
	var names := {}
	for unit in Units.resources(): names[unit.unit_id] = unit.display_name
	for hero_id in Party.HERO_IDS:
		_hero.add_item(str(names.get(hero_id, hero_id)))
		_hero.set_item_metadata(_hero.item_count - 1, hero_id)
		if hero_id == str(_context.get("hero", Party.LEADER_ID)): _hero.select(_hero.item_count - 1)
	actor_row.add_child(_hero)
	var level_label := _label("Ур.")
	level_label.custom_minimum_size.x = 28
	actor_row.add_child(level_label)
	_level = SpinBox.new()
	_level.name = "EquipmentPreviewLevel"
	_level.min_value = 1
	_level.max_value = Party.MAX_LEVEL
	_level.value = int(_context.get("level", 1))
	actor_row.add_child(_level)
	var clear := Button.new()
	clear.text = "Очистить комплект"
	clear.name = "EquipmentPreviewClear"
	clear.pressed.connect(_clear_loadout)
	actor_row.add_child(clear)
	add_child(_label("Куда примерить предмет"))
	_target_slot = OptionButton.new()
	_target_slot.name = "EquipmentPreviewTargetSlot"
	_target_slot.item_selected.connect(func(index: int) -> void:
		_context["target_slot"] = _target_slot.get_item_metadata(index)
		_refresh()
	)
	add_child(_target_slot)
	var loadout := VBoxContainer.new()
	loadout.name = "EquipmentPreviewLoadout"
	for slot in Equipment.SLOTS:
		loadout.add_child(_label(str(Equipment.SLOT_LABELS[slot])))
		var choice := OptionButton.new()
		choice.name = "EquipmentPreviewSlot_" + slot
		choice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		choice.item_selected.connect(_choose_item.bind(slot))
		_choices[slot] = choice
		loadout.add_child(choice)
	_summary = _label("")
	_summary.name = "EquipmentPreviewSummary"
	add_child(_summary)
	var table := GridContainer.new()
	table.name = "EquipmentPreviewStats"
	table.columns = 4
	table.add_theme_constant_override("h_separation", 16)
	for title in ["Показатель", "До", "После", "Разница"]: table.add_child(_label(title))
	for stat in STATS:
		var label := _label(str(stat[1]))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		table.add_child(label)
		var cells: Array[Label] = []
		for column in 3:
			var cell := _label("—")
			cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			table.add_child(cell)
			cells.append(cell)
		_numbers[stat[0]] = cells
	add_child(table)
	var configure := Button.new()
	configure.name = "EquipmentPreviewConfigureLoadout"
	configure.text = "Настроить исходный комплект"
	configure.toggle_mode = true
	configure.button_pressed = bool(_context.get("loadout_open", false))
	loadout.visible = configure.button_pressed
	configure.toggled.connect(func(open: bool) -> void:
		_context["loadout_open"] = open
		loadout.visible = open
	)
	add_child(configure)
	add_child(loadout)
	add_child(_label("Комплект для сравнения берётся из сохранённых карточек библиотеки. «После» учитывает текущий черновик, включая несохранённые изменения."))
	_hero.item_selected.connect(_change_hero)
	_level.value_changed.connect(func(value: float) -> void:
		_context["level"] = int(value)
		_refresh()
	)
	_build_choices()

func set_document(document: Dictionary) -> void:
	_document = document.duplicate(true)
	var slots := Equipment.slots_for_item(_document)
	_target_slot.clear()
	var preferred := str(_context.get("target_slot", ""))
	if preferred not in slots: preferred = slots[0] if not slots.is_empty() else ""
	_context["target_slot"] = preferred
	for slot in slots:
		_target_slot.add_item(str(Equipment.SLOT_LABELS[slot]))
		_target_slot.set_item_metadata(_target_slot.item_count - 1, slot)
		if slot == preferred: _target_slot.select(_target_slot.item_count - 1)
	_target_slot.disabled = slots.size() <= 1
	if slots.is_empty(): _target_slot.add_item("Нет подходящего слота")
	_refresh()

func _hero_id() -> String:
	return str(_hero.get_item_metadata(_hero.selected))

func _loadout() -> Dictionary:
	var loadouts: Dictionary = _context.get("loadouts", {})
	return Equipment.normalize(loadouts.get(_hero_id(), {}))

func _remember_loadout(value: Dictionary) -> void:
	if not _context.has("loadouts"): _context["loadouts"] = {}
	_context.loadouts[_hero_id()] = value.duplicate(true)

func _build_choices() -> void:
	var loadout := _loadout()
	var ids: Array = _items.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		return str(_items[a].get("nameRu", a)).naturalnocasecmp_to(str(_items[b].get("nameRu", b))) < 0
	)
	for slot in _choices:
		var choice := _choices[slot] as OptionButton
		choice.clear()
		choice.add_item("— пусто —")
		choice.set_item_metadata(0, "")
		for item_id in ids:
			var item: Dictionary = _items[item_id]
			if slot not in Equipment.slots_for_item(item) or not Party.equipment_allowed(item, _hero_id()): continue
			choice.add_item(str(item.get("nameRu", item_id)))
			choice.set_item_metadata(choice.item_count - 1, item_id)
			if str(loadout.get(slot, "")) == item_id: choice.select(choice.item_count - 1)
		# A vanished/unavailable reference cannot contribute invisible stats.
		loadout[slot] = null if choice.selected == 0 else choice.get_item_metadata(choice.selected)
	_remember_loadout(loadout)

func _choose_item(index: int, slot: String) -> void:
	var loadout := _loadout()
	loadout[slot] = null if index == 0 else _choices[slot].get_item_metadata(index)
	_remember_loadout(loadout)
	_refresh()

func _change_hero(_index: int) -> void:
	_context["hero"] = _hero_id()
	_build_choices()
	_refresh()

func _clear_loadout() -> void:
	_remember_loadout(Equipment.empty())
	_build_choices()
	_refresh()

func _refresh() -> void:
	if _document.is_empty(): return
	var hero := _hero_id()
	var level := int(_level.value)
	var before_equipment := _loadout()
	var before := Party.derived_stats(hero, {"level": level, "equipment": before_equipment}, _items)
	var slot := str(_context.get("target_slot", ""))
	var compatible := not slot.is_empty() and Party.equipment_allowed(_document, hero)
	var after := before
	var replaced_id := str(before_equipment.get(slot, "")) if not slot.is_empty() and before_equipment.get(slot) != null else ""
	if compatible:
		var candidate_id := str(_document.get("id", ""))
		if candidate_id.is_empty():
			candidate_id = "editor_preview_candidate"
			while _items.has(candidate_id): candidate_id += "_"
		var after_items := _items.duplicate()
		after_items[candidate_id] = _document
		var equipped := Equipment.equip({candidate_id: 1}, before_equipment, candidate_id, after_items, slot)
		compatible = bool(equipped.get("ok", false))
		if compatible: after = Party.derived_stats(hero, {"level": level, "equipment": equipped.equipment}, after_items)
	_comparison = {"ok": compatible, "hero": hero, "level": level, "slot": slot, "replacedId": replaced_id, "before": before, "after": after, "changes": {}}
	_summary.modulate = Color("79d99a") if compatible else Color("e6bb78")
	_summary.text = "Слот: %s. Замена: %s → %s." % [Equipment.SLOT_LABELS.get(slot, slot), str(_items.get(replaced_id, {}).get("nameRu", "пусто")), str(_document.get("nameRu", "Новый предмет"))]
	if not compatible:
		_summary.text = "Этот герой не может экипировать предмет. Показатели остаются прежними."
		if slot.is_empty(): _summary.text = "У предмета нет действующего слота экипировки."
	for stat in STATS:
		var key := str(stat[0])
		var delta := int(after.get(key, 0)) - int(before.get(key, 0))
		_comparison.changes[key] = delta
		var cells: Array = _numbers[key]
		cells[0].text = str(before.get(key, 0))
		cells[1].text = str(after.get(key, 0)) if compatible else "—"
		cells[2].text = ("+" if delta > 0 else "") + str(delta) if compatible else "—"
		cells[2].modulate = Color("79d99a") if delta > 0 else Color("ef9589") if delta < 0 else Color("bfc5cc")

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
