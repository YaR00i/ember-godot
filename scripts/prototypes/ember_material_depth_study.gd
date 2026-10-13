extends "res://scripts/prototypes/ember_mountain_anomaly_study.gd"
## Presentation only. Existing Map/Source/Smooth/Player own shape and physics.
const DepthFixture=preload("res://scripts/prototypes/ember_material_depth_fixture.gd")
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
@export var depth_enabled:=true
@export_range(0.0,0.08,0.001) var amplitude_m:=0.04
@export_range(8,64,1) var steps:=32
@export_range(2.0,10.0,0.5) var fade_near_m:=6.0
@export_range(10.0,30.0,0.5) var fade_far_m:=14.0
var ready_for_depth:=false
var depth_material: ShaderMaterial
var baseline_shader: Shader
var depth_shader: Shader
var coverage_image: Image
var coverage_texture: ImageTexture
var height_texture: Texture2D
var texture_build_count:=0
var reference_attribute_bytes:=0 # Compatibility with previous capture records: no reference attributes now.
var _depth_caption: Label
var _amplitude_control: HSlider
var _depth_stone: EmberCompactTerrainPattern
var _depth_sand: EmberCompactTerrainPattern

func prepare() -> void:
	await super.prepare()
	_depth_stone=Materials.load_compact_terrain_variant("cartoon_stone").duplicate(true)
	_depth_sand=Materials.load_compact_terrain_variant("cartoon_sand").duplicate(true)
	_depth_stone.albedo_texture=load("res://content/terrain_materials/textures/material_depth_study/stone_color.png")
	_depth_stone.pattern_size_m=DepthFixture.SPAN_M;_depth_stone.pixel_relief=0.04
	_depth_stone.base_color=Color("979184")
	depth_material=Materials.compact_terrain_material()
	var shared_shader: Shader=depth_material.shader
	Materials.set_compact_terrain_roles(depth_material,_projection.document.palette_surface_roles,_projection.document.palette_material_ids,_projection.document.palette,{"cartoon_stone":_depth_stone,"cartoon_sand":_depth_sand},PackedStringArray(["cartoon_stone"]))
	depth_material.set_shader_parameter("smooth_surface_enabled",true)
	depth_material.set_shader_parameter("material_light_mode",get_node("Map").compact_material_light_mode)
	baseline_shader=shared_shader
	depth_shader=Materials.compact_terrain_depth_shader()
	coverage_image=DepthFixture.coverage(_projection.document)
	coverage_texture=ImageTexture.create_from_image(coverage_image)
	var height_image: Image=(load("res://content/terrain_materials/textures/material_depth_study/stone_height.png") as Texture2D).get_image()
	if height_image.is_compressed():height_image.decompress()
	height_image.convert(Image.FORMAT_R8);height_image.generate_mipmaps()
	height_texture=ImageTexture.create_from_image(height_image)
	texture_build_count=2
	for tile in _projection._tiles.values():
		var ground: MeshInstance3D=tile.get_node("Ground")
		ground.material_override=depth_material
	_create_depth_controls();ready_for_depth=true;apply_depth()
	get_node("Camera3D").make_current()
	print("MATERIAL_DEPTH_READY tiles=",_projection._tiles.size()," source=",_projection.document.width,"x",_projection.document.depth)

func _create_depth_controls() -> void:
	get_node("Instructions/Caption").text="Камень и песок · B — сравнить · ПКМ — камера · колесо — масштаб · L — свет"
	var panel:=VBoxContainer.new();panel.position=Vector2(20,260);panel.custom_minimum_size.x=410
	get_node("Instructions").add_child(panel)
	_depth_caption=Label.new();panel.add_child(_depth_caption)
	var toggle:=Button.new();toggle.text="A / B — сравнить глубину";panel.add_child(toggle)
	toggle.pressed.connect(func():set_depth(not depth_enabled))
	var amount:=Label.new();amount.text="Глубина рисунка, см";panel.add_child(amount)
	_amplitude_control=HSlider.new();_amplitude_control.max_value=8;_amplitude_control.step=0.1;_amplitude_control.value=amplitude_m*100
	panel.add_child(_amplitude_control);_amplitude_control.value_changed.connect(func(value):amplitude_m=value/100.0;apply_depth())
	var quality:=OptionButton.new()
	for count in [16,32,48,64]:quality.add_item("Качество: %d шагов"%count,count)
	quality.select([16,32,48,64].find(steps));panel.add_child(quality)
	quality.item_selected.connect(func(index):steps=quality.get_item_id(index);apply_depth())

func set_depth(enabled: bool) -> void:
	depth_enabled=enabled
	if ready_for_depth:apply_depth()

func apply_depth() -> void:
	# Shader switching is explicit A/B only. Camera and physics never rebuild
	# textures/meshes. A (or zero amplitude) compiles the actual previous path.
	var active:=depth_enabled and amplitude_m>0.00001
	depth_material.shader=depth_shader if active else baseline_shader
	if active:
		assert(Materials.bind_compact_terrain_depth(depth_material,height_texture,coverage_texture,Vector2i(1,2),amplitude_m,steps,Vector2(fade_near_m,fade_far_m),Vector2.ZERO,get_node("Map/Look/Sun").global_basis.z))
	_depth_caption.text=("B — объём рисунка" if active else "A — прежний световой рельеф")+" · %.1f см"%(amplitude_m*100)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_B:set_depth(not depth_enabled);return
		if event.keycode==KEY_L:
			get_node("Map/Look/Sun").rotate_y(deg_to_rad(25));apply_depth();return
	super._unhandled_input(event)
