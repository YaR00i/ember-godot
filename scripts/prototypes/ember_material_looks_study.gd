extends "res://scripts/prototypes/ember_painted_light_study.gd"
## Same accepted grass field, scatter, Pattern, POM, player and physical surface.
## All added choices are temporary F6 presentation controls, not a new schema.
@export_enum("Painted", "Faceted light", "Pixel light") var presentation_mode := 0
@export_range(0.015625,0.125,0.015625) var presentation_pixel_m := 0.0625
@export_range(4,16,4) var presentation_light_levels := 8
var ready_for_looks := false
var moving_sun := false
var accepted_shader: Shader
var _looks_caption: Label
var _sun_elapsed := 0.0
var _sun_base_yaw := 0.0
var _sun_motion_switch: CheckBox
const LOOK_NAMES := ["А · живописный", "Б · гранёный свет", "В · пиксельный"]

func prepare() -> void:
	await super.prepare()
	accepted_shader = depth_shader
	var variant := Shader.new()
	variant.code = "#define EMBER_MATERIAL_LOOK_STUDY\n" + accepted_shader.code
	variant.set_meta("ember_compact_terrain_shader",true)
	depth_shader = variant
	apply_depth()
	_sync_tuft_material()
	for child in get_node("Instructions").get_children():
		if child is CanvasItem: child.hide()
	_build_looks_controls()
	ready_for_looks = true
	set_presentation(presentation_mode)
	print("MATERIAL_LOOKS_READY accepted grass field; tufts=",tuft_points.size()," POM4cm/32")

func set_presentation(mode: int) -> void:
	presentation_mode = clampi(mode,0,2)
	for material: ShaderMaterial in [depth_material,tuft_visual.material_override]:
		material.shader = accepted_shader if presentation_mode==0 else depth_shader
		material.set_shader_parameter("look_study_mode",presentation_mode)
		material.set_shader_parameter("look_study_pixel_m",presentation_pixel_m)
		material.set_shader_parameter("look_study_light_levels",presentation_light_levels)
	_update_looks_caption()

func apply_depth() -> void:
	super.apply_depth()
	if ready_for_looks: set_presentation(presentation_mode)

func _sync_tuft_material() -> void:
	super._sync_tuft_material()
	if ready_for_looks: set_presentation(presentation_mode)

func set_light_motion(enabled: bool) -> void:
	moving_sun = enabled
	if _sun_motion_switch!=null: _sun_motion_switch.set_pressed_no_signal(enabled)
	_sun_elapsed = 0.0
	_sun_base_yaw = get_node("Map/Look/Sun").rotation.y

func _process(delta: float) -> void:
	if not ready_for_looks or not moving_sun: return
	_sun_elapsed += delta
	set_sun_yaw(_sun_base_yaw + sin(_sun_elapsed * 0.4) * deg_to_rad(55.0))

func set_sun_yaw(yaw: float) -> void:
	var sun: DirectionalLight3D = get_node("Map/Look/Sun")
	sun.rotation.y = yaw
	depth_material.set_shader_parameter("material_depth_sun_direction",sun.global_basis.z)

func _build_looks_controls() -> void:
	var panel := PanelContainer.new();panel.position=Vector2(18,18)
	get_node("Instructions").add_child(panel)
	var column := VBoxContainer.new();column.custom_minimum_size.x=375;panel.add_child(column)
	_looks_caption=Label.new();column.add_child(_looks_caption)
	var choices:=HBoxContainer.new();column.add_child(choices)
	for i in 3:
		var button:=Button.new();button.text=LOOK_NAMES[i];choices.add_child(button)
		button.pressed.connect(func():set_presentation(i))
	var presets:=HBoxContainer.new();column.add_child(presets)
	for i in 3:
		var button:=Button.new();button.text=EmberLights.MATERIAL_LIGHT_PRESETS[i].name;presets.add_child(button)
		button.pressed.connect(func():set_light_motion(false);set_lighting_preset(i))
	var poses:=HBoxContainer.new();column.add_child(poses)
	for i in 2:
		var button:=Button.new();button.text=["Контровой","Боковой"][i];poses.add_child(button)
		button.pressed.connect(func():set_light_motion(false);set_sun_pose(i))
	var motion:=CheckBox.new();motion.text="Движение солнца";column.add_child(motion)
	_sun_motion_switch=motion
	motion.toggled.connect(set_light_motion)
	var pixel:=OptionButton.new();column.add_child(pixel)
	for size_m in [0.03125,0.0625,0.125]:pixel.add_item("Пиксель поверхности · %.3f м"%size_m)
	pixel.select(maxi(0,[0.03125,0.0625,0.125].find(presentation_pixel_m)));pixel.item_selected.connect(func(index):presentation_pixel_m=[0.03125,0.0625,0.125][index];set_presentation(presentation_mode))
	var levels:=OptionButton.new();column.add_child(levels)
	for count in [4,8,16]:levels.add_item("Ступени света · %d"%count)
	levels.select(maxi(0,[4,8,16].find(presentation_light_levels)));levels.item_selected.connect(func(index):presentation_light_levels=[4,8,16][index];set_presentation(presentation_mode))
	var tufts:=CheckBox.new();tufts.text="Принятое покрытие травой";tufts.button_pressed=true;column.add_child(tufts)
	tufts.toggled.connect(set_tufts)
	var geometry:=HBoxContainer.new();column.add_child(geometry)
	for i in 3:
		var button:=Button.new();button.text=["Гладко","Полублоки","Воксели"][i];geometry.add_child(button)
		button.pressed.connect(func():set_phase(i*0.5))
	var hint:=Label.new();hint.text="1/2/3 — А/Б/В · WASD — ходить · ПКМ — камера\nF1 — панель · настройки пробы временные";column.add_child(hint)

func _update_looks_caption() -> void:
	if _looks_caption!=null:
		_looks_caption.text=LOOK_NAMES[presentation_mode]+" · одинаковая покраска и трава\nГлубина камня 4 см · Б проверяет только освещение"

func _unhandled_input(event: InputEvent) -> void:
	if ready_for_looks and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_1,KEY_2,KEY_3]:set_presentation(event.keycode-KEY_1);return
	super._unhandled_input(event)
