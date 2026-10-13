extends "res://scripts/prototypes/ember_material_depth_study.gd"
const PaintedFixture = preload("res://scripts/prototypes/ember_painted_light_fixture.gd")
## LAB presentation; shape, floor, player and material depth retain their owners.
@export var painted_light := true
@export var painted_grass := true
@export var calm_stone := true
@export var grass_tufts := true
@export var grass_masses := true
@export var grass_color := true
@export_group("Grass light study · scene settings")
@export_range(0.52,0.85,0.01) var grass_low := 0.64
@export_range(0.0,1.0,0.01) var grass_tint_strength := 1.0
@export var grass_cool := Color(0.96,1.0,1.04)
@export var grass_warm := Color(1.075,1.0,0.94)
@export var grass_shadow_color := Color(0.62,0.90,1.02)
@export_range(0.0,0.15,0.005) var grass_shadow_fill := 0.07
@export_enum("Evening","Day","Night") var lighting_preset := 0
@export_group("")
var tuft_visual: MultiMeshInstance3D
var tuft_points := PackedVector2Array()
var tuft_bases: Array[Basis] = []
var tuft_samples := PackedVector3Array()
var tuft_morph_ids := PackedInt32Array()
var tuft_fit := PackedFloat32Array()
var tuft_update_ms := 0.0
var _tuft_to_field := Transform3D.IDENTITY
var _tuft_from_field := Transform3D.IDENTITY
const TUFT_LIMIT := 20000
var ready_for_painted := false
var _painted_status: Label
var _grass: EmberCompactTerrainPattern
var _stone: EmberCompactTerrainPattern
var _sun_pose := 0
const SUN_POSES := [Vector3(-32, -145, 0), Vector3(-40, -65, 0), Vector3(-45, 30, 0)]

func prepare() -> void:
	await _prepare_rock_field()
	await super.prepare()
	_grass = load("res://content/terrain_materials/painted_light_grass.tres").duplicate(true)
	if _grass.grass_light_enabled:
		# Saved material is now the authoring owner. F6 remains a temporary
		# comparison panel operating on this private copy.
		grass_low=_grass.grass_light_low;grass_tint_strength=_grass.grass_light_tint_strength
		grass_cool=_grass.grass_light_cool;grass_warm=_grass.grass_light_warm
		grass_shadow_color=_grass.grass_light_shadow_color;grass_shadow_fill=_grass.grass_light_shadow_fill
	_stone = load("res://content/terrain_materials/painted_light_stone.tres")
	var variant := Shader.new()
	variant.code = "#define EMBER_PAINTERLY_STUDY\n" + depth_shader.code
	variant.set_meta("ember_compact_terrain_shader", true)
	depth_shader = variant
	depth_enabled = true
	apply_depth()
	set_grass(painted_grass)
	set_grass_masses(grass_masses)
	set_grass_color(grass_color)
	for child in get_node("Instructions").get_children():
		if child is CanvasItem: child.hide()
	_build_painted_controls()
	follow_camera.follow_distance = 9.5
	follow_camera.polar_angle = 0.95
	follow_camera.yaw = 0.35
	follow_camera.look_height = 0.6
	follow_camera._cam.make_current()
	get_node("Camera3D").look_at(orbit_center)
	set_painted(painted_light)
	_create_grass_tufts()
	apply_grass_settings()
	set_lighting_preset(lighting_preset)
	ready_for_painted = true
	print("PAINTED_LIGHT_READY preserved POM=4cm/32; shared renderer; real follow camera")

func _create_grass_tufts() -> void:
	var source: Resource = _projection.document
	var rng := RandomNumberGenerator.new(); rng.seed = 101304
	var material_cache: Dictionary = {}
	var patches := FastNoiseLite.new()
	patches.seed = 7153; patches.frequency = 0.72
	patches.fractal_octaves = 2
	# Joined patches with small clearings. Scatter is derived once from Source.
	for z in floori((source.depth/16.0-0.36)/0.10):
		for x in floori((source.width/16.0-0.36)/0.10):
			var p := Vector2(0.18+x*0.10,0.18+z*0.10) + Vector2(rng.randf_range(-0.04,0.04),rng.randf_range(-0.04,0.04))
			var cell := Vector2i(p*16.0)
			if Smooth.palette_at(source,cell.x,cell.y,0) != 3: continue
			var weights: Dictionary = Smooth.material_weights(source,cell,material_cache)
			var grass := float(weights.get(3,0.0))
			if grass < 0.60: continue
			var patch := smoothstep(-0.35,0.32,patches.get_noise_2dv(p))
			var density := lerpf(0.78,1.0,patch) * lerpf(0.60,1.0,smoothstep(0.60,0.95,grass))
			if rng.randf() > density: continue
			var width := rng.randf_range(0.92,1.18)
			var height := lerpf(1.40,2.10,patch) * rng.randf_range(0.94,1.06)
			# Short stems can overhang sand; their roots remain on grass. The
			# complete footprint excludes stone and abrupt rises, not only the root.
			if not tuft_footprint_clear(p,0.128*width,material_cache): continue
			if tuft_points.size()>=TUFT_LIMIT: continue
			tuft_points.append(p)
			tuft_bases.append(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3(width,height,width)))
			for zone in anomaly_zones:
				if p.distance_to(Vector2(zone.x,zone.y))<zone.z+0.40:
					tuft_morph_ids.append(tuft_points.size()-1); break
	tuft_visual = MultiMeshInstance3D.new()
	tuft_visual.name = "GrassTufts"
	tuft_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = PaintedFixture.grass_tuft_mesh()
	var unique: Dictionary = {}
	for vertex in instances.mesh.get_faces(): unique[vertex]=true
	tuft_samples = PackedVector3Array(unique.keys())
	_prepare_tuft_support()
	instances.instance_count = tuft_points.size()
	tuft_visual.multimesh = instances
	add_child(tuft_visual)
	_sync_tuft_material()
	_place_grass_tufts()
	set_tufts(grass_tufts)
	print("PAINTED_TUFTS ", tuft_points.size(), " patch cover; shared material/floor; no collision")

func tuft_footprint_clear(p: Vector2, radius: float, cache: Dictionary) -> bool:
	var source: Resource = _projection.document
	var center: Dictionary = get_node("Map").surface_floor_sample(Vector3(p.x,8,p.y))
	if not center.get("solid",false): return false
	for i in 9:
		var q := p if i == 8 else p + Vector2.from_angle(i*TAU/8.0) * (radius+0.035)
		if q.x<0.04 or q.y<0.04 or q.x>source.width/16.0-0.04 or q.y>source.depth/16.0-0.04: return false
		var weights: Dictionary = Smooth.material_weights(source,Vector2i(q*16.0),cache)
		if float(weights.get(1,0.0))>0.02: return false
		var floor: Dictionary = get_node("Map").surface_floor_sample(Vector3(q.x,8,q.y))
		if not floor.get("solid",false) or absf(floor.position.y-center.position.y)>0.055: return false
	return true

func _sync_tuft_material() -> void:
	if not is_instance_valid(tuft_visual): return
	# Same material and light response. Only ground-depth tracing is unnecessary
	# on these narrow decorative blades; the terrain keeps Sol's POM untouched.
	var material: ShaderMaterial = depth_material.duplicate()
	material.set_shader_parameter("material_depth_enabled", false)
	material.set_shader_parameter("painterly_blades", true)
	tuft_visual.material_override = material

func _place_grass_tufts(morph_only := false) -> void:
	if not is_instance_valid(tuft_visual): return
	var started := Time.get_ticks_usec()
	var indices = tuft_morph_ids if morph_only else range(tuft_points.size())
	for i: int in indices:
		var p := tuft_points[i]
		var floor: Dictionary = get_node("Map").surface_floor_sample(Vector3(p.x,8,p.y))
		var position: Vector3 = floor.position - Vector3.UP * 0.005
		# Upright stems retain their support column even at a voxel step. A
		# terrain-normal tilt can push the entire upper blade inside that step.
		var aligned := tuft_bases[i]
		var fit := tuft_fit[i]
		aligned.x *= fit; aligned.z *= fit
		tuft_visual.multimesh.set_instance_transform(i, Transform3D(aligned,position))
	tuft_update_ms = (Time.get_ticks_usec()-started)/1000.0

func _prepare_tuft_support() -> void:
	_tuft_from_field = _projection.global_transform
	_tuft_to_field = _tuft_from_field.affine_inverse()
	var kept_points := PackedVector2Array()
	var kept_bases: Array[Basis] = []
	var kept_morph := PackedInt32Array()
	var moving: Dictionary = {}
	for i in tuft_morph_ids: moving[i]=true
	for i in tuft_points.size():
		var p := Vector3(tuft_points[i].x,0,tuft_points[i].y)
		var fit := 1.0
		# Current morph blends these three fields with nonnegative weights.
		# An upright fixed footprint safe at all endpoints remains safe between
		# them. Reject unsuitable anchors once, never hide them during morph.
		for endpoint in (3 if moving.has(i) else 1):
			var position := _tuft_support(p,endpoint)-Vector3.UP*0.005
			if _tuft_fits(position,tuft_bases[i],fit,endpoint): continue
			var lo := 0.0; var hi := fit
			for step in 7:
				var middle := (lo+hi)*0.5
				if _tuft_fits(position,tuft_bases[i],middle,endpoint): lo=middle
				else: hi=middle
			fit=lo
		if fit<0.30: continue
		if moving.has(i): kept_morph.append(kept_points.size())
		kept_points.append(tuft_points[i]); kept_bases.append(tuft_bases[i]); tuft_fit.append(fit)
	tuft_points=kept_points; tuft_bases=kept_bases; tuft_morph_ids=kept_morph

func _tuft_support(point: Vector3, endpoint: int) -> Vector3:
	var local := _tuft_to_field * point
	var key := Vector2i(floori(local.x/64.0),floori(local.z/64.0))
	if preparations.has(key):
		local.y = Smooth.sample(preparations[key][["base","half","voxel"][endpoint]],Vector2(local.x,local.z))
	else:
		local.y = _projection._smooth_height(Vector2(local.x,local.z))
	return _tuft_from_field * local

func _tuft_fits(position: Vector3, basis: Basis, width: float, endpoint: int) -> bool:
	for vertex in tuft_samples:
		var v := position + basis * Vector3(vertex.x*width,vertex.y,vertex.z*width)
		# Scatter already validated solid in-bounds terrain. Reuse the exact
		# floor owner's cached field; avoid building a material-role dictionary
		# for every trial vertex. Native QA compares to Map.surface_floor_sample.
		var support := _tuft_support(v,endpoint)
		# Leave 0.2mm for float32 instance-transform/readback rounding.
		if v.y-support.y < -0.0118: return false
	return true

func set_tufts(enabled: bool) -> void:
	grass_tufts = enabled
	if is_instance_valid(tuft_visual): tuft_visual.visible = enabled

func set_grass_masses(enabled: bool) -> void:
	grass_masses = enabled
	depth_material.set_shader_parameter("painterly_grass_masses", enabled)
	apply_grass_settings()

func set_grass_color(enabled: bool) -> void:
	grass_color = enabled
	depth_material.set_shader_parameter("painterly_grass_color", enabled)
	apply_grass_settings()

func apply_grass_settings() -> void:
	if _grass!=null:
		_grass.grass_light_enabled=grass_masses and painted_light
		_grass.grass_light_low=grass_low
		_grass.grass_light_tint_strength=grass_tint_strength if grass_color else 0.0
		_grass.grass_light_cool=grass_cool;_grass.grass_light_warm=grass_warm
		_grass.grass_light_shadow_color=grass_shadow_color;_grass.grass_light_shadow_fill=grass_shadow_fill
		if painted_grass:
			for slot in _projection.document.palette_material_ids.size():
				if _projection.document.palette_material_ids[slot]=="cartoon_grass":Materials.update_grass_light_profile(depth_material,slot,_grass)
	for entry in [["low",grass_low],["tint_strength",grass_tint_strength],["shadow_fill",grass_shadow_fill]]:
		depth_material.set_shader_parameter("painterly_grass_"+entry[0],entry[1])
	for entry in [["cool",grass_cool],["warm",grass_warm],["shadow_color",grass_shadow_color]]:
		var c: Color = entry[1]
		depth_material.set_shader_parameter("painterly_grass_"+entry[0],Vector3(c.r,c.g,c.b))
	_sync_tuft_material()

func reset_grass_tones() -> void:
	# Neutral relative tints preserve any base pigment/paint chosen in Pattern.
	grass_cool=Color(0.96,1.0,1.04); grass_warm=Color(1.075,1.0,0.94)
	grass_shadow_color=Color(0.62,0.90,1.02)
	apply_grass_settings()

func set_lighting_preset(index: int) -> void:
	lighting_preset=posmod(index,3)
	EmberLights.apply_material_light_preset(get_node("Map/Look/Sun"),get_node("Map/Look/WorldEnvironment").environment,lighting_preset)
	set_sun_pose(_sun_pose)

func set_phase(value: float) -> void:
	super.set_phase(value)
	_place_grass_tufts(true)

func _prepare_rock_field() -> void:
	# LAB-only opt-in. Ordinary maps retain three filter passes. The parent
	# morph captures this same field after installation, including collision.
	var projection = get_node("Map")._visual_surface_projection
	while projection.pending_tile_count() > 0: await get_tree().process_frame
	var source: Resource = projection.document
	for key: Vector2i in projection._tiles:
		var begin := key * 64
		var bounds := Rect2i(begin, Vector2i(mini(64, source.width - begin.x), mini(64, source.depth - begin.y)))
		var original: Dictionary = projection._smooth_field(key)
		var sharp: Dictionary = Smooth.field(source, bounds, 1)
		var cache: Dictionary = {}
		var size: Vector2i = sharp.size
		var heights: PackedFloat32Array = sharp.heights
		for z in size.y:
			for x in size.x:
				var point: Vector2i = sharp.start + Vector2i(x,z)
				var weights: Dictionary = Smooth.material_weights(source, point, cache)
				var stone := smoothstep(0.0, 0.6, float(weights.get(1,0.0)))
				var i := x + z * size.x
				heights[i] = lerpf(original.heights[i], heights[i], stone)
		sharp.heights = heights
		var built: Dictionary = Smooth.build(source, bounds, true, true, sharp)
		var ground: MeshInstance3D = projection._tiles[key].get_node("Ground")
		built.terrain.surface_set_material(0, ground.mesh.surface_get_material(0))
		ground.mesh = built.terrain
		assert(projection.apply_study_smooth_tile(key, sharp, built.collision_faces))
		await get_tree().process_frame

func _build_painted_controls() -> void:
	var panel := VBoxContainer.new()
	panel.position = Vector2(20, 20)
	get_node("Instructions").add_child(panel)
	_painted_status = Label.new(); panel.add_child(_painted_status)
	var hint := Label.new()
	hint.text = "WASD — ходить · ПКМ — камера · V — общий вид · F1 — скрыть панель"
	panel.add_child(hint)
	for spec in [["B · исходный / живописный свет", "light"], ["R · световая кромка", "rim"], ["G · исходная / рисованная трава", "grass"], ["T · короткие пучки травы", "tufts"], ["H · газон / цельные мазки", "masses"], ["J · нейтральный / градация оттенков", "color"], ["C · исходная / крупная фактура камня", "stone"], ["L · направление солнца", "sun"], ["O · контактные тени", "ao"], ["P · проход / стоп", "walk"]]:
		var button := Button.new(); button.text = spec[0]; panel.add_child(button)
		button.pressed.connect(func(): command(spec[1]))
	var row := HBoxContainer.new(); panel.add_child(row)
	for i in 3:
		var button := Button.new(); button.text = ["Гладко", "Полублоки", "Воксели"][i]; row.add_child(button)
		button.pressed.connect(func(): set_phase(i * 0.5))
	_build_grass_settings_controls()

func _build_grass_settings_controls() -> void:
	var panel := PanelContainer.new(); get_node("Instructions").add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left=-355; panel.offset_right=-20; panel.offset_top=20
	var column := VBoxContainer.new(); panel.add_child(column)
	var title := Label.new(); title.text="Материалы · проверка света"; column.add_child(title)
	var choice := OptionButton.new(); column.add_child(choice)
	for caption in ["Вечер · прежний", "День · нейтральный", "Ночь · лунный"]: choice.add_item(caption)
	choice.select(lighting_preset); choice.item_selected.connect(set_lighting_preset)
	for spec in [["grass_low","Яркость тёмного мазка",0.52,0.85,0.01], ["grass_tint_strength","Сила дополнительных оттенков",0.0,1.0,0.01], ["grass_shadow_fill","Мягкий цвет внутри тени",0.0,0.15,0.005]]:
		var label := Label.new(); label.text=spec[1]; column.add_child(label)
		var slider := HSlider.new(); slider.min_value=spec[2]; slider.max_value=spec[3]; slider.step=spec[4]
		slider.value=get(spec[0]); column.add_child(slider)
		slider.value_changed.connect(func(value): set(spec[0],value); apply_grass_settings())
	var pickers: Array[ColorPickerButton] = []
	for spec in [["grass_cool","Оттенок нижней ступени"],["grass_warm","Оттенок верхней ступени"],["grass_shadow_color","Оттенок настоящей тени"]]:
		var label := Label.new(); label.text=spec[1]; column.add_child(label)
		var picker := ColorPickerButton.new(); picker.color=get(spec[0]); picker.edit_alpha=false
		picker.custom_minimum_size=Vector2(0,28)
		column.add_child(picker); pickers.append(picker)
		picker.color_changed.connect(func(value): set(spec[0],value); apply_grass_settings())
	var auto_tones := Button.new(); auto_tones.text="Подобрать к основной траве"; column.add_child(auto_tones)
	auto_tones.pressed.connect(func():
		reset_grass_tones()
		for i in 3: pickers[i].color=[grass_cool,grass_warm,grass_shadow_color][i]
	)
	var note := Label.new(); note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	note.text="Основной цвет — из материала земли. Это пробные тонировки света. F6-правки временные; постоянные значения — в Inspector корня сцены."
	column.add_child(note)

func set_painted(enabled: bool) -> void:
	painted_light = enabled
	depth_material.set_shader_parameter("painterly_enabled", enabled)
	apply_grass_settings()
	if is_instance_valid(_painted_status):
		_painted_status.text = ("B · живописный свет" if enabled else "A · исходный свет") + " | глубина камня неизменна: 4 см"

func set_grass(enabled: bool) -> void:
	painted_grass = enabled
	depth_material.set_shader_parameter("painterly_grass_enabled", enabled)
	var grass: Resource = _grass if enabled else Materials.load_compact_terrain_variant("cartoon_grass")
	Materials.set_compact_terrain_roles(depth_material, _projection.document.palette_surface_roles,
		_projection.document.palette_material_ids, _projection.document.palette,
		{"cartoon_stone": _stone if calm_stone else _depth_stone, "cartoon_sand": _depth_sand, "cartoon_grass": grass},
		PackedStringArray(["cartoon_stone", "cartoon_grass"] if enabled else ["cartoon_stone"]))
	_sync_tuft_material()

func set_sun_pose(index: int) -> void:
	_sun_pose = posmod(index, SUN_POSES.size())
	get_node("Map/Look/Sun").rotation_degrees = SUN_POSES[_sun_pose]
	if lighting_preset==1: get_node("Map/Look/Sun").rotation_degrees.x=-62.0
	elif lighting_preset==2: get_node("Map/Look/Sun").rotation_degrees.x=-38.0
	depth_material.set_shader_parameter("material_depth_sun_direction", get_node("Map/Look/Sun").global_basis.z)

func command(action: String) -> void:
	match action:
		"light": set_painted(not painted_light)
		"grass": set_grass(not painted_grass)
		"tufts": set_tufts(not grass_tufts)
		"masses": set_grass_masses(not grass_masses)
		"color": set_grass_color(not grass_color)
		"stone": calm_stone = not calm_stone; set_grass(painted_grass)
		"rim": depth_material.set_shader_parameter("painterly_rim_enabled", not depth_material.get_shader_parameter("painterly_rim_enabled"))
		"sun": set_sun_pose(_sun_pose + 1)
		"ao":
			var environment: Environment = get_node("Map/Look/WorldEnvironment").environment
			environment.ssao_enabled = not environment.ssao_enabled
		"walk": set_demo_walking(not demo_walking)

func set_demo_walking(enabled: bool) -> void:
	super.set_demo_walking(enabled)
	playing = false # A/B movement must not also animate terrain geometry.

func _unhandled_input(event: InputEvent) -> void:
	if not ready_for_painted: return
	if event is InputEventKey and event.pressed and not event.echo:
		var actions := {KEY_B: "light", KEY_R: "rim", KEY_G: "grass", KEY_T: "tufts", KEY_H: "masses", KEY_J: "color", KEY_C: "stone", KEY_L: "sun", KEY_O: "ao", KEY_P: "walk"}
		if actions.has(event.keycode): command(actions[event.keycode]); return
		if event.keycode == KEY_F1:
			get_node("Instructions").visible = not get_node("Instructions").visible; return
	super._unhandled_input(event)
