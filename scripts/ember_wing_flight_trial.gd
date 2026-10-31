extends Node3D
## Disposable flight course; reuses EmberPlayer and EmberFollowCamera.
## Route and solid obstacles belong to the .tscn. No map/save/battle binding.

const Player := preload("res://scripts/ember_player.gd")
const FollowCamera := preload("res://scripts/ember_follow_camera.gd")
const Motion := preload("res://scripts/ember_wing_flight_motion.gd")
const FlapMotion := preload("res://scripts/ember_wing_flap_motion.gd")
const HoshiFlight := preload("res://scripts/ember_hoshi_flight_visual.gd")
var hoshi_mode := "--hoshi-wings" in OS.get_cmdline_user_args()
var hoshi_visual: Node3D
var _hoshi_ready := false
const GATE_RADIUS := 18.0
var player: EmberPlayer
var camera: EmberFollowCamera
var gates: Array[Node3D] = []
var gate_materials: Array[StandardMaterial3D] = []
var next_gate := 0
var running := false
var elapsed := 0.0
var previous_position := Vector3.ZERO
var _reset_pending := false
var _gate_message := ""
var _hud: Label
var _menu: PanelContainer
var _menu_title: Label
var _start_button: Button
var _velocity_marker: Label
var tuning_path := "user://ember-flight-trial-tuning-v1.json"
var _cloud_settings := CLOUD_DEFAULTS.duplicate()
var _cloud_ui_dirty := false
var _cloud_controls := {}
var _cloud_value_labels := {}
var _tuning_tabs: TabContainer
const CLOUD_RANGES := {
	"density_scale": Vector3(0, 3, 0.05), "wind_scale": Vector3(0, 4, 0.1),
	"height_offset_m": Vector3(-500, 4000, 10), "thickness_scale": Vector3(0.25, 3, 0.05),
	"near_cloud_count": Vector3(0, 5, 1), "edge_softness": Vector3(0.1, 0.45, 0.01),
	"rim_strength": Vector3(0, 1.5, 0.05), "rim_width": Vector3(0.1, 0.9, 0.05),
	"rim_steps": Vector3(0, 6, 1), "shadow_strength": Vector3(0, 1, 0.05),
}
const CLOUD_LABELS := {"density_scale": "Плотность", "wind_scale": "Движение фактуры",
	"height_offset_m": "Сдвиг высоты, м", "thickness_scale": "Толщина слоя", "near_cloud_count": "Число ближних облаков",
	"edge_softness": "Мягкость края", "rim_strength": "Сила светового канта", "rim_width": "Ширина канта",
	"rim_steps": "Ступени канта (0 — плавно)", "shadow_strength": "Сила самозатенения"}
var tuning := Motion.defaults()
var camera_tuning := FollowCamera.flight_defaults()
var _clouds: Array[FogVolume] = []
var cloud_settings_path := "res://content/flight_trial_clouds.cfg"
var _cloud_origins: Array[Transform3D] = []
var _cloud_sizes: Array[Vector3] = []
const CLOUD_DEFAULTS := {
	"highlight_color": Color(0.70, 0.70, 0.70), "shadow_color": Color(0.32, 0.32, 0.32),
	"density_scale": 1.0, "wind_scale": 1.0, "height_offset_m": 0.0,
	"thickness_scale": 1.0, "near_cloud_count": 5, "distant_clouds_enabled": true,
	"edge_softness": 0.26, "rim_strength": 0.0, "rim_width": 0.35, "rim_steps": 0,
	"rim_color": Color(0.85, 0.85, 0.85), "shadow_strength": 1.0,
}
var _tuning_sliders := {}
var _tuning_labels := {}
var _tuning_status: Label
var _tuning_status_text := "Настройки действуют сразу. Сохраните удачный набор."


func _enter_tree() -> void:
	add_to_group("ember_flight_trial")
	RenderingServer.environment_set_volumetric_fog_volume_size(192, 128)
	RenderingServer.environment_set_volumetric_fog_filter_active(false)

func _exit_tree() -> void:
	remove_from_group("ember_flight_trial")
	if get_tree().get_nodes_in_group("ember_flight_trial").is_empty():
		RenderingServer.environment_set_volumetric_fog_filter_active(bool(ProjectSettings.get_setting("rendering/environment/volumetric_fog/use_filter", true)))
		RenderingServer.environment_set_volumetric_fog_volume_size(
			int(ProjectSettings.get_setting("rendering/environment/volumetric_fog/volume_size", 64)),
			int(ProjectSettings.get_setting("rendering/environment/volumetric_fog/volume_depth", 64)))

func _ready() -> void:
	load_tuning()
	var trial_state := EmberExploreState.new()
	trial_state.name = "TrialProgress"
	trial_state.persistence_enabled = false
	trial_state.restore_enabled = false
	add_child(trial_state)
	player = Player.new()
	player.name = "FlightPlayer"
	player.tile_size = 1.0
	player.progress_state = trial_state
	add_child(player)
	player.set_physics_process(false)
	camera = FollowCamera.new()
	camera.name = "FlightCamera"
	camera.target = player
	camera.fov = 72.0
	camera.cam_near = 0.05
	camera.cam_far = 12000.0
	if hoshi_mode:
		camera.flight_framing_scale = 0.6
	add_child(camera)
	camera.configure_flight(camera_tuning)
	_setup_clouds()
	player.camera_rig = camera
	_add_wings()
	_build_gates()
	_build_hud()
	_reset_flight_body()
	player.flight_collision.connect(_on_collision)
	_show_menu("Хоши · крылья и взлёт" if hoshi_mode else "Полёт на крыльях", "Начать пробу" if hoshi_mode else "Начать полёт")
	if hoshi_mode and not _hoshi_ready:
		_menu_title.text = "Не найдены локальные Хоши / крылья"
		_start_button.disabled = true
	_update_hud()
	get_window().focus_exited.connect(_focus_lost)


func _add_wings() -> void:
	if hoshi_mode:
		hoshi_visual = HoshiFlight.new()
		player.add_child(hoshi_visual)
		_hoshi_ready = hoshi_visual.setup(player)
		$StartPlatform.show()
		$StartPlatform.collision_layer = 1
		return
	var body := MeshInstance3D.new()
	body.name = "FlightBody"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.28
	capsule.height = 1.8
	body.mesh = capsule
	body.rotation.x = PI * 0.5
	body.material_override = _material(Color("f1d1a0"))
	player.add_child(body)
	# Two clearly readable placeholder wings; own geometry, not game assets.
	for side in [-1, 1]:
		var wing := MeshInstance3D.new()
		var mesh := PrismMesh.new()
		mesh.size = Vector3(2.8, 0.12, 1.3)
		wing.mesh = mesh
		wing.position = Vector3(side * 1.55, 0.0, 0.15)
		wing.rotation.z = side * -0.10
		wing.material_override = _material(Color("93e3ed") if side < 0 else Color("f6af78"))
		player.add_child(wing)


func _material(color: Color, glow: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	mat.emission_enabled = glow > 0.0
	mat.emission = color
	mat.emission_energy_multiplier = glow
	return mat


func _build_gates() -> void:
	for marker in $Route.get_children():
		var gate := marker as Node3D
		gates.append(gate)
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = GATE_RADIUS - 0.6
		torus.outer_radius = GATE_RADIUS + 0.6
		torus.rings = 48
		torus.ring_segments = 8
		ring.mesh = torus
		ring.rotation.x = PI * 0.5
		var mat := _material(Color("829cae"), 0.4)
		ring.material_override = mat
		gate_materials.append(mat)
		gate.add_child(ring)
		var label := Label3D.new()
		label.text = str(gates.size())
		label.font_size = 64
		label.pixel_size = 0.045
		label.position.y = GATE_RADIUS + 3.0
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		gate.add_child(label)
		for segment in range(24):
			var angle := TAU * segment / 24.0
			var solid := StaticBody3D.new()
			var shape_node := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(1.2, 4.9, 1.2)
			shape_node.shape = shape
			solid.add_child(shape_node)
			solid.position = Vector3(cos(angle), sin(angle), 0) * GATE_RADIUS
			solid.rotation.z = angle
			gate.add_child(solid)
	_refresh_gates()


func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "FlightHUD"
	add_child(canvas)
	_hud = Label.new()
	_hud.position = Vector2(26, 20)
	_hud.add_theme_font_size_override("font_size", 23)
	_hud.add_theme_color_override("font_shadow_color", Color.BLACK)
	_hud.add_theme_constant_override("shadow_offset_x", 2)
	_hud.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(_hud)
	_velocity_marker = Label.new()
	_velocity_marker.text = "⊙"
	_velocity_marker.add_theme_font_size_override("font_size", 30)
	_velocity_marker.modulate = Color("c8f6ef")
	canvas.add_child(_velocity_marker)
	var centering := CenterContainer.new()
	centering.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centering.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(centering)
	_menu = PanelContainer.new()
	_menu.custom_minimum_size = Vector2(1220, 0)
	centering.add_child(_menu)
	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 24)
	_menu.add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 30)
	margin.add_child(columns)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 700
	column.add_theme_constant_override("separation", 16)
	columns.add_child(column)
	_menu_title = Label.new()
	_menu_title.add_theme_font_size_override("font_size", 30)
	column.add_child(_menu_title)
	var instructions := Label.new()
	instructions.text = "Пройди 6 ворот по порядку. Бирюзовые — следующие.\n\nСтик вбок — крен · назад — нос вверх · вперёд — вниз\nRT — разгон · LT — тормоз · LB/RB — доворот\nОтпусти курки — достигнутая скорость сохраняется\nRT + LT — готовность виража; стик назад — усиленный поворот\nПравый стик / ПКМ + мышь — осмотр камеры\nStart / Esc — пауза и настройки · Back / R — заново\n\nКлавиатура: A/D — крен · W/S — нос вниз/вверх\nQ/E — доворот · Пробел — разгон · Shift — тормоз\nПробел + Shift + S — крутой вираж\n\nНа высокой скорости поворот шире, на малой отклик слабее.\n⊙ показывает траекторию. RT/LT в HUD — фактический ввод.\nКасание препятствия возвращает на старт."
	instructions.add_theme_font_size_override("font_size", 20)
	if hoshi_mode:
		instructions.text = "На площадке: левый стик / WASD — ходьба.\nA / Пробел — прыжок. Нажми ещё раз в воздухе:\nкокон → вращение → раскрытие крыльев → полёт.\nОдин прыжок заканчивается обычным приземлением.\n\nRT / Ctrl — один рывок в коконе на нажатие.\nУдержание не повторяет рывки; быстрые — в очередь.\nПоддерживающие взмахи — автоматически.\nПри пикировании крылья планируют.\n\nВ воздухе стик вбок — крен до90°; назад — нос вверх.\nLT / Shift — тормоз · LB/RB / Q/E — доворот\nW/S — нос вниз/вверх · A/D — крен\nПравый стик / ПКМ + мышь — осмотр\nStart / Esc — пауза · Back / R — на площадку\n\nКрылья — частный AION2-референс.\nПоза тела и тонкое движение перьев — черновые."
	column.add_child(instructions)
	_start_button = Button.new()
	_start_button.custom_minimum_size.y = 48
	_start_button.pressed.connect(_start_or_resume)
	column.add_child(_start_button)
	var quit_button := Button.new()
	quit_button.text = "Закрыть пробу"
	quit_button.pressed.connect(func(): get_tree().quit())
	column.add_child(quit_button)
	var tuning_column := VBoxContainer.new()
	tuning_column.custom_minimum_size.x = 400
	tuning_column.add_theme_constant_override("separation", 8)
	columns.add_child(tuning_column)
	_build_tuning(tuning_column)


func _build_tuning(column: VBoxContainer) -> void:
	var heading := Label.new()
	heading.text = "Настройки"
	heading.add_theme_font_size_override("font_size", 26)
	column.add_child(heading)
	var tabs := TabContainer.new()
	_tuning_tabs = tabs
	tabs.custom_minimum_size = Vector2(460, 490)
	column.add_child(tabs)
	for section in ["Полёт", "Камера"]:
		var page := VBoxContainer.new()
		page.name = section
		tabs.add_child(page)
		var definitions: Dictionary = Motion.TUNING if section == "Полёт" else FollowCamera.FLIGHT_TUNING
		for key in definitions:
			if hoshi_mode and section == "Полёт" and key in ["acceleration_kmh_s", "high_g_multiplier"]:
				continue
			_add_tuning_slider(page, key, definitions[key], section == "Камера")
	_build_cloud_tab(tabs)
	var note := Label.new()
	note.text = "Камера: больше задержка — сильнее отставание.\nОсмотр отпущен — камера возвращается за самолёт."
	tabs.tab_changed.connect(func(index: int): note.text = "Облака: изменения применяются сразу.\nСохранить — в cfg; R оставляет текущие правки." if index == 2 else "Камера: больше задержка — сильнее отставание.\nОсмотр отпущен — камера возвращается за самолёт.")
	note.add_theme_font_size_override("font_size", 17)
	column.add_child(note)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	for definition in [["Сохранить", save_tuning], ["Загрузить", load_tuning], ["Сбросить", reset_tuning]]:
		var button := Button.new()
		button.text = definition[0]
		button.custom_minimum_size = Vector2(125, 40)
		button.pressed.connect(_settings_action.bind(actions.get_child_count()))
		actions.add_child(button)
	_tuning_status = Label.new()
	_tuning_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tuning_status.custom_minimum_size = Vector2(390, 54)
	column.add_child(_tuning_status)
	_sync_tuning_ui()


func _add_tuning_slider(page: VBoxContainer, key: String, definition: Vector4, is_camera: bool) -> void:
	var id := "camera_" + key if is_camera else key
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 19)
	page.add_child(label)
	_tuning_labels[id] = label
	var slider := HSlider.new()
	slider.min_value = definition.x
	slider.max_value = definition.y
	slider.step = definition.z
	slider.custom_minimum_size = Vector2(430, 24)
	slider.value_changed.connect(_change_tuning.bind(id))
	page.add_child(slider)
	_tuning_sliders[id] = slider

func _change_tuning(value: float, key: String) -> void:
	if key.begins_with("camera_"):
		camera_tuning[key.trim_prefix("camera_")] = value
	else:
		tuning[key] = value
	_apply_tuning()
	_tuning_status_text = "Изменено. Сохраните набор, чтобы оставить его после закрытия."
	_sync_tuning_ui()


func _apply_tuning() -> void:
	tuning = Motion.sanitize(tuning)
	camera_tuning = FollowCamera.sanitize_flight(camera_tuning)
	if is_instance_valid(camera):
		camera.configure_flight(camera_tuning)
	if is_instance_valid(player) and player.flight_motion != null:
		player.flight_motion.configure(tuning)


func _sync_tuning_ui() -> void:
	var names := {"max_speed_kmh": "Предел скорости, км/ч", "acceleration_kmh_s": "Разгон, км/ч за секунду", "pitch_rate_deg": "Поворот, °/с", "roll_rate_deg": "Крен, °/с", "response_seconds": "Отклик, с", "high_g_multiplier": "Усиление виража, ×"}
	var camera_names := {"lag_seconds": "Задержка вращения, с", "lag_angle_deg": "Предел отставания, °", "push_shift": "Смещение: стик вперёд", "pull_shift": "Смещение: стик назад", "return_seconds": "Возврат после манёвра, с", "speed_fov": "Расширение FOV от скорости, °", "look_angle_deg": "Угол осмотра, °"}
	for key in _tuning_sliders:
		if key.begins_with("camera_"):
			var camera_key: String = key.trim_prefix("camera_")
			_tuning_sliders[key].set_value_no_signal(camera_tuning[camera_key])
			_tuning_labels[key].text = camera_names[camera_key] + "  %.2f" % camera_tuning[camera_key]
			continue
		_tuning_sliders[key].set_value_no_signal(tuning[key])
		_tuning_labels[key].text = names[key] + ("  %.2f" % tuning[key] if key in ["response_seconds", "high_g_multiplier"] else "  %d" % roundi(tuning[key]))
	if is_instance_valid(_tuning_status):
		_tuning_status.text = _tuning_status_text


func save_tuning() -> bool:
	var file := FileAccess.open(tuning_path, FileAccess.WRITE)
	if file == null:
		_tuning_status_text = "Не удалось сохранить набор. Текущие значения остаются в сессии."
		_sync_tuning_ui()
		return false
	file.store_string(JSON.stringify({"version": 1, "values": Motion.sanitize(tuning), "camera": FollowCamera.sanitize_flight(camera_tuning)}, "\t"))
	file.close()
	_tuning_status_text = "Сохранено и уже действует. Перезапуск не нужен; R — трасса заново."
	_sync_tuning_ui()
	return true


func load_tuning() -> bool:
	if not FileAccess.file_exists(tuning_path):
		return false
	var parser := JSON.new()
	var parse_error := parser.parse(FileAccess.get_file_as_string(tuning_path))
	var data: Variant = parser.data if parse_error == OK else null
	if not data is Dictionary or data.get("version") != 1 or not data.get("values") is Dictionary:
		_tuning_status_text = "Набор не прочитан. Текущие значения сохранены в сессии."
		_sync_tuning_ui()
		return false
	tuning = Motion.sanitize(data["values"])
	camera_tuning = FollowCamera.sanitize_flight(data.get("camera", {}) if data.get("camera", {}) is Dictionary else {})
	_apply_tuning()
	_tuning_status_text = "Сохранённый набор загружен."
	_sync_tuning_ui()
	return true


func reset_tuning() -> void:
	tuning = Motion.defaults()
	camera_tuning = FollowCamera.flight_defaults()
	_apply_tuning()
	_tuning_status_text = "Базовый набор восстановлен. Сохранённый файл не перезаписан."
	_sync_tuning_ui()


func start_run() -> void:
	if hoshi_mode and not _hoshi_ready:
		return
	if not _cloud_ui_dirty:
		reload_cloud_settings()
	next_gate = 0
	elapsed = 0.0
	_update_clouds(0.0)
	_gate_message = ""
	_reset_pending = false
	_reset_flight_body()
	previous_position = player.global_position
	running = true
	_menu.hide()
	_hud.show()
	player.set_physics_process(true)
	_refresh_gates()


func _reset_flight_body() -> void:
	player.begin_wing_flight($Start.global_transform, minf(360.0, tuning.max_speed_kmh) / 3.6)
	if hoshi_mode:
		player.flight_motion = FlapMotion.new()
		player.flight_motion.reset($Start.global_basis.get_rotation_quaternion())
		player.velocity = Vector3.ZERO
		var shape: CollisionShape3D = player.get_node("Shape")
		shape.shape = shape.shape.duplicate()
		shape.shape.height = 1.48
		shape.shape.radius = 0.22
		shape.rotation = Vector3.ZERO
		shape.position = Vector3(0, 0.74, 0)
		if _hoshi_ready:
			hoshi_visual._lean = 0.0
			hoshi_visual.update_pose(0.0, player.flight_motion)
	player.flight_motion.configure(tuning)


func _start_or_resume() -> void:
	if running:
		_menu.hide()
		_hud.show()
		player.set_physics_process(true)
	else:
		start_run()


func _show_menu(title: String, button: String) -> void:
	player.set_physics_process(false)
	if hoshi_mode and player.flight_motion != null:
		player.flight_motion.suspend_trigger()
	_menu_title.text = title
	_start_button.text = button
	_menu.show()
	_hud.hide()
	_start_button.grab_focus()


func _input(event: InputEvent) -> void:
	if hoshi_mode and running and not _menu.visible:
		var lift: bool = event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_SPACE
		lift = lift or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_A)
		if lift:
			player.flight_motion.jump_pressed()
			get_viewport().set_input_as_handled()
			return
	var pause_pressed: bool = event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE
	var reset_pressed: bool = event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R
	if event is InputEventJoypadButton and event.pressed:
		pause_pressed = event.button_index == JOY_BUTTON_START
		reset_pressed = event.button_index == JOY_BUTTON_BACK
	if reset_pressed:
		start_run()
	elif pause_pressed:
		if _menu.visible:
			_start_or_resume()
		else:
			_show_menu("Пауза", "Продолжить")
	else:
		return
	get_viewport().set_input_as_handled()


func _focus_lost() -> void:
	if running and not _menu.visible:
		_show_menu("Пауза · окно потеряло фокус", "Продолжить")


func _on_collision() -> void:
	if hoshi_mode and player.flight_motion.phase != FlapMotion.Phase.FLYING:
		# Resting contact / safe-margin recovery on the launch pad is support,
		# not a failed flight. Other colliders still use the ordinary reset path.
		var pad_only := player.get_slide_collision_count() > 0
		for index in range(player.get_slide_collision_count()):
			if player.get_slide_collision(index).get_collider() != $StartPlatform:
				pad_only = false
		if pad_only:
			return
	if not _reset_pending:
		_reset_pending = true
		player.set_physics_process(false)
		_restart_after_collision.call_deferred()


func _restart_after_collision() -> void:
	start_run()
	_gate_message = "Касание — новый старт. Можно попробовать медленнее."
	_update_hud()


static func crosses_gate(from: Vector3, to: Vector3, gate: Transform3D) -> bool:
	var a := gate.affine_inverse() * from
	var b := gate.affine_inverse() * to
	if a.z < 0.0 or b.z >= 0.0 or is_equal_approx(a.z, b.z):
		return false
	var hit := a.lerp(b, a.z / (a.z - b.z))
	return Vector2(hit.x, hit.y).length() < GATE_RADIUS - 1.2


func _physics_process(dt: float) -> void:
	if not running or _menu.visible or _reset_pending:
		return
	elapsed += dt
	if hoshi_mode and _hoshi_ready:
		hoshi_visual.update_pose(dt, player.flight_motion)
	var current := player.global_position
	if next_gate < gates.size() and crosses_gate(previous_position, current, gates[next_gate].global_transform):
		next_gate += 1
		_gate_message = "Ворота %d — пройдены" % next_gate
		_refresh_gates()
		if next_gate == gates.size():
			running = false
			_show_menu("Финиш · %.1f с" % elapsed, "Ещё полёт")
	previous_position = current
	if current.distance_to($Start.global_position) > 12000.0:
		_on_collision()
	if hoshi_mode and current.y < $Start.global_position.y - 15.0:
		_on_collision()
	_update_hud()


func _refresh_gates() -> void:
	for index in range(gate_materials.size()):
		var color := Color("65dbb0") if index < next_gate else (Color("78f1ff") if index == next_gate else Color("829cae"))
		gate_materials[index].albedo_color = color
		gate_materials[index].emission = color


func _update_hud() -> void:
	var pad := "Геймпад подключён" if not Input.get_connected_joypads().is_empty() else "Клавиатура · геймпад можно подключить"
	_hud.text = "ПОЛЁТ НА КРЫЛЬЯХ · ПРОБА\n%03d км/ч    Ворота %d / %d    %.1f с\n%s\nEsc / Start — пауза и управление · R / Back — заново\n%s" % [roundi(player.velocity.length() * 3.6), next_gate, gates.size(), elapsed, pad, _gate_message]
	if hoshi_mode:
		var phases := ["Ходьба · A / Пробел — прыжок", "Прыжок · ещё A / Пробел — крылья", "Кокон · раскрытие крыльев", "Полёт · RT / Ctrl — рывок"]
		_hud.text += "\n%s\nРывки %d · толчки %d · в очереди %d" % [phases[player.flight_motion.phase], player.flight_motion.boost_count, player.flight_motion.impulse_count, player.flight_motion.queued_boosts]
		if player.flight_motion.is_diving():
			_hud.text += "\nПикирование · планирование без взмахов"
		return
	if player.flight_motion != null:
		_hud.text += "\nRT %d%% · LT %d%%" % [roundi(player.flight_motion.throttle_input * 100), roundi(player.flight_motion.brake_input * 100)]
		if player.flight_motion.high_g_armed:
			if player.velocity.length() < 12.0:
				_hud.text += "\nДля крутого виража нужна скорость"
			else:
				_hud.text += "\nКРУТОЙ ВИРАЖ · расход скорости" if player.flight_motion.tight_turn > 0.1 else "\nВИРАЖ ГОТОВ · потяни стик назад"


func _process(_dt: float) -> void:
	if not _clouds.is_empty():
		_update_clouds(elapsed)
	if not is_instance_valid(player) or not is_instance_valid(camera) or camera._cam == null:
		return
	var point := player.global_position + player.velocity.normalized() * 80.0
	_velocity_marker.visible = not _menu.visible and not camera._cam.is_position_behind(point)
	if hoshi_mode and player.flight_motion.phase != FlapMotion.Phase.FLYING:
		_velocity_marker.hide()
	if _velocity_marker.visible:
		_velocity_marker.position = camera._cam.unproject_position(point) - Vector2(12, 18)


func _setup_clouds() -> void:
	_clouds.append($Cloud)
	# All placements and sizes stay authored in this course's scene.
	for child in get_children():
		if child is FogVolume and child != $Cloud:
			child.material = $Cloud.material.duplicate()
			_clouds.append(child)
	for cloud in _clouds:
		_cloud_origins.append(cloud.transform)
		_cloud_sizes.append(cloud.size)
	reload_cloud_settings()
	_update_clouds(0.0)

func reload_cloud_settings() -> bool:
	var config := ConfigFile.new()
	var error := config.load(cloud_settings_path)
	if error != OK:
		push_warning("Cloud settings not loaded; current values retained: " + cloud_settings_path)
		return false
	var candidate := _cloud_settings.duplicate()
	var limits := CLOUD_RANGES
	for key in limits:
		var value: Variant = config.get_value("edge" if key in ["edge_softness", "rim_strength", "rim_width", "rim_steps", "shadow_strength"] else "clouds", key, candidate[key])
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
			push_warning("Invalid cloud setting: " + key)
			return false
		candidate[key] = clampf(float(value), limits[key].x, limits[key].y)
	candidate.near_cloud_count = roundi(candidate.near_cloud_count)
	candidate.rim_steps = roundi(candidate.rim_steps)
	for key in ["highlight_color", "shadow_color", "rim_color"]:
		var value: Variant = config.get_value("colors", key, candidate[key])
		if not value is Color or not is_finite(value.r) or not is_finite(value.g) or not is_finite(value.b):
			push_warning("Invalid cloud color: " + key)
			return false
		candidate[key] = Color(clampf(value.r, 0, 1), clampf(value.g, 0, 1), clampf(value.b, 0, 1), 1.0)
	var distant: Variant = config.get_value("sky", "distant_clouds_enabled", candidate.distant_clouds_enabled)
	if not distant is bool:
		push_warning("Invalid distant_clouds_enabled")
		return false
	candidate.distant_clouds_enabled = distant
	_cloud_settings = candidate
	_cloud_ui_dirty = false
	_apply_cloud_settings()
	_sync_cloud_ui()
	return true

func _apply_cloud_settings() -> void:
	var candidate := _cloud_settings
	for index in range(_clouds.size()):
		var cloud := _clouds[index]
		cloud.visible = index < candidate.near_cloud_count
		cloud.transform = _cloud_origins[index]
		cloud.position.y += candidate.height_offset_m
		cloud.size = _cloud_sizes[index] * Vector3(1.0, candidate.thickness_scale, 1.0)
		for key in ["density_scale", "wind_scale", "edge_softness", "rim_strength", "rim_width", "rim_steps", "shadow_strength"]:
			cloud.material.set_shader_parameter(key, candidate[key])
		for key in ["highlight_color", "shadow_color", "rim_color"]:
			var color: Color = candidate[key]
			cloud.material.set_shader_parameter(key, Vector3(color.r, color.g, color.b))
	var environment: Environment = $WorldEnvironment.environment
	environment.sky.sky_material.set_shader_parameter("distant_clouds_enabled", candidate.distant_clouds_enabled)
	for pair in [["cloud_highlight", "highlight_color"], ["cloud_shadow", "shadow_color"]]:
		var color: Color = candidate[pair[1]]
		environment.sky.sky_material.set_shader_parameter(pair[0], Vector3(color.r, color.g, color.b))

func _update_clouds(seconds: float) -> void:
	var sun: DirectionalLight3D = $Sun
	for index in range(_clouds.size()):
		var material: ShaderMaterial = _clouds[index].material
		material.set_shader_parameter("cloud_time", seconds + index * 83.0)
		material.set_shader_parameter("transport_phase", float(Engine.get_process_frames() % 1024))
		material.set_shader_parameter("sun_direction", sun.global_basis.z.normalized())
		if is_instance_valid(camera) and camera._cam != null:
			material.set_shader_parameter("view_position", camera._cam.global_position)
		material.set_shader_parameter("sun_color", Vector3(sun.light_color.r, sun.light_color.g, sun.light_color.b) * sun.light_energy * float(sun.visible))


func _build_cloud_tab(tabs: TabContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Облака"
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 8)
	scroll.add_child(page)
	for definition in [["highlight_color", "Цвет освещённой части"], ["shadow_color", "Цвет тени"], ["rim_color", "Цвет светового канта"]]:
		var row := HBoxContainer.new()
		page.add_child(row)
		var label := Label.new()
		label.text = definition[1]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var picker := ColorPickerButton.new()
		picker.custom_minimum_size = Vector2(90, 32)
		picker.edit_alpha = false
		picker.color_changed.connect(_change_cloud_value.bind(definition[0]))
		row.add_child(picker)
		_cloud_controls[definition[0]] = picker
	var distant := CheckBox.new()
	distant.text = "Дальние облака у горизонта"
	distant.toggled.connect(_change_cloud_value.bind("distant_clouds_enabled"))
	page.add_child(distant)
	_cloud_controls["distant_clouds_enabled"] = distant
	for key in CLOUD_RANGES:
		var label := Label.new()
		page.add_child(label)
		_cloud_value_labels[key] = label
		var slider := HSlider.new()
		slider.min_value = CLOUD_RANGES[key].x
		slider.max_value = CLOUD_RANGES[key].y
		slider.step = CLOUD_RANGES[key].z
		slider.custom_minimum_size = Vector2(420, 24)
		slider.value_changed.connect(_change_cloud_value.bind(key))
		page.add_child(slider)
		_cloud_controls[key] = slider
	_sync_cloud_ui()

func _sync_cloud_ui() -> void:
	for key in _cloud_controls:
		var control = _cloud_controls[key]
		if control is ColorPickerButton:
			control.color = _cloud_settings[key]
		elif control is CheckBox:
			control.set_pressed_no_signal(_cloud_settings[key])
		else:
			control.set_value_no_signal(_cloud_settings[key])
			_cloud_value_labels[key].text = CLOUD_LABELS[key] + "  %.2f" % _cloud_settings[key]

func _change_cloud_value(value: Variant, key: String) -> void:
	_cloud_settings[key] = value
	if key in ["near_cloud_count", "rim_steps"]:
		_cloud_settings[key] = roundi(value)
	_cloud_ui_dirty = true
	_apply_cloud_settings()
	_update_clouds(elapsed)
	_sync_cloud_ui()
	_tuning_status_text = "Облака изменены сразу. Сохранить — записать в cfg; Загрузить — прочитать cfg."
	_sync_tuning_ui()

func _settings_action(index: int) -> void:
	if _tuning_tabs.current_tab != 2:
		[save_tuning, load_tuning, reset_tuning][index].call()
		return
	if index == 0:
		save_cloud_settings()
	elif index == 1:
		_tuning_status_text = "Облака загружены из cfg." if reload_cloud_settings() else "Ошибка чтения cfg. Прежние облака сохранены."
	else:
		_cloud_settings = CLOUD_DEFAULTS.duplicate()
		_cloud_ui_dirty = true
		_apply_cloud_settings()
		_sync_cloud_ui()
		_tuning_status_text = "Базовые облака. Файл не перезаписан; Сохранить — записать этот набор."
	_sync_tuning_ui()

func save_cloud_settings() -> bool:
	var config := ConfigFile.new()
	config.load(cloud_settings_path)
	for key in _cloud_settings:
		var section := "clouds"
		if key in ["highlight_color", "shadow_color", "rim_color"]:
			section = "colors"
		elif key == "distant_clouds_enabled":
			section = "sky"
		elif key in ["edge_softness", "rim_strength", "rim_width", "rim_steps", "shadow_strength"]:
			section = "edge"
		config.set_value(section, key, _cloud_settings[key])
	var file := FileAccess.open(cloud_settings_path, FileAccess.WRITE)
	if file == null:
		_tuning_status_text = "Не удалось записать cfg. Изменения остаются в текущей пробе."
		_sync_tuning_ui()
		return false
	file.store_string("; Настройки облаков. Меню Esc → Облака; Сохранить записывает этот файл.\n; Цвета линейные 0–1. Внешние изменения: Загрузить либо R без несохранённых правок.\n" + config.encode_to_text())
	file.close()
	_cloud_ui_dirty = false
	_tuning_status_text = "Облака сохранены в cfg и уже действуют."
	_sync_tuning_ui()
	return true
