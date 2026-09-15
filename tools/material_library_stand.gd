extends Node3D
## Disposable native preview only. Never publishes models, maps or prefabs.
const Library = preload("res://scripts/ember_material_library.gd")
const Mesher = preload("res://scripts/vox_mesher.gd")
var materials: Array[ShaderMaterial] = []
var samples: Array[MeshInstance3D] = []
var environment: Environment
var sun: DirectionalLight3D
var lamp: OmniLight3D
var camera: Camera3D
var selector: OptionButton
var controls: Dictionary = {}
var selected := 0
var orbit := Vector2(0.35,0.62)
var distance := 30.0
var updating := false
var tabs: TabContainer
var reflection_probe: ReflectionProbe

func _ready() -> void:
	_build_world()
	_build_ui()
	select_preset(0)
	set_lighting("day")
	_update_camera()

func sample_mesh() -> ArrayMesh:
	var voxels := PackedByteArray()
	voxels.resize(5*5*7)
	for y in 7:
		for z in 5:
			for x in 5:
				var edge := maxi(absi(x-2),absi(z-2))
				if y < 5 or edge < 2 and y < 6 or edge == 0:
					voxels[x+z*5+y*25] = 1 if (x+z+y)%5 != 0 else 2
	return Mesher.build_from_packed_voxel_region(voxels,Vector3i(5,7,5),
		PackedColorArray([Color.TRANSPARENT,Color.WHITE,Color("d6ded5")]),
		PackedByteArray(),Vector3i.ZERO,Vector3i(5,7,5),0.38)

func _box(name_text: String, position_value: Vector3, size_value: Vector3, color: Color) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = name_text
	visual.position = position_value
	var mesh := BoxMesh.new()
	mesh.size = size_value
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	visual.material_override = material
	add_child(visual)
	return visual

func _build_world() -> void:
	var world_environment := WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Default reflected source follows the Sky background.
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_intensity = 0.45
	environment.sky = Sky.new()
	environment.sky.sky_material = ProceduralSkyMaterial.new()
	world_environment.environment = environment
	add_child(world_environment)
	sun = DirectionalLight3D.new()
	sun.name = "StandSun"
	sun.light_specular = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
	lamp = OmniLight3D.new()
	lamp.name = "SeparateDemoLamp"
	lamp.position = Vector3(5,4,6)
	lamp.omni_range = 16.0
	lamp.light_color = Color(1,0.68,0.30)
	lamp.light_energy = 2.4
	lamp.light_specular = 1.0
	add_child(lamp)
	_box("Floor",Vector3(0,-0.24,0),Vector3(21,0.3,20),Color("52615d"))
	var shape := sample_mesh()
	for i in Library.PRESETS.size():
		var position_value := Vector3((i%3-1)*6.5,0,(i/3-1)*6.0)
		_box("Base"+str(i),position_value+Vector3(0,0.03,0),Vector3(5.4,0.2,4.8),Color("87928c"))
		# Contrasting solid backing makes alpha and depth order visible.
		_box("BackingWarm"+str(i),position_value+Vector3(-0.66,1.25,-0.55),Vector3(1.25,2.3,0.22),Color("b46748"))
		_box("BackingCool"+str(i),position_value+Vector3(0.66,1.25,-0.55),Vector3(1.25,2.3,0.22),Color("405f7a"))
		var material := Library.create(Library.PRESETS[i].id)
		materials.append(material)
		var sample := MeshInstance3D.new()
		sample.name = "Sample_"+Library.PRESETS[i].id
		sample.mesh = shape
		sample.material_override = material
		sample.position = position_value + Vector3(-0.95,0.15,0.15)
		sample.rotation_degrees.y = -12
		add_child(sample)
		samples.append(sample)
		var title := Label3D.new()
		title.text = Library.PRESETS[i].name
		title.position = position_value + Vector3(0,0.38,2.35)
		title.font_size = 42
		title.pixel_size = 0.009
		title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		title.no_depth_test = true
		add_child(title)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 25.0
	camera.far = 100.0
	add_child(camera)
	camera.current = true
	reflection_probe = ReflectionProbe.new()
	reflection_probe.name = "StandReflection"
	reflection_probe.position = Vector3(0,2,0)
	reflection_probe.size = Vector3(26,14,26)
	reflection_probe.box_projection = true
	reflection_probe.update_mode = ReflectionProbe.UPDATE_ALWAYS
	reflection_probe.intensity = 1.0
	add_child(reflection_probe)

func set_lighting(mode: String) -> void:
	var sky := environment.sky.sky_material as ProceduralSkyMaterial
	var night := mode == "night"
	sun.visible = not night
	lamp.visible = night
	sun.rotation_degrees = Vector3(-48,-32,0) if mode != "back" else Vector3(-15,150,0)
	sun.light_color = Color(1,0.94,0.82)
	sun.light_energy = 0.85
	environment.ambient_light_color = Color("a9c1c1") if not night else Color("4e668d")
	environment.ambient_light_energy = 0.30 if not night else 0.06
	sky.sky_top_color = Color("648ea5") if not night else Color("070e21")
	sky.sky_horizon_color = Color("c3cec4") if not night else Color("25334e")
	sky.ground_bottom_color = Color("3d4e43") if not night else Color("070a12")
	sky.ground_horizon_color = sky.sky_horizon_color

func _button(row: HBoxContainer, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	row.add_child(button)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -375
	panel.offset_right = -15
	panel.offset_top = 15
	panel.offset_bottom = 600
	layer.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,14)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",10)
	margin.add_child(column)
	var heading := Label.new()
	heading.text = "Библиотека материалов"
	heading.add_theme_font_size_override("font_size",20)
	column.add_child(heading)
	var row := HBoxContainer.new()
	column.add_child(row)
	_button(row,"День",set_lighting.bind("day"))
	_button(row,"Ночь",set_lighting.bind("night"))
	_button(row,"Контровой",set_lighting.bind("back"))
	selector = OptionButton.new()
	for preset in Library.PRESETS: selector.add_item(preset.name)
	selector.item_selected.connect(select_preset)
	column.add_child(selector)
	tabs = TabContainer.new()
	tabs.custom_minimum_size.y = 410
	tabs.add_theme_font_size_override("font_size",14)
	column.add_child(tabs)
	var groups := {
		"Основа":["base_color","surface_metallic","opacity","transmission_strength"],
		"Блики":["surface_roughness","highlight_strength","highlight_color","highlight_color_strength","iridescence_strength","iridescence_frequency"],
		"Фактура":["texture_kind","texture_scale","texture_strength","texture_relief"],
		"Свечение":["emission_color","emission_energy"],
	}
	var names := {"base_color":"Цвет поверхности","surface_roughness":"Шероховатость","highlight_strength":"Блеск","surface_metallic":"Металличность","opacity":"Непрозрачность","transmission_strength":"Просвечивание","emission_color":"Цвет свечения","emission_energy":"Сила свечения","highlight_color":"Цвет блика","highlight_color_strength":"Окрашивание блика","iridescence_strength":"Сила перелива","iridescence_frequency":"Частота перелива","texture_kind":"Особенность поверхности","texture_scale":"Масштаб фактуры","texture_strength":"Выраженность фактуры","texture_relief":"Мелкий рельеф"}
	var glow_column: VBoxContainer
	for group in groups:
		var group_column := VBoxContainer.new()
		group_column.name = group
		group_column.add_theme_constant_override("separation",10)
		tabs.add_child(group_column)
		if group == "Свечение": glow_column = group_column
		for parameter in groups[group]:
			var label := Label.new()
			label.text = names[parameter]
			group_column.add_child(label)
			if parameter.ends_with("color"):
				var picker := ColorPickerButton.new()
				picker.custom_minimum_size.y = 28
				picker.edit_alpha = false
				picker.color_changed.connect(_edit.bind(parameter))
				group_column.add_child(picker)
				controls[parameter] = picker
			elif parameter == "texture_kind":
				var kind := OptionButton.new()
				for title in ["Без фактуры","Древесные волокна","Каменные пятна","Зернистость"]: kind.add_item(title)
				kind.item_selected.connect(_edit.bind(parameter))
				group_column.add_child(kind)
				controls[parameter] = kind
			else:
				var slider := HSlider.new()
				slider.min_value = Library.RANGES[parameter].x
				slider.max_value = Library.RANGES[parameter].y
				slider.step = 0.001 if parameter == "texture_relief" else 0.01 if parameter != "emission_energy" else 0.1
				slider.value_changed.connect(_edit.bind(parameter))
				group_column.add_child(slider)
				controls[parameter] = slider
	var following := CheckButton.new()
	following.text = "Свечение цвета поверхности"
	following.toggled.connect(_edit.bind("emission_follow_base"))
	glow_column.add_child(following)
	controls.emission_follow_base = following
	_button(column_row(column),"Вернуть исходный вариант",_reset)
	var note := Label.new()
	note.text = "Изменения только на стенде.\nСвечение и свет лампы — отдельные эффекты.\nЛКМ: вращать · колесо: масштаб · R: камера"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size",13)
	column.add_child(note)

func column_row(column: VBoxContainer) -> HBoxContainer:
	var row := HBoxContainer.new()
	column.add_child(row)
	return row

func select_preset(index: int) -> void:
	selected = index
	updating = true
	selector.select(index)
	var material := materials[index]
	for parameter in controls:
		var value = material.get_shader_parameter(parameter)
		var control: Control = controls[parameter]
		if control is ColorPickerButton: control.color = value
		elif control is OptionButton: control.select(value)
		elif control is Range: control.value = value
		elif control is BaseButton: control.set_pressed_no_signal(value)
		if parameter in ["opacity","transmission_strength"]:
			# Opaque pipeline never turns into alpha by moving a slider.
			var enabled: bool = parameter != "opacity" or Library.PRESETS[index].id in ["glass","crystal"]
			control.editable = enabled
	controls.emission_color.disabled = material.get_shader_parameter("emission_follow_base")
	updating = false

func _edit(value: Variant, parameter: String) -> void:
	if updating: return
	if Library.validate_options({parameter:value}).is_empty():
		materials[selected].set_shader_parameter(parameter,value)
		if parameter == "emission_follow_base": controls.emission_color.disabled = value

func _reset() -> void:
	materials[selected] = Library.create(Library.PRESETS[selected].id)
	samples[selected].material_override = materials[selected]
	select_preset(selected)

func _update_camera() -> void:
	var focus := Vector3(3.0,0.7,0)
	camera.position = focus+Vector3(sin(orbit.x)*cos(orbit.y),sin(orbit.y),cos(orbit.x)*cos(orbit.y))*distance
	camera.look_at(focus)
	camera.size = distance*0.83

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		orbit.x -= event.relative.x*0.006
		orbit.y = clampf(orbit.y+event.relative.y*0.006,0.2,1.3)
		_update_camera()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: distance = maxf(18,distance-1.5)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: distance = minf(55,distance+1.5)
		_update_camera()
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		orbit = Vector2(0.35,0.62)
		distance = 30
		_update_camera()
