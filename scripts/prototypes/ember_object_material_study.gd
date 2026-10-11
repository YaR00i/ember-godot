@tool
extends Node3D
## Inspector controls only update light/uniforms; saved sample meshes are baked.
const LIGHT_PRESETS := [
	{"yaw":-28.0,"elevation":42.0,"sun":1.2,"sky":0.65,"color":Color("fff1da")},
	{"yaw":-35.0,"elevation":55.0,"sun":0.45,"sky":1.0,"color":Color("e4edf3")},
	{"yaw":-130.0,"elevation":18.0,"sun":1.1,"sky":0.55,"color":Color("ffd4a2")},
]
@export_group("Сравнение материалов")
@export var surface_response := true:
	set(value): surface_response = value; _schedule_update()
@export var gray_preview := false:
	set(value): gray_preview = value; _schedule_update()
@export_range(0.25, 2.0, 0.05) var roughness_scale := 1.0:
	set(value): roughness_scale = value; _schedule_update()
@export_range(0.0, 2.0, 0.05) var specular_scale := 1.0:
	set(value): specular_scale = value; _schedule_update()
@export_range(0.0, 2.0, 0.05) var grain_scale := 1.0:
	set(value): grain_scale = value; _schedule_update()
@export_group("Оптика кристалла, льда и стекла")
@export var optics_enabled := true:
	set(value): optics_enabled = value; _schedule_update()
@export_range(0.0, 2.0, 0.05) var refraction_scale := 1.0:
	set(value): refraction_scale = value; _schedule_update()
@export_range(0.0, 1.0, 0.02) var clarity := 0.94:
	set(value): clarity = value; _schedule_update()
@export_range(0.0, 2.0, 0.05) var body_scale := 1.0:
	set(value): body_scale = value; _schedule_update()
@export_group("Профили льда и кристалла")
@export var finish_overrides := true:
	set(value): finish_overrides = value; _schedule_update()
@export_enum("Чистый лёд", "Трещины и пузырьки") var ice_finish := 1:
	set(value): ice_finish = clampi(value,0,1); _schedule_update()
@export_enum("Чистый кристалл", "Грубый природный кристалл") var crystal_finish := 1:
	set(value): crystal_finish = clampi(value,0,1); _schedule_update()
@export_enum("Стекло", "Лёд", "Кристалл") var probe_kind := 0:
	set(value): probe_kind = clampi(value,0,2); _schedule_update()
@export_range(0.0, 2.0, 0.05) var surface_detail_scale := 1.0:
	set(value): surface_detail_scale = value; _schedule_update()
@export_range(0.0, 2.0, 0.05) var crack_strength := 1.0:
	set(value): crack_strength = value; _schedule_update()
@export_range(0.0, 2.0, 0.05) var bubble_strength := 1.0:
	set(value): bubble_strength = value; _schedule_update()
@export_group("Неоднородность кристалла и льда")
@export_range(0.0, 2.0, 0.05) var cloud_strength := 1.0:
	set(value): cloud_strength = value; _schedule_update()
@export_range(0.25, 3.0, 0.05) var cloud_scale := 1.0:
	set(value): cloud_scale = value; _schedule_update()
@export_range(0, 1000, 1) var cloud_seed := 0:
	set(value): cloud_seed = value; _schedule_update()
@export var crystal_cloud_light := Color("e3ccf0"):
	set(value): crystal_cloud_light = value; _schedule_update()
@export var crystal_cloud_deep := Color("663f7b"):
	set(value): crystal_cloud_deep = value; _schedule_update()
@export var ice_cloud_light := Color("dcf3f3"):
	set(value): ice_cloud_light = value; _schedule_update()
@export var ice_cloud_deep := Color("5b7f81"):
	set(value): ice_cloud_deep = value; _schedule_update()
@export_group("Свет")
@export var neutral_light := true:
	set(value): neutral_light = value; _schedule_update()
@export_enum("Мягкий день", "Рассеянный свет", "Низкое солнце") var light_preset := 0:
	set(value):
		light_preset = clampi(value,0,2)
		_schedule_update()
@export var contact_shading := true:
	set(value): contact_shading = value; _schedule_update()
## Дневное положение; другие пресеты добавляют свой поворот. Ручная подстройка сохраняется.
@export_range(-180, 180, 1) var sun_yaw := -28.0:
	set(value): sun_yaw = value; _schedule_update()
## Высота в дневной основе; пресет меняет её относительно этой настройки.
@export_range(5, 85, 1) var sun_elevation := 42.0:
	set(value): sun_elevation = value; _schedule_update()
@export_range(0.0, 3.0, 0.05) var sun_energy := 1.2:
	set(value): sun_energy = value; _schedule_update()
@export_range(0.0, 2.0, 0.05) var sky_energy := 0.65:
	set(value): sky_energy = value; _schedule_update()
@export_group("Исходники примеров")
@export var sample_sources: Array[EmberVoxelModelResource] = []
var _update_queued := false
var _optical_materials: Dictionary = {}

func _ready() -> void:
	# Keep baked materials; switching optics costs no mesh/collision/source rebuild.
	for node in find_children("*", "MeshInstance3D", true, false):
		if node.mesh == null: continue
		var saved: Dictionary = node.mesh.get_meta("ember_optics_materials",{})
		for surface in node.mesh.get_surface_count():
			var material := node.mesh.surface_get_material(surface) as ShaderMaterial
			if saved.has(surface): material = saved[surface]
			if material and material.shader and material.shader.code.contains("ember_surface_optics"):
				saved[surface] = material
				_optical_materials[str(node.get_path())+":"+str(surface)] = material
		if not saved.is_empty(): node.mesh.set_meta("ember_optics_materials",saved)
	apply_settings()
	if not Engine.is_editor_hint(): Engine.max_fps = 30
	if not Engine.is_editor_hint() and OS.get_environment("EMBER_OBJECT_MATERIAL_QA") == "1": _capture_runtime.call_deferred()

func _schedule_update() -> void:
	if not is_node_ready() or _update_queued: return
	_update_queued = true
	apply_settings.call_deferred()

func effective_light() -> Dictionary:
	# Preset selection never overwrites authored controls. Inspector Undo of one
	# preset therefore also restores a manually adjusted sun without extra history.
	var preset: Dictionary = LIGHT_PRESETS[light_preset]
	var base: Dictionary = LIGHT_PRESETS[0]
	return {"yaw":float(preset.yaw)+sun_yaw-float(base.yaw),
		"elevation":clampf(float(preset.elevation)+sun_elevation-float(base.elevation),5,85),
		"sun":sun_energy*float(preset.sun)/float(base.sun),
		"sky":sky_energy*float(preset.sky)/float(base.sky)}

func apply_settings() -> void:
	_update_queued = false
	if not is_node_ready(): return
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = node.mesh
		if mesh == null: continue
		for surface in mesh.get_surface_count():
			var key := str(node.get_path())+":"+str(surface)
			if _optical_materials.has(key):
				var optical: ShaderMaterial = _optical_materials[key]
				var fallback: ShaderMaterial = optical.get_meta("opaque_comparison") if optical.has_meta("opaque_comparison") else null
				if fallback == null:
					fallback = EmberVoxelPrefab.voxel_material().duplicate(true)
					optical.set_meta("opaque_comparison",fallback)
				mesh.surface_set_material(surface,optical if optics_enabled else fallback)
				var role := str(optical.get_meta("optics_role","glass"))
				if node.get_parent().name == "Sample5" and probe_kind != 0: role = "ice" if probe_kind == 1 else "crystal"
				var parameters: Dictionary = optical.get_meta("optics_parameters",{}).duplicate(true)
				if parameters.is_empty():
					parameters = preload("res://scripts/ember_voxel_material_profiles.gd").OPTICS_DEFAULTS.duplicate()
					for parameter in parameters:
						if parameter not in ["enabled","finish","cloud_light","cloud_deep"]:
							var saved: Variant = optical.get_shader_parameter("optics_"+parameter)
							if saved != null: parameters[parameter] = saved
					optical.set_meta("optics_parameters",parameters.duplicate(true))
				if finish_overrides and role in ["ice","crystal"]:
					var finish := ("ice_clean" if ice_finish == 0 else "ice_natural") if role == "ice" else ("crystal_clean" if crystal_finish == 0 else "crystal_rough")
					parameters.merge(preload("res://scripts/ember_voxel_material_profiles.gd").FINISH_PROFILES[finish],true)
				for parameter in parameters:
					if parameter not in ["enabled","finish"]:
						optical.set_shader_parameter("optics_"+parameter,Color(parameters[parameter]) if parameter in ["cloud_light","cloud_deep"] else parameters[parameter])
				optical.set_shader_parameter("optics_refraction_strength",float(parameters.refraction_strength)*refraction_scale)
				optical.set_shader_parameter("optics_body_opacity",float(parameters.body_opacity)*body_scale)
				optical.set_shader_parameter("optics_clarity",clampf(clarity+float(parameters.clarity)-0.94,0,1))
				optical.set_shader_parameter("optics_cloud_strength",clampf(float(parameters.cloud_strength)*cloud_strength,0,1))
				optical.set_shader_parameter("optics_cloud_scale",float(parameters.cloud_scale)*cloud_scale)
				optical.set_shader_parameter("optics_cloud_seed",float(parameters.cloud_seed)+cloud_seed)
				optical.set_shader_parameter("optics_surface_detail",float(parameters.surface_detail)*surface_detail_scale)
				optical.set_shader_parameter("optics_crack_strength",clampf(float(parameters.crack_strength)*crack_strength,0,1))
				optical.set_shader_parameter("optics_bubble_strength",clampf(float(parameters.bubble_strength)*bubble_strength,0,1))
				if role in ["crystal","ice"]:
					optical.set_shader_parameter("optics_cloud_light",crystal_cloud_light if role == "crystal" else ice_cloud_light)
					optical.set_shader_parameter("optics_cloud_deep",crystal_cloud_deep if role == "crystal" else ice_cloud_deep)

			var material := node.get_active_material(surface) as ShaderMaterial
			if material == null or material.shader == null or not material.shader.code.contains("ember_voxel_surface_light"): continue
			material.set_shader_parameter("surface_response_enabled", surface_response)
			material.set_shader_parameter("surface_gray_preview", gray_preview)
			material.set_shader_parameter("surface_roughness_scale", roughness_scale)
			material.set_shader_parameter("surface_specular_scale", specular_scale)
			material.set_shader_parameter("surface_grain_scale", grain_scale)
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	var light := effective_light()
	if sun:
		sun.rotation_degrees = Vector3(-light.elevation, light.yaw, 0)
		sun.light_energy = light.sun
		sun.light_color = Color.WHITE if neutral_light else LIGHT_PRESETS[light_preset].color
	var fill := get_node_or_null("Fill") as DirectionalLight3D
	if fill:
		fill.light_energy = 0.10 if light_preset != 1 else 0.04
		fill.light_specular = 0.0
	var environment := get_node_or_null("Environment") as WorldEnvironment
	if environment:
		var env := environment.environment
		env.background_energy_multiplier = light.sky
		env.ambient_light_energy = light.sky * 0.35
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		env.ssao_enabled = contact_shading
		env.ssao_radius = 0.30; env.ssao_intensity = 1.15; env.ssao_detail = 0.5
		env.ssao_light_affect = 0.08
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.background_mode = Environment.BG_COLOR; env.background_color = Color("4c5b65")
		var sky := env.sky.sky_material as ProceduralSkyMaterial if env.sky != null else null
		if sky:
			sky.sky_top_color = Color("3f6484"); sky.sky_horizon_color = Color("c0c8ca")
			sky.ground_bottom_color = Color("1a2229"); sky.ground_horizon_color = Color("adb6bb")
	var probe_label := get_node_or_null("Label5") as Label3D
	if probe_label: probe_label.text = ["Стекло", "Лёд · простая форма", "Кристалл · простая форма"][probe_kind]
	var caption := get_node_or_null("UI/Caption") as Label
	if caption: caption.text = "Материалы объектов · %s\nF: чистый/природный · C: мутность · O: оптика · R: искажение" % ("реакция на свет" if surface_response else "прежняя поверхность")
	if caption: caption.text += "\nЛёд: %s · Кристалл: %s" % [["чистый","природный"][ice_finish],["чистый","грубый"][crystal_finish]]

func _unhandled_key_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_SPACE: surface_response = not surface_response
		KEY_G: gray_preview = not gray_preview
		KEY_F: ice_finish = 1-ice_finish; crystal_finish = 1-crystal_finish
		KEY_C: cloud_strength = 0.0 if cloud_strength > 0.0 else 1.0
		KEY_O: optics_enabled = not optics_enabled
		KEY_R: refraction_scale = 0.0 if refraction_scale > 0.0 else 1.0
		KEY_LEFT: sun_yaw -= 10
		KEY_RIGHT: sun_yaw += 10
		KEY_1: light_preset = 0
		KEY_2: light_preset = 1
		KEY_3: light_preset = 2

func _capture_runtime() -> void:
	print("OBJECT_MATERIAL runtime-start")
	var saved_preset := light_preset
	var saved_light := effective_light()
	var output := "user://ember-tests/object-materials"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	for mode in [true, false]:
		surface_response = mode
		for gray in [false, true]:
			gray_preview = gray
			for frame in 12: await get_tree().process_frame
			RenderingServer.force_draw(false)
			var path := "%s/%s_%s.png" % [output, "surface" if mode else "legacy", "gray" if gray else "color"]
			assert(get_viewport().get_texture().get_image().save_png(path) == OK)
	surface_response = true; gray_preview = false
	for preset in 3:
		light_preset = preset
		for frame in 12: await get_tree().process_frame
		RenderingServer.force_draw(false)
		assert(get_viewport().get_texture().get_image().save_png(output+"/preset_"+str(preset)+".png") == OK)
	var file := FileAccess.open(output+"/runtime-result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"ok":true,"saved_sun_yaw":sun_yaw,"sources":sample_sources.size(),"saved_preset":saved_preset,"effective_yaw":saved_light.yaw,"optics_enabled":optics_enabled,"refraction_scale":refraction_scale,"cloud_strength":cloud_strength,"cloud_scale":cloud_scale,"cloud_seed":cloud_seed,"cloud_light":crystal_cloud_light.to_html(false),"ice_finish":ice_finish,"crystal_finish":crystal_finish,"probe_kind":probe_kind,"neutral_light":neutral_light}))
	print("OBJECT_MATERIAL runtime completed ok=true")
	get_tree().quit()
