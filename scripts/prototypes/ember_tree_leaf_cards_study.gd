extends "res://scripts/prototypes/ember_smooth_bark_material_study.gd"
const LeafCards=preload("res://scripts/prototypes/ember_tree_leaf_cards_fixture.gd")
const CARD_NAMES: Array[String]=["А · прежняя округлая крона","Б · листва из плоскостей, силуэт","В · плоскости с рисованной листвой"]
@export_enum("Previous rounded canopy","Plain leaf cards","Painted leaf cards") var leaf_cards_mode:=2
var ready_for_leaf_cards:=false
var card_inputs: Dictionary
var card_visual: MeshInstance3D
var card_plain: ShaderMaterial
var card_painted: ShaderMaterial
var card_label: Label
var card_build_ms:=0.0

func prepare() -> void:
	await super.prepare();set_smooth_bark_mode(2)
	var started:=Time.get_ticks_msec()
	card_inputs=LeafCards.build(restored_inputs)
	card_visual=MeshInstance3D.new();card_visual.name="FixedLeafCards";card_visual.mesh=card_inputs.mesh;smooth_tree.add_child(card_visual)
	var profile: Resource=load("res://content/terrain_materials/painted_light_grass.tres")
	card_painted=PaintedBark.leaf_cards_material(restored_inputs.meshes.clouds,profile,true)
	card_plain=card_painted.duplicate() as ShaderMaterial
	card_plain.set_shader_parameter("painted_leaf_card_coloured",false)
	card_build_ms=Time.get_ticks_msec()-started
	for child in get_node("Instructions").get_children():
		if child is CanvasItem:child.hide()
	_build_card_controls();ready_for_leaf_cards=true;set_leaf_cards_mode(leaf_cards_mode)
	print("LEAF_CARDS_READY fixed3D cards=",card_inputs.cards," triangles=",card_inputs.triangles," groups=",card_inputs.groups," build_ms=",card_build_ms)

func set_leaf_cards_mode(mode: int) -> void:
	leaf_cards_mode=clampi(mode,0,2)
	if card_visual==null:return
	card_visual.visible=leaf_cards_mode!=0
	card_visual.material_override=card_painted if leaf_cards_mode==2 else card_plain
	for name in ["CloudMasses","IrregularHangingLeaves"]:
		(smooth_tree.get_node(name) as MeshInstance3D).visible=leaf_cards_mode==0
	# Calm bark/branch/Source/terrain remain the same in every comparison.
	wood.material_override=calm_wood_material
	if card_label!=null:card_label.text=CARD_NAMES[leaf_cards_mode]+"\nСтвол прежний · плоскости закреплены в 3D"

func _build_card_controls() -> void:
	var panel:=PanelContainer.new();panel.position=Vector2(18,18);get_node("Instructions").add_child(panel)
	var column:=VBoxContainer.new();column.custom_minimum_size.x=425;panel.add_child(column)
	card_label=Label.new();column.add_child(card_label)
	for i in CARD_NAMES.size():
		var button:=Button.new();button.text=CARD_NAMES[i];column.add_child(button);button.pressed.connect(set_leaf_cards_mode.bind(i))
	for pair in [["Вечер",0],["День",1],["Ночь",2]]:
		var button:=Button.new();button.text=pair[0];column.add_child(button);button.pressed.connect(set_lighting_preset.bind(pair[1]))
	var pose:=Button.new();pose.text="Боковой / контровой свет";column.add_child(pose)
	pose.pressed.connect(func():set_sun_pose(0 if _sun_pose==1 else 1))
	var hint:=Label.new();hint.text="1–3 — варианты · L / P — свет · F1 — панель\nWASD / ПКМ — обычное управление\nПроба формы · без ветра и дальнего LOD";column.add_child(hint)

func _unhandled_input(event: InputEvent) -> void:
	if ready_for_leaf_cards and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_1,KEY_2,KEY_3]:set_leaf_cards_mode(event.keycode-KEY_1);return
		if event.keycode==KEY_L:set_lighting_preset(lighting_preset+1);return
		if event.keycode==KEY_P:set_sun_pose(_sun_pose+1);return
		if event.keycode==KEY_4:return
	super._unhandled_input(event)
