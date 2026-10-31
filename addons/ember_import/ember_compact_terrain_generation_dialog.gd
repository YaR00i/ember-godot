@tool
extends VBoxContainer
## Parameters route to the existing WorldEditor selection and authoring session.

signal apply_requested
signal cancel_requested
signal preview_requested(parameters: Dictionary)
signal settings_changed
signal select_area_requested
signal plan_settings_requested(parameters: Dictionary)
signal return_plan_requested
signal paint_protection_requested(locked: bool)

const Math = preload("res://scripts/prototypes/ember_terrain_generation_math.gd")
const MathPlan = preload("res://scripts/prototypes/ember_terrain_plan_math.gd")
var _apply_button: Button
var _title: Label
var _scroll: ScrollContainer
var title: String:
	set(value): _title.text = value
var ok_button_text: String:
	set(value):
		_apply_button.text = "Добавить" if value == "Добавить участки" else "Применить"
		_apply_button.tooltip_text = value
var _fields := {}
var _surface_fields := {}
var _operation: OptionButton
var _macro_grid: VBoxContainer
var _surface_box: VBoxContainer
var _coverage_grid: VBoxContainer
var _coverage_fields := {}
var _coverage_profile: OptionButton
var _coverage_zone_grid: VBoxContainer
var _coverage_legacy_controls: Array[Control]=[]
var _paint_protect: Button
var _paint_release: Button
var _fine: CheckBox
var _massif: CheckBox
var _shape_seed: SpinBox
var _profile: OptionButton
var _land_shape: OptionButton
var _coast_controls: Array[Control]=[]
var _status: Label
var _area: Label
var _preview_button: Button
var _help: Label
var _back_button: Button
var _plan_save_button: Button
var _plan_mode := false
var _plateau_mode := false
var _terrain_grid: GridContainer
var _plateau_grid: GridContainer
var _plateau_fields := {}
var _plains_grid: GridContainer
var _plains_fields := {}
var _coast_mode:=false
var _coast_grid: GridContainer
var _coast_fields: Dictionary={}
var _lake_mode := false
var _lake_grid: GridContainer
var _lake_fields := {}
var _river_mode := false
var _river_grid: GridContainer
var _river_fields := {}
var _mountain_mode := false
var _mountain_grid: GridContainer
var _mountain_fields := {}
var _road_mode := false
var _road_grid: GridContainer
var _road_fields := {}
var _grove_mode := false
var _grove_grid: VBoxContainer
var _grove_fields := {}
var _grove_choices: ItemList
var _grove_choice_ids := PackedStringArray()
var _placement_mode := false
var _placement_pattern: OptionButton
var _cluster_grid: VBoxContainer
var _cluster_controls: VBoxContainer
var _cluster_fields := {}
var _source_filter: OptionButton
var _source_search: LineEdit
var _source_selection: Label
var _source_choices: Array[Dictionary] = []
var _selected_sources := PackedStringArray()
var _source_updating := false
var _clearance_caption: Label
var _units_hint: Label
var _source_clear: Button


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_title = Label.new(); _title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(_title)
	_apply_button = Button.new()
	title = "Рельеф выбранной области"
	ok_button_text = "Применить рельеф"
	var content: VBoxContainer = self
	var scroll := ScrollContainer.new()
	_scroll = scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	_area = Label.new()
	_area.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_area)
	var units := Label.new()
	_units_hint = units
	units.text = "Высоты и размеры — в метрах; море отсчитывается от основания карты."
	units.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(units)
	_fine=CheckBox.new();_fine.text="Сетка 16×16";box.add_child(_fine)
	_fine.tooltip_text="Единая подробная основа для гладкого, полублочного и воксельного облика. Выключено — прежняя точность рецепта."
	_fine.toggled.connect(_changed.unbind(1))
	var grid := GridContainer.new()
	_terrain_grid = grid
	grid.columns = 1
	box.add_child(grid)
	var action_label:=Label.new();action_label.text="Что сделать с выбранной землёй";action_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;grid.add_child(action_label)
	_operation=OptionButton.new()
	for action in ["Создать рельеф","Добавить фактуру","Распределить покрытия"]:_operation.add_item(action)
	_operation.set_item_tooltip(0,"Новая форма земли и воды; существующая покраска сохраняется.")
	_operation.set_item_tooltip(1,"Мелкие формы по текущим покрытиям; покраска и вода сохраняются.")
	_operation.set_item_tooltip(2,"Только распределение материалов; форма земли и вода сохраняются.")
	grid.add_child(_operation)
	_operation.item_selected.connect(func(_value):_refresh_operation();_changed())
	_macro_grid=VBoxContainer.new();grid.add_child(_macro_grid)
	var label := Label.new()
	label.text = "Рисунок рельефа"
	_macro_grid.add_child(label)
	_profile = OptionButton.new()
	for name in ["Мягкие холмы", "Горные хребты", "Изрезанные склоны", "Игровая суша"]: _profile.add_item(name)
	_macro_grid.add_child(_profile)
	_profile.item_selected.connect(func(_index): _refresh_plains_fields(); _changed())
	var land_shape_label:=Label.new();land_shape_label.text="Форма суши";_macro_grid.add_child(land_shape_label)
	_land_shape=OptionButton.new();_land_shape.add_item("Остров · берег по периметру");_land_shape.add_item("Сплошная суша · без нового берега")
	_macro_grid.add_child(_land_shape)
	_land_shape.item_selected.connect(func(_index): _refresh_land_shape();_changed())
	for spec in [["sea_m", "Уровень моря", 0.5, 16.0, 0.25],
		["land_m", "Подъём суши над морем", 0.25, 8.0, 0.25],
		["relief_m", "Высота холмов / хребтов", 0.0, 24.0, 0.25],
		["feature_m", "Ширина крупных форм", 2.0, 96.0, 1.0],
		["shore_m", "Ширина перехода берега", 0.5, 24.0, 0.5],
		["land_fraction", "Размер острова в области", 0.3, 0.9, 0.01],
		["seed", "Номер рисунка", 0.0, 1000000.0, 1.0]]:
		var name_label := Label.new()
		name_label.text = spec[1]
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_macro_grid.add_child(name_label)
		var value := SpinBox.new()
		value.min_value = spec[2]
		value.max_value = spec[3]
		value.step = spec[4]
		value.value = Math.DEFAULTS[spec[0]]
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_macro_grid.add_child(value)
		_fields[spec[0]] = value
		if spec[0] in ["shore_m","land_fraction"]:_coast_controls.append(name_label);_coast_controls.append(value)
		value.value_changed.connect(_changed.unbind(1))
	var surface_box:=VBoxContainer.new();grid.add_child(surface_box)
	_surface_box=surface_box
	var surface_title:=Label.new();surface_title.text="Фактурность выбранных покрытий";surface_title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;surface_box.add_child(surface_title)
	for spec in [["surface_strength","Сила фактурности, %",0.0,100.0,5.0],
		["surface_scale","Масштаб деталей",0.5,3.0,0.1],
		["surface_seed","Рисунок деталей",0.0,1000000.0,1.0]]:
		var caption:=Label.new();caption.text=spec[1];caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;surface_box.add_child(caption)
		var number:=SpinBox.new();number.min_value=spec[2];number.max_value=spec[3];number.step=spec[4]
		number.value=float(Math.SURFACE_DEFAULTS[spec[0]])*(100.0 if spec[0]=="surface_strength" else 1.0)
		number.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		if spec[0]=="surface_scale":number.suffix="×"
		surface_box.add_child(number);_surface_fields[spec[0]]=number
		number.value_changed.connect(func(_value):_refresh_surface_fields();_changed())
	_surface_fields.surface_strength.tooltip_text="0 — прежняя земля. Фактурность добавляет мелкий рельеф камня, песка и грунта в области до 32×32 м. Детальный вид выбирается в «Вид мира → Материалы»."
	_surface_fields.surface_scale.tooltip_text="1 — обычный размер форм; 2 — вдвое крупнее. Высоту задаёт сила фактурности. Размер рисунка PNG меняется в самом материале."
	_surface_fields.surface_seed.tooltip_text="Другие мелкие детали при тех же крупных холмах и береговой форме."
	_refresh_surface_fields()
	_coverage_grid=VBoxContainer.new();grid.add_child(_coverage_grid);_coverage_grid.hide()
	var zone_title:=Label.new();zone_title.text="Распределение покрытий";_coverage_grid.add_child(zone_title)
	_coverage_profile=OptionButton.new();_coverage_profile.add_item("Крупные зоны");_coverage_profile.add_item("Прежний рисунок")
	_coverage_grid.add_child(_coverage_profile);_coverage_profile.item_selected.connect(func(_index):_refresh_coverage_fields();_changed())
	for spec in [["coverage_scale","Масштаб зон покрытий, ×",0.5,8.0,0.1],["coverage_seed","Рисунок покрытий",0.0,1000000.0,1.0],["coverage_sea_m","Уровень берега для покрытий, м",0.0,16.0,0.25]]:
		var caption:=Label.new();caption.text=spec[1];caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_coverage_grid.add_child(caption)
		var number:=SpinBox.new();number.min_value=spec[2];number.max_value=spec[3];number.step=spec[4];number.value=Math.COVERAGE_DEFAULTS[spec[0]]
		_coverage_grid.add_child(number);_coverage_fields[spec[0]]=number;number.value_changed.connect(_changed.unbind(1))
		if spec[0]!="coverage_seed":_coverage_legacy_controls.append(caption);_coverage_legacy_controls.append(number)
	_coverage_zone_grid=VBoxContainer.new();_coverage_grid.add_child(_coverage_zone_grid)
	for spec in [["coverage_zone_m","Размер пятен грунта, м",4.0,48.0,1.0],["coverage_soil_amount","Частота грунтовых пятен, %",0.0,100.0,5.0],["coverage_stone_slope","Камень на склонах от, %",5.0,100.0,5.0],["coverage_sand_width_m","Ширина песка у воды, м",0.0,6.0,0.25]]:
		var caption:=Label.new();caption.text=spec[1];caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_coverage_zone_grid.add_child(caption)
		var number:=SpinBox.new();number.min_value=spec[2];number.max_value=spec[3];number.step=spec[4]
		number.value=float(Math.ZONE_DEFAULTS[spec[0]])*(100.0 if spec[0]=="coverage_soil_amount" else 1.0)
		_coverage_zone_grid.add_child(number);_coverage_fields[spec[0]]=number;number.value_changed.connect(_changed.unbind(1))
	_coverage_fields.coverage_zone_m.tooltip_text="Крупные нерегулярные пятна грунта среди травяной основы. Масштаб фактуры и рисунка материала задаётся отдельно."
	_coverage_fields.coverage_soil_amount.tooltip_text="Вероятность появления грунтового пятна; это не точный процент площади. 0 оставляет траву без случайного грунта."
	_coverage_fields.coverage_stone_slope.tooltip_text="Широкий уклон: перепад в сантиметрах на метр. Мелкие детали сглажены в расчёте зон. Больше — меньше каменных склонов."
	_coverage_fields.coverage_sand_width_m.tooltip_text="Расстояние до текущей воды. 0 отключает автоматический песок. Форма берега и вода не меняются."
	_paint_protect=Button.new();_paint_protect.text="Защитить покраску выделения";_coverage_grid.add_child(_paint_protect)
	_paint_release=Button.new();_paint_release.text="Снять защиту выделения";_coverage_grid.add_child(_paint_release)
	_paint_protect.pressed.connect(func():paint_protection_requested.emit(true));_paint_release.pressed.connect(func():paint_protection_requested.emit(false))
	_paint_protect.tooltip_text="Защитить нынешнюю покраску всей выбранной области от распределения покрытий. Новые ручные мазки защищаются автоматически. Ctrl+Z отменяет защиту."
	_paint_release.tooltip_text="Разрешить генератору покрытий перекрашивать выбранную область. Рисунок материала и фактура не изменяются. Ctrl+Z возвращает защиту."
	_refresh_coverage_fields()
	_plains_grid = GridContainer.new(); _plains_grid.columns = 1; box.add_child(_plains_grid)
	for spec in [["flat_fraction","Количество ровных мест, %",0,100,5],
		["flat_size_m","Размер ровных мест, м",8,48,1],
		["micro_m","Мелкая неровность, м",0,1,0.05],
		["flat_transition_m","Пологий переход, м",0.5,12,0.5]]:
		var caption := Label.new(); caption.text = spec[1]; caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_plains_grid.add_child(caption)
		var number := SpinBox.new(); number.min_value = spec[2]; number.max_value = spec[3]; number.step = spec[4]
		number.value = float(Math.PLAINS_DEFAULTS[spec[0]])*(100.0 if spec[0] == "flat_fraction" else 1.0)
		number.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _plains_grid.add_child(number); _plains_fields[spec[0]] = number
		number.value_changed.connect(_changed.unbind(1))
	_plains_fields.flat_fraction.tooltip_text = "Больше — больше ровных площадок. Это доля опорных участков рисунка, не точный процент площади земли: берег и переходы остаются пологими."
	_plains_fields.flat_size_m.tooltip_text = "Средний размер нерегулярных площадок; высоты задаёт высота холмов."
	_plains_fields.micro_m.tooltip_text = "Небольшие колебания поверхности, отдельно от высоты крупных форм. Ноль оставляет площадки ровными."
	_plains_fields.flat_transition_m.tooltip_text = "Переход между площадкой и исходным рельефом. Не более четверти размера ровных мест."
	_refresh_plains_fields()
	_help = Label.new()
	_plateau_grid = GridContainer.new(); _plateau_grid.columns = 1; box.add_child(_plateau_grid)
	for spec in [["height_m", "Высота плато, м", 0.25, 28.0, 0.25, 4.0], ["transition_m", "Пологий край, м", 0.5, 16.0, 0.5, 4.0]]:
		var label_field := Label.new(); label_field.text = spec[1]; label_field.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; _plateau_grid.add_child(label_field)
		var spin := SpinBox.new(); spin.min_value = spec[2]; spin.max_value = spec[3]; spin.step = spec[4]; spin.value = spec[5]
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _plateau_grid.add_child(spin); _plateau_fields[spec[0]] = spin
		spin.value_changed.connect(_changed.unbind(1))
	_plateau_grid.hide()
	_coast_grid=GridContainer.new();_coast_grid.columns=1;box.add_child(_coast_grid)
	for spec in [["water_m","Уровень моря, м",-16.0,28.0,0.25],["depth_m","Глубина моря, м",0.25,16.0,0.25],["shore_m","Ширина берега, м",0.5,16.0,0.25]]:
		var caption:=Label.new();caption.text=spec[1];_coast_grid.add_child(caption)
		var spin:=SpinBox.new();spin.min_value=spec[2];spin.max_value=spec[3];spin.step=0.001;spin.custom_arrow_step=spec[4];spin.value=MathPlan.COAST_DEFAULTS[spec[0]]
		_coast_grid.add_child(spin);_coast_fields[spec[0]]=spin;spin.value_changed.connect(_changed.unbind(1))
	_coast_fields.water_m.tooltip_text="Высота поверхности в мировых метрах, та же отметка, что у существующего моря."
	_coast_grid.hide()
	_lake_grid = GridContainer.new(); _lake_grid.columns = 1; box.add_child(_lake_grid)
	for spec in [["water_m","Уровень озера, м",0.5,28.0,0.25],["depth_m","Глубина озера, м",0.25,16.0,0.25],["shore_m","Ширина берега, м",0.5,16.0,0.5]]:
		var caption := Label.new(); caption.text = spec[1]; caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; _lake_grid.add_child(caption)
		var spin := SpinBox.new(); spin.min_value = spec[2]; spin.max_value = spec[3]; spin.step = spec[4]; spin.value = MathPlan.LAKE_DEFAULTS[spec[0]]
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _lake_grid.add_child(spin); _lake_fields[spec[0]] = spin
		spin.value_changed.connect(_changed.unbind(1))
	_lake_fields.water_m.tooltip_text = "Высота поверхности от основания карты. У озера свой уровень, независимо от моря."
	_lake_fields.depth_m.tooltip_text = "Глубина от поверхности озера до дна. Дно должно оставаться выше основания карты."
	_lake_fields.shore_m.tooltip_text = "Пологий берег внутри овала; не шире четверти меньшей стороны области."
	_lake_grid.hide()
	_river_grid = GridContainer.new(); _river_grid.columns = 1; box.add_child(_river_grid)
	for spec in [["width_m","Ширина русла, м",2.0,12.0,0.5],["depth_m","Глубина русла, м",0.25,8.0,0.25],["shore_m","Ширина берега, м",0.5,8.0,0.5],["flow","Сила течения",0.0,1.0,0.05]]:
		var caption := Label.new(); caption.text = spec[1]; caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; _river_grid.add_child(caption)
		var spin := SpinBox.new(); spin.min_value = spec[2]; spin.max_value = spec[3]; spin.step = spec[4]; spin.value = MathPlan.RIVER_DEFAULTS[spec[0]]
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _river_grid.add_child(spin); _river_fields[spec[0]] = spin
		spin.value_changed.connect(_changed.unbind(1))
	_river_fields.flow.tooltip_text = "Относительная сила потока в русле; скорость анимации воды дополнительно управляется в «Вид мира → Вода»."
	_river_grid.hide()
	_mountain_grid = GridContainer.new(); _mountain_grid.columns = 1; box.add_child(_mountain_grid)
	for spec in [["height_m","Высота вершины, м",0.25,28.0,0.25],["summit_m","Ширина вершины, м",0.0,48.0,0.25],["slope_m","Ширина склонов, м",0.5,32.0,0.25]]:
		var caption := Label.new(); caption.text = spec[1]; caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; _mountain_grid.add_child(caption)
		var spin := SpinBox.new(); spin.min_value = spec[2]; spin.max_value = spec[3]; spin.step = spec[4]; spin.value = MathPlan.MOUNTAIN_DEFAULTS[spec[0]]
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _mountain_grid.add_child(spin); _mountain_fields[spec[0]] = spin
		spin.value_changed.connect(_changed.unbind(1))
	_mountain_fields.height_m.tooltip_text = "Высота от основания карты, как у плато. Более высокая исходная земля сохраняется; гора не вырезает впадину."
	_mountain_fields.summit_m.tooltip_text = "Ширина верхней части по меньшей оси выделения. У массива — округлый вытянутый гребень; у прежней овальной горы — ровная площадка."
	_mountain_fields.slope_m.tooltip_text = "Горизонтальное расстояние от края вершины до подножия по меньшей оси. Больше — шире и положе склон при той же высоте. Вершина и два склона должны помещаться в области."
	_massif=CheckBox.new();_massif.text="Горный массив";_mountain_grid.add_child(_massif)
	_massif.tooltip_text="Неодинаковые склоны, вытянутый гребень и плавное подножие. Выключено — прежняя овальная гора."
	_massif.toggled.connect(func(on):_shape_seed.editable=on;_changed())
	var shape_label:=Label.new();shape_label.text="Вариант формы массива";_mountain_grid.add_child(shape_label)
	_shape_seed=SpinBox.new();_shape_seed.min_value=0;_shape_seed.max_value=1000000;_shape_seed.step=1;_shape_seed.value=7
	_mountain_grid.add_child(_shape_seed);_shape_seed.value_changed.connect(_changed.unbind(1))
	_mountain_grid.hide()
	_road_grid = GridContainer.new(); _road_grid.columns = 1; box.add_child(_road_grid)
	for spec in [["width_m","Ширина дороги, м",2.0,12.0,0.5],["edge_m","Мягкий край, м",0.5,8.0,0.5],["grade_percent","Допустимый уклон, %",1.0,50.0,1.0]]:
		var caption := Label.new(); caption.text = spec[1]; caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; _road_grid.add_child(caption)
		var spin := SpinBox.new(); spin.min_value = spec[2]; spin.max_value = spec[3]; spin.step = spec[4]; spin.value = MathPlan.ROAD_DEFAULTS[spec[0]]
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _road_grid.add_child(spin); _road_fields[spec[0]] = spin
		spin.value_changed.connect(_changed.unbind(1))
	_road_fields.edge_m.tooltip_text = "Плавный переход от ровного коридора к прежней земле по бокам дороги."
	_road_fields.grade_percent.tooltip_text = "Продольный подъём на 100 м пути: 25% — это 25 м. Слишком большой перепад между концами отклоняется; удлините путь или измените площадки. Ручные правки остаются защищёнными."
	_road_grid.hide()
	_grove_grid = VBoxContainer.new(); box.add_child(_grove_grid)
	var grove_label := Label.new(); grove_label.text = "Готовые объекты · до четырёх в наборе\nCtrl + клик — добавить или убрать объект"; grove_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; _grove_grid.add_child(grove_label)
	_source_filter = OptionButton.new(); _source_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for name_value in ["Все объекты","Деревья","Кусты","Камни","Прочие"]: _source_filter.add_item(name_value)
	_source_filter.item_selected.connect(func(_index): _filter_sources()); _grove_grid.add_child(_source_filter)
	_source_search = LineEdit.new(); _source_search.placeholder_text = "Поиск по имени или ID"; _source_search.text_changed.connect(func(_text): _filter_sources()); _grove_grid.add_child(_source_search)
	_grove_choices = ItemList.new(); _grove_choices.select_mode = ItemList.SELECT_MULTI; _grove_choices.custom_minimum_size = Vector2(0,110); _grove_grid.add_child(_grove_choices)
	_grove_choices.multi_selected.connect(func(_index,_selected):
		if _source_updating: return
		_sync_sources(); _changed())
	_source_selection = Label.new(); _source_selection.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; _grove_grid.add_child(_source_selection); _grove_grid.move_child(_source_selection,1)
	_source_clear = Button.new(); _source_clear.text = "Очистить набор"
	_source_clear.pressed.connect(func(): _selected_sources.clear(); _filter_sources(false); _changed())
	_grove_grid.add_child(_source_clear); _grove_grid.move_child(_source_clear,2)
	for spec in [["density","Плотность, %",0.0,100.0,5.0],["spacing_m","Минимальный интервал центров, м",2.0,24.0,0.5],["clearance_m","Свободное место между основаниями, м",0.0,8.0,0.1],["slope_percent","Допустимый уклон, %",0.0,50.0,1.0],["seed","Номер варианта",0.0,2147483646.0,1.0]]:
		var caption := Label.new(); caption.text = spec[1]; caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; _grove_grid.add_child(caption)
		if spec[0] == "clearance_m": _clearance_caption = caption
		var spin := SpinBox.new(); spin.min_value = spec[2]; spin.max_value = spec[3]; spin.step = spec[4]; spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.value_changed.connect(_changed.unbind(1)); _grove_grid.add_child(spin); _grove_fields[spec[0]] = spin
	_cluster_grid = VBoxContainer.new(); _grove_grid.add_child(_cluster_grid)
	var pattern_caption := Label.new(); pattern_caption.text = "Рисунок расстановки"; _cluster_grid.add_child(pattern_caption)
	_placement_pattern = OptionButton.new(); _placement_pattern.add_item("Равномерно"); _placement_pattern.add_item("Группами")
	_placement_pattern.item_selected.connect(func(_index): _refresh_cluster_controls(); _changed())
	_cluster_grid.add_child(_placement_pattern)
	_cluster_controls = VBoxContainer.new(); _cluster_grid.add_child(_cluster_controls)
	for spec in [["cluster_strength","Кучность, %",0.0,100.0,5.0],["cluster_size_m","Размер группы, м",8.0,96.0,1.0]]:
		var caption := Label.new(); caption.text = spec[1]; caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; _cluster_controls.add_child(caption)
		var spin := SpinBox.new(); spin.min_value = spec[2]; spin.max_value = spec[3]; spin.step = spec[4]; spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.value_changed.connect(_changed.unbind(1)); _cluster_controls.add_child(spin); _cluster_fields[spec[0]] = spin
	_cluster_fields.cluster_strength.tooltip_text = "Усиливает плотные участки и просветы. 0% сохраняет равномерный рисунок. Плотность 0% / 100% сохраняет прежний отбор."
	_cluster_fields.cluster_size_m.tooltip_text = "Масштаб плотных участков и просветов в метрах; не минимальный интервал объектов и не точный диаметр группы."
	_cluster_grid.hide()
	var another := Button.new(); another.text = "Другой вариант"; another.pressed.connect(func(): _grove_fields.seed.value = (int(_grove_fields.seed.value)+1)%2147483647); _grove_grid.add_child(another)
	_grove_grid.hide()
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_help)
	_back_button = Button.new()
	_back_button.text = "← Изменить выделение"
	_back_button.pressed.connect(func():
		hide()
		if _plan_mode: return_plan_requested.emit()
		else: select_area_requested.emit())
	content.add_child(_back_button)
	_plan_save_button = Button.new()
	_plan_save_button.text = "Сохранить в плане"
	_plan_save_button.pressed.connect(func(): plan_settings_requested.emit(parameters()))
	content.add_child(_plan_save_button)
	_plan_save_button.hide()
	_preview_button = Button.new()
	_preview_button.text = "Показать предпросмотр"
	_preview_button.pressed.connect(func(): set_pending("Подготавливаю землю…"); preview_requested.emit(parameters()))
	content.add_child(_preview_button)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_status)
	var actions := HBoxContainer.new(); content.add_child(actions)
	_apply_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_button.pressed.connect(func(): apply_requested.emit())
	actions.add_child(_apply_button)
	var cancel := Button.new(); cancel.text = "Отмена"
	cancel.pressed.connect(func(): cancel_requested.emit()); actions.add_child(cancel)
	_apply_button.disabled = true


func open_for(bounds_blocks: Rect2i, new_sections_count := 0) -> void:
	_fine.set_pressed_no_signal(true);_fine.show()
	_grove_mode = false; _placement_mode = false; _grove_grid.hide()
	_area.show()
	_units_hint.text = "Высоты и размеры — в метрах; море отсчитывается от основания карты."
	_coast_mode=false;_coast_grid.hide()
	_plateau_mode = false; _lake_mode = false; _river_mode = false; _mountain_mode = false; _road_mode = false; _terrain_grid.show(); _plateau_grid.hide(); _lake_grid.hide(); _river_grid.hide(); _mountain_grid.hide(); _road_grid.hide()
	_operation.select(0);_operation.disabled=new_sections_count>0;_refresh_operation()
	_coverage_profile.select(0);_refresh_coverage_fields()
	_refresh_plains_fields()
	_plan_mode = false
	_back_button.text = "← Изменить выделение"
	_plan_save_button.hide()
	title = "Новые участки · рельеф и вода" if new_sections_count > 0 else "Рельеф выбранной области"
	ok_button_text = "Добавить участки" if new_sections_count > 0 else "Применить рельеф"
	_back_button.visible = new_sections_count > 0
	_help.text = "Добавится новых участков: %d. Уже созданная земля и объекты сохранятся. На стыке будет плавный переход." % new_sections_count if new_sections_count > 0 else "Склоны имитируют следы эрозии. На границе с существующей землёй будет плавный переход.\nПрименение заменяет землю, покрытия и воду внутри области. Объекты остаются на своих местах."
	_area.text = "Область: %d×%d м · начало (%d, %d)" % [bounds_blocks.size.x, bounds_blocks.size.y, bounds_blocks.position.x, bounds_blocks.position.y]
	set_pending("Настройте форму и нажмите «Показать предпросмотр».")
	_refresh_operation()
	_scroll.scroll_vertical = 0
	show()


func parameters() -> Dictionary:
	var values := _parameters()
	if not _grove_mode and _fine.button_pressed and (_operation.selected==0 or _plateau_mode or _mountain_mode or _river_mode or _lake_mode or _road_mode or _coast_mode):values.terrain_sampling="fine16"
	if _mountain_mode and _massif.button_pressed:
		values.mountain_shape="massif";values.shape_seed=int(_shape_seed.value)
	return values

func _parameters() -> Dictionary:
	if _grove_mode:
		_sync_sources()
		var values := {"density":float(_grove_fields.density.value)/100.0,"spacing_m":float(_grove_fields.spacing_m.value),"slope_percent":float(_grove_fields.slope_percent.value),"seed":int(_grove_fields.seed.value),"model_ids":_selected_sources.duplicate()}
		if _placement_mode:
			values.clearance_m = float(_grove_fields.clearance_m.value)
			if _placement_pattern.selected == 1:
				values.pattern = "groups"; values.cluster_strength = float(_cluster_fields.cluster_strength.value)/100.0
				values.cluster_size_m = float(_cluster_fields.cluster_size_m.value)
		return values
	if _coast_mode:
		var values: Dictionary={}
		for key in _coast_fields:values[key]=float(_coast_fields[key].value)
		return values
	if _road_mode:
		var values := {}
		for key in _road_fields: values[key] = float(_road_fields[key].value)
		return values
	if _mountain_mode:
		var values := {}
		for key in _mountain_fields: values[key] = float(_mountain_fields[key].value)
		return values
	if _river_mode:
		var values := {}
		for key in _river_fields: values[key] = float(_river_fields[key].value)
		return values
	if _lake_mode:
		var values := {}
		for key in _lake_fields: values[key] = float(_lake_fields[key].value)
		return values
	if _plateau_mode:
		return {"height_m": float(_plateau_fields.height_m.value), "transition_m": float(_plateau_fields.transition_m.value)}
	var values := {"profile": Math.PROFILES[_profile.selected],"land_shape":"mainland" if _land_shape.selected==1 else "island","terrain_operation":Math.OPERATIONS[_operation.selected]}
	for key in _fields: values[key] = int(_fields[key].value) if key == "seed" else float(_fields[key].value)
	for key in _surface_fields:
		values[key]=int(_surface_fields[key].value) if key=="surface_seed" else float(_surface_fields[key].value)/(100.0 if key=="surface_strength" else 1.0)
	if _operation.selected==2:
		values.coverage_profile="large" if _coverage_profile.selected==0 else "legacy"
		for key in _coverage_fields:
			if _coverage_profile.selected==1 and Math.ZONE_DEFAULTS.has(key):continue
			values[key]=int(_coverage_fields[key].value) if key=="coverage_seed" else float(_coverage_fields[key].value)/(100.0 if key=="coverage_soil_amount" else 1.0)
	if values.profile == "plains":
		for key in _plains_fields: values[key] = float(_plains_fields[key].value)/(100.0 if key == "flat_fraction" else 1.0)
	return values

func open_plan(bounds_blocks: Rect2i, values: Dictionary) -> void:
	open_for(bounds_blocks)
	_plan_mode = true
	_fine.set_pressed_no_signal(values.get("terrain_sampling","legacy8")=="fine16")
	_back_button.text = "← План областей"
	_back_button.show()
	_profile.select(Math.PROFILES.find(values.profile))
	_land_shape.select(1 if values.get("land_shape","island")=="mainland" else 0);_refresh_land_shape()
	for key in _fields: _fields[key].value = values[key]
	for key in _surface_fields:_surface_fields[key].value=float(values.get(key,Math.SURFACE_DEFAULTS[key]))*(100.0 if key=="surface_strength" else 1.0)
	_operation.select(Math.OPERATIONS.find(values.get("terrain_operation","generate")))
	_coverage_profile.select(0 if values.get("coverage_profile","legacy")=="large" else 1)
	for key in _coverage_fields:
		var fallback: Variant=Math.ZONE_DEFAULTS.get(key,Math.COVERAGE_DEFAULTS.get(key))
		_coverage_fields[key].value=float(values.get(key,fallback))*(100.0 if key=="coverage_soil_amount" else 1.0)
	_refresh_coverage_fields()
	for key in _plains_fields: _plains_fields[key].value = float(values.get(key,Math.PLAINS_DEFAULTS[key]))*(100.0 if key == "flat_fraction" else 1.0)
	_refresh_plains_fields()
	_plan_save_button.show()
	_help.text = "Параметры сохраняются отдельно от земли. Предпросмотр и применение заменят землю, покрытия и воду в выбранной области; ручные правки внутри неё будут заменены. Объекты сохранятся."
	_refresh_operation()
	set_pending("Сохраните параметры в плане или подготовьте предпросмотр.")


func _changed() -> void:
	if _coast_mode:
		title="Берег";_area.hide();_fine.hide()
		_units_hint.text="Ширина — поперёк линии; уровень — от мирового нуля."
		_help.text="Точки меняют контур. «Применить» обновляет землю и воду."
	set_pending("Есть неприменённые изменения." if _coast_mode else "Параметры изменены. Обновите предпросмотр.")
	settings_changed.emit()

func _refresh_surface_fields() -> void:
	if not _surface_fields.has("surface_strength"):return
	var enabled: bool=_surface_fields.surface_strength.value>0.0
	_surface_fields.surface_scale.editable=enabled
	_surface_fields.surface_seed.editable=enabled

func _refresh_operation() -> void:
	if _operation==null or _surface_box==null:return
	_fine.visible=_operation.selected==0
	_macro_grid.visible=_operation.selected==0
	_surface_box.visible=_operation.selected!=2
	if _coverage_grid!=null:_coverage_grid.visible=_operation.selected==2
	_refresh_plains_fields()
	if _units_hint!=null:_units_hint.text=["Высоты и размеры — в метрах; море отсчитывается от основания карты.","Фактура добавляется к нынешней лепке и сохраняет покраску.","Меняются только покрытия. Геометрия, фактура и вода сохраняются."][_operation.selected]
	if _apply_button!=null and not _operation.disabled:ok_button_text=["Применить рельеф","Применить фактуру","Применить покрытия"][_operation.selected]
	if _help!=null and not _operation.disabled:
		_help.text=["Создаётся новая форма земли и воды. Существующая покраска сохраняется; ручная лепка заменяется внутри области. Фактура не распределяет покрытия.","Добавляются только мелкие формы по текущим покрытиям. Покраска, вода и подводное дно сохраняются. Новые холмы не генерируются. 0% сохраняет исходную землю.","Трава — основа; грунт — крупные пятна, песок — у воды, камень — на широких склонах. Форма и фактура не меняются. Новые ручные мазки защищены; старую покраску защитите выделением."][_operation.selected]

func _refresh_coverage_fields() -> void:
	if _coverage_profile==null or _coverage_zone_grid==null:return
	_coverage_zone_grid.visible=_coverage_profile.selected==0
	for control in _coverage_legacy_controls:control.visible=_coverage_profile.selected==1

func _refresh_land_shape() -> void:
	for control in _coast_controls:control.visible=_land_shape.selected==0
	_fields.sea_m.min_value=0.0 if _land_shape.selected==1 else 0.5


func _refresh_plains_fields() -> void:
	if is_instance_valid(_plains_grid): _plains_grid.visible = _operation.selected==0 and not _grove_mode and not _plateau_mode and not _lake_mode and not _river_mode and not _mountain_mode and not _road_mode and not _coast_mode and Math.PROFILES[_profile.selected] == "plains"

func open_grove(bounds_blocks: Rect2i, values: Dictionary, choices: Array[Dictionary], selected := true) -> void:
	open_for(bounds_blocks); _plan_mode = true; _grove_mode = true; _terrain_grid.hide(); _refresh_plains_fields()
	_fine.hide()
	_grove_grid.visible = selected; _plan_save_button.visible = selected; _back_button.text = "← План областей"
	_source_choices = choices.duplicate(true); _selected_sources = PackedStringArray(values.get("model_ids",[]))
	_grove_choices.clear(); _grove_choice_ids.clear(); _source_search.text = ""; _source_filter.select(0); _filter_sources(false)
	for key in _grove_fields: _grove_fields[key].value = values.get(key,MathPlan.PLACEMENT_DEFAULTS[key])*(100.0 if key == "density" else 1.0)
	_clearance_caption.hide(); _grove_fields.clearance_m.hide()
	_cluster_grid.hide()
	title = "Роща · расстановка деревьев" if selected else "Обновить рощи"
	_help.text = "Используются готовые варианты из мастерской. Вода, крутые места, дорожный коридор и ручные объекты исключаются. Количество ограничено площадью рощи и размером созданной земли. Земля не меняется. После применения деревья редактируются обычными инструментами. Ручные изменения и удаления защищаются; перенос/off не стирает такие деревья."
	set_pending("Настройте рощу и обновите предпросмотр." if selected else "Обновите предпросмотр для переноса/выключения рощ.")

func _sync_sources() -> void:
	if _source_updating: return
	var selected := _grove_choices.get_selected_items()
	for i in _grove_choice_ids.size():
		var id: String = _grove_choice_ids[i]
		if i in selected and id not in _selected_sources: _selected_sources.append(id)
		elif i not in selected and id in _selected_sources: _selected_sources.remove_at(_selected_sources.find(id))
	var names := PackedStringArray()
	for id in _selected_sources:
		var found := _source_choices.filter(func(choice): return choice.id == id)
		names.append(str(found[0].title) if not found.is_empty() else "Недоступно: "+id)
	_source_selection.text = "В наборе: %d / 4\n%s"%[_selected_sources.size(),", ".join(names)]
	_source_clear.disabled = _selected_sources.is_empty()

func _filter_sources(sync := true) -> void:
	if _source_updating: return
	if sync: _sync_sources()
	_source_updating = true; _grove_choices.clear(); _grove_choice_ids.clear()
	var role: String = ["","tree","bush","rock","other"][_source_filter.selected]
	var query := _source_search.text.strip_edges().to_lower()
	for choice in _source_choices:
		if not role.is_empty() and choice.get("role","other") != role: continue
		if not query.is_empty() and query not in (str(choice.title)+" "+str(choice.id)).to_lower(): continue
		var index := _grove_choices.add_item(choice.title); _grove_choice_ids.append(choice.id)
		_grove_choices.set_item_tooltip(index,str(choice.get("tooltip",choice.id)))
		if choice.id in _selected_sources: _grove_choices.select(index,false)
	_source_updating = false; _sync_sources()

func open_placement(bounds_blocks: Rect2i, values: Dictionary, choices: Array[Dictionary], selected := true) -> void:
	open_grove(bounds_blocks,values,choices,selected); _placement_mode = true
	_placement_pattern.select(1 if values.get("pattern","uniform") == "groups" else 0)
	for key in _cluster_fields: _cluster_fields[key].value = float(values.get(key,MathPlan.PLACEMENT_GROUP_DEFAULTS[key]))*(100.0 if key == "cluster_strength" else 1.0)
	_cluster_grid.visible = selected; _refresh_cluster_controls()
	_units_hint.text = "Интервалы и свободное место — в метрах. Размеры готовых объектов сохраняются."
	_clearance_caption.visible = selected; _grove_fields.clearance_m.visible = selected
	title = "Расстановка объектов" if selected else "Обновить расстановку"
	_help.text = "Готовые объекты из общей библиотеки, включая сделанные вручную. Основание и свободное место учитываются вместе с соседями, водой и дорогами. Группы создают плотные участки и просветы; плотность не задаёт точное количество. Количество ограничено площадью области и размером созданной земли. Ручные изменения и удаления сохраняются."
	set_pending("Выберите набор и подготовьте предпросмотр." if selected else "Подготовьте предпросмотр всех областей расстановки.")

func _refresh_cluster_controls() -> void:
	_cluster_controls.visible = _placement_mode and _placement_pattern.selected == 1

func open_plateau(bounds_blocks: Rect2i, values: Dictionary, selected := true) -> void:
	open_influence(bounds_blocks,values,"plateau",selected)

func open_influence(bounds_blocks: Rect2i, values: Dictionary, kind: String, selected := true) -> void:
	open_for(bounds_blocks)
	_coast_mode=kind=="coast";_coast_grid.visible=selected and _coast_mode
	if _coast_mode:_units_hint.text="Уровень моря — от мирового нуля; глубина и ширина берега — в метрах."
	_plateau_mode = kind == "plateau"; _lake_mode = kind == "lake"; _river_mode = kind == "river"; _mountain_mode = kind == "mountain"; _road_mode = kind == "road"; _plan_mode = true
	_refresh_plains_fields()
	_fine.set_pressed_no_signal(values.get("terrain_sampling","legacy8")=="fine16");_fine.visible=selected
	_massif.set_pressed_no_signal(values.get("mountain_shape","ellipse")=="massif");_shape_seed.value=values.get("shape_seed",7);_shape_seed.editable=_massif.button_pressed
	_terrain_grid.hide(); _plateau_grid.visible = selected and _plateau_mode; _lake_grid.visible = selected and _lake_mode
	_river_grid.visible = selected and _river_mode
	_mountain_grid.visible = selected and _mountain_mode
	_road_grid.visible = selected and _road_mode
	_back_button.text = "← Области"; _back_button.show()
	_plan_save_button.visible = selected
	if selected:
		var fields: Dictionary = _coast_fields if _coast_mode else _road_fields if _road_mode else _mountain_fields if _mountain_mode else _river_fields if _river_mode else _lake_fields if _lake_mode else _plateau_fields
		for key in fields: fields[key].value = values[key]
	title = "Море · берег и уровень" if _coast_mode else "Дорога · коридор и уклон" if _road_mode else "Гора · вершина и склоны" if _mountain_mode else "Река · русло и течение" if _river_mode else "Озеро · котловина и вода" if _lake_mode else "Плато · локальные влияния" if selected else "Локальные области"
	if not selected: _area.text = "Обновление локальных областей, включая прежний след"
	elif _coast_mode:_area.text="Берег по линии в 3D · море справа по ходу линии"
	elif _river_mode: _area.text = "Русло по линии в 3D · уровни из водоёмов"
	elif _road_mode: _area.text = "Дорога по линии в 3D · высоты из земли"
	ok_button_text = "Применить озеро" if _lake_mode else "Применить области"
	_help.text = "Озеро создаёт овальную котловину с замкнутым берегом внутри выделения. Уровень отсчитывается от основания карты; если он выше окружающей земли, берег внутри области поднимается. Первая проба работает на сухой земле без течения; пересечение с другой водой требует изменения границ.\n" if _lake_mode else "Плато выравнивает сухую землю. Высота отсчитывается от основания карты. Пологий край находится внутри выделения. Пересечения учитывают порядок списка.\n"
	if _river_mode: _help.text = "Уровни поверхности берутся из двух водоёмов на концах линии. Русло плавно спускается между ними; берега и течение идут по изгибу. Дно должно оставаться выше основания карты. Развилки и водопады добавим отдельно.\n"
	if _mountain_mode: _help.text = "Гора поднимает сухую землю к высоте вершины от основания карты. Массив создаёт неодинаковые склоны и мягкое подножие; номер варианта меняет его направление. Ширина вершины и два склона должны помещаться в меньшей стороне выделения. Вода и покрытия сохраняются.\n"
	if _road_mode: _help.text = "Дорога выравнивает сухую землю между высотами на концах линии и использует существующее покрытие грунта. Мягкий край возвращается к соседнему рельефу. Слишком большой продольный уклон и пересечение с водой отклоняются; мосты добавим отдельно. Защищённые ручные правки могут оставить неровности в коридоре — они видны в предпросмотре.\n"
	if _coast_mode:_help.text="Область моря следует сохранённой линии берега. Уровень — в мировых метрах; глубина формирует дно, ширина — пологий переход от суши. Чтобы изменить берег, вернитесь в план и перенаметьте линию.\n"
	_help.text += "Перенос и выключение возвращают прежнюю землю и воду после обновления областей. Ручные правки защищаются и отмечаются крестиками в предпросмотре."
	if _coast_mode:
		title="Берег";_area.hide();_fine.hide()
		_units_hint.text="Ширина — поперёк линии; уровень — от мирового нуля."
		_help.text="Точки меняют контур. «Применить» обновляет землю и воду."
	set_pending("Есть неприменённые изменения." if _coast_mode else "Параметры изменены. Обновите предпросмотр.")


func update_plan_bounds(bounds: Rect2i) -> void:
	_area.text="Область: %d×%d м · начало (%d, %d)"%[bounds.size.x,bounds.size.y,bounds.position.x,bounds.position.y]

func set_pending(message: String) -> void:
	get_apply_button().disabled = true
	_status.text = _short_coast_status(message) if _coast_mode else message


func set_ready(message: String) -> void:
	get_apply_button().disabled = false
	_status.text = _short_coast_status(message) if _coast_mode else message


func get_apply_button() -> Button:
	return _apply_button


func _short_coast_status(message:String)->String:
	_status.tooltip_text=message
	if "Предпросмотр" in message and "готов" in message:return "Предпросмотр готов. Примени или отмени."
	if "Подготавливаю" in message or "Строю" in message:return "Готовлю предпросмотр…"
	return message
