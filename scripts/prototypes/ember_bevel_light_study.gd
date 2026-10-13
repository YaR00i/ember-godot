extends "res://scripts/prototypes/ember_material_depth_study.gd"
## Same Sol Source/artwork/POM, isolated light-only A/B.
@export var bevel_enabled := true
var ready_for_bevel := false
var sun_pose := 0
const SUN_POSES := [Vector3(-32,-65,0), Vector3(-27,-145,0)]
var caption: Label

func prepare() -> void:
	await super.prepare()
	var variant := Shader.new()
	variant.code = "#define EMBER_BEVEL_STUDY\n" + depth_shader.code
	variant.set_meta("ember_compact_terrain_shader",true)
	depth_shader = variant
	apply_depth()
	follow_camera.follow_distance = 9.5
	follow_camera.polar_angle = 0.95
	follow_camera.yaw = 0.35
	follow_camera.look_height = 0.6
	follow_camera._cam.make_current()
	for child in get_node("Instructions").get_children():
		if child is CanvasItem: child.hide()
	var panel := VBoxContainer.new(); panel.position = Vector2(20,20)
	get_node("Instructions").add_child(panel)
	caption = Label.new(); panel.add_child(caption)
	var hint := Label.new(); hint.text = "B — свет на фасках · L — боковое/контровое солнце · F1 — панель · WASD/ПКМ"
	panel.add_child(hint)
	for label in ["B · до / после", "L · сменить солнце"]:
		var button := Button.new(); button.text = label; panel.add_child(button)
		if label.begins_with("B"): button.pressed.connect(func(): set_bevel(not bevel_enabled))
		else: button.pressed.connect(func(): set_sun(sun_pose+1))
	set_bevel(bevel_enabled); set_sun(0)
	ready_for_bevel = true
	print("BEVEL_READY same Sol Source/artwork/POM 4cm/32; real game camera")

func set_bevel(enabled: bool) -> void:
	bevel_enabled = enabled
	depth_material.set_shader_parameter("bevel_light_enabled",enabled)
	if is_instance_valid(caption): caption.text = ("B · свет на фасках" if enabled else "A · исходный свет Сола") + " | глубина 4 см сохранена"

func set_sun(index: int) -> void:
	sun_pose = posmod(index,SUN_POSES.size())
	get_node("Map/Look/Sun").rotation_degrees = SUN_POSES[sun_pose]
	depth_material.set_shader_parameter("material_depth_sun_direction",get_node("Map/Look/Sun").global_basis.z)

func _unhandled_input(event: InputEvent) -> void:
	if not ready_for_bevel: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_B: set_bevel(not bevel_enabled); return
		if event.keycode == KEY_L: set_sun(sun_pose+1); return
		if event.keycode == KEY_F1:
			get_node("Instructions").visible = not get_node("Instructions").visible; return
	super._unhandled_input(event)
