@tool
extends VBoxContainer
## View of the common Session draft, never a second inventory/party/Undo owner.
const Party = preload("res://scripts/ember_party_state.gd")
const Gear = preload("res://scripts/ember_equipment.gd")
const Items = preload("res://scripts/ember_item_catalog.gd")
var _session
var _draft: Resource
var _items := {}
var _item_ids: Array[String] = []
var _previews := {}
var _bag: VBoxContainer

func setup(session: RefCounted) -> void:
	name = "GameStartEditor"
	_session = session
	_draft = session.draft
	_items = Items.definitions()
	_item_ids.assign(_items.keys())
	_item_ids.sort_custom(func(a: String, b: String) -> bool: return str(_items[a].get("nameRu", a)).naturalnocasecmp_to(str(_items[b].get("nameRu", b))) < 0)
	add_theme_constant_override("separation", 8)
	_label(self, "Герои · начальный уровень и экипировка", 16)
	var tabs := TabContainer.new()
	tabs.name = "StartHeroTabs"
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(tabs)
	for id in Party.HERO_IDS:
		var card := VBoxContainer.new()
		card.name = id
		tabs.add_child(card)
		tabs.set_tab_title(tabs.get_tab_count() - 1, str(Party.unit_definition(id).get("name", id)))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("v_separation", 6)
		card.add_child(grid)
		_slot_label(grid, "Уровень")
		var level := SpinBox.new()
		level.name = "StartLevel_" + id
		level.min_value = 1
		level.max_value = Party.MAX_LEVEL
		level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		level.value = float(_draft.hero_levels.get(id, 1)) if _draft.hero_levels.get(id, 1) is int else 1
		level.value_changed.connect(func(value: float) -> void:
			var levels: Dictionary = _draft.hero_levels.duplicate(true)
			levels[id] = int(value)
			_set_value("hero_levels", levels, id)
		)
		grid.add_child(level)
		var raw: Variant = _draft.hero_equipment.get(id, Gear.empty())
		if not raw is Dictionary:
			_label(card, "Некорректная экипировка: выберите любой слот, чтобы восстановить пять слотов.")
		var gear := Gear.normalize(raw)
		for slot in Gear.SLOTS:
			_slot_label(grid, Gear.SLOT_LABELS[slot])
			var picker := _picker(str(gear[slot]) if gear[slot] != null else "", slot, id)
			picker.name = "StartGear_%s_%s" % [id, slot]
			grid.add_child(picker)
			picker.item_selected.connect(func(index: int) -> void:
				var all: Dictionary = _draft.hero_equipment.duplicate(true)
				var next := Gear.normalize(all.get(id, {}))
				var selected := str(picker.get_item_metadata(index))
				next[slot] = selected if not selected.is_empty() else null
				all[id] = next
				_set_value("hero_equipment", all)
			)
		var preview := _label(card, "")
		preview.name = "StartStats_" + id
		_previews[id] = preview
	_label(self, "Общая сумка · дополнительно к надетым предметам", 16)
	_label(self, "Монеты — такой же предмет сумки. Пустая сумка допустима; экипировка героев не вычитается из неё.")
	_bag = VBoxContainer.new()
	_bag.name = "StartBag"
	add_child(_bag)
	_build_bag()
	_session.changed.connect(_refresh_previews)
	_refresh_previews()

func _set_value(key: String, value: Variant, field_key := "") -> void:
	if _session.draft == _draft: _session.set_value(key, value, field_key)

func _picker(selected: String, slot := "", hero := "", excluded: Array = []) -> OptionButton:
	var picker := OptionButton.new()
	picker.fit_to_longest_item = false
	picker.custom_minimum_size.x = 160
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.add_item("Не надето" if not slot.is_empty() else "Выберите предмет…")
	picker.set_item_metadata(0, "")
	for id in _item_ids:
		if id in excluded and id != selected: continue
		if not slot.is_empty() and (slot not in Gear.slots_for_item(_items[id]) or not Party.equipment_allowed(_items[id], hero)): continue
		picker.add_item(str(_items[id].get("nameRu", id)) + " · " + id)
		picker.set_item_metadata(picker.item_count - 1, id)
		if id == selected: picker.select(picker.item_count - 1)
	if not selected.is_empty() and picker.selected == 0:
		picker.add_item("Не подходит / отсутствует: " + selected)
		picker.set_item_metadata(picker.item_count - 1, selected)
		picker.select(picker.item_count - 1)
	return picker

func _build_bag() -> void:
	for child in _bag.get_children():
		_bag.remove_child(child)
		child.queue_free()
	for raw_id in _draft.inventory:
		var id := str(raw_id)
		var row := HBoxContainer.new()
		_bag.add_child(row)
		var picker := _picker(id, "", "", _draft.inventory.keys())
		picker.name = "StartBagItem_" + id
		picker.set_item_disabled(0, true)
		row.add_child(picker)
		picker.item_selected.connect(func(index: int) -> void:
			var next: Dictionary = _draft.inventory.duplicate(true)
			var selected := str(picker.get_item_metadata(index))
			if selected.is_empty() or selected == id or next.has(selected): return
			var count: Variant = next[raw_id]
			next.erase(raw_id)
			next[selected] = count
			_set_value("inventory", next)
			_build_bag()
		)
		var count := SpinBox.new()
		count.name = "StartBagCount_" + id
		count.min_value = 1
		count.max_value = 2147483647
		count.custom_minimum_size.x = 110
		var raw_count: Variant = _draft.inventory[raw_id]
		count.value = float(raw_count) if raw_count is int else 1
		count.value_changed.connect(func(value: float) -> void:
			var next: Dictionary = _draft.inventory.duplicate(true)
			next[raw_id] = int(value)
			_set_value("inventory", next, id)
		)
		row.add_child(count)
		var remove := Button.new()
		remove.name = "StartBagRemove_" + id
		remove.text = "Убрать"
		remove.pressed.connect(func() -> void:
			var next: Dictionary = _draft.inventory.duplicate(true)
			next.erase(raw_id)
			_set_value("inventory", next)
			_build_bag()
		)
		row.add_child(remove)
	var add_row := HBoxContainer.new()
	_bag.add_child(add_row)
	var choice := _picker("", "", "", _draft.inventory.keys())
	choice.name = "StartBagAddItem"
	add_row.add_child(choice)
	var add := Button.new()
	add.name = "StartBagAdd"
	add.text = "Добавить"
	add.disabled = true
	choice.item_selected.connect(func(index: int) -> void: add.disabled = str(choice.get_item_metadata(index)).is_empty())
	add.pressed.connect(func() -> void:
		var id := str(choice.get_item_metadata(choice.selected))
		if id.is_empty() or _draft.inventory.has(id): return
		var next: Dictionary = _draft.inventory.duplicate(true)
		next[id] = 1
		_set_value("inventory", next)
		_build_bag()
	)
	add_row.add_child(add)

func _refresh_previews() -> void:
	if _session.draft != _draft: return
	for id in _previews:
		var level: Variant = _draft.hero_levels.get(id, 1)
		if not level is int or level < 1 or level > Party.MAX_LEVEL:
			_previews[id].text = "Исправьте начальный уровень."
			continue
		var member := {"level": level, "equipment": Gear.normalize(_draft.hero_equipment.get(id, {}))}
		var stats := Party.derived_stats(id, member, _items)
		_previews[id].text = "Полные HP %d · MP %d · сила %d · защита %d · скорость %d" % [stats.maxHp, stats.maxMp, stats.str, stats.def, stats.speed]

func _label(parent: Node, text: String, font_size := 14) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label

func _slot_label(parent: Node, text: String) -> void:
	var label := _label(parent, text)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.custom_minimum_size.x = 120
