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
const COLORS := {
	"sun_color": ["Тон солнца", "light_color"],
	"ambient_color": ["Тон тени", "ambient_light_color"],
}
const WATER_VALUES = preload("res://scripts/prototypes/ember_compact_planar_reflection_study.gd").WATER_VALUES
const MATERIAL_VALUES := {
	"compact_material_light_mode": ["Освещение поверхности", "compact_material_light_mode", 0, 2, 1,
		["Прежний свет", "Естественный мультяшный", "Игрушечный пластик"]],
}

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
var _hint: Label
var _water_hint: Label
var _water: Node
var _light_rows: VBoxContainer
var _water_rows: VBoxContainer
var _tabs: TabContainer
var _gray_switch: CheckBox
var _contact_switch: CheckBox


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
	_water_rows = VBoxContainer.new()
	_water_rows.name = "Вода"
	_tabs.add_child(_water_rows)
	var material_rows := VBoxContainer.new()
	material_rows.name = "Материалы"
	_tabs.add_child(material_rows)
	for key in MATERIAL_VALUES:
		_add_slider(key, material_rows)
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
		_add_slider(key, _light_rows)
	_shadow_switch = CheckBox.new()
	_shadow_switch.text = "Тени от солнца"
	_shadow_switch.toggled.connect(_shadow_toggled)
	_light_rows.add_child(_shadow_switch)
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
			toggle.button_pressed = group in ["Поверхность и течение", "Пена и кромка"]
			toggle.text = group + (" ▾" if toggle.button_pressed else " ▸")
			_water_rows.add_child(toggle)
			var rows := VBoxContainer.new()
			rows.visible = toggle.button_pressed
			_water_rows.add_child(rows)
			toggle.toggled.connect(func(open: bool): rows.visible = open; toggle.text = group + (" ▾" if open else " ▸"))
			groups[group] = rows
		_add_slider(key, groups[group])
	refresh()


func set_target(scene: Node, map: EmberMapLoader, history: Object) -> void:
	if not _dragging.is_empty(): _drag_ended(true, _dragging)
	if not _color_editing.is_empty(): _color_closed(_color_editing)
	if is_instance_valid(_history) and _history.has_signal("version_changed") and _history.is_connected("version_changed", refresh):
		_history.disconnect("version_changed", refresh)
	_scene = scene
	_map = map
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


func apply_runtime_water(scene_path: String, node_path: NodePath, values: Dictionary, sun_values := {}) -> Dictionary:
	if not is_instance_valid(_scene) or not is_instance_valid(_water) or _scene.scene_file_path != scene_path or _scene.get_path_to(_water) != node_path:
		return {"ok": false, "message": "Откройте исходную сцену воды в редакторе."}
	if not _dragging.is_empty() or not _color_editing.is_empty():
		return {"ok": false, "message": "Завершите изменение ползунка в редакторе и повторите."}
	# Reject both allowlists before touching the scene. Arbitrary transforms,
	# camera state, paths and unknown properties are never imported.
	if values.size() != WATER_VALUES.size():
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
	if MATERIAL_VALUES.has(key) or key == "compact_material_gray_preview":
		return _map if is_instance_valid(_map) and _map.compact_terrain != null else null
	if WATER_VALUES.has(key): return _water if is_instance_valid(_water) else null
	if key.begins_with("sun_") or key == "shadow_softness" or key == "shadows":
		return _sun if is_instance_valid(_sun) else null
	return _environment if is_instance_valid(_environment) else null


func _property(key: String) -> String:
	if MATERIAL_VALUES.has(key) or key in ["compact_material_gray_preview", "ssao_enabled"]: return key
	if WATER_VALUES.has(key): return key
	if key == "shadows": return "shadow_enabled"
	return str(VALUES[key][1]) if VALUES.has(key) else str(COLORS[key][1])

func _value(target: Object, property: String) -> Variant:
	if property.begins_with("_sun_"):
		return EmberLights.sun_look_value(target as DirectionalLight3D, property)
	return target.get(property)


func _slider_spec(key: String) -> Array:
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
	if key in ["water_detail_begin_m", "water_detail_end_m"]:
		row.tooltip_text = "Расстояние от камеры: рядом полная рябь и разводы, вдали меньше мелких деталей. Второй порог должен быть больше первого; иначе переход занимает 1 м."
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	if MATERIAL_VALUES.has(key) or (WATER_VALUES.has(key) and WATER_VALUES[key].size() > 5):
		var choice := OptionButton.new()
		choice.name = key
		for item in (MATERIAL_VALUES[key][5] if MATERIAL_VALUES.has(key) else WATER_VALUES[key][5]): choice.add_item(str(item))
		row.add_child(choice)
		_choices[key] = choice
		choice.item_selected.connect(func(index: int):
			if _syncing or _target(key) == null: return
			_commit(key, _value(_target(key), _property(key)), index, false, -1.0))
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


func _add_color(key: String) -> void:
	var row := HBoxContainer.new()
	_light_rows.add_child(row)
	var label := Label.new()
	label.text = str(COLORS[key][0])
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
	_hint.text = "Настройки сохраняются в сцене карты." if available else "На карте нужны Look/Sun и Look/WorldEnvironment."
	_water_hint.text = "Вода пробной карты · 3D и F6. Отражение объектов и подводный свет проверяйте в F6." if is_instance_valid(_water) else "Эти настройки доступны на пробной карте воды."
	for key in _choices:
		var choice := _choices[key] as OptionButton
		var target := _target(key)
		choice.disabled = target == null
		if target != null: choice.select(int(_value(target, _property(key))))
	_gray_switch.disabled = _target("compact_material_gray_preview") == null
	if not _gray_switch.disabled: _gray_switch.set_pressed_no_signal(_map.compact_material_gray_preview)
	_contact_switch.disabled = not available
	if _environment != null: _contact_switch.set_pressed_no_signal(_environment.ssao_enabled)
	for key in _sliders:
		var slider := _sliders[key] as HSlider
		var target := _target(key)
		slider.editable = is_instance_valid(_scene) and target != null
		if target != null and key != _dragging:
			slider.set_value_no_signal(float(_value(target, _property(key))))
		(_readouts[key] as Label).text = _readout_text(key, slider.value)
	_shadow_switch.disabled = not available
	if is_instance_valid(_sun):
		_shadow_switch.set_pressed_no_signal(_sun.shadow_enabled)
	for key in COLORS:
		var picker := _pickers[key] as ColorPickerButton
		picker.disabled = not available
		if _target(key) != null and key != _color_editing:
			picker.color = _target(key).get(_property(key))
	_syncing = false


func _process(_delta: float) -> void:
	if visible and Engine.get_process_frames() % 15 == 0 and _dragging.is_empty() and _color_editing.is_empty():
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
	if property.begins_with("_sun_"):
		EmberLights.apply_sun_look_value(target as DirectionalLight3D, property, float(value))
	else: target.set(property, value)
	if target.has_method("refresh_water_settings"):
		target.call("refresh_water_settings")
	if target is Environment and sky_share >= 0.0:
		(target as Environment).ambient_light_sky_contribution = sky_share
	if target is Environment and property.begins_with("adjustment_"):
		(target as Environment).adjustment_enabled = adjustments_enabled
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
	var caption := "Тени от солнца" if key == "shadows" else "Сравнить материалы в сером" if key == "compact_material_gray_preview" else "Мягкое затемнение в стыках" if key == "ssao_enabled" else str(_slider_spec(key)[0]) if _sliders.has(key) or _choices.has(key) else str(COLORS[key][0])
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
