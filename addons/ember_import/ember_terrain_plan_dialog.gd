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
var _compact:=false
var _scroll: ScrollContainer
var _picker: OptionButton
var _add_menu: MenuButton
var _more_menu: MenuButton
var _general_row: GridContainer
var _point_tools: GridContainer
var _point_info: Label
var _point_mode:="move"
var _hint: Label
const ADD_ACTIONS := ["add","add_plateau","add_lake","add_river","add_coast","add_mountain","add_road","add_placement","add_grove"]
const ADD_NAMES := ["Область рельефа","Плато","Озеро","Река","Море","Гора","Дорога","Объекты","Роща"]
const MORE_ACTIONS := ["bounds","reverse","toggle","rename_ui","delete","compose","groves"]

func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var header:=HBoxContainer.new();add_child(header)
	var title := Label.new(); title.text = "Области";title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(title)
	_add_menu=MenuButton.new();_add_menu.text="+ Область";header.add_child(_add_menu)
	for name in ADD_NAMES:_add_menu.get_popup().add_item(name)
	_add_menu.get_popup().id_pressed.connect(func(index):action_requested.emit(ADD_ACTIONS[index],selected_id(),""))
	_more_menu=MenuButton.new();_more_menu.text="Ещё";header.add_child(_more_menu)
	for name in ["Нарисовать границы заново","Развернуть линию","Включить / выключить","Переименовать","Удалить область","Обновить рельеф…","Обновить расстановку…"]:_more_menu.get_popup().add_item(name)
	_more_menu.get_popup().id_pressed.connect(func(index):
		if index==3:_rename_selected();return
		action_requested.emit(MORE_ACTIONS[index],selected_id(),""))
	_picker=OptionButton.new();add_child(_picker);_picker.hide()
	_picker.item_selected.connect(func(index):_list.select(index);_refresh_selection();selection_changed.emit(selected_id()))
	_point_tools=GridContainer.new();_point_tools.columns=2;add_child(_point_tools)
	for spec in [["move","Точки"],["translate","Перенос"],["insert","+ Точку"],["remove","− Точку"]]:
		var button:=Button.new();button.text=spec[1];button.toggle_mode=true;button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_point_tools.add_child(button);_buttons["point_"+spec[0]]=button
		button.pressed.connect(func():set_point_mode(spec[0]);action_requested.emit("point_mode",selected_id(),spec[0]))
	_point_info=Label.new();_point_info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(_point_info)
	_point_tools.hide();_point_info.hide()
	var scroll := ScrollContainer.new();_scroll=scroll; scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; add_child(scroll)
	var box := VBoxContainer.new(); box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(box)
	var hint := Label.new();_hint=hint;hint.text="Выбери область в списке или на карте."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; box.add_child(hint)
	_list = ItemList.new(); _list.custom_minimum_size = Vector2(0, 130); box.add_child(_list)
	_list.item_selected.connect(func(_index): _refresh_selection(); selection_changed.emit(selected_id()))
	var row := GridContainer.new();_general_row=row;row.columns = 2; box.add_child(row)
	for spec in [["add", "+ Область"], ["add_plateau", "+ Плато"], ["add_lake", "+ Озеро"], ["add_river", "+ Река"], ["add_coast", "+ Море"], ["add_mountain", "+ Гора"], ["add_road", "+ Дорога"], ["add_placement", "+ Объекты"], ["add_grove", "+ Роща"], ["bounds", "Границы"], ["delete", "Удалить"]]:
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
	_ensure_controls()
	_plan = plan; _updating = true
	_list.clear();_picker.clear()
	for region: Dictionary in plan.regions:
		var kind: String = region.get("kind","generation")
		var suffix := " · море" if kind=="coast" else " · роща" if kind == "grove" else " · объекты" if kind == "placement" else " · дорога" if kind == "road" else " · гора" if kind == "mountain" else " · река" if kind == "river" else " · озеро" if kind == "lake" else " · плато" if kind == "plateau" else ""
		var text: String=region.name+suffix+(" (выкл.)" if kind != "generation" and not region.get("enabled",true) else "")
		_list.add_item(text);_picker.add_item(text)
	var index: int = plan.index_of(selected)
	if index < 0 and not plan.regions.is_empty(): index = 0
	if index >= 0: _list.select(index);_picker.select(index)
	_updating = false; _refresh_selection()
	if reveal: show()

func _refresh_selection() -> void:
	if _updating: return
	var id := selected_id()
	for key in ["bounds", "delete", "name", "generate"]: _buttons[key].disabled = id.is_empty()
	var river: bool = not id.is_empty() and _plan.regions[_plan.index_of(id)].get("kind") == "river"
	var road: bool = not id.is_empty() and _plan.regions[_plan.index_of(id)].get("kind") == "road"
	var coast: bool=not id.is_empty() and _plan.regions[_plan.index_of(id)].get("kind")=="coast"
	_buttons.reverse.visible = river or coast;_buttons.reverse.text="Поменять сторону моря" if coast else "Развернуть реку"
	_buttons.bounds.text="Линия берега" if coast else "Границы"
	if not coast: _buttons.bounds.text = "Линия дороги" if road else "Линия реки" if river else "Границы"
	_buttons.toggle.disabled = id.is_empty() or _plan.regions[_plan.index_of(id)].get("kind", "generation") not in ["plateau","lake","river","mountain","road","grove","placement","coast"]
	_buttons.groves.visible = not _plan.object_layers.is_empty() or _plan.regions.any(func(region): return region.get("kind") in ["grove","placement"])
	_buttons.compose.disabled = _plan.patches.is_empty() and not _plan.regions.any(func(region): return region.get("kind", "generation") in ["plateau","lake","river","mountain","road","coast"])
	_name.editable = not id.is_empty()
	if id.is_empty():
		_name.text = ""; _description.text = "Областей пока нет."
		_point_tools.hide();_point_info.hide();_more_menu.hide();_general_row.show()
		return
	var region: Dictionary = _plan.regions[_plan.index_of(id)]
	_name.text = region.name
	var rect: Rect2i = region.bounds
	var overlaps: PackedStringArray = _plan.overlaps(id)
	_description.text = "Начало (%d, %d) м · размер %d×%d м.\nПересечения: %s" % [rect.position.x, rect.position.y, rect.size.x, rect.size.y, "нет" if overlaps.is_empty() else ", ".join(overlaps)]
	if region.get("kind") not in ["river","road","coast","grove","placement"] and (rect.size.x > 96 or rect.size.y > 96): _description.text += "\nГенерация сейчас доступна для области до 96×96 м."
	if region.get("kind", "generation") == "plateau": _description.text += "\nВлияния плато применяются в порядке списка. Ручные правки сохраняются; вода не меняется."
	if region.get("kind", "generation") == "lake": _description.text += "\nОвальная котловина со своим уровнем воды. После переноса/выключения обновите локальные области; ручные правки сохраняются."
	if coast:_description.text+="\nЛиния берега, море справа по её ходу. Перенаметьте линию или поменяйте сторону; уровень, глубина и ширина берега — в параметрах. Предпросмотр и применение обновляют только область моря; ручные правки защищаются."
	if river: _description.text += "\nЛиния от высокого водоёма к низкому, до 96 м. Уровни берутся из водоёмов на концах; озеро должно стоять раньше реки в списке. «Линия реки» позволяет перенаметить точки."
	if region.get("kind") == "mountain": _description.text += "\nГора поднимает сухую землю к заданной высоте вершины. Ширина вершины и склонов измеряется по меньшей стороне области; вытянутое выделение даёт вытянутую возвышенность."
	if road: _description.text += "\nДорога выравнивает сухой коридор между высотами на концах линии, до 96 м. Покрытие — существующий грунт. Вода требует отдельного моста; ручные правки сохраняются."
	if region.get("kind") == "placement": _description.text += "\nГотовые объекты из общей библиотеки, один или смешанный набор. Размеры оснований, интервалы, вода, дороги и соседи учитываются в предпросмотре. Бюджет зависит от площади области и созданных участков. После переноса/off/delete нажмите «Обновить расстановку». Ручные правки сохраняются."
	if region.get("kind") == "grove": _description.text += "\nСохранённые варианты деревьев на готовой земле. Бюджет зависит от площади рощи и созданных участков. После переноса, выключения или удаления нажмите «Обновить расстановку». Ручные объекты и изменённые деревья сохраняются. Изменение земли не переставляет деревья автоматически."

	_general_row.hide(); _hint.hide(); _more_menu.show()
	_point_tools.show(); _point_info.show(); _name.hide()
	_buttons.generate.text="Параметры области →"
	for key in ["bounds","delete","toggle","reverse","compose","groves","name"]: _buttons[key].hide()
	var path := Plan.Influence.plan_is_path(region)
	_buttons.point_move.text="Точки" if path else "Углы"
	_buttons.point_insert.visible=path; _buttons.point_remove.visible=path
	_more_menu.get_popup().set_item_text(0,"Нарисовать линию заново" if path else "Нарисовать границы заново")
	_more_menu.get_popup().set_item_text(1,"Поменять сторону моря" if coast else "Развернуть реку")
	_more_menu.get_popup().set_item_disabled(1,not (river or coast))
	_more_menu.get_popup().set_item_disabled(2,_buttons.toggle.disabled)
	_more_menu.get_popup().set_item_disabled(5,_buttons.compose.disabled)
	_more_menu.get_popup().set_item_disabled(6,_plan.object_layers.is_empty() and not _plan.regions.any(func(item):return item.get("kind") in ["grove","placement"]))
	_description.tooltip_text=_description.text
	_description.text="%d×%d м · начало (%d, %d)"%[rect.size.x,rect.size.y,rect.position.x,rect.position.y]
	if not path and _point_mode in ["insert","remove"]: _point_mode="move"
	set_point_mode(_point_mode)

func set_compact(value: bool)->void:
	_ensure_controls()
	_compact=value;_scroll.visible=not value;_picker.visible=value
	size_flags_vertical=Control.SIZE_SHRINK_BEGIN if value else Control.SIZE_EXPAND_FILL

func set_point_mode(value:String)->void:
	_point_mode=value
	for mode in ["move","translate","insert","remove"]:_buttons["point_"+mode].set_pressed_no_signal(mode==value)
	var index:int=_plan.index_of(selected_id()) if _plan!=null else -1
	var path:bool=index>=0 and Plan.Influence.plan_is_path(_plan.regions[index])
	_point_info.text="Тяни центр или область целиком · Esc отменяет" if value=="translate" else "Кликни по линии, чтобы добавить точку" if value=="insert" else "Кликни по точке, чтобы удалить" if value=="remove" else "Тяни точку · Esc отменяет" if path else "Тяни угол границы · Esc отменяет"

func set_point_selection(index:int,count:int)->void:
	if index<0:return
	var region_index:int=_plan.index_of(selected_id()) if _plan!=null else -1
	var path:bool=region_index>=0 and Plan.Influence.plan_is_path(_plan.regions[region_index])
	_point_info.text="Точка %d из %d · Delete — удалить"%[index+1,count] if path else "Угол %d из 4 · Esc отменяет"%[index+1]

func set_status(message: String) -> void:
	_status.text = message
	if _compact:_point_info.text=message

func _rename_selected()->void:
	var id:=selected_id()
	if id.is_empty():return
	var dialog:=ConfirmationDialog.new();dialog.title="Название области";add_child(dialog)
	var field:=LineEdit.new();field.text=_name.text;dialog.add_child(field)
	dialog.confirmed.connect(func():action_requested.emit("name",id,field.text);dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(360,110));field.grab_focus();field.select_all()

func _ensure_controls()->void:
	# Reconstruct only this view after a tool-script reload; document/history
	# stay with WorldEditor and the same Plan Resource.
	if is_instance_valid(_picker):return
	var old_plan:Resource=_plan
	var old_id:=selected_id() if is_instance_valid(_list) else ""
	for child in get_children():remove_child(child);child.queue_free()
	_buttons={};_ready()
	if old_plan!=null:show_plan(old_plan,old_id,false)
