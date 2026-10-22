extends "res://scripts/prototypes/ember_diorama_readability_study.gd"
## Bounded three-look lab. Persistent authoring stays in the published Source.
const LookBake=preload("res://scripts/ember_tree_look_bake.gd")
@export_file("*.tres") var look_source_path:="res://content/voxel_models/vox_painted_oak.tres"
@export_range(0.0,1.0,0.01) var voxel_fraction:=0.5
@export_enum("6.25 cm","12.5 cm") var voxel_detail:=0
var looks_ready:=false
var look_source: EmberVoxelModelResource
var look_model: Dictionary
var look_prop: EmberVoxelProp
var smooth_visual: MeshInstance3D
var voxel_visual: MeshInstance3D
var faceted_visual: MeshInstance3D
var alternate_look:=0
var leaf_shape_amount:=0.7
var leaf_shape_kind:=0
var look_bounds: AABB
var baked_looks: Dictionary={}
var bake_count:=0
var look_caption: Label
var look_slider: HSlider
var look_animation: Tween

func prepare() -> void:
	await super.prepare()
	var position_before:=tree.global_position;tree.hide()
	# Let the existing deferred material binding finish before retiring its prop.
	await get_tree().process_frame
	tree.queue_free()
	look_source=load(look_source_path)
	assert(look_source!=null and look_source.validation_errors().is_empty())
	look_model=look_source.to_definition().model
	assert(LookBake.Surface.active(look_model))
	look_prop=Prefab.prepare_resource(look_source).instantiate();add_child(look_prop)
	tree=look_prop
	look_prop.configure_voxel_scale(16,1.0);look_prop.global_position=position_before
	smooth_visual=look_prop.get_node("Mesh")
	smooth_visual.mesh=private_materials(smooth_visual.mesh)
	look_bounds=smooth_visual.mesh.get_aabb()
	voxel_visual=MeshInstance3D.new();voxel_visual.name="VoxelLook";look_prop.add_child(voxel_visual)
	voxel_visual.transform=smooth_visual.transform
	faceted_visual=MeshInstance3D.new();faceted_visual.name="FacetedLook";look_prop.add_child(faceted_visual)
	faceted_visual.transform=smooth_visual.transform;faceted_visual.hide()
	# Keep the ordinary Prefab's single wood collider. The extra shell is visual.
	for child in get_node("Instructions").get_children():
		if child is CanvasItem:child.hide()
	if not OS.get_cmdline_user_args().has("--baseline"):
		await get_tree().process_frame
		set_voxel_detail(voxel_detail)
	else:voxel_visual.hide()
	_build_look_controls();set_look_view(1)
	if not OS.get_cmdline_user_args().has("--baseline"):set_look_fraction(voxel_fraction)
	looks_ready=true
	print("OAK_LOOKS_READY ",baked_looks.keys())

static func private_materials(mesh: ArrayMesh) -> ArrayMesh:
	var copy:=mesh.duplicate() as ArrayMesh
	for i in copy.get_surface_count():copy.surface_set_material(i,mesh.surface_get_material(i).duplicate())
	return copy

func set_voxel_detail(index: int) -> void:
	alternate_look=0
	voxel_detail=clampi(index,0,1)
	if not baked_looks.has(voxel_detail):
		baked_looks[voxel_detail]=LookBake.build(look_model,[0.0625,0.125][voxel_detail]);bake_count+=1
	voxel_visual.mesh=baked_looks[voxel_detail].mesh
	set_look_fraction(voxel_fraction)

func set_alternate_look(index: int) -> void:
	alternate_look=clampi(index,0,1)
	if alternate_look==1 and not baked_looks.has(2):
		baked_looks[2]=LookBake.build_faceted(look_model);bake_count+=1
		faceted_visual.mesh=baked_looks[2].mesh
		set_leaf_shape(leaf_shape_amount)
		set_leaf_shape_kind(leaf_shape_kind)
	set_look_fraction(voxel_fraction)

func set_leaf_shape(value: float) -> void:
	leaf_shape_amount=clampf(value,0.0,1.0)
	if faceted_visual.mesh!=null and faceted_visual.mesh.get_surface_count()>1:
		faceted_visual.mesh.surface_get_material(1).set_shader_parameter("faceted_leaf_shape_amount",leaf_shape_amount)

func set_leaf_shape_kind(value: int) -> void:
	leaf_shape_kind=clampi(value,0,2)
	if faceted_visual.mesh!=null and faceted_visual.mesh.get_surface_count()>1:
		faceted_visual.mesh.surface_get_material(1).set_shader_parameter("faceted_leaf_shape_kind",leaf_shape_kind)

func set_look_rim(enabled: bool) -> void:
	for visual in [smooth_visual,voxel_visual,faceted_visual]:visual.set_instance_shader_parameter("ember_style_rim_master",enabled)

func set_look_fraction(value: float) -> void:
	voxel_fraction=clampf(value,0,1)
	if voxel_visual.mesh==null:return
	# The middle stop bisects the trunk's authoring axis, not an asymmetric crown.
	var data: Dictionary=look_model.treeSurface
	var trunk_x: float=(data.structure.lines[0].start.x+data.pivot.x)/float(data.settings.density)
	var boundary:=lerpf(look_bounds.end.x,trunk_x,voxel_fraction*2.0) if voxel_fraction<=0.5 else lerpf(trunk_x,look_bounds.position.x,(voxel_fraction-0.5)*2.0)
	voxel_visual.visible=false;faceted_visual.visible=false
	var alternate: MeshInstance3D=voxel_visual if alternate_look==0 else faceted_visual
	for pair in [[smooth_visual,false],[alternate,true]]:
		var visual: MeshInstance3D=pair[0]
		visual.visible=voxel_fraction>0 if pair[1] else voxel_fraction<1
		for i in visual.mesh.get_surface_count():
			var material: ShaderMaterial=visual.mesh.surface_get_material(i)
			material.set_shader_parameter("object_look_clip_enabled",voxel_fraction>0 and voxel_fraction<1)
			material.set_shader_parameter("object_look_plane",Vector4(1,0,0,boundary))
			material.set_shader_parameter("object_look_positive",pair[1])
	if look_slider!=null:look_slider.set_value_no_signal(voxel_fraction)
	if look_caption!=null:
		var baked: Dictionary=baked_looks[voxel_detail if alternate_look==0 else 2]
		look_caption.text="Гладкий ← граница → %s · %d%%\nОбщая крона: %d пучков / %d участков\n%d треугольников"%["воксельный" if alternate_look==0 else "гранёный",roundi(voxel_fraction*100),baked.puffs.size(),baked.cards,baked.triangles]

func set_look_view(index: int) -> void:
	if index==0:
		set_comparison(0);follow_camera._cam.fov=follow_camera.fov;follow_camera.set_process(true);return
	follow_camera.set_process(false)
	var camera: Camera3D=follow_camera._cam
	var centre:=look_bounds.get_center()
	var target: Vector3=look_prop.to_global(centre)
	var offset:=Vector3(1.4,-0.1,13.5)
	if index==2:target=look_prop.to_global(Vector3(centre.x,look_bounds.position.y+look_bounds.size.y*0.72,centre.z));offset=Vector3(0.7,0.3,7.0)
	if index==3:target=look_prop.to_global(Vector3(0,0.75,0));offset=Vector3(0.15,0.05,2.5)
	camera.fov=40;camera.global_position=target+offset;camera.look_at(target)

func _build_look_controls() -> void:
	var panel:=PanelContainer.new();panel.position=Vector2(18,18);get_node("Instructions").add_child(panel)
	var column:=VBoxContainer.new();column.custom_minimum_size.x=340;panel.add_child(column)
	look_caption=Label.new();look_caption.text="Дуб · три облика одного Source";column.add_child(look_caption)
	var appearance:=OptionButton.new();appearance.add_item("Сравнивать с воксельным");appearance.add_item("Сравнивать с гранёным");column.add_child(appearance)
	appearance.item_selected.connect(set_alternate_look)
	var shape_label:=Label.new();shape_label.text="Грани отдельных листьев · low poly";column.add_child(shape_label)
	var shape_slider:=HSlider.new();shape_slider.min_value=0;shape_slider.max_value=1;shape_slider.step=0.01;shape_slider.value=leaf_shape_amount;column.add_child(shape_slider)
	shape_slider.value_changed.connect(set_leaf_shape)
	var shape_kind:=OptionButton.new();shape_kind.add_item("Лист → ромб");shape_kind.add_item("Лист → треугольник");shape_kind.add_item("Лист → прямоугольник");column.add_child(shape_kind)
	shape_kind.item_selected.connect(set_leaf_shape_kind)
	look_slider=HSlider.new();look_slider.min_value=0;look_slider.max_value=1;look_slider.step=0.01;column.add_child(look_slider)
	look_slider.value_changed.connect(func(value):stop_look_animation();set_look_fraction(value))
	for spec in [["Только гладкий",0.0],["Половина / половина",0.5],["Только выбранный облик",1.0]]:
		var button:=Button.new();button.text=spec[0];column.add_child(button)
		button.pressed.connect(func():stop_look_animation();set_look_fraction(spec[1]))
	for spec in [["Листва · 6.25 см",0],["Листва · 12.5 см",1]]:
		var button:=Button.new();button.text=spec[0];column.add_child(button);button.pressed.connect(func():appearance.select(0);set_voxel_detail(spec[1]))
	var rim:=CheckButton.new();rim.text="Общая световая кромка";rim.button_pressed=true;column.add_child(rim);rim.toggled.connect(set_look_rim)
	var animate:=Button.new();animate.text="Движение границы / остановить";column.add_child(animate)
	animate.pressed.connect(func():
		if look_animation!=null and look_animation.is_running():stop_look_animation();return
		look_animation=create_tween().set_loops();look_animation.tween_method(set_look_fraction,0.0,1.0,5.0);look_animation.tween_method(set_look_fraction,1.0,0.0,5.0))
	for spec in [["День",1],["Вечер",0],["Ночь",2]]:
		var button:=Button.new();button.text=spec[0];column.add_child(button);button.pressed.connect(set_lighting_preset.bind(spec[1]))
	var sun_button:=Button.new();sun_button.text="Боковой / контровой свет";column.add_child(sun_button);sun_button.pressed.connect(func():set_sun_pose(1-_sun_pose))
	for spec in [["Целое дерево",1],["Крона ближе",2],["Кора ближе",3],["Игровая камера",0]]:
		var button:=Button.new();button.text=spec[0];column.add_child(button);button.pressed.connect(set_look_view.bind(spec[1]))
	var hint:=Label.new();hint.text="F1 — скрыть панели. Настройки пробы временные.";column.add_child(hint)

func stop_look_animation() -> void:
	if look_animation!=null:look_animation.kill();look_animation=null
