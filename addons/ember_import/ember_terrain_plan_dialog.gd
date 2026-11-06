@tool
extends VBoxContainer
signal action_requested(action: String, id: String, value: String)
signal selection_changed(id: String)
const Plan = preload("res://scripts/ember_terrain_plan_resource.gd")
const Plot = preload("res://addons/ember_import/ember_plot_construction.gd")
var _list: ItemList
var _name: LineEdit
var _description: Label
var _status: Label
var _buttons := {}
var _plan: Resource
var _updating := false
var _compact:=false
var _scroll: ScrollContainer
var _street_tools: VBoxContainer
var _picker: OptionButton
var _add_menu: MenuButton
var _more_menu: MenuButton
var _general_row: GridContainer
var _point_tools: GridContainer
var _point_info: Label
var _profile_box: VBoxContainer
var _profile_plot: Control
var _profile_label: Label
var _profile_bridge: Button
var _profile_bridge_shape: OptionButton
var _profile_bridge_rise: SpinBox
var _profile_bridge_supports: OptionButton
var _profile_bridge_covering: OptionButton
var _profile_plank_roughness: SpinBox
var _profile_bridge_railing: OptionButton
var _road_profile := {}
var _point_mode:="move"
var _hint: Label
var _plot_tools: VBoxContainer
var _selected_roof_settings: Dictionary = {}
var _selected_window_settings: Dictionary = {}
var _selected_finish_settings: Dictionary = {}
var _house: OptionButton
var _opening_fields: GridContainer
const ADD_ACTIONS := ["add","add_plateau","add_lake","add_river","add_coast","add_mountain","add_road","add_surface_road","add_placement","add_grove","add_plot"]
const ADD_NAMES := ["Область рельефа","Плато","Озеро","Река","Море","Гора","Дорога","Дорога по уступу","Объекты","Роща","Строительный участок"]
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
		action_requested.emit("extend_branch" if index == 0 and _buttons.extend_branch.visible else MORE_ACTIONS[index],selected_id(),""))
	_picker=OptionButton.new();add_child(_picker);_picker.hide()
	_picker.item_selected.connect(func(index):_list.select(index);_refresh_selection();selection_changed.emit(selected_id()))
	_point_tools=GridContainer.new();_point_tools.columns=2;add_child(_point_tools)
	for spec in [["move","Точки"],["translate","Перенос"],["insert","+ Точку"],["remove","− Точку"]]:
		var button:=Button.new();button.text=spec[1];button.toggle_mode=true;button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_point_tools.add_child(button);_buttons["point_"+spec[0]]=button
		button.pressed.connect(func():set_point_mode(spec[0]);action_requested.emit("point_mode",selected_id(),spec[0]))
	_point_info=Label.new();_point_info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(_point_info)
	_point_tools.hide();_point_info.hide()
	for spec in [["extend_branch","Продолжить с конца"],["preview_branch","Предпросмотр правок"]]:
		var branch_button := Button.new()
		branch_button.text = spec[1]
		branch_button.pressed.connect(func(): action_requested.emit(spec[0],selected_id(),""))
		add_child(branch_button)
		branch_button.hide()
		_buttons[spec[0]] = branch_button
	_profile_box = VBoxContainer.new()
	add_child(_profile_box)
	var profile_title := Label.new()
	profile_title.text = "Профиль высот"
	_profile_box.add_child(profile_title)
	_profile_plot = Control.new()
	_profile_plot.custom_minimum_size.y = 84
	_profile_plot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_profile_plot.draw.connect(_draw_road_profile)
	_profile_plot.resized.connect(_profile_plot.queue_redraw)
	_profile_box.add_child(_profile_plot)
	_profile_label = Label.new()
	_profile_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_profile_box.add_child(_profile_label)
	_profile_bridge_shape = OptionButton.new()
	_profile_bridge_shape.add_item("Настил · прямой")
	_profile_bridge_shape.add_item("Настил · дуга")
	_profile_bridge_shape.item_selected.connect(func(index): _profile_bridge_rise.visible = index == 1)
	_profile_box.add_child(_profile_bridge_shape)
	_profile_bridge_rise = SpinBox.new()
	_profile_bridge_rise.prefix = "Подъём"
	_profile_bridge_rise.suffix = "м"
	_profile_bridge_rise.min_value = 0.05
	_profile_bridge_rise.max_value = 4.0
	_profile_bridge_rise.step = 0.05
	_profile_bridge_rise.value = 0.5
	_profile_box.add_child(_profile_bridge_rise)
	_profile_bridge_supports = OptionButton.new()
	for option in [["none", "Опоры · без опор"], ["wood", "Опоры · деревянные стойки"],
			["stone", "Опоры · каменные быки"], ["arch", "Опоры · каменные арки"]]:
		_profile_bridge_supports.add_item(option[1])
		_profile_bridge_supports.set_item_metadata(_profile_bridge_supports.item_count - 1, option[0])
	_profile_box.add_child(_profile_bridge_supports)
	_profile_bridge_covering = OptionButton.new()
	_profile_bridge_covering.add_item("Покрытие моста · по дороге")
	_profile_bridge_covering.add_item("Покрытие моста · доски")
	_profile_bridge_covering.item_selected.connect(func(index): _profile_plank_roughness.visible = index == 1)
	_profile_box.add_child(_profile_bridge_covering)
	_profile_plank_roughness = SpinBox.new()
	_profile_plank_roughness.prefix = "Неровность досок"
	_profile_plank_roughness.suffix = "%"
	_profile_plank_roughness.max_value = 100.0
	_profile_plank_roughness.step = 5.0
	_profile_box.add_child(_profile_plank_roughness)
	_profile_bridge_railing = OptionButton.new()
	_profile_bridge_railing.add_item("Перила моста · каменный парапет")
	_profile_bridge_railing.add_item("Перила моста · деревянная решётка")
	_profile_box.add_child(_profile_bridge_railing)
	_profile_bridge = Button.new()
	_profile_bridge.text = "Примерить мост"
	_profile_bridge.pressed.connect(func(): action_requested.emit("surface_bridge_preview", selected_id(), ""))
	_profile_box.add_child(_profile_bridge)
	_profile_box.hide()
	var street_open := Button.new()
	street_open.text = "Участки вдоль дороги"
	street_open.pressed.connect(_request_plot_piece.bind("street_panel", ""))
	add_child(street_open)
	_buttons.street_panel = street_open
	street_open.hide()
	var bridge_style := OptionButton.new()
	bridge_style.add_item("Мост · дерево")
	bridge_style.set_item_metadata(0, "wood")
	bridge_style.add_item("Мост · камень")
	bridge_style.set_item_metadata(1, "stone")
	bridge_style.add_item("Мост · разрушен")
	bridge_style.set_item_metadata(2, "broken")
	bridge_style.item_selected.connect(func(index: int):
		_request_plot_piece("street_bridge_style", bridge_style.get_item_metadata(index)))
	add_child(bridge_style)
	_buttons.street_bridge_style = bridge_style
	bridge_style.hide()
	for spec in [
		["deck", [["Настил · по облику", "preset"], ["Настил · дерево", "wood"], ["Настил · камень", "stone"], ["Настил · брусчатка", "paving"]]],
		["rail", [["Перила · по облику", "preset"], ["Перила · деревянные", "wood"], ["Перила · каменные", "stone"], ["Перила · деревянная решётка", "lattice"]]],
		["snap", [["Стык · как у моста", "keep"], ["Стык · край дороги", "edge"], ["Стык · ось дороги", "axis"]]],
	]:
		var control := OptionButton.new()
		var key: String = spec[0]
		for item in spec[1]:
			control.add_item(item[0])
			control.set_item_metadata(control.item_count - 1, item[1])
		control.item_selected.connect(func(_index): _request_plot_piece("street_bridge_" + key, ""))
		add_child(control)
		_buttons["street_bridge_" + key] = control
		control.hide()
	var bridge := Button.new()
	bridge.text = "Соединить дороги мостом"
	bridge.pressed.connect(_request_plot_piece.bind("street_bridge", ""))
	add_child(bridge)
	_buttons.street_bridge = bridge
	bridge.hide()
	var edit_bridge := Button.new()
	edit_bridge.text = "Изменить облик моста"
	edit_bridge.pressed.connect(_request_plot_piece.bind("street_bridge_edit", ""))
	add_child(edit_bridge)
	_buttons.street_bridge_edit = edit_bridge
	var branch := Button.new()
	branch.text = "Начать ответвление"
	branch.pressed.connect(func(): action_requested.emit("add_road_branch", selected_id(), ""))
	add_child(branch)
	_buttons.road_branch = branch
	edit_bridge.hide()
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
	_street_tools = VBoxContainer.new()
	box.add_child(_street_tools)
	_street_tools.hide()
	var street_side := OptionButton.new()
	street_side.add_item("Справа по ходу дороги")
	street_side.add_item("Слева по ходу дороги")
	street_side.item_selected.connect(func(_index): _request_plot_piece("street_clear", ""))
	_street_tools.add_child(street_side)
	_buttons.street_side = street_side
	for spec in [["width", "Ширина вдоль улицы", 4, 24, 8], ["depth", "Глубина участка", 4, 24, 10],
			["gap", "Промежуток", 0, 8, 2], ["setback", "Отступ от обочины", 0, 12, 2]]:
		var street_size := SpinBox.new()
		street_size.prefix = spec[1]
		street_size.suffix = "м"
		street_size.min_value = spec[2]
		street_size.max_value = spec[3]
		street_size.step = 1
		street_size.value = spec[4]
		street_size.value_changed.connect(func(_value): _request_plot_piece("street_clear", ""))
		_street_tools.add_child(street_size)
		_buttons["street_" + spec[0]] = street_size
	var street_entries := CheckBox.new()
	street_entries.text = "Деревянная ограда и подход"
	street_entries.tooltip_text = "Снимите галочку для свободных участков. Ограду или живую изгородь можно поставить позднее."
	street_entries.button_pressed = true
	street_entries.toggled.connect(func(_enabled): _request_plot_piece("street_clear", ""))
	_street_tools.add_child(street_entries)
	_buttons.street_entries = street_entries
	var block_scope := OptionButton.new()
	for option in [["Квартал · внутри", "inside"], ["Квартал · снаружи", "outside"], ["Квартал · с обеих сторон", "both"]]:
		block_scope.add_item(option[0])
		block_scope.set_item_metadata(block_scope.item_count - 1, option[1])
	block_scope.item_selected.connect(func(_index): _request_plot_piece("street_clear", ""))
	_street_tools.add_child(block_scope)
	_buttons.street_block_scope = block_scope
	for spec in [["street_preview", "Показать участки"], ["street_block_preview", "Разметить квартал"],
			["street_place", "Примерить один участок"],
			["street_apply", "Создать участки"], ["street_clear", "Убрать предпросмотр"]]:
		var street_action := Button.new()
		street_action.text = spec[1]
		street_action.pressed.connect(_request_plot_piece.bind(spec[0], ""))
		_street_tools.add_child(street_action)
		_buttons[spec[0]] = street_action
	_buttons.street_block_preview.tooltip_text = "Выберите одну из улиц кольца. Концы улиц должны совпадать. Сторона определяется по контуру."
	_buttons.street_place.tooltip_text = "Щёлкните рядом с улицей. Участок встанет по её направлению с текущими размерами и отступом."
	var bulk := HBoxContainer.new()
	_street_tools.add_child(bulk)
	for spec in [["street_select_all", "Выбрать все"], ["street_deselect_all", "Снять выбор"]]:
		var button := Button.new()
		button.text = spec[1]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_request_plot_piece.bind(spec[0], ""))
		bulk.add_child(button)
		_buttons[spec[0]] = button
	show_street_preview(0, 0)
	_plot_tools = VBoxContainer.new()
	box.add_child(_plot_tools)
	_house = OptionButton.new()
	_house.fit_to_longest_item = false
	_plot_tools.add_child(_house)
	var house := Button.new()
	house.text = "Поставить дом в 3D"
	house.pressed.connect(func(): action_requested.emit("plot_house", selected_id(), str(_house.get_selected_metadata())))
	_plot_tools.add_child(house)
	_buttons.plot_house = house
	var fence := Button.new()
	fence.text = "Провести ограду с проходом"
	fence.pressed.connect(func(): action_requested.emit("plot_fence", selected_id(), ""))
	_plot_tools.add_child(fence)
	var frontage := Button.new()
	frontage.text = "Ограда и вход к дороге"
	frontage.tooltip_text = "Выбрать соседнюю дорогу и примерить ограду с подходом."
	frontage.pressed.connect(_request_plot_piece.bind("plot_street_front", ""))
	_plot_tools.add_child(frontage)
	_buttons.plot_street_front = frontage
	var level := OptionButton.new()
	for index in preload("res://addons/ember_import/ember_plot_construction.gd").LEVEL_COUNT:
		level.add_item("Этаж %d" % (index + 1))
	level.item_selected.connect(func(index: int): action_requested.emit("plot_level", selected_id(), str(index)))
	_plot_tools.add_child(level)
	_buttons.plot_level = level
	var grid := CheckButton.new()
	grid.text = "Сетка этажа · привязка 0,25 м"
	grid.button_pressed = true
	grid.toggled.connect(func(_pressed: bool): action_requested.emit("plot_grid", selected_id(), ""))
	_plot_tools.add_child(grid)
	_buttons.plot_grid = grid
	var floor := Button.new()
	floor.text = "Положить перекрытие"
	floor.pressed.connect(func(): action_requested.emit("plot_floor", selected_id(), ""))
	_plot_tools.add_child(floor)
	_buttons.plot_floor = floor
	for spec in [["round", "Круглая площадка"], ["half", "Полукруглая площадка"]]:
		var radial_floor := Button.new()
		radial_floor.text = spec[1]
		radial_floor.pressed.connect(_request_plot_piece.bind("plot_floor", spec[0]))
		_plot_tools.add_child(radial_floor)
		_buttons["plot_floor_" + spec[0]] = radial_floor
	var cuts_toggle := CheckButton.new()
	cuts_toggle.text = "Срезы углов"
	_plot_tools.add_child(cuts_toggle)
	var cuts := VBoxContainer.new()
	cuts.hide()
	_plot_tools.add_child(cuts)
	cuts_toggle.toggled.connect(func(opened: bool): cuts.visible = opened)
	for pair in [["СЗ", "СВ"], ["ЮВ", "ЮЗ"]]:
		var cut_row := HBoxContainer.new()
		cuts.add_child(cut_row)
		for corner_label: String in pair:
			var cut := SpinBox.new()
			cut.prefix = corner_label
			cut.suffix = "м"
			cut.tooltip_text = "Сколько отступить от угла вдоль обеих сторон. 0 оставляет прямой угол."
			cut.max_value = 12.0
			cut.step = 0.25
			cut.value = 1.0
			cut.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cut_row.add_child(cut)
			_buttons["plot_cut_" + corner_label] = cut
	var chamfer_floor := Button.new()
	chamfer_floor.text = "Площадка со срезами"
	chamfer_floor.pressed.connect(_request_plot_piece.bind("plot_floor", "chamfer"))
	cuts.add_child(chamfer_floor)
	_buttons.plot_floor_chamfer = chamfer_floor
	var tower := HBoxContainer.new()
	_plot_tools.add_child(tower)
	for index in 2:
		var port := OptionButton.new()
		port.add_item("Проход %d · нет" % (index + 1))
		for label in Plot.TOWER_PORT_LABELS:
			port.add_item(label)
		tower.add_child(port)
		_buttons["plot_tower_port_%d" % index] = port
	var tower_deck := Button.new()
	tower_deck.text = "Площадка башни"
	tower_deck.tooltip_text = "Перекрытие с зубчатым парапетом и проходами по центру выбранных граней."
	tower_deck.pressed.connect(func(): action_requested.emit("plot_floor", selected_id(), "tower"))
	_plot_tools.add_child(tower_deck)
	_buttons.plot_tower_deck = tower_deck
	for spec in [["plot_wall_depth", "Толщина стены", 0.25, 1.5, 0.125, Plot.WALL_DEPTH_M],
			["plot_walk_width", "Ширина хода", 2.0, 8.0, 0.25, Plot.ARC_WALK_WIDTH_M],
			["plot_tower_height", "Высота башни", 2.0, 24.0, 0.25, 6.0]]:
		var size := SpinBox.new()
		size.prefix = spec[1]
		size.suffix = "м"
		size.min_value = spec[2]
		size.max_value = spec[3]
		size.step = spec[4]
		size.value = spec[5]
		_plot_tools.add_child(size)
		_buttons[spec[0]] = size
	var fortress := Button.new()
	fortress.text = "Построить башню"
	fortress.tooltip_text = "Стены от земли, площадка на заданной высоте и проёмы под выбранную ширину хода."
	fortress.pressed.connect(func(): action_requested.emit("plot_floor", selected_id(), "fortress"))
	_plot_tools.add_child(fortress)
	_buttons.plot_fortress = fortress
	var column := Button.new()
	column.text = "Поставить колонну"
	column.tooltip_text = "Щёлкните по перекрытию выбранного этажа. Цвет берётся из настройки стены."
	column.pressed.connect(func(): action_requested.emit("plot_column", selected_id(), ""))
	_plot_tools.add_child(column)
	_buttons.plot_column = column
	var apple_tree := Button.new()
	apple_tree.text = "Поставить яблоню"
	apple_tree.pressed.connect(func(): action_requested.emit("plot_apple_tree", selected_id(), ""))
	_plot_tools.add_child(apple_tree)
	_buttons.plot_apple_tree = apple_tree
	var fountain_style := OptionButton.new()
	fountain_style.add_item("Садовый фонтан · 2,25 м")
	fountain_style.add_item("Парадный фонтан · 4 м")
	_plot_tools.add_child(fountain_style)
	_buttons.fountain_style = fountain_style
	var fountain := Button.new()
	fountain.text = "Поставить фонтан"
	fountain.pressed.connect(func(): action_requested.emit("plot_fountain", selected_id(), ""))
	_plot_tools.add_child(fountain)
	_buttons.plot_fountain = fountain
	var railing := Button.new()
	railing.text = "Поставить перила"
	railing.pressed.connect(func(): action_requested.emit("plot_railing", selected_id(), ""))
	_plot_tools.add_child(railing)
	_buttons.plot_railing = railing
	var round_railing := Button.new()
	round_railing.text = "Перила по краю круга"
	round_railing.tooltip_text = "Щёлкните у края круглой площадки там, где хотите оставить вход."
	round_railing.pressed.connect(_request_plot_piece.bind("plot_railing", "round"))
	_plot_tools.add_child(round_railing)
	_buttons.plot_round_railing = round_railing
	var railing_style := OptionButton.new()
	railing_style.add_item("Металлические перила")
	railing_style.add_item("Каменный парапет")
	railing_style.add_item("Зубчатый парапет")
	_plot_tools.add_child(railing_style)
	_buttons.railing_style = railing_style
	var entry := Button.new()
	entry.text = "Поставить крыльцо"
	entry.pressed.connect(func(): action_requested.emit("plot_entry", selected_id(), ""))
	_plot_tools.add_child(entry)
	_buttons.plot_entry = entry
	var portico := CheckButton.new()
	portico.text = "Крыльцо с колоннами"
	portico.tooltip_text = "Добавляет две колонны и козырёк при постановке крыльца."
	_plot_tools.add_child(portico)
	_buttons.entry_portico = portico
	var canopy := SpinBox.new()
	canopy.min_value = 2.625
	canopy.max_value = 4.0
	canopy.step = 0.125
	canopy.value = 3.0
	canopy.prefix = "Козырёк"
	canopy.suffix = "м"
	canopy.tooltip_text = "Высота низа козырька от земли. 3 м — уровень верха первого этажа."
	canopy.hide()
	_plot_tools.add_child(canopy)
	_buttons.entry_canopy = canopy
	portico.toggled.connect(func(enabled: bool): canopy.visible = enabled)
	var edging := HBoxContainer.new()
	_plot_tools.add_child(edging)
	var edge_style := OptionButton.new()
	edge_style.fit_to_longest_item = false
	edge_style.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for label in ["Каменные плиты", "Клумба с землёй", "Клумба с кустами", "Живая изгородь"]:
		edge_style.add_item(label)
	edging.add_child(edge_style)
	_buttons.edge_style = edge_style
	var edge_depth := SpinBox.new()
	edge_depth.min_value = Plot.EDGE_MIN_DEPTH
	edge_depth.max_value = Plot.EDGE_MAX_DEPTH
	edge_depth.step = 0.25
	edge_depth.value = 1.5
	edge_depth.suffix = "м"
	edge_depth.tooltip_text = "Ширина полосы от стены наружу."
	edging.add_child(edge_depth)
	_buttons.edge_depth = edge_depth
	var hedge_height := SpinBox.new()
	hedge_height.min_value = Plot.HEDGE_MIN_HEIGHT_M
	hedge_height.max_value = Plot.HEDGE_MAX_HEIGHT_M
	hedge_height.step = 0.25
	hedge_height.value = Plot.HEDGE_HEIGHT_M
	hedge_height.prefix = "Высота изгороди "
	hedge_height.suffix = "м"
	var hedge_controls := VBoxContainer.new()
	hedge_controls.hide()
	_plot_tools.add_child(hedge_controls)
	hedge_controls.add_child(hedge_height)
	_buttons.hedge_height = hedge_height
	var hedge_leaf_size := SpinBox.new()
	hedge_leaf_size.min_value = Plot.HEDGE_MIN_LEAF_SCALE * 100.0
	hedge_leaf_size.max_value = Plot.HEDGE_MAX_LEAF_SCALE * 100.0
	hedge_leaf_size.step = 5.0
	hedge_leaf_size.value = 100.0
	hedge_leaf_size.prefix = "Размер листьев "
	hedge_leaf_size.suffix = "%"
	hedge_controls.add_child(hedge_leaf_size)
	_buttons.hedge_leaf_size = hedge_leaf_size
	var hedge_season := OptionButton.new()
	hedge_season.add_item("Изгородь · Зелёная")
	hedge_season.add_item("Изгородь · Осенняя")
	hedge_controls.add_child(hedge_season)
	_buttons.hedge_season = hedge_season
	edge_style.item_selected.connect(func(index: int): hedge_controls.visible = index == Plot.EDGE_HEDGE)
	var edge := Button.new()
	edge.text = "Провести полосу у дома"
	edge.pressed.connect(func(): action_requested.emit("plot_edge", selected_id(), ""))
	_plot_tools.add_child(edge)
	_buttons.plot_edge = edge
	var snap := CheckButton.new()
	snap.text = "Привязать полосу к крыльцу"
	snap.button_pressed = true
	snap.tooltip_text = "Притягивает концы полосы к углам площадки и ступеней."
	_plot_tools.add_child(snap)
	_buttons.edge_snap = snap
	var cornice := Button.new()
	cornice.text = "Провести карниз"
	cornice.pressed.connect(func(): action_requested.emit("plot_cornice", selected_id(), ""))
	_plot_tools.add_child(cornice)
	_buttons.plot_cornice = cornice
	var pilaster := Button.new()
	pilaster.text = "Поставить пилястру"
	pilaster.pressed.connect(func(): action_requested.emit("plot_pilaster", selected_id(), ""))
	_plot_tools.add_child(pilaster)
	_buttons.plot_pilaster = pilaster
	var balcony := Button.new()
	balcony.text = "Поставить выступающий балкон"
	balcony.pressed.connect(func(): action_requested.emit("plot_balcony", selected_id(), ""))
	_plot_tools.add_child(balcony)
	_buttons.plot_balcony = balcony
	var balcony_depth := SpinBox.new()
	balcony_depth.min_value = 1.0
	balcony_depth.max_value = 4.0
	balcony_depth.step = 0.25
	balcony_depth.value = 2.25
	balcony_depth.prefix = "Вынос балкона "
	balcony_depth.suffix = "м"
	_plot_tools.add_child(balcony_depth)
	_buttons.balcony_depth = balcony_depth
	var balcony_columns := CheckButton.new()
	balcony_columns.text = "Балкон с колоннами"
	_plot_tools.add_child(balcony_columns)
	_buttons.balcony_columns = balcony_columns
	var roof_toggle := Button.new()
	roof_toggle.text = "Крыша"
	roof_toggle.toggle_mode = true
	_plot_tools.add_child(roof_toggle)
	var roof_section := VBoxContainer.new()
	_plot_tools.add_child(roof_section)
	roof_section.hide()
	roof_toggle.toggled.connect(func(opened: bool): roof_section.visible = opened)
	var roof_form := OptionButton.new()
	for label in Plot.ROOF_FINISHES:
		roof_form.add_item(label)
	roof_section.add_child(roof_form)
	_buttons.roof_form = roof_form
	var roof_height := SpinBox.new()
	roof_height.min_value = 0.25
	roof_height.max_value = 6.0
	roof_height.step = 0.125
	roof_height.value = 2.25
	roof_height.prefix = "Высота"
	roof_height.suffix = "м"
	roof_height.tooltip_text = "От карниза до конька, верха плоской крыши или парапета."
	roof_section.add_child(roof_height)
	_buttons.roof_height = roof_height
	var roof_color := ColorPickerButton.new()
	roof_color.text = "Цвет кровли"
	roof_color.edit_alpha = false
	roof_color.color = Plot.ROOF_COLOR
	roof_section.add_child(roof_color)
	_buttons.roof_color = roof_color
	var bay := CheckButton.new()
	bay.text = "С выступом фасада"
	roof_section.add_child(bay)
	_buttons.roof_bay = bay
	var bay_fields := VBoxContainer.new()
	roof_section.add_child(bay_fields)
	bay_fields.hide()
	bay.toggled.connect(func(enabled: bool): bay_fields.visible = enabled)
	var side := OptionButton.new()
	for label in ["Передняя сторона (−Z)", "Задняя сторона (+Z)", "Левая сторона (−X)", "Правая сторона (+X)"]:
		side.add_item(label)
	bay_fields.add_child(side)
	_buttons.roof_bay_side = side
	for spec: Array in [["width", "Ширина", 2.5, 20.0, 4.0], ["depth", "Вынос", 0.5, 3.0, 1.0],
			["offset", "Сдвиг от середины", -20.0, 20.0, 0.0]]:
		var field := SpinBox.new()
		field.prefix = spec[1]
		field.min_value = spec[2]
		field.max_value = spec[3]
		field.value = spec[4]
		field.step = 0.25
		field.suffix = "м"
		bay_fields.add_child(field)
		_buttons["roof_bay_" + spec[0]] = field
	var place_roof := Button.new()
	place_roof.text = "Поставить крышу"
	place_roof.pressed.connect(func(): action_requested.emit("plot_roof", selected_id(), ""))
	roof_section.add_child(place_roof)
	_buttons.plot_roof = place_roof
	var round_roof := Button.new()
	round_roof.text = "Крыша по контуру площадки"
	round_roof.tooltip_text = "Круглая, полукруглая или гранёная кровля по выбранной площадке."
	round_roof.pressed.connect(_request_plot_piece.bind("plot_roof", "round"))
	roof_section.add_child(round_roof)
	_buttons.plot_round_roof = round_roof
	var roofs := OptionButton.new()
	roofs.fit_to_longest_item = false
	roofs.item_selected.connect(func(_index: int): action_requested.emit("plot_roof_select", selected_id(), str(roofs.get_selected_metadata())))
	roof_section.add_child(roofs)
	_buttons.plot_roofs = roofs
	var apply_roof := Button.new()
	apply_roof.text = "Изменить выбранную крышу"
	apply_roof.disabled = true
	apply_roof.pressed.connect(func(): action_requested.emit("plot_roof_apply", selected_id(), str(roofs.get_selected_metadata())))
	roof_section.add_child(apply_roof)
	_buttons.plot_roof_apply = apply_roof
	var opening := OptionButton.new()
	for label in ["Сплошная стена", "Стена с окном", "Стена с дверью", "Стена с проходом"]:
		opening.add_item(label)
	_plot_tools.add_child(opening)
	_buttons.wall_opening = opening
	var customize := CheckButton.new()
	customize.text = "Настроить проём"
	customize.hide()
	_plot_tools.add_child(customize)
	_buttons.custom_opening = customize
	_opening_fields = GridContainer.new()
	_opening_fields.columns = 2
	_opening_fields.hide()
	_plot_tools.add_child(_opening_fields)
	_add_opening_size("opening_width", "Ширина", 0.75, 3.5)
	_add_opening_size("opening_height", "Высота", 0.75, 2.875)
	_add_opening_size("opening_bottom", "От пола", 0.25, 1.75)
	_add_opening_choice("opening_top", "Верх", ["Прямой", "Арка", "Треугольник"])
	_add_opening_choice("opening_leaves", "Створки", ["Одна створка", "Две створки"])
	_add_opening_choice("opening_grid", "Переплёт", ["Цельный", "4 секции", "8 секций"])
	_add_opening_choice("opening_sill", "Подоконник", ["Нет", "Выступ справа"])
	_add_opening_choice("opening_shutters", "Ставни", ["Нет", "Открыты", "Закрыты"])
	_add_opening_choice("opening_casing", "Наличник", ["Нет", "Выступ справа"])
	_buttons.opening_sill.tooltip_text = "Наружная сторона справа по направлению от первой точки стены ко второй."
	_buttons.opening_shutters.tooltip_text = _buttons.opening_sill.tooltip_text
	_buttons.opening_casing.tooltip_text = _buttons.opening_sill.tooltip_text
	_buttons.opening_leaves.item_selected.connect(func(index: int):
		if index == 1 and _buttons.opening_width.value < Plot.DOUBLE_DOOR_MIN_WIDTH:
			_buttons.opening_width.value = 2.0
		_update_opening_leaves())
	customize.toggled.connect(func(active: bool): _opening_fields.visible = active and customize.visible)
	opening.item_selected.connect(_opening_selected)
	var paint := HBoxContainer.new()
	_plot_tools.add_child(paint)
	var paint_label := Label.new()
	paint_label.text = "Цвет стены"
	paint.add_child(paint_label)
	var wall_color := ColorPickerButton.new()
	wall_color.color = Color("e1c9a2")
	wall_color.edit_alpha = false
	wall_color.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paint.add_child(wall_color)
	_buttons.wall_color = wall_color
	var finish := OptionButton.new()
	for label in Plot.WALL_FINISHES:
		finish.add_item(label)
	finish.tooltip_text = "Материал новой стены. Цвет из поля выше тонирует текстуру."
	_plot_tools.add_child(finish)
	_buttons.wall_finish = finish
	var wall := Button.new()
	wall.text = "Провести стену"
	wall.pressed.connect(func(): action_requested.emit("plot_wall", selected_id(), str(opening.selected)))
	_plot_tools.add_child(wall)
	_buttons.plot_wall = wall
	var arc_wall := Button.new()
	arc_wall.text = "Провести дуговую стену"
	arc_wall.tooltip_text = "Три щелчка по сетке: начало, точка на дуге и конец."
	arc_wall.pressed.connect(func(): action_requested.emit("plot_arc_wall", selected_id(), ""))
	_plot_tools.add_child(arc_wall)
	_buttons.plot_arc_wall = arc_wall
	var wall_walk := CheckBox.new()
	wall_walk.text = "Ход с парапетом"
	wall_walk.tooltip_text = "Для дуговой стены. Ход будет на уровне перекрытия следующего этажа."
	_plot_tools.add_child(wall_walk)
	_buttons.plot_arc_walk = wall_walk
	var dock := CheckBox.new()
	dock.text = "Стыковать ход с башнями"
	dock.tooltip_text = "Начало и конец привязываются к открытым проходам на площадках башен."
	_plot_tools.add_child(dock)
	_buttons.plot_arc_dock = dock
	var rounding := HBoxContainer.new()
	_plot_tools.add_child(rounding)
	var round_corner := Button.new()
	round_corner.text = "Скруглить угол"
	round_corner.tooltip_text = "Наведите на верхний край стыка двух глухих стен одного этажа."
	round_corner.pressed.connect(func(): action_requested.emit("plot_round_corner", selected_id(), ""))
	rounding.add_child(round_corner)
	_buttons.plot_round_corner = round_corner
	var radius := SpinBox.new()
	radius.prefix = "Радиус"
	radius.suffix = "м"
	radius.min_value = 0.75
	radius.max_value = 48.0
	radius.step = 0.25
	radius.value = 2.0
	radius.tooltip_text = "Радиус по середине стены. Уменьшите его, если на стенах не хватает места."
	radius.value_changed.connect(func(_value): action_requested.emit("plot_round_radius", selected_id(), ""))
	rounding.add_child(radius)
	_buttons.plot_round_radius = radius
	var choose_window := Button.new()
	choose_window.text = "Выбрать окно или дверь"
	choose_window.pressed.connect(func(): action_requested.emit("plot_window_pick", selected_id(), ""))
	_plot_tools.add_child(choose_window)
	_buttons.plot_window_pick = choose_window
	var window_edit := VBoxContainer.new()
	window_edit.hide()
	_plot_tools.add_child(window_edit)
	_buttons.window_edit = window_edit
	var center := SpinBox.new()
	center.min_value = 0.0
	center.max_value = 48.0
	center.step = 0.125
	center.prefix = "От начала стены "
	center.suffix = "м"
	center.tooltip_text = "Положение центра окна вдоль стены от первой точки."
	window_edit.add_child(center)
	_buttons.window_center = center
	var recenter := Button.new()
	recenter.text = "По центру стены"
	recenter.pressed.connect(func(): center.value = center.max_value * 0.5)
	window_edit.add_child(recenter)
	_buttons.window_recenter = recenter
	var apply_window := Button.new()
	apply_window.text = "Применить к проёму и стене"
	apply_window.pressed.connect(func(): action_requested.emit("plot_window_apply", selected_id(), ""))
	window_edit.add_child(apply_window)
	_buttons.plot_window_apply = apply_window
	var pick_finish := Button.new()
	pick_finish.text = "Выбрать деталь для отделки"
	pick_finish.pressed.connect(func(): action_requested.emit("plot_finish_pick", selected_id(), ""))
	_plot_tools.add_child(pick_finish)
	_buttons.plot_finish_pick = pick_finish
	var finish_edit := VBoxContainer.new()
	finish_edit.hide()
	_plot_tools.add_child(finish_edit)
	_buttons.finish_edit = finish_edit
	var finish_target := Label.new()
	finish_edit.add_child(finish_target)
	_buttons.finish_target = finish_target
	var finish_texture := OptionButton.new()
	finish_texture.add_item("Без текстуры")
	for index in range(1, Plot.WALL_FINISHES.size()):
		finish_texture.add_item(Plot.WALL_FINISHES[index])
	finish_edit.add_child(finish_texture)
	_buttons.finish_texture = finish_texture
	var finish_color := ColorPickerButton.new()
	finish_color.text = "Оттенок отделки"
	finish_color.edit_alpha = false
	finish_edit.add_child(finish_color)
	_buttons.finish_color = finish_color
	var finish_scale := SpinBox.new()
	finish_scale.min_value = 0.25
	finish_scale.max_value = 4.0
	finish_scale.step = 0.05
	finish_scale.prefix = "Частота рисунка ×"
	finish_scale.tooltip_text = "Чем больше число, тем мельче рисунок текстуры."
	finish_edit.add_child(finish_scale)
	_buttons.finish_scale = finish_scale
	finish_texture.item_selected.connect(func(index: int): finish_scale.editable = index != 0)
	for spec in [["plot_finish_apply", "Применить отделку"], ["plot_finish_reset", "Вернуть исходную отделку"]]:
		var action: String = spec[0]
		var button := Button.new()
		button.text = spec[1]
		button.pressed.connect(func(): action_requested.emit(action, selected_id(), ""))
		finish_edit.add_child(button)
		_buttons[action] = button
	_plot_tools.hide()
	var toggle := Button.new(); toggle.text = "Включить / выключить"; toggle.pressed.connect(func(): action_requested.emit("toggle", selected_id(), "")); box.add_child(toggle); _buttons.toggle = toggle
	var reverse := Button.new(); reverse.text = "Развернуть реку"; reverse.pressed.connect(func(): action_requested.emit("reverse",selected_id(),"")); box.add_child(reverse); _buttons.reverse = reverse
	var compose := Button.new(); compose.text = "Обновить области →"; compose.pressed.connect(func(): action_requested.emit("compose", "", "")); box.add_child(compose); _buttons.compose = compose
	var groves := Button.new(); groves.text = "Обновить расстановку →"; groves.pressed.connect(func(): action_requested.emit("groves","","")); box.add_child(groves); _buttons.groves = groves
	_status = Label.new(); _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; box.add_child(_status)


func _add_opening_label(key: String, title: String) -> void:
	var label := Label.new()
	label.text = title
	_opening_fields.add_child(label)
	_buttons[key + "_label"] = label


func _add_opening_size(key: String, title: String, minimum: float, maximum: float) -> void:
	_add_opening_label(key, title)
	var field := SpinBox.new()
	field.min_value = minimum
	field.max_value = maximum
	field.step = 0.125
	field.suffix = "м"
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_opening_fields.add_child(field)
	_buttons[key] = field


func _add_opening_choice(key: String, title: String, labels: Array) -> void:
	_add_opening_label(key, title)
	var field := OptionButton.new()
	for label in labels:
		field.add_item(label)
	_opening_fields.add_child(field)
	_buttons[key] = field


func _opening_selected(kind: int) -> void:
	var window := kind == Plot.WALL_WINDOW
	_buttons.custom_opening.visible = window or kind == Plot.WALL_DOOR
	_opening_fields.visible = _buttons.custom_opening.visible and _buttons.custom_opening.button_pressed
	if not _buttons.custom_opening.visible:
		return
	var defaults := Plot.opening_defaults(kind)
	_buttons.opening_width.value = defaults.width
	if kind == Plot.WALL_DOOR and _buttons.opening_leaves.selected == 1:
		_buttons.opening_width.value = 2.0
	_buttons.opening_height.value = defaults.height
	if window:
		_buttons.opening_bottom.value = defaults.bottom
	for key in ["opening_bottom", "opening_sill", "opening_shutters"]:
		_buttons[key].visible = window
		_buttons[key + "_label"].visible = window
	_update_opening_leaves()


func _update_opening_leaves() -> void:
	var door: bool = _buttons.wall_opening.selected == Plot.WALL_DOOR
	_buttons.opening_leaves.visible = door
	_buttons.opening_leaves_label.visible = door
	var show_grid: bool = not door or _buttons.opening_leaves.selected == 0
	_buttons.opening_grid.visible = show_grid
	_buttons.opening_grid_label.visible = show_grid


func _request_plot_piece(action: String, value: String) -> void:
	action_requested.emit(action, selected_id(), value)


func street_plot_options() -> Dictionary:
	return {"size": Vector2i(_buttons.street_width.value, _buttons.street_depth.value),
		"side": 1 if _buttons.street_side.selected == 0 else -1,
		"gap": int(_buttons.street_gap.value), "setback": int(_buttons.street_setback.value),
		"entries": _buttons.street_entries.button_pressed,
		"scope": _buttons.street_block_scope.get_selected_metadata()}


func show_street_preview(accepted: int, total: int) -> void:
	_buttons.street_apply.disabled = accepted == 0
	_buttons.street_apply.text = "Создать участки (%d)" % accepted if total > 0 else "Создать участки"
	_buttons.street_clear.disabled = total == 0
	_buttons.street_select_all.disabled = accepted == total
	_buttons.street_deselect_all.disabled = accepted == 0


func opening_options(kind: int) -> Dictionary:
	if kind not in [Plot.WALL_WINDOW, Plot.WALL_DOOR] or not _buttons.custom_opening.button_pressed:
		return {}
	return {
		"width": _buttons.opening_width.value,
		"height": _buttons.opening_height.value,
		"bottom": _buttons.opening_bottom.value if kind == Plot.WALL_WINDOW else 0.0,
		"top_shape": _buttons.opening_top.selected,
		"grid": _buttons.opening_grid.selected,
		"sill": kind == Plot.WALL_WINDOW and _buttons.opening_sill.selected == 1,
		"shutters": _buttons.opening_shutters.selected if kind == Plot.WALL_WINDOW else 0,
		"casing": _buttons.opening_casing.selected == 1,
		"double_leaf": kind == Plot.WALL_DOOR and _buttons.opening_leaves.selected == 1,
	}


func selected_id() -> String:
	var selected := _list.get_selected_items()
	return _plan.regions[selected[0]].id if _plan != null and not selected.is_empty() else ""


func roof_options() -> Dictionary:
	var bay := {}
	if _buttons.roof_bay.button_pressed:
		bay = {"side": _buttons.roof_bay_side.selected, "width": _buttons.roof_bay_width.value,
			"depth": _buttons.roof_bay_depth.value, "offset": _buttons.roof_bay_offset.value}
	return {"shape": _buttons.roof_form.selected, "height": _buttons.roof_height.value, "color": _buttons.roof_color.color, "bay": bay}


func show_window(options: Dictionary, finish: Dictionary, span: float) -> void:
	_buttons.window_edit.visible = not options.is_empty()
	if options.is_empty():
		_selected_window_settings.clear()
		return
	var state := options.merged(finish)
	if _selected_window_settings == state:
		return
	_selected_window_settings = state
	_buttons.wall_opening.select(options.kind)
	_opening_selected(options.kind)
	_buttons.custom_opening.button_pressed = true
	_buttons.opening_width.value = options.width
	_buttons.opening_height.value = options.height
	_buttons.opening_bottom.value = options.bottom
	_buttons.opening_top.select(options.get("top_shape", 0))
	_buttons.opening_grid.select(options.get("grid", 0))
	_buttons.opening_sill.select(1 if options.get("sill", false) else 0)
	_buttons.opening_shutters.select(options.get("shutters", 0))
	_buttons.opening_casing.select(1 if options.get("casing", false) else 0)
	_buttons.opening_leaves.select(1 if options.get("double_leaf", false) else 0)
	_update_opening_leaves()
	_buttons.wall_color.color = finish.color
	_buttons.wall_finish.select(maxi(0, finish.finish))
	_buttons.window_center.visible = options.kind == Plot.WALL_WINDOW
	_buttons.window_recenter.visible = options.kind == Plot.WALL_WINDOW
	_buttons.window_center.max_value = span
	_buttons.window_center.value = options.center


func show_piece_finish(piece: String, settings: Dictionary) -> void:
	_buttons.finish_edit.visible = not settings.is_empty()
	if settings.is_empty():
		_selected_finish_settings.clear()
		return
	var state := settings.merged({"piece": piece})
	if _selected_finish_settings == state:
		return
	_selected_finish_settings = state
	_buttons.finish_target.text = piece
	_buttons.finish_texture.select(settings.finish)
	_buttons.finish_color.color = settings.color
	_buttons.finish_scale.set_value_no_signal(settings.scale)
	_buttons.finish_scale.editable = settings.finish != 0


func set_roof_options(settings: Dictionary) -> void:
	_selected_roof_settings = settings.duplicate()
	_buttons.roof_form.select(settings.shape)
	_buttons.roof_height.value = settings.height
	_buttons.roof_color.color = settings.color
	var bay: Dictionary = settings.get("bay", {})
	_buttons.roof_bay.button_pressed = not bay.is_empty()
	if not bay.is_empty():
		_buttons.roof_bay_side.select(bay.side)
		_buttons.roof_bay_width.value = bay.width
		_buttons.roof_bay_depth.value = bay.depth
		_buttons.roof_bay_offset.value = bay.offset


func show_roofs(members: Array[Node3D]) -> void:
	var roofs: OptionButton = _buttons.plot_roofs
	var selected = roofs.get_selected_metadata() if roofs.selected >= 0 else null
	roofs.clear()
	roofs.add_item("Выбрать крышу")
	roofs.set_item_metadata(0, "")
	var index := 0
	var current: Dictionary = {}
	for node in members:
		var settings: Dictionary = node.get_meta(Plot.ROOF_META)
		if settings.has("round") and settings.round.has("points"):
			roofs.add_item("%d · Гранёная · сторон %d" % [roofs.item_count, settings.round.points.size()])
		elif settings.has("round"):
			var title := "Полукруглая" if settings.round.half else "Круглая"
			roofs.add_item("%d · %s · радиус %.2f м" % [roofs.item_count, title, settings.round.radius])
		else:
			roofs.add_item("%d · %s · %s × %s м" % [roofs.item_count, Plot.ROOF_FINISHES[settings.shape], settings.size.x, settings.size.y])
		roofs.set_item_metadata(roofs.item_count - 1, node.name)
		if node.name == selected:
			index = roofs.item_count - 1
			current = settings
	roofs.select(index)
	roofs.disabled = members.is_empty()
	_buttons.plot_roof_apply.disabled = index == 0
	if current.is_empty():
		_selected_roof_settings.clear()
	elif current != _selected_roof_settings:
		set_roof_options(current)

func show_plan(plan: Resource, selected := "", reveal := true) -> void:
	_ensure_controls()
	_plan = plan; _updating = true
	_list.clear();_picker.clear()
	for region: Dictionary in plan.regions:
		var kind: String = region.get("kind","generation")
		var suffix := " · море" if kind=="coast" else " · роща" if kind == "grove" else " · объекты" if kind == "placement" else " · дорога" if kind == "road" else " · гора" if kind == "mountain" else " · река" if kind == "river" else " · озеро" if kind == "lake" else " · плато" if kind == "plateau" else ""
		if kind == "construction": suffix = " · строительство"
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
	var construction: bool = not id.is_empty() and _plan.regions[_plan.index_of(id)].get("kind") == "construction"
	_plot_tools.visible = construction
	_buttons.generate.visible = not construction
	if construction and _house.item_count == 0:
		for house in Plot.house_choices():
			_house.add_item(house.name)
			_house.set_item_metadata(_house.item_count - 1, house.id)
		_buttons.plot_house.disabled = _house.item_count == 0
	for key in ["bounds", "delete", "name", "generate"]: _buttons[key].disabled = id.is_empty()
	var river: bool = not id.is_empty() and _plan.regions[_plan.index_of(id)].get("kind") == "river"
	var road: bool = not id.is_empty() and _plan.regions[_plan.index_of(id)].get("kind") == "road"
	var branch: bool = road and _plan.regions[_plan.index_of(id)].has("road_join")
	_buttons.extend_branch.visible = branch
	_buttons.preview_branch.visible = branch
	_buttons.point_translate.visible = not branch
	set_branch_pending(false)
	_street_tools.visible = road
	_buttons.street_panel.visible = road and _compact
	_buttons.street_bridge.visible = road
	_buttons.street_bridge_style.visible = road
	for key in ["deck", "rail", "snap"]:
		_buttons["street_bridge_" + key].visible = road
	_buttons.street_bridge_edit.visible = road
	_buttons.road_branch.visible = road and not _plan.regions[_plan.index_of(id)].has("support_placement_id") and not _plan.regions[_plan.index_of(id)].has("road_join")
	_buttons.road_branch.disabled = road and not _plan.regions[_plan.index_of(id)].get("enabled", true)
	var coast: bool=not id.is_empty() and _plan.regions[_plan.index_of(id)].get("kind")=="coast"
	_buttons.reverse.visible = river or coast;_buttons.reverse.text="Поменять сторону моря" if coast else "Развернуть реку"
	_buttons.bounds.text="Линия берега" if coast else "Границы"
	if not coast: _buttons.bounds.text = "Линия дороги" if road else "Линия реки" if river else "Границы"
	if road and _plan.regions[_plan.index_of(id)].has("support_placement_id"):
		_buttons.bounds.text = "Линия и профиль"
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
	if region.get("kind") not in ["river","road","coast","grove","placement","construction"] and (rect.size.x > 96 or rect.size.y > 96): _description.text += "\nГенерация сейчас доступна для области до 96×96 м."
	if region.get("kind", "generation") == "plateau": _description.text += "\nВлияния плато применяются в порядке списка. Ручные правки сохраняются; вода не меняется."
	if region.get("kind", "generation") == "lake": _description.text += "\nОвальная котловина со своим уровнем воды. После переноса/выключения обновите локальные области; ручные правки сохраняются."
	if coast:_description.text+="\nЛиния берега, море справа по её ходу. Перенаметьте линию или поменяйте сторону; уровень, глубина и ширина берега — в параметрах. Предпросмотр и применение обновляют только область моря; ручные правки защищаются."
	if river: _description.text += "\nЛиния от высокого водоёма к низкому, до 96 м. Уровни берутся из водоёмов на концах; озеро должно стоять раньше реки в списке. «Линия реки» позволяет перенаметить точки."
	if region.get("kind") == "mountain": _description.text += "\nГора поднимает сухую землю к заданной высоте вершины. Ширина вершины и склонов измеряется по меньшей стороне области; вытянутое выделение даёт вытянутую возвышенность."
	if road: _description.text += "\nВ параметрах дороги можно выбрать ширину и покрытие. Ручные правки земли сохраняются."
	if region.get("kind") == "placement": _description.text += "\nГотовые объекты из общей библиотеки, один или смешанный набор. Размеры оснований, интервалы, вода, дороги и соседи учитываются в предпросмотре. Бюджет зависит от площади области и созданных участков. После переноса/off/delete нажмите «Обновить расстановку». Ручные правки сохраняются."
	if region.get("kind") == "grove": _description.text += "\nСохранённые варианты деревьев на готовой земле. Бюджет зависит от площади рощи и созданных участков. После переноса, выключения или удаления нажмите «Обновить расстановку». Ручные объекты и изменённые деревья сохраняются. Изменение земли не переставляет деревья автоматически."

	_general_row.hide(); _hint.hide(); _more_menu.show()
	_point_tools.show(); _point_info.show(); _name.hide()
	_buttons.generate.text="Параметры области →"
	for key in ["bounds","delete","toggle","reverse","compose","groves","name"]: _buttons[key].hide()
	var path := Plan.Influence.plan_is_path(region)
	_buttons.point_move.text="Точки" if path else "Углы"
	_buttons.point_insert.visible=path; _buttons.point_remove.visible=path
	_more_menu.get_popup().set_item_text(0,"Продолжить с конца" if branch else "Нарисовать линию заново" if path
		else "Двигать углы по сетке участка" if region.has("plot_frame") else "Нарисовать границы заново")
	_more_menu.get_popup().set_item_text(1,"Поменять сторону моря" if coast else "Развернуть реку")
	_more_menu.get_popup().set_item_disabled(1,not (river or coast))
	_more_menu.get_popup().set_item_disabled(2,_buttons.toggle.disabled)
	_more_menu.get_popup().set_item_disabled(5,_buttons.compose.disabled)
	_more_menu.get_popup().set_item_disabled(6,_plan.object_layers.is_empty() and not _plan.regions.any(func(item):return item.get("kind") in ["grove","placement"]))
	_description.tooltip_text=_description.text
	if region.has("plot_frame"):
		_description.text = "%d×%d м · сетка вдоль улицы" % [region.plot_size_m.x, region.plot_size_m.y]
		_description.tooltip_text = _description.text
	else:
		_description.text="%d×%d м · начало (%d, %d)"%[rect.size.x,rect.size.y,rect.position.x,rect.position.y]
	if not path and _point_mode in ["insert","remove"]: _point_mode="move"
	set_point_mode(_point_mode)

func bridge_options() -> Dictionary:
	return {
		"deck": _buttons.street_bridge_deck.get_selected_metadata(),
		"rail": _buttons.street_bridge_rail.get_selected_metadata(),
		"snap": _buttons.street_bridge_snap.get_selected_metadata(),
	}


func set_compact(value: bool)->void:
	_ensure_controls()
	_compact=value;_scroll.visible=not value;_picker.visible=value
	_buttons.street_panel.visible = _street_tools.visible and value
	size_flags_vertical=Control.SIZE_SHRINK_BEGIN if value else Control.SIZE_EXPAND_FILL

func set_point_mode(value:String)->void:
	_point_mode=value
	for mode in ["move","translate","insert","remove"]:_buttons["point_"+mode].set_pressed_no_signal(mode==value)
	var index:int=_plan.index_of(selected_id()) if _plan!=null else -1
	var path:bool=index>=0 and Plan.Influence.plan_is_path(_plan.regions[index])
	_point_info.text="Тяни центр или область целиком · Esc отменяет" if value=="translate" else "Наведи на линию для примерки точки, щёлкни для вставки" if value=="insert" else "Кликни по точке, чтобы удалить" if value=="remove" else "Тяни точку · наведение показывает сетку и координаты" if path else "Тяни угол границы · Esc отменяет"

func set_point_selection(index:int,count:int)->void:
	if index<0:return
	var region_index:int=_plan.index_of(selected_id()) if _plan!=null else -1
	var path:bool=region_index>=0 and Plan.Influence.plan_is_path(_plan.regions[region_index])
	_point_info.text="Точка %d из %d · Delete — удалить"%[index+1,count] if path else "Угол %d из 4 · Esc отменяет"%[index+1]

func set_status(message: String) -> void:
	_status.text = message
	if _compact:_point_info.text=message


func set_branch_pending(pending: bool) -> void:
	_buttons.preview_branch.disabled = not pending


func bridge_profile_rise() -> float:
	return _profile_bridge_rise.value if _profile_bridge_shape.selected == 1 else 0.0


func bridge_profile_supports() -> String:
	return _profile_bridge_supports.get_selected_metadata()


func bridge_plank_roughness() -> Variant:
	return _profile_plank_roughness.value / 100.0 if _profile_bridge_covering.selected == 1 else null


func bridge_profile_railing() -> String:
	return "lattice" if _profile_bridge_railing.selected == 1 else "stone"


func set_road_profile(profile: Dictionary, problem := "", offer_bridge := false, rise := 0.0, supports := "none", planks: Variant = null, railing := "stone") -> void:
	if not is_instance_valid(_profile_box):
		return
	_road_profile = profile
	_profile_bridge.visible = offer_bridge
	_profile_bridge.text = "Обновить примерку моста" if profile.has("deck") else "Примерить мост"
	_profile_bridge_shape.visible = offer_bridge
	_profile_bridge_supports.visible = offer_bridge
	_profile_bridge_covering.visible = offer_bridge
	_profile_bridge_railing.visible = offer_bridge
	_profile_bridge_railing.select(1 if railing == "lattice" else 0)
	_profile_bridge_covering.select(0 if planks == null else 1)
	_profile_plank_roughness.visible = offer_bridge and planks != null
	_profile_plank_roughness.set_value_no_signal(0.0 if planks == null else float(planks) * 100.0)
	for index in _profile_bridge_supports.item_count:
		if _profile_bridge_supports.get_item_metadata(index) == supports:
			_profile_bridge_supports.select(index)
			break
	_profile_bridge_shape.select(1 if rise > 0.0 else 0)
	_profile_bridge_rise.visible = offer_bridge and rise > 0.0
	_profile_bridge_rise.set_value_no_signal(rise if rise > 0.0 else 0.5)
	_profile_box.visible = not profile.is_empty()
	if profile.is_empty():
		return
	var lines := PackedStringArray(["Зелёный — земля · голубой — уступ · красный — разрыв или ступень"])
	var spacing: float = profile.length / (profile.heights.size() - 1)
	if profile.has("deck"):
		var rows: Vector2i = profile.deck.rows
		lines.append("Настил: %.1f–%.1f м от начала. Enter — поставить · Esc — отменить." % [rows.x * spacing, rows.y * spacing])
	else:
		for span: Vector2i in profile.spans.slice(0, 3):
			lines.append("Предложение: мост на %.1f–%.1f м от начала" % [span.x * spacing, span.y * spacing])
	if profile.spans.size() > 3:
		lines.append("Других пролётов на профиле: %d" % (profile.spans.size() - 3))
	if not problem.is_empty():
		lines.append(problem)
	_profile_label.text = "\n".join(lines)
	_profile_plot.queue_redraw()


func _draw_road_profile() -> void:
	if _road_profile.is_empty():
		return
	var profile := _road_profile
	var heights: PackedFloat32Array = profile.heights
	var kinds: PackedByteArray = profile.kinds
	var bounds := Rect2(Vector2(6, 17), _profile_plot.size - Vector2(12, 35))
	var low := INF
	var high := -INF
	for height in heights:
		if is_finite(height):
			low = minf(low, height)
			high = maxf(high, height)
	if profile.has("deck"):
		for height: float in profile.deck.heights:
			low = minf(low, height)
			high = maxf(high, height)
	var plot := _profile_plot
	plot.draw_rect(Rect2(Vector2.ZERO, plot.size), Color("#202a33"))
	var spacing := bounds.size.x / (heights.size() - 1)
	var points := PackedVector2Array()
	for index in heights.size():
		var x := bounds.position.x + index * spacing
		var y := bounds.get_center().y
		if is_finite(heights[index]) and high > low:
			y = lerpf(bounds.end.y, bounds.position.y, (heights[index] - low) / (high - low))
		points.append(Vector2(x, y))
		if profile.cross_sections[index] == 0:
			plot.draw_rect(Rect2(x - spacing * 0.5, bounds.position.y, spacing + 0.5, bounds.size.y), Color("#843d48"))
		if index == 0 or not is_finite(heights[index - 1]) or not is_finite(heights[index]):
			continue
		var color := Color("#8bdaac")
		if kinds[index] == Plot.RoadSupport.LEDGE:
			color = Color("#8cd7f6")
		elif kinds[index] == Plot.RoadSupport.WATER or kinds[index - 1] == Plot.RoadSupport.WATER:
			color = Color("#e9919b")
		plot.draw_line(points[index - 1], points[index], color, 2, true)
	for step: int in profile.steps:
		plot.draw_line(points[step - 1], points[step], Color("#ef8994"), 2, true)
	var deck_color := Color("#ffcd72")
	if profile.has("deck"):
		var rows: Vector2i = profile.deck.rows
		var deck_heights: PackedFloat32Array = profile.deck.heights
		var deck_points := PackedVector2Array()
		for index in deck_heights.size():
			var y := lerpf(bounds.end.y, bounds.position.y, (deck_heights[index] - low) / maxf(high - low, 0.001))
			deck_points.append(Vector2(points[rows.x + index].x, y))
		plot.draw_polyline(deck_points, deck_color, 2, true)
	else:
		for span: Vector2i in profile.spans:
			plot.draw_dashed_line(points[span.x], points[span.y], deck_color, 2, 4.0)
			plot.draw_circle(points[span.x], 3, deck_color)
			plot.draw_circle(points[span.y], 3, deck_color)
	var font := get_theme_default_font()
	var caption := "Высота %.1f–%.1f м" % [low, high] if is_finite(low) else "Высота недоступна"
	plot.draw_string(font, Vector2(6, 12), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	plot.draw_string(font, Vector2(6, plot.size.y - 4), "0 — %.1f м от начала" % profile.length, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)

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
