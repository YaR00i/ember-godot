extends "res://scripts/prototypes/ember_diorama_readability_study.gd"
const Restored=preload("res://scripts/prototypes/ember_smooth_tree_material_fixture.gd")
const PaintedBark=preload("res://scripts/prototypes/ember_painted_bark_projection.gd")
const NAMES_SMOOTH: Array[String]=["А · прежняя кора и листва","Б · более спокойная кора","В · спокойная кора и рисованная листва"]
@export_enum("Previous artwork","Calm bark","Calm bark and painted foliage") var smooth_bark_mode:=2
var ready_for_smooth_bark:=false
var restored_inputs: Dictionary
var smooth_tree: Node3D
var wood: MeshInstance3D
var wood_material: ShaderMaterial
var calm_wood_material: ShaderMaterial
var foliage_material: ShaderMaterial
var canopy_material: StandardMaterial3D
var plain_material: StandardMaterial3D
var build_ms:=0.0
var bark_label: Label

func prepare() -> void:
	await super.prepare();set_comparison(0)
	for child in get_node("Instructions").get_children():
		if child is CanvasItem:child.hide()
	var loading:=Label.new();loading.position=Vector2(18,18);loading.text="Восстанавливаем выбранное гладкое дерево…"
	get_node("Instructions").add_child(loading)
	await get_tree().process_frame
	var started:=Time.get_ticks_msec()
	restored_inputs=Restored.new().build()
	var mapped:=PaintedBark.mesh(restored_inputs.meshes.wood,restored_inputs.structure,restored_inputs.pivot_bias)
	build_ms=Time.get_ticks_msec()-started
	var tree_position:=tree.global_position
	# This is the old non-interactive smooth LAB. Tree collision/editor transfer
	# is deliberately deferred; the existing Map floor/real player stay intact.
	remove_child(tree);tree.free()
	smooth_tree=Node3D.new();smooth_tree.name="RestoredSmoothTree";add_child(smooth_tree);smooth_tree.global_position=tree_position
	plain_material=StandardMaterial3D.new();plain_material.vertex_color_use_as_albedo=true
	plain_material.vertex_color_is_srgb=true;plain_material.roughness=0.90;plain_material.metallic_specular=0.15
	wood=MeshInstance3D.new();wood.name="RoundedTrunk";wood.mesh=mapped;smooth_tree.add_child(wood)
	wood_material=PaintedBark.material(restored_inputs.structure,restored_inputs.pivot_bias)
	calm_wood_material=PaintedBark.material(restored_inputs.structure,restored_inputs.pivot_bias,PaintedBark.CALM_ART)
	foliage_material=PaintedBark.foliage_material(restored_inputs.meshes.clouds,load("res://content/terrain_materials/painted_light_grass.tres"))
	canopy_material=plain_material.duplicate() as StandardMaterial3D
	canopy_material.albedo_texture=load("res://content/material_studies/trees/saved_canopy_motifs.png")
	canopy_material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for pair in [["CloudMasses",restored_inputs.meshes.clouds,canopy_material],["IrregularHangingLeaves",restored_inputs.meshes.leaves,plain_material]]:
		var visual:=MeshInstance3D.new();visual.name=pair[0];visual.mesh=pair[1];visual.material_override=pair[2];smooth_tree.add_child(visual)
	loading.queue_free();_build_smooth_controls()
	ready_for_smooth_bark=true;set_smooth_bark_mode(smooth_bark_mode)
	set_lighting_preset(1);set_sun_pose(1)
	print("SMOOTH_BARK_READY restored17/7; clouds=",restored_inputs.cloud_lobes," leaves=",restored_inputs.hanging_leaves," branches=",restored_inputs.wood_segments," build_ms=",build_ms)

func set_smooth_bark_mode(mode: int) -> void:
	smooth_bark_mode=clampi(mode,0,2)
	if wood==null:return
	wood.material_override=wood_material if smooth_bark_mode==0 else calm_wood_material
	(smooth_tree.get_node("CloudMasses") as MeshInstance3D).material_override=foliage_material if smooth_bark_mode==2 else canopy_material
	(smooth_tree.get_node("IrregularHangingLeaves") as MeshInstance3D).material_override=foliage_material if smooth_bark_mode==2 else plain_material
	if bark_label!=null:bark_label.text=NAMES_SMOOTH[smooth_bark_mode]+"\nФорма дерева прежняя · меняем только материалы"

func _update_caption() -> void:
	if not ready_for_smooth_bark:super._update_caption()

func _build_smooth_controls() -> void:
	var panel:=PanelContainer.new();panel.position=Vector2(18,18);get_node("Instructions").add_child(panel)
	var column:=VBoxContainer.new();column.custom_minimum_size.x=380;panel.add_child(column)
	bark_label=Label.new();column.add_child(bark_label)
	for i in NAMES_SMOOTH.size():
		var button:=Button.new();button.text=NAMES_SMOOTH[i];column.add_child(button);button.pressed.connect(set_smooth_bark_mode.bind(i))
	for pair in [["Вечер",0],["День",1],["Ночь",2]]:
		var button:=Button.new();button.text=pair[0];column.add_child(button);button.pressed.connect(set_lighting_preset.bind(pair[1]))
	var pose:=Button.new();pose.text="Боковой / контровой свет";column.add_child(pose)
	pose.pressed.connect(func():set_sun_pose(0 if _sun_pose==1 else 1))
	var hint:=Label.new();hint.text="1–3 — варианты · L / P — свет · F1 — панель\nWASD / ПКМ — обычное управление\nПробы временные · воксельный вид после выбора";column.add_child(hint)

func _unhandled_input(event: InputEvent) -> void:
	if ready_for_smooth_bark and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_1,KEY_2,KEY_3]:set_smooth_bark_mode(event.keycode-KEY_1);return
		if event.keycode==KEY_4:return
		if event.keycode==KEY_L:set_lighting_preset(lighting_preset+1);return
		if event.keycode==KEY_P:set_sun_pose(_sun_pose+1);return
	super._unhandled_input(event)
