extends "res://scripts/prototypes/ember_diorama_readability_study.gd"
const BarkFixture = preload("res://scripts/prototypes/ember_bark_material_fixture.gd")
const BARK_NAMES := ["А · исходное дерево","Б · живописная кора + углубления","В · пиксельная кора + углубления","Г · та же кора без углублений"]
@export_enum("Original","Painterly relief","Pixel relief","Painterly flat") var bark_mode := 1
var ready_for_bark := false
var bark_inputs: Dictionary
var bark_layers: Array[Image]=[]
var bark_field: ImageTexture3D
var bark_material: ShaderMaterial
var panel_material: ShaderMaterial
var panel: MeshInstance3D
var original_shader: Shader
var bark_shader: Shader
var bark_caption: Label
var bake_ms := 0.0

func prepare() -> void:
	await super.prepare()
	# Keep the accepted material A on the ground and the same comparison camera.
	set_comparison(0)
	for child in get_node("Instructions").get_children():
		if child is CanvasItem:child.hide()
	var loading:=Label.new();loading.position=Vector2(18,18);loading.text="Готовим фактуру коры из рисунка генератора…"
	get_node("Instructions").add_child(loading)
	var started := Time.get_ticks_msec()
	bark_inputs=BarkFixture.build_inputs()
	for z in bark_inputs.field_grid.z:
		bark_layers.append(BarkFixture.layer(bark_inputs,z))
		if z%4==3:await get_tree().process_frame
	bark_field=BarkFixture.texture(bark_layers)
	bake_ms=Time.get_ticks_msec()-started
	var position_before := tree.global_position
	remove_child(tree);tree.free()
	var packed:=Prefab.prepare_resource(bark_inputs.private_source)
	tree=packed.instantiate() as EmberVoxelProp
	tree.configure_voxel_scale(16,1.0);add_child(tree);tree.global_position=position_before
	var visual: MeshInstance3D=tree.get_node("Mesh")
	bark_material=BarkFixture.material(bark_field,bark_inputs)
	original_shader=Prefab.voxel_material().shader;bark_shader=bark_material.shader
	visual.material_override=bark_material
	panel=MeshInstance3D.new();panel.name="FlatBarkProbe";panel.mesh=BarkFixture.panel_mesh(bark_inputs)
	panel_material=bark_material.duplicate() as ShaderMaterial
	panel.material_override=panel_material;add_child(panel)
	var center:=Vector3(bark_inputs.offset)/16.0
	panel.position=get_node("Map").surface_floor_sample(Vector3(6.5,8.0,3.4)).position-Vector3(center.x,0.0,center.z)
	loading.queue_free()
	_build_bark_controls()
	ready_for_bark=true
	set_bark_mode(bark_mode)
	set_lighting_preset(1);set_sun_pose(1)
	print("BARK_READY supports=",bark_inputs.support_count," marks=",bark_inputs.mark_count," bake_ms=",bake_ms," POM trace=12mm/24; recess <=5.04mm")

func set_bark_mode(mode: int) -> void:
	bark_mode=clampi(mode,0,3)
	if bark_material==null:return
	for material in [bark_material,panel_material]:
		material.shader=original_shader if mode==0 else bark_shader
		material.set_shader_parameter("surface_response_enabled",mode!=0)
		material.set_shader_parameter("bark_study_enabled",mode!=0)
		material.set_shader_parameter("bark_study_pixel",mode==2)
		material.set_shader_parameter("material_depth_amplitude_m",0.0 if mode in [0,3] else 0.012)
	_sync_bark_sun()
	if bark_caption!=null:
		bark_caption.text=BARK_NAMES[bark_mode]+"\nСтвол и плоский образец · исходная форма\nДень / вечер / ночь · рисунок генератора"

func _sync_bark_sun() -> void:
	if bark_material==null or tree==null:return
	var sun: Vector3=get_node("Map/Look/Sun").global_basis.z
	for visual in [tree.get_node("Mesh"),panel]:
		if visual==null:continue
		var material: ShaderMaterial=visual.material_override
		material.set_shader_parameter("material_depth_sun_direction",(visual.global_basis.inverse()*sun).normalized())

func set_sun_pose(index: int) -> void:
	super.set_sun_pose(index)
	_sync_bark_sun()

func _build_bark_controls() -> void:
	var controls:=PanelContainer.new();controls.position=Vector2(18,18)
	get_node("Instructions").add_child(controls)
	var column:=VBoxContainer.new();column.custom_minimum_size.x=385;controls.add_child(column)
	bark_caption=Label.new();column.add_child(bark_caption)
	for i in BARK_NAMES.size():
		var button:=Button.new();button.text=BARK_NAMES[i];column.add_child(button)
		button.pressed.connect(func():set_bark_mode(i))
	for pair in [["Вечер",0],["День",1],["Ночь",2]]:
		var button:=Button.new();button.text=pair[0];column.add_child(button)
		button.pressed.connect(set_lighting_preset.bind(pair[1]))
	var side:=Button.new();side.text="Боковой / контровой свет";column.add_child(side)
	side.pressed.connect(func():set_sun_pose(0 if _sun_pose==1 else 1))
	var hint:=Label.new();hint.text="1–4 — кора · L — пресет · P — направление\nWASD / ПКМ — движение · F1 — панель\nПробы временные · источник и коллизия прежние";column.add_child(hint)

func _unhandled_input(event: InputEvent) -> void:
	if ready_for_bark and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_1,KEY_2,KEY_3,KEY_4]:set_bark_mode(event.keycode-KEY_1);return
		if event.keycode==KEY_L:set_lighting_preset(lighting_preset+1);return
		if event.keycode==KEY_P:set_sun_pose(_sun_pose+1);return
	super._unhandled_input(event)
