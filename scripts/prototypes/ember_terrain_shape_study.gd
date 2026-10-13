extends "res://scripts/prototypes/ember_material_depth_study.gd"
## Bounded shape LAB. Source, smoothing, morph, physics and POM keep their owners.
const ShapeFixture=preload("res://scripts/prototypes/ember_terrain_shape_fixture.gd")
@export_range(0.0,1.0,0.05) var rounding_strength:=1.0
@export_range(1,3,1) var rounding_radius_cells:=3
@export var preserve_breaks:=true
@export var protect_regions:=true
var shape_mode:=1 # 0 current, 1 local control, 2 globally weakened filter.
var diagnostic:=true
var ready_for_shape:=false
var rebuilding:=false
var rebuild_ms:=0.0
var _shape_status: Label
var _diagnostic_material: StandardMaterial3D
var _shape_profile: Dictionary
var _grass_profile: EmberCompactTerrainPattern

func prepare() -> void:
	_projection=get_node("Map")._visual_surface_projection
	while _projection.pending_tile_count()>0:await get_tree().process_frame
	_shape_profile=ShapeFixture.profile(rounding_strength,rounding_radius_cells,preserve_breaks,protect_regions)
	await _install_shape()
	await super.prepare()
	_grass_profile=load("res://content/terrain_materials/painted_light_grass.tres").duplicate(true)
	Materials.set_compact_terrain_roles(depth_material,_projection.document.palette_surface_roles,_projection.document.palette_material_ids,_projection.document.palette,{"cartoon_stone":_depth_stone,"cartoon_sand":_depth_sand,"cartoon_grass":_grass_profile},PackedStringArray(["cartoon_stone"]))
	_diagnostic_material=StandardMaterial3D.new();_diagnostic_material.albedo_color=Color("b7b2a6");_diagnostic_material.roughness=0.9
	for child in get_node("Instructions").get_children():
		if child is CanvasItem:child.hide()
	_create_shape_controls()
	follow_camera.follow_distance=11.5;follow_camera.polar_angle=0.95;follow_camera.yaw=0.35;follow_camera.look_height=0.6
	follow_camera._cam.make_current()
	ready_for_shape=true;set_diagnostic(true);set_light(0,0)
	print("TERRAIN_SHAPE_READY");_update_shape_caption()

func _install_shape() -> void:
	var prepared: Dictionary={}
	var profile:=_shape_profile.duplicate(true)
	for key: Vector2i in _projection._tiles:
		var bounds:=Rect2i(key*64,Vector2i(64,64))
		var data: Dictionary
		if shape_mode==1:data=Smooth.controlled_field(_projection.document,bounds,profile)
		else:data=Smooth.field(_projection.document,bounds,1 if shape_mode==2 else 3)
		var result:=Smooth.build(_projection.document,bounds,true,true,data)
		# Preserve the shared role material used by the existing morph builder.
		result.terrain.surface_set_material(0,_projection._ground_material)
		prepared[key]=result
		await get_tree().process_frame
	# Publish all seams together after preparation; the player never walks on
	# a mixture of A and B tiles. All physical/query owners switch with the mesh.
	for key: Vector2i in prepared:
		var result: Dictionary=prepared[key]
		var ground: MeshInstance3D=_projection._tiles[key].get_node("Ground")
		ground.mesh=result.terrain
		assert(_projection.apply_study_smooth_tile(key,result.smooth_field,result.collision_faces))

func choose_shape(mode: int) -> void:
	if rebuilding or not ready_for_shape:return
	rebuilding=true;playing=false;demo_walking=false;set_demo_walking(false)
	walker.set_physics_process(false)
	_shape_status.text="Подготовка формы…"
	shape_mode=clampi(mode,0,2);phase=0.0;ready_for_morph=false
	var started:=Time.get_ticks_usec()
	await _install_shape()
	# Retire only derived morph nodes created by the existing LAB owner.
	# Keep the previous stationary collision alive during preparation, then
	# retire it after all replacement full-tile shapes have been installed.
	for entry: Dictionary in preparations.values():
		entry.collision_mesh.free()
		var stationary: Node=entry.ground.get_parent().get_node_or_null("GroundPhysics/StudyStationaryGround")
		if stationary!=null:stationary.free()
	preparations.clear()
	await prepare_morph_fields()
	rebuild_ms=(Time.get_ticks_usec()-started)/1000.0
	# Comparison starts on the same safe route, with no ceiling in this fixture.
	reset_walker();set_diagnostic(diagnostic)
	walker.set_physics_process(true)
	rebuilding=false;_update_shape_caption()

func reset_walker() -> void:
	walker.position=Vector3(walk_start.x,8,walk_start.y)
	var floor: Dictionary=get_node("Map").surface_floor_sample(walker.global_position)
	walker.position.y=floor.position.y+0.04;walker.velocity=Vector3.ZERO
	follow_camera.reset_follow_height()

func set_diagnostic(enabled: bool) -> void:
	diagnostic=enabled
	for tile in _projection._tiles.values():tile.get_node("Ground").material_override=_diagnostic_material if enabled else depth_material
	_update_shape_caption()

func set_light(preset: int,pose: int) -> void:
	var sun: DirectionalLight3D=get_node("Map/Look/Sun")
	EmberLights.apply_material_light_preset(sun,get_node("Map/Look/WorldEnvironment").environment,preset)
	sun.rotation_degrees.y=-145 if pose==0 else -65
	if depth_material!=null:depth_material.set_shader_parameter("material_depth_sun_direction",sun.global_basis.z)

func _create_shape_controls() -> void:
	var panel:=VBoxContainer.new();panel.name="ShapeControls";panel.position=Vector2(18,18);panel.custom_minimum_size.x=390
	get_node("Instructions").add_child(panel)
	_shape_status=Label.new();panel.add_child(_shape_status)
	var modes:=HBoxContainer.new();panel.add_child(modes)
	for mode in 3:
		var button:=Button.new();button.text=["A · прежнее","B · сохранить форму","C · слабый фильтр"][mode]
		modes.add_child(button);button.pressed.connect(func():choose_shape(mode))
	var material:=Button.new();material.text="Однотонный / принятые материалы";panel.add_child(material)
	material.pressed.connect(func():set_diagnostic(not diagnostic))
	var amount:=Label.new();amount.text="Округление · применяется кнопкой ниже";panel.add_child(amount)
	var strength:=HSlider.new();strength.name="Strength";strength.max_value=1.0;strength.step=0.05;strength.value=rounding_strength;panel.add_child(strength)
	var radius:=OptionButton.new();radius.name="Radius";panel.add_child(radius)
	for value in [1,2,3]:radius.add_item("Радиус прохода: %d клеток (%.2f м)"%[value,value/16.0])
	radius.select(rounding_radius_cells-1)
	var edge:=CheckBox.new();edge.text="Сохранять резкие перепады";edge.button_pressed=preserve_breaks;panel.add_child(edge)
	var protection:=CheckBox.new();protection.text="Защитить площадку и гребень";protection.button_pressed=protect_regions;panel.add_child(protection)
	var apply:=Button.new();apply.name="Apply";apply.text="Обновить B";panel.add_child(apply)
	apply.pressed.connect(func():
		if rebuilding:return
		rounding_strength=strength.value;rounding_radius_cells=radius.selected+1;preserve_breaks=edge.button_pressed;protect_regions=protection.button_pressed
		_shape_profile=ShapeFixture.profile(rounding_strength,rounding_radius_cells,preserve_breaks,protect_regions);choose_shape(1))
	var lights:=HBoxContainer.new();panel.add_child(lights)
	for preset in 3:
		var button:=Button.new();button.text=EmberLights.MATERIAL_LIGHT_PRESETS[preset].name;lights.add_child(button)
		button.pressed.connect(func():set_light(preset,0))
	var side:=Button.new();side.text="Боковой свет";panel.add_child(side);side.pressed.connect(func():get_node("Map/Look/Sun").rotation_degrees.y=-65;depth_material.set_shader_parameter("material_depth_sun_direction",get_node("Map/Look/Sun").global_basis.z))
	var endpoints:=HBoxContainer.new();panel.add_child(endpoints)
	for endpoint in 3:
		var button:=Button.new();button.text=["Гладко","Полублоки","Воксели"][endpoint];endpoints.add_child(button)
		button.pressed.connect(func():if not rebuilding:set_phase(endpoint*0.5))
	var hint:=Label.new();hint.text="WASD — ходить · V — общий вид · F1 — панель";panel.add_child(hint)

func _update_shape_caption() -> void:
	if _shape_status!=null:_shape_status.text=["A · прежнее округление","B · площадка и излом","C · один проход везде"][shape_mode]+(" · однотонный" if diagnostic else " · материалы/POM")+"\nОбновление %.1f мс"%rebuild_ms

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode==KEY_F1:
		get_node("Instructions").visible=not get_node("Instructions").visible;return
	super._unhandled_input(event)
