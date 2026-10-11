@tool
extends VBoxContainer
signal action_requested(action: String, id: String, value: String)
signal selection_changed(id: String)
const Plan = preload("res://scripts/ember_terrain_plan_resource.gd")
var _list: ItemList
var _name: LineEdit
var _description: Label
var _status: Label
var _buttons := {}
var _plan: Resource
var _updating := false

func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var title := Label.new(); title.text = "План областей"; add_child(title)
	var scroll := ScrollContainer.new(); scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; add_child(scroll)
	var box := VBoxContainer.new(); box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(box)
	var hint := Label.new(); hint.text = "Выделяйте области в 3D. План сохраняется вместе со сценой; земля меняется только после предпросмотра и применения."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; box.add_child(hint)
	_list = ItemList.new(); _list.custom_minimum_size = Vector2(0, 130); box.add_child(_list)
	_list.item_selected.connect(func(_index): _refresh_selection(); selection_changed.emit(selected_id()))
	var row := GridContainer.new(); row.columns = 2; box.add_child(row)
	for spec in [["add", "+ Область"], ["add_plateau", "+ Плато"], ["add_lake", "+ Озеро"], ["add_river", "+ Река"], ["add_mountain", "+ Гора"], ["add_road", "+ Дорога"], ["add_placement", "+ Объекты"], ["add_grove", "+ Роща"], ["bounds", "Границы"], ["delete", "Удалить"]]:
		var button := Button.new(); button.text = spec[1]; button.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(button); _buttons[spec[0]] = button
		button.pressed.connect(func(): action_requested.emit(spec[0], selected_id(), ""))
	_name = LineEdit.new(); _name.placeholder_text = "Название области"; _name.max_length = 120; box.add_child(_name)
	_name.text_submitted.connect(func(text): action_requested.emit("name", selected_id(), text))
	var rename := Button.new(); rename.text = "Сохранить название"; rename.pressed.connect(func(): action_requested.emit("name", selected_id(), _name.text)); box.add_child(rename); _buttons.name = rename
	_description = Label.new(); _description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; box.add_child(_description)
	var generate := Button.new(); generate.text = "Параметры области →"; generate.pressed.connect(func(): action_requested.emit("generate", selected_id(), "")); box.add_child(generate); _buttons.generate = generate
	var toggle := Button.new(); toggle.text = "Включить / выключить"; toggle.pressed.connect(func(): action_requested.emit("toggle", selected_id(), "")); box.add_child(toggle); _buttons.toggle = toggle
	var reverse := Button.new(); reverse.text = "Развернуть реку"; reverse.pressed.connect(func(): action_requested.emit("reverse",selected_id(),"")); box.add_child(reverse); _buttons.reverse = reverse
	var compose := Button.new(); compose.text = "Обновить области →"; compose.pressed.connect(func(): action_requested.emit("compose", "", "")); box.add_child(compose); _buttons.compose = compose
	var groves := Button.new(); groves.text = "Обновить расстановку →"; groves.pressed.connect(func(): action_requested.emit("groves","","")); box.add_child(groves); _buttons.groves = groves
	_status = Label.new(); _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; box.add_child(_status)

func selected_id() -> String:
	var selected := _list.get_selected_items()
	return _plan.regions[selected[0]].id if _plan != null and not selected.is_empty() else ""

func show_plan(plan: Resource, selected := "", reveal := true) -> void:
	_plan = plan; _updating = true
	_list.clear()
	for region: Dictionary in plan.regions:
		var kind: String = region.get("kind","generation")
		var suffix := " · роща" if kind == "grove" else " · объекты" if kind == "placement" else " · дорога" if kind == "road" else " · гора" if kind == "mountain" else " · река" if kind == "river" else " · озеро" if kind == "lake" else " · плато" if kind == "plateau" else ""
		_list.add_item(region.name+suffix+(" (выкл.)" if kind != "generation" and not region.get("enabled",true) else ""))
	var index: int = plan.index_of(selected)
	if index < 0 and not plan.regions.is_empty(): index = 0
	if index >= 0: _list.select(index)
	_updating = false; _refresh_selection()
	if reveal: show()

func _refresh_selection() -> void:
	if _updating: return
	var id := selected_id()
	for key in ["bounds", "delete", "name", "generate"]: _buttons[key].disabled = id.is_empty()
	var river: bool = not id.is_empty() and _plan.regions[_plan.index_of(id)].get("kind") == "river"
	var road: bool = not id.is_empty() and _plan.regions[_plan.index_of(id)].get("kind") == "road"
	_buttons.reverse.visible = river; _buttons.bounds.text = "Линия дороги" if road else "Линия реки" if river else "Границы"
	_buttons.toggle.disabled = id.is_empty() or _plan.regions[_plan.index_of(id)].get("kind", "generation") not in ["plateau","lake","river","mountain","road","grove","placement"]
	_buttons.groves.visible = not _plan.object_layers.is_empty() or _plan.regions.any(func(region): return region.get("kind") in ["grove","placement"])
	_buttons.compose.disabled = _plan.patches.is_empty() and not _plan.regions.any(func(region): return region.get("kind", "generation") in ["plateau","lake","river","mountain","road"])
	_name.editable = not id.is_empty()
	if id.is_empty(): _name.text = ""; _description.text = "Областей пока нет."; return
	var region: Dictionary = _plan.regions[_plan.index_of(id)]
	_name.text = region.name
	var rect: Rect2i = region.bounds
	var overlaps: PackedStringArray = _plan.overlaps(id)
	_description.text = "Начало (%d, %d) м · размер %d×%d м.\nПересечения: %s" % [rect.position.x, rect.position.y, rect.size.x, rect.size.y, "нет" if overlaps.is_empty() else ", ".join(overlaps)]
	if not (river or road) and (rect.size.x > 96 or rect.size.y > 96): _description.text += "\nГенерация сейчас доступна для области до 96×96 м."
	if region.get("kind", "generation") == "plateau": _description.text += "\nВлияния плато применяются в порядке списка. Ручные правки сохраняются; вода не меняется."
	if region.get("kind", "generation") == "lake": _description.text += "\nОвальная котловина со своим уровнем воды. После переноса/выключения обновите локальные области; ручные правки сохраняются."
	if river: _description.text += "\nЛиния от высокого водоёма к низкому, до 96 м. Уровни берутся из водоёмов на концах; озеро должно стоять раньше реки в списке. «Линия реки» позволяет перенаметить точки."
	if region.get("kind") == "mountain": _description.text += "\nГора поднимает сухую землю к заданной высоте вершины. Ширина вершины и склонов измеряется по меньшей стороне области; вытянутое выделение даёт вытянутую возвышенность."
	if road: _description.text += "\nДорога выравнивает сухой коридор между высотами на концах линии, до 96 м. Покрытие — существующий грунт. Вода требует отдельного моста; ручные правки сохраняются."
	if region.get("kind") == "placement": _description.text += "\nГотовые объекты из общей библиотеки, один или смешанный набор. Размеры оснований, интервалы, вода, дороги и соседи учитываются в предпросмотре. До 64 объектов в области / 256 в плане. После переноса/off/delete нажмите «Обновить расстановку». Ручные правки сохраняются."
	if region.get("kind") == "grove": _description.text += "\nСохранённые варианты деревьев на готовой земле: до 64 деревьев в роще / 256 в плане. После переноса, выключения или удаления нажмите «Обновить расстановку». Ручные объекты и изменённые деревья сохраняются. Изменение земли не переставляет деревья автоматически."

func set_status(message: String) -> void: _status.text = message
