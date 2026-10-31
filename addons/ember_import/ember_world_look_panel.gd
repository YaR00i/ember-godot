@tool
class_name EmberWorldLookPanel
extends VBoxContainer

## Scene-owned look controls. The Sun and Environment remain the source of truth.
const VALUES := {
	"sun_azimuth": EmberLights.SUN_LOOK_VALUES.sun_azimuth,
	"sun_elevation": EmberLights.SUN_LOOK_VALUES.sun_elevation,
	"sun_energy": EmberLights.SUN_LOOK_VALUES.sun_energy,
	"shadow_softness": EmberLights.SUN_LOOK_VALUES.shadow_softness,
	"ambient_energy": ["Свет в тени", "ambient_light_energy", 0.0, 2.0, 0.01],
	"ambient_sky_contribution": ["Свет неба в тени", "ambient_light_sky_contribution", 0.0, 1.0, 0.01],
	"exposure": ["Яркость", "tonemap_exposure", 0.25, 3.0, 0.01],
	"contrast": ["Контраст", "adjustment_contrast", 0.5, 1.5, 0.01],
	"saturation": ["Насыщенность", "adjustment_saturation", 0.0, 2.0, 0.01],
}
# UI metadata only: Sun owns its shadow values; Map owns the existing atlas quality.
const SHADOW_VALUES := {
	"sun_shadow_distance": ["Дальность теней, м", "directional_shadow_max_distance", 1, 256, 1],
	"sun_shadow_fade": ["Начало затухания, % дальности", "directional_shadow_fade_start", 0, 100, 1],
	"sun_shadow_mode": ["Распределение детализации", "directional_shadow_mode", 0, 2, 1,
		["Одна зона", "Две зоны · быстрее", "Четыре зоны · подробнее вблизи"]],
	"shadow_resolution": ["Чёткость карты теней", "directional_shadow_size", 1024, 8192, 1,
		["1024", "2048", "4096", "8192"], [1024, 2048, 4096, 8192]],
	"sun_shadow_bias": ["Смещение глубины", "shadow_bias", 0, 1, 0.001],
	"sun_shadow_normal_bias": ["Смещение от поверхности", "shadow_normal_bias", 0, 4, 0.01],
	"sun_shadow_pancake": ["Сжатие глубины тени, м", "directional_shadow_pancake_size", 0, 32, 0.05],
	"sun_shadow_blur": ["Размытие карты тени", "shadow_blur", 0, 4, 0.05],
	"shadow_filter": ["Фильтрация теней", "directional_shadow_filter", 0, 5, 1,
		["Без сглаживания", "Очень низкое", "Низкое", "Среднее", "Высокое", "Очень высокое"]],
}
const SHADOW_ADVANCED := ["sun_shadow_bias", "sun_shadow_normal_bias", "sun_shadow_pancake", "sun_shadow_blur"]
const SHADOW_HELP := {
	"sun_shadow_distance": "Расстояние от камеры. Большая дальность охватывает больше мира, но снижает чёткость при том же разрешении.",
	"sun_shadow_fade": "В этой доле дальности тень начинает исчезать. Например, 80% при 35 м — затухание с 28 до 35 м.",
	"sun_shadow_mode": "Каскады распределяют детализацию по расстоянию от камеры. Четыре зоны сохраняют больше деталей рядом.",
	"shadow_resolution": "Общее разрешение солнечных и лунных теней этой карты. Повышение требует больше видеопамяти и времени отрисовки.",
	"sun_shadow_bias": "Убирает ложные полосы на поверхности. Слишком большое смещение отрывает тень от объекта.",
	"sun_shadow_normal_bias": "Убирает самозатенение. Слишком большое значение съедает тени тонких ветвей и мелких деталей.",
	"sun_shadow_pancake": "Управляет сжатием глубины в теневой камере. При пропаже тени крупного объекта у края кадра сравните меньшее значение или 0. Это не дальность отрисовки.",
	"sun_shadow_blur": "Дополнительное размытие карты тени; размер солнца выше по-прежнему определяет мягкость источника.",
	"shadow_filter": "Более ровный мягкий край требует больше работы видеокарты. Это качество края, а не дальность.",
}
const COLORS := {
	"sun_color": ["Тон солнца", "light_color"],
	"ambient_color": ["Тон тени", "ambient_light_color"],
}
const WATER_VALUES = preload("res://scripts/prototypes/ember_compact_planar_reflection_study.gd").WATER_VALUES
const WATER_COLORS = preload("res://scripts/prototypes/ember_compact_planar_reflection_study.gd").WATER_COLORS
const MATERIAL_VALUES := {
	"world_look": ["Облик всей локации", "world_look", 0, 2, 1,
		["Детальный мир", "Low poly", "Воксельный мир"]],
	"compact_ground_style": ["Поверхность земли", "compact_ground_style", 0, 1, 1,
		["Воксельная", "Детальная"]],
	"compact_material_light_mode": ["Освещение поверхности", "compact_material_light_mode", 0, 2, 1,
		["Прежний свет", "Естественный мультяшный", "Игрушечный пластик"]],
}
const GRASS_VALUES := {
	"grass_x": ["Положение участка X, м", "_grass_x", -32, 64, 0.25],
	"grass_z": ["Положение участка Z, м", "_grass_z", -32, 64, 0.25],
	"grass_density": ["Плотность травы, пучков/м²", "tufts_per_block", 0, 200, 5],
	"grass_size": ["Размер пучков", "tuft_size", 0.2, 4.0, 0.05],
	"grass_width": ["Ширина участка, м", "_grass_width", 0.5, 32, 0.5],
	"grass_length": ["Длина участка, м", "_grass_length", 0.5, 32, 0.5],
	"grass_seed": ["Вариант расстановки", "scatter_seed", 0, 100000, 1],
}
const VOXEL_LIGHT_VALUES := {
	"voxel_light_cell_m": ["Ячейка воксельного света, м", "voxel_light_cell_m", 0.015625, 0.5, 0.015625],
	"voxel_light_levels": ["Градации воксельного света", "voxel_light_levels", 2, 32, 1],
}
const DEPTH_VALUES := {
	"compact_depth_fade_near_m": ["Полная глубина материалов до, м", "compact_depth_fade_near_m", 0, 64, 1],
	"compact_depth_fade_far_m": ["Глубина исчезает после, м", "compact_depth_fade_far_m", 1, 128, 1],
}
const ANOMALY_VALUES := {
	"anomaly_enabled": ["Сфера аномалии", "enabled", 0, 1, 1, ["Выключена", "Включена"]],
	"anomaly_look": ["Мир внутри сферы", "inner_look", 1, 2, 1, ["Low poly", "Воксельный мир"]],
	"anomaly_x": ["Центр X, м", "_anomaly_x", -32, 64, 0.1],
	"anomaly_y": ["Центр Y, м", "_anomaly_y", -16, 32, 0.1],
	"anomaly_z": ["Центр Z, м", "_anomaly_z", -32, 64, 0.1],
	"anomaly_radius": ["Радиус, м", "radius_m", 0.1, 32, 0.1],
	"anomaly_feather": ["Полоса перехода, м", "feather_m", 0.1, 2, 0.05],
}
var _anomaly_hint: Label
var _grass_choice: OptionButton
var _grass_paths: Array[NodePath] = []

var _scene: Node
var _map: EmberMapLoader
var _sun: DirectionalLight3D
var _environment: Environment
var _history: Object
var _sliders: Dictionary = {}
var _choices: Dictionary = {}
var _readouts: Dictionary = {}
var _pickers: Dictionary = {}
var _dragging := ""
var _color_editing := ""
var _before: Variant
var _enabled_before := false
var _sky_before := 1.0
var _syncing := false
var _shadow_switch: CheckBox
var _taa_switch: CheckBox
var _editor_quality_before: Array[Dictionary] = []
var _shadow_hint: Label
var _shadow_advanced: VBoxContainer
var _shadow_advanced_toggle: Button
var _hint: Label
var _water_hint: Label
var _water: Node
var _light_rows: VBoxContainer
var _water_rows: VBoxContainer
var _tabs: TabContainer
var _rim_switch: CheckBox
var _gray_switch: CheckBox
var _contact_switch: CheckBox
var _material_light_buttons: Array[Button]=[]


func _ready() -> void:
	var title := Label.new()
	title.text = "ВИД МИРА · ЭТА КАРТА"
	add_child(title)
	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.text = "Свет, тень и цвет сохраняются в сцене карты."
	add_child(_hint)
	_tabs = TabContainer.new()
	_tabs.use_hidden_tabs_for_min_size = false
	add_child(_tabs)
	_light_rows = VBoxContainer.new()
	_light_rows.name = "Свет и цвет"
	_tabs.add_child(_light_rows)
	var preset_title:=Label.new();preset_title.text="Проверка материалов · свет";_light_rows.add_child(preset_title)
	var presets:=HBoxContainer.new();_light_rows.add_child(presets)
	for i in EmberLights.MATERIAL_LIGHT_PRESETS.size():
		var button:=Button.new();button.text=EmberLights.MATERIAL_LIGHT_PRESETS[i].name;button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.pressed.connect(apply_material_light_preset.bind(i));presets.add_child(button);_material_light_buttons.append(button)
	_water_rows = VBoxContainer.new()
	_water_rows.name = "Вода"
	_tabs.add_child(_water_rows)
	var material_rows := VBoxContainer.new()
	material_rows.name = "Материалы"
	_tabs.add_child(material_rows)
	var anomaly_rows := VBoxContainer.new()
	anomaly_rows.name = "Аномалия"
	_tabs.add_child(anomaly_rows)
	var preview := Button.new()
	preview.text = "Предпросмотр аномалии"
	preview.pressed.connect(_preview_anomaly)
	anomaly_rows.add_child(preview)
	var stop := Button.new()
	stop.text = "Вернуться к редактированию земли"
	stop.pressed.connect(_stop_anomaly_preview)
	anomaly_rows.add_child(stop)
	_anomaly_hint = Label.new()
	_anomaly_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	anomaly_rows.add_child(_anomaly_hint)
	for key in ANOMALY_VALUES: _add_slider(key, anomaly_rows)
	for key in MATERIAL_VALUES:
		_add_slider(key, material_rows)
	for key in DEPTH_VALUES: _add_slider(key, material_rows)
	for key in VOXEL_LIGHT_VALUES: _add_slider(key, material_rows)
	var grass_title := Label.new();grass_title.text="Травяной покров";material_rows.add_child(grass_title)
	_grass_choice = OptionButton.new();material_rows.add_child(_grass_choice)
	_grass_choice.item_selected.connect(func(_index): refresh())
	for key in GRASS_VALUES: _add_slider(key, material_rows)
	_rim_switch = CheckBox.new()
	_rim_switch.text = "Световая кромка · вся карта"
	_rim_switch.toggled.connect(func(value: bool):
		if not _syncing and is_instance_valid(_map):
			_commit("compact_style_rim_enabled", _map.compact_style_rim_enabled, value, false))
	material_rows.add_child(_rim_switch)
	_gray_switch = CheckBox.new()
	_gray_switch.text = "Сравнить в одном сером цвете"
	_gray_switch.toggled.connect(func(value: bool):
		if not _syncing and is_instance_valid(_map):
			_commit("compact_material_gray_preview", _map.compact_material_gray_preview, value, false))
	material_rows.add_child(_gray_switch)
	_contact_switch = CheckBox.new()
	_contact_switch.text = "Мягкое затемнение в стыках"
	_contact_switch.toggled.connect(func(value: bool):
		if not _syncing and _environment != null:
			_commit("ssao_enabled", _environment.ssao_enabled, value, false))
	material_rows.add_child(_contact_switch)
	var material_hint := Label.new()
	material_hint.text = "Сравнивайте при одинаковом свете. Поверните солнце и камеру: блик должен перемещаться по поверхности. Настройки сохраняются в сцене и работают в 3D и F6."
	material_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	material_rows.add_child(material_hint)
	for key in VALUES:
		if key != "shadow_softness": _add_slider(key, _light_rows)
	_shadow_switch = CheckBox.new()
	_shadow_switch.text = "Тени от солнца"
	_shadow_switch.toggled.connect(_shadow_toggled)
	_light_rows.add_child(_shadow_switch)
	_shadow_hint = Label.new()
	_shadow_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_light_rows.add_child(_shadow_hint)
	_add_slider("shadow_softness", _light_rows)
	_add_slider("shadow_filter", _light_rows)
	_taa_switch = CheckBox.new()
	_taa_switch.text = "Сглаживать зерно теней · TAA"
	_taa_switch.tooltip_text = "Сглаживает точки света и теней по нескольким кадрам. Кадр становится немного мягче; можно выключить. Работает в 3D-окне редактора и в игре."
	_taa_switch.toggled.connect(func(value: bool):
		if not _syncing and is_instance_valid(_map): _commit("use_taa", _map.use_taa, value, false))
	_light_rows.add_child(_taa_switch)
	for key in SHADOW_VALUES:
		if key not in SHADOW_ADVANCED and key != "shadow_filter": _add_slider(key, _light_rows)
	_shadow_advanced_toggle = Button.new()
	_shadow_advanced_toggle.text = "Дополнительно · солнечные тени ▸"
	_shadow_advanced_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_shadow_advanced_toggle.toggle_mode = true
	_light_rows.add_child(_shadow_advanced_toggle)
	_shadow_advanced = VBoxContainer.new()
	_shadow_advanced.visible = false
	_light_rows.add_child(_shadow_advanced)
	_shadow_advanced_toggle.toggled.connect(func(open: bool):
		_shadow_advanced.visible = open
		_shadow_advanced_toggle.text = "Дополнительно · солнечные тени" + (" ▾" if open else " ▸"))
	for key in SHADOW_ADVANCED: _add_slider(key, _shadow_advanced)
	for key in COLORS:
		_add_color(key)
	_water_hint = Label.new()
	_water_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_water_rows.add_child(_water_hint)
	var groups: Dictionary = {}
	for key in WATER_VALUES:
		var group: String = WATER_VALUES[key][4]
		if not groups.has(group):
			var toggle := Button.new()
			toggle.text = group + " ▾"
			toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
			toggle.toggle_mode = true
			toggle.button_pressed = group in ["Цвет и прозрачность", "Поверхность и течение", "Пена и кромка"]
			toggle.text = group + (" ▾" if toggle.button_pressed else " ▸")
			_water_rows.add_child(toggle)
			var rows := VBoxContainer.new()
			rows.visible = toggle.button_pressed
			_water_rows.add_child(rows)
			toggle.toggled.connect(func(open: bool): rows.visible = open; toggle.text = group + (" ▾" if open else " ▸"))
			groups[group] = rows
			if group == "Цвет и прозрачность":
				for color_key in WATER_COLORS: _add_color(color_key, rows)
		_add_slider(key, groups[group])
	refresh()


func set_target(scene: Node, map: EmberMapLoader, history: Object) -> void:
	if not _dragging.is_empty(): _drag_ended(true, _dragging)
	if not _color_editing.is_empty(): _color_closed(_color_editing)
	if is_instance_valid(_history) and _history.has_signal("version_changed") and _history.is_connected("version_changed", refresh):
		_history.disconnect("version_changed", refresh)
	if _map != map:
		_disconnect_quality()
		_restore_editor_quality()
	_scene = scene
	_map = map
	if is_instance_valid(_map):
		if not _map.quality_changed.is_connected(_map_quality_changed): _map.quality_changed.connect(_map_quality_changed)
		_map.apply_quality()
		_apply_editor_quality()
	_refresh_grass_choices()
	if is_instance_valid(_map): _map.refresh_compact_material_light()
	_sun = map.get_node_or_null("Look/Sun") as DirectionalLight3D if is_instance_valid(map) else null
	var world := map.get_node_or_null("Look/WorldEnvironment") as WorldEnvironment if is_instance_valid(map) else null
	_environment = world.environment if world != null else null
	_history = history
	if is_instance_valid(_history) and _history.has_signal("version_changed"):
		_history.connect("version_changed", refresh)
	_water = null
	if is_instance_valid(scene):
		for node in scene.find_children("*", "Node", true, false):
			if node.has_method("water_settings_map") and node.call("water_settings_map") == map:
				_water = node
				break
	_dragging = ""
	_color_editing = ""
	refresh()


func _disconnect_quality() -> void:
	if is_instance_valid(_map) and _map.quality_changed.is_connected(_map_quality_changed):
		_map.quality_changed.disconnect(_map_quality_changed)


func _map_quality_changed() -> void:
	_apply_editor_quality()
	if is_instance_valid(_tabs): refresh()


func _apply_editor_quality() -> void:
	if not Engine.is_editor_hint() or not is_instance_valid(_map): return
	# Resolve the editor-only service dynamically: this panel also runs in F6/export.
	var editor := Engine.get_singleton("EditorInterface")
	if editor == null: return
	# Map.get_viewport() is the editor Window, not its four 3D SubViewports.
	for index in 4:
		var viewport := editor.call("get_editor_viewport_3d", index) as SubViewport
		if viewport == null: continue
		var known := false
		for previous in _editor_quality_before:
			if previous.viewport.get_ref() == viewport: known = true; break
		if not known:
			_editor_quality_before.append({"viewport": weakref(viewport), "taa": viewport.use_taa,
				"msaa": viewport.msaa_3d, "debanding": viewport.use_debanding, "atlas": viewport.positional_shadow_atlas_size})
		_map.apply_viewport_quality(viewport)


func _restore_editor_quality() -> void:
	for previous in _editor_quality_before:
		var viewport := previous.viewport.get_ref() as Viewport
		if not is_instance_valid(viewport): continue
		viewport.use_taa = previous.taa
		viewport.msaa_3d = previous.msaa
		viewport.use_debanding = previous.debanding
		viewport.positional_shadow_atlas_size = previous.atlas
	_editor_quality_before.clear()


func _exit_tree() -> void:
	_disconnect_quality()
	_restore_editor_quality()


func apply_runtime_water(scene_path: String, node_path: NodePath, values: Dictionary, sun_values := {}) -> Dictionary:
	if not is_instance_valid(_scene) or not is_instance_valid(_water) or _scene.scene_file_path != scene_path or _scene.get_path_to(_water) != node_path:
		return {"ok": false, "message": "Откройте исходную сцену воды в редакторе."}
	if not _dragging.is_empty() or not _color_editing.is_empty():
		return {"ok": false, "message": "Завершите изменение ползунка в редакторе и повторите."}
	# Reject both allowlists before touching the scene. Arbitrary transforms,
	# camera state, paths and unknown properties are never imported.
	if values.size() != WATER_VALUES.size() + WATER_COLORS.size():
		return {"ok": false, "message": "Состав настроек изменился. Перезапустите F6."}
	var before: Dictionary = {}
	var after: Dictionary = {}
	var sun_before: Dictionary = {}
	var sun_after: Dictionary = {}
	if not sun_values.is_empty():
		if not is_instance_valid(_sun) or sun_values.size() != EmberLights.SUN_LOOK_VALUES.size():
			return {"ok": false, "message": "Состав настроек света изменился. Перезапустите F6."}
		for key in EmberLights.SUN_LOOK_VALUES:
			var value: Variant = sun_values.get(key)
			var spec: Array = EmberLights.SUN_LOOK_VALUES[key]
			if not (value is float or value is int) or not is_finite(float(value)) or float(value) < float(spec[2]) or float(value) > float(spec[3]):
				return {"ok": false, "message": "Получены некорректные настройки солнца."}
			var previous := EmberLights.sun_look_value(_sun, spec[1])
			if not is_equal_approx(previous, float(value)):
				sun_before[spec[1]] = previous
				sun_after[spec[1]] = float(value)
	for key in WATER_VALUES:
		var value: Variant = values.get(key)
		if not (value is float or value is int) or not is_finite(float(value)):
			return {"ok": false, "message": "Получены некорректные настройки воды."}
		var spec: Array = WATER_VALUES[key]
		if float(value) < float(spec[1]) or float(value) > float(spec[2]):
			return {"ok": false, "message": "Настройки воды выходят за допустимые границы."}
		if spec.size() > 5 and float(value) != roundf(float(value)):
			return {"ok": false, "message": "Выберите один из способов обтекания."}
		if not is_equal_approx(float(_water.get(key)), float(value)):
			before[key] = _water.get(key)
			after[key] = float(value)
	for key in WATER_COLORS:
		var value: Variant = values.get(key)
		if not value is Color:
			return {"ok": false, "message": "Получен некорректный цвет воды."}
		for component in [value.r, value.g, value.b, value.a]:
			if not is_finite(component) or component < 0.0 or component > 1.0:
				return {"ok": false, "message": "Цвет воды выходит за допустимые границы."}
		if value.a != 1.0:
			return {"ok": false, "message": "Для прозрачности используйте отдельный регулятор воды."}
		if _water.get(key) != value:
			before[key] = _water.get(key)
			after[key] = value
	if float(values.water_color_end_m) < float(values.water_color_start_m) + 0.009:
		return {"ok": false, "message": "Конец цветового перехода должен быть глубже начала."}
	if after.is_empty() and sun_after.is_empty():
		return {"ok": true, "message": "Редактор уже содержит эти настройки."}
	if _history is EditorUndoRedoManager:
		(_history as EditorUndoRedoManager).create_action("Вода: применить настройки F6", UndoRedo.MERGE_DISABLE, _scene)
		for property in sun_after:
			Callable(_history, "add_do_method").callv([self, "_apply_value", _sun, property, sun_after[property], false, -1.0])
			Callable(_history, "add_undo_method").callv([self, "_apply_value", _sun, property, sun_before[property], false, -1.0])
		for key in after:
			(_history as EditorUndoRedoManager).add_do_property(_water, key, after[key])
			(_history as EditorUndoRedoManager).add_undo_property(_water, key, before[key])
		Callable(_history, "add_do_method").callv([_water, "refresh_water_settings"])
		Callable(_history, "add_undo_method").callv([_water, "refresh_water_settings"])
		(_history as EditorUndoRedoManager).commit_action()
	elif _history is UndoRedo:
		(_history as UndoRedo).create_action("Вода: применить настройки F6")
		for property in sun_after:
			(_history as UndoRedo).add_do_method(Callable(self, "_apply_value").bind(_sun, property, sun_after[property], false, -1.0))
			(_history as UndoRedo).add_undo_method(Callable(self, "_apply_value").bind(_sun, property, sun_before[property], false, -1.0))
		for key in after:
			(_history as UndoRedo).add_do_property(_water, key, after[key])
			(_history as UndoRedo).add_undo_property(_water, key, before[key])
		(_history as UndoRedo).add_do_method(Callable(_water, "refresh_water_settings"))
		(_history as UndoRedo).add_undo_method(Callable(_water, "refresh_water_settings"))
		(_history as UndoRedo).commit_action()
	else:
		return {"ok": false, "message": "История редактора недоступна. Повторите после открытия сцены."}
	refresh()
	return {"ok": true, "message": "Перенесено. В редакторе: Ctrl+S — сохранить, Ctrl+Z — отменить."}


func _target(key: String) -> Object:
	if not is_instance_valid(_scene): return null
	if ANOMALY_VALUES.has(key):
		return _map.get_node_or_null("WorldAnomaly") if is_instance_valid(_map) else null
	if GRASS_VALUES.has(key):
		return _map.get_node_or_null(_grass_paths[_grass_choice.selected]) if is_instance_valid(_map) and _grass_choice.selected >= 0 and _grass_choice.selected < _grass_paths.size() else null
	if key == "compact_style_rim_enabled": return _map if is_instance_valid(_map) else null
	if MATERIAL_VALUES.has(key) or DEPTH_VALUES.has(key) or VOXEL_LIGHT_VALUES.has(key) or key == "compact_material_gray_preview":
		return _map if is_instance_valid(_map) and _map.compact_terrain != null else null
	if WATER_VALUES.has(key) or WATER_COLORS.has(key): return _water if is_instance_valid(_water) else null
	if key in ["shadow_resolution", "shadow_filter", "use_taa"]: return _map if is_instance_valid(_map) else null
	if key.begins_with("sun_") or key == "shadow_softness" or key == "shadows":
		return _sun if is_instance_valid(_sun) else null
	return _environment if is_instance_valid(_environment) else null


func _property(key: String) -> String:
	if SHADOW_VALUES.has(key): return SHADOW_VALUES[key][1]
	if ANOMALY_VALUES.has(key): return ANOMALY_VALUES[key][1]
	if DEPTH_VALUES.has(key) or VOXEL_LIGHT_VALUES.has(key): return key
	if GRASS_VALUES.has(key): return GRASS_VALUES[key][1]
	if MATERIAL_VALUES.has(key) or key in ["compact_material_gray_preview", "compact_style_rim_enabled", "ssao_enabled"]: return key
	if WATER_VALUES.has(key) or WATER_COLORS.has(key): return key
	if key == "shadows": return "shadow_enabled"
	if key == "use_taa": return "use_taa"
	return str(VALUES[key][1]) if VALUES.has(key) else str(COLORS[key][1])

func _shadow_world_unit(target: Object) -> float:
	# Read the target's map, so undoing after switching maps keeps the right scale.
	var node := target as Node
	while node != null:
		if node is EmberMapLoader: return maxf(node.imported_tile_size, 0.001)
		node = node.get_parent()
	return 1.0


func _value(target: Object, property: String) -> Variant:
	if property in ["directional_shadow_max_distance", "directional_shadow_pancake_size"]:
		return float(target.get(property)) / _shadow_world_unit(target)
	if property == "directional_shadow_fade_start": return float(target.get(property)) * 100.0
	if property.begins_with("_anomaly_"):
		return target.position["xyz".find(property.right(1))]/_map.imported_tile_size
	if property in ["_grass_x", "_grass_z"]:
		var map: EmberMapLoader = target._map()
		var unit: float = map.imported_tile_size if map != null else 1.0
		return (target.position.x if property == "_grass_x" else target.position.z)/unit
	if property in ["_grass_width", "_grass_length"]: return target.size_blocks.x if property == "_grass_width" else target.size_blocks.y
	if property.begins_with("_sun_"):
		return EmberLights.sun_look_value(target as DirectionalLight3D, property)
	return target.get(property)


func _slider_spec(key: String) -> Array:
	if SHADOW_VALUES.has(key): return SHADOW_VALUES[key]
	if ANOMALY_VALUES.has(key): return ANOMALY_VALUES[key]
	if DEPTH_VALUES.has(key): return DEPTH_VALUES[key]
	if VOXEL_LIGHT_VALUES.has(key): return VOXEL_LIGHT_VALUES[key]
	if GRASS_VALUES.has(key): return GRASS_VALUES[key]
	if MATERIAL_VALUES.has(key): return MATERIAL_VALUES[key]
	if WATER_VALUES.has(key):
		var water: Array = WATER_VALUES[key]
		return [water[0], key, water[1], water[2], water[3]]
	return VALUES[key]


func _add_slider(key: String, parent: VBoxContainer) -> void:
	var spec: Array = _slider_spec(key)
	var row := VBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = str(spec[0])
	if SHADOW_HELP.has(key): row.tooltip_text = SHADOW_HELP[key]
	if key in ["water_detail_begin_m", "water_detail_end_m"]:
		row.tooltip_text = "Расстояние от камеры: рядом полная рябь и разводы, вдали меньше мелких деталей. Второй порог должен быть больше первого; иначе переход занимает 1 м."
	if key == "water_density": row.tooltip_text = "Как быстро с глубиной скрывается дно. 0 — без поглощения; 1 — прежняя вода. Пена и отражения сохраняются."
	if key == "water_transparency": row.tooltip_text = "Общая видимость дна: 0 — только цвет воды; 1 — прежняя прозрачность с учётом плотности и глубины."
	if key == "water_color_softness": row.tooltip_text = "0 — резкая граница оттенков, 1 — плавное смешивание между заданными глубинами."
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	if (SHADOW_VALUES.has(key) and spec.size() > 5) or (ANOMALY_VALUES.has(key) and spec.size() > 5) or MATERIAL_VALUES.has(key) or (WATER_VALUES.has(key) and WATER_VALUES[key].size() > 5):
		var choice := OptionButton.new()
		choice.name = key
		var items: Array = spec[5] if SHADOW_VALUES.has(key) or ANOMALY_VALUES.has(key) or MATERIAL_VALUES.has(key) else WATER_VALUES[key][5]
		for i in items.size(): choice.add_item(str(items[i]), int(spec[6][i]) if SHADOW_VALUES.has(key) and spec.size()>6 else i)
		row.add_child(choice)
		_choices[key] = choice
		choice.item_selected.connect(func(index: int):
			if _syncing or _target(key) == null: return
			var value: Variant = choice.get_item_id(index) if SHADOW_VALUES.has(key) else bool(index) if key == "anomaly_enabled" else index+(1 if key == "anomaly_look" else 0)
			_commit(key, _value(_target(key), _property(key)), value, false, -1.0))
		return
	var controls := HBoxContainer.new()
	row.add_child(controls)
	var slider := HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.min_value = float(spec[2])
	slider.max_value = float(spec[3])
	slider.step = float(spec[4])
	controls.add_child(slider)
	var readout := Label.new()
	readout.custom_minimum_size.x = 38
	controls.add_child(readout)
	_sliders[key] = slider
	_readouts[key] = readout
	slider.drag_started.connect(_drag_started.bind(key))
	slider.drag_ended.connect(_drag_ended.bind(key))
	slider.value_changed.connect(_slider_changed.bind(key))


func _add_color(key: String, parent: VBoxContainer = null) -> void:
	var row := HBoxContainer.new()
	(parent if parent != null else _light_rows).add_child(row)
	var label := Label.new()
	label.text = str(WATER_COLORS[key]) if WATER_COLORS.has(key) else str(COLORS[key][0])
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(68, 26)
	picker.edit_alpha = false
	row.add_child(picker)
	_pickers[key] = picker
	picker.pressed.connect(_color_started.bind(key))
	picker.color_changed.connect(_color_changed.bind(key))
	picker.popup_closed.connect(_color_closed.bind(key))


func refresh() -> void:
	if not is_node_ready(): return
	_syncing = true
	var available := is_instance_valid(_scene) and is_instance_valid(_sun) and _environment != null
	for button in _material_light_buttons:button.disabled=not available
	_hint.text = "Настройки сохраняются в сцене карты." if available else "На карте нужны Look/Sun и Look/WorldEnvironment."
	_water_hint.text = "Вода карты · 3D и F6. Настройки сохраняются в сцене; отражение объектов и подводный свет проверяйте в F6." if is_instance_valid(_water) else "На карте не найден контроллер воды."
	for key in _choices:
		var choice := _choices[key] as OptionButton
		var target := _target(key)
		choice.disabled = target == null
		if key == "world_look" and is_instance_valid(_map):
			choice.disabled = _map.compact_terrain == null or _map.compact_ground_style != 1
			choice.tooltip_text = "Общий облик земли, камней, деревьев и травы. Требуется детальная исходная поверхность земли."
		if key == "compact_ground_style" and is_instance_valid(_map):
			var terrain := _map.compact_terrain
			choice.disabled = _map.world_look >= 0 or terrain == null or terrain.width*terrain.depth > _map.smooth_column_limit()
			choice.tooltip_text = "Для общей локации используйте «Облик всей локации»." if _map.world_look >= 0 else "Форма исходной физической поверхности."
		if target != null:
			var value := int(_value(target, _property(key)))
			choice.select(choice.get_item_index(value) if SHADOW_VALUES.has(key) else value-(1 if key == "anomaly_look" else 0))
	_rim_switch.disabled = not is_instance_valid(_map)
	if is_instance_valid(_map): _rim_switch.set_pressed_no_signal(_map.compact_style_rim_enabled)
	_gray_switch.disabled = _target("compact_material_gray_preview") == null
	if not _gray_switch.disabled: _gray_switch.set_pressed_no_signal(_map.compact_material_gray_preview)
	_contact_switch.disabled = not available
	if _environment != null: _contact_switch.set_pressed_no_signal(_environment.ssao_enabled)
	for key in _sliders:
		var slider := _sliders[key] as HSlider
		var target := _target(key)
		slider.editable = is_instance_valid(_scene) and target != null
		if key in ["reaction_spread_speed", "reaction_opening", "reaction_birth_seconds"]:
			var analytic: bool = not is_instance_valid(_water) or _water.obstacle_wave_mode == 0
			slider.editable = slider.editable and analytic
			slider.tooltip_text = "Параметр отдельных дуг. В живом взаимодействии след распространяется общим полем волн." if not analytic else ""
		if target != null and key != _dragging:
			slider.set_value_no_signal(float(_value(target, _property(key))))
		(_readouts[key] as Label).text = _readout_text(key, slider.value)
	_taa_switch.disabled = not is_instance_valid(_map)
	if is_instance_valid(_map): _taa_switch.set_pressed_no_signal(_map.use_taa)
	_shadow_switch.disabled = not available
	if is_instance_valid(_sun):
		_shadow_switch.set_pressed_no_signal(_sun.shadow_enabled)
		var distance := _sun.directional_shadow_max_distance / _shadow_world_unit(_sun)
		if _shadow_hint != null: _shadow_hint.text = "Солнце · затухание с %.1f до %.1f м от камеры. Пропажу вблизи проверяйте отдельно: «Дополнительно»." % [distance*_sun.directional_shadow_fade_start, distance]
	elif _shadow_hint != null: _shadow_hint.text = "На карте нужен источник Look/Sun."
	for key in _pickers:
		var picker := _pickers[key] as ColorPickerButton
		picker.disabled = _target(key) == null if WATER_COLORS.has(key) else not available
		if _target(key) != null and key != _color_editing:
			picker.color = _target(key).get(_property(key))
	var anomaly := _target("anomaly_radius") as Node
	_anomaly_hint.text = "На этой карте нет сферы WorldAnomaly." if anomaly == null else "Снаружи — детальный мир. " + str(anomaly.preparation_state) + (". Для сферы выберите детальный облик всей локации." if _map.world_look != 0 else "")
	_syncing = false


func _process(_delta: float) -> void:
	if visible and Engine.get_process_frames() % 15 == 0 and _dragging.is_empty() and _color_editing.is_empty():
		refresh()


func _preview_anomaly() -> void:
	if not is_instance_valid(_map): return
	var anomaly := _map.get_node_or_null("WorldAnomaly")
	if anomaly != null: anomaly.request_preview()
	refresh()


func _stop_anomaly_preview() -> void:
	if not is_instance_valid(_map): return
	var anomaly := _map.get_node_or_null("WorldAnomaly")
	if anomaly != null: anomaly.stop_preview()
	refresh()


func _drag_started(key: String) -> void:
	var target := _target(key)
	if target == null: return
	_dragging = key
	_before = _value(target, _property(key))
	_enabled_before = _environment.adjustment_enabled if _environment != null else false
	_sky_before = _environment.ambient_light_sky_contribution if _environment != null else 1.0


func _slider_changed(value: float, key: String) -> void:
	if _syncing: return
	if WATER_VALUES.has(key) and is_instance_valid(_water):
		value = _water.water_color_depth_value(key, value)
		(_sliders[key] as HSlider).set_value_no_signal(value)
	(_readouts[key] as Label).text = _readout_text(key, value)
	var target := _target(key)
	if target == null: return
	if _dragging == key:
		_apply_value(target, _property(key), value, true, _active_sky_share(key, _sky_before))
	else:
		_commit(key, _value(target, _property(key)), value, _environment.adjustment_enabled if _environment != null else false)


func _readout_text(key: String, value: float) -> String:
	var step := float(_slider_spec(key)[4])
	return ("%.4f" if step < 0.001 else "%.3f" if step < 0.01 else "%.2f") % value


func _drag_ended(_changed: bool, key: String) -> void:
	if _dragging != key: return
	_dragging = ""
	_commit(key, _before, (_sliders[key] as HSlider).value, _enabled_before, _sky_before)


func _shadow_toggled(value: bool) -> void:
	if _syncing or not is_instance_valid(_sun): return
	_commit("shadows", _sun.shadow_enabled, value, _environment.adjustment_enabled if _environment != null else false)


func _color_started(key: String) -> void:
	var target := _target(key)
	if target == null: return
	_color_editing = key
	_before = target.get(_property(key))
	_enabled_before = _environment.adjustment_enabled if _environment != null else false
	_sky_before = _environment.ambient_light_sky_contribution if _environment != null else 1.0


func _color_changed(value: Color, key: String) -> void:
	if _syncing: return
	var target := _target(key)
	if target == null: return
	if _color_editing == key:
		_apply_value(target, _property(key), value, true, _active_sky_share(key, _sky_before))
	else:
		_commit(key, target.get(_property(key)), value, _environment.adjustment_enabled if _environment != null else false)


func _color_closed(key: String) -> void:
	if _color_editing != key: return
	_color_editing = ""
	_commit(key, _before, (_pickers[key] as ColorPickerButton).color, _enabled_before, _sky_before)


func _active_sky_share(key: String, before: float) -> float:
	if key != "ambient_color" and key != "ambient_energy":
		return -1.0
	return 0.25 if before >= 0.999 else before


func _apply_value(target: Object, property: String, value: Variant,
		adjustments_enabled: bool, sky_share := -1.0) -> void:
	if not is_instance_valid(target): return
	if property in ["directional_shadow_max_distance", "directional_shadow_pancake_size"]:
		target.set(property, float(value)*_shadow_world_unit(target))
	elif property == "directional_shadow_fade_start": target.set(property, float(value)/100.0)
	elif property.begins_with("_anomaly_"):
		var point: Vector3 = target.position
		point["xyz".find(property.right(1))] = float(value)*_map.imported_tile_size
		target.position = point
	elif property in ["_grass_x", "_grass_z"]:
		var map: EmberMapLoader = target._map()
		var unit: float = map.imported_tile_size if map != null else 1.0
		var point: Vector3 = target.position
		if property == "_grass_x": point.x = value*unit
		else: point.z = value*unit
		target.position = point
	elif property in ["_grass_width", "_grass_length"]:
		var dimensions: Vector2 = target.size_blocks
		if property == "_grass_width": dimensions.x = value
		else: dimensions.y = value
		target.size_blocks = dimensions
	elif property.begins_with("_sun_"):
		EmberLights.apply_sun_look_value(target as DirectionalLight3D, property, float(value))
	else: target.set(property, value)
	if target is EmberMapLoader and property in ["directional_shadow_size", "directional_shadow_filter"]: target.apply_quality()
	if target is EmberMapLoader and target != _map and is_instance_valid(_map) and property in ["use_taa", "directional_shadow_size", "directional_shadow_filter"]:
		_map.apply_quality()
	if target.has_method("refresh_water_settings"):
		target.call("refresh_water_settings")
	if target is Environment and sky_share >= 0.0:
		(target as Environment).ambient_light_sky_contribution = sky_share
	if target is Environment and property.begins_with("adjustment_"):
		(target as Environment).adjustment_enabled = adjustments_enabled
	refresh()


func _refresh_grass_choices() -> void:
	if _grass_choice == null: return
	var previous := _grass_paths[_grass_choice.selected] if _grass_choice.selected >= 0 and _grass_choice.selected < _grass_paths.size() else NodePath()
	_grass_paths.clear();_grass_choice.clear()
	if is_instance_valid(_map):
		for node in _map.find_children("*", "Node3D", true, false):
			if node.get_script() == null or node.get_script().resource_path != "res://scripts/ember_grass_patch.gd": continue
			var path: NodePath = _map.get_path_to(node)
			_grass_paths.append(path);_grass_choice.add_item(str(path))
	_grass_choice.disabled = _grass_paths.is_empty()
	if not _grass_paths.is_empty(): _grass_choice.select(maxi(0,_grass_paths.find(previous)))


func apply_material_light_preset(index: int) -> void:
	if not is_instance_valid(_scene) or not is_instance_valid(_sun) or _environment==null or index<0 or index>=EmberLights.MATERIAL_LIGHT_PRESETS.size():return
	if not _dragging.is_empty():_drag_ended(true,_dragging)
	if not _color_editing.is_empty():_color_closed(_color_editing)
	var before: Dictionary={"sun_rotation":_sun.rotation_degrees,"sun_color":_sun.light_color,"sun_energy":_sun.light_energy,"ambient_color":_environment.ambient_light_color,"ambient_energy":_environment.ambient_light_energy,"ambient_source":_environment.ambient_light_source,"background_color":_environment.background_color}
	var p: Dictionary=EmberLights.MATERIAL_LIGHT_PRESETS[index]
	var rotation:=_sun.rotation_degrees;rotation.x=-p.elevation
	var after: Dictionary={"sun_rotation":rotation,"sun_color":p.sun_color,"sun_energy":p.sun_energy,"ambient_color":p.ambient_color,"ambient_energy":p.ambient_energy,"ambient_source":Environment.AMBIENT_SOURCE_COLOR,"background_color":p.background_color}
	if before==after:return
	var action:="Вид мира: "+str(p.name)
	if _history is EditorUndoRedoManager:
		(_history as EditorUndoRedoManager).create_action(action,UndoRedo.MERGE_DISABLE,_scene)
		Callable(_history,"add_do_method").callv([self,"_apply_material_light_values",after])
		Callable(_history,"add_undo_method").callv([self,"_apply_material_light_values",before])
		(_history as EditorUndoRedoManager).commit_action()
	elif _history is UndoRedo:
		(_history as UndoRedo).create_action(action)
		(_history as UndoRedo).add_do_method(_apply_material_light_values.bind(after))
		(_history as UndoRedo).add_undo_method(_apply_material_light_values.bind(before))
		(_history as UndoRedo).commit_action()
	else:_apply_material_light_values(after)

func _apply_material_light_values(values: Dictionary) -> void:
	if not is_instance_valid(_sun) or _environment==null:return
	_sun.rotation_degrees=values.sun_rotation;_sun.light_color=values.sun_color;_sun.light_energy=values.sun_energy
	_environment.ambient_light_color=values.ambient_color;_environment.ambient_light_energy=values.ambient_energy
	_environment.ambient_light_source=values.ambient_source
	_environment.background_color=values.background_color
	refresh()

func _commit(key: String, previous: Variant, next: Variant, enabled_before: bool,
		sky_before := -1.0) -> void:
	var target := _target(key)
	if target == null or not is_instance_valid(_scene): return
	if sky_before < 0.0 and _environment != null:
		sky_before = _environment.ambient_light_sky_contribution
	var sky_after := _active_sky_share(key, sky_before)
	var restore_sky := sky_before if sky_after >= 0.0 else -1.0
	var property := _property(key)
	var enabled_after := true if property.begins_with("adjustment_") else enabled_before
	_apply_value(target, property, previous, enabled_before, restore_sky)
	if previous == next: return
	var caption := "Световая кромка" if key == "compact_style_rim_enabled" else "Сглаживание зерна теней" if key == "use_taa" else "Тени от солнца" if key == "shadows" else "Сравнить материалы в сером" if key == "compact_material_gray_preview" else "Мягкое затемнение в стыках" if key == "ssao_enabled" else str(_slider_spec(key)[0]) if _sliders.has(key) or _choices.has(key) else str(WATER_COLORS[key]) if WATER_COLORS.has(key) else str(COLORS[key][0])
	var action := "Вид мира: %s" % caption
	if _history is EditorUndoRedoManager:
		(_history as EditorUndoRedoManager).create_action(action, UndoRedo.MERGE_DISABLE, _scene)
		Callable(_history, "add_do_method").callv([self, "_apply_value", target, property, next, enabled_after, sky_after])
		Callable(_history, "add_undo_method").callv([self, "_apply_value", target, property, previous, enabled_before, restore_sky])
		(_history as EditorUndoRedoManager).commit_action()
	elif _history is UndoRedo:
		(_history as UndoRedo).create_action(action)
		(_history as UndoRedo).add_do_method(Callable(self, "_apply_value").bind(target, property, next, enabled_after, sky_after))
		(_history as UndoRedo).add_undo_method(Callable(self, "_apply_value").bind(target, property, previous, enabled_before, restore_sky))
		(_history as UndoRedo).commit_action()
	else:
		_apply_value(target, property, next, enabled_after, sky_after)
