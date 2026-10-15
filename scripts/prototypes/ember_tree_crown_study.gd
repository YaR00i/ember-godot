extends "res://scripts/prototypes/ember_tree_branching_study.gd"
const CROWN_ART := "res://content/material_studies/trees/leaf_cluster_atlas_v2.png"
const CROWN_NAMES: Array[String] = ["А · предыдущая проба18", "Б · новая крона, одноцветная", "В · новая крона, атлас листьев"]
var crown_inputs: Dictionary
var crown_wood: MeshInstance3D
var crown_cards: MeshInstance3D
var crown_plain: ShaderMaterial
var crown_painted: ShaderMaterial
var crown_build_ms := 0.0
var ready_for_crown := false
var leaves_visible := true
var leaf_toggle: Button

func prepare() -> void:
	await super.prepare()
	var started := Time.get_ticks_msec()
	crown_inputs = Branching.build(7,19)
	crown_wood = MeshInstance3D.new(); crown_wood.name = "Crown19Wood"
	crown_wood.mesh = PaintedBark.mesh(crown_inputs.wood,crown_inputs.structure,crown_inputs.pivot_bias)
	crown_wood.material_override = PaintedBark.material(crown_inputs.structure,crown_inputs.pivot_bias,PaintedBark.CALM_ART)
	smooth_tree.add_child(crown_wood)
	crown_cards = MeshInstance3D.new(); crown_cards.name = "Crown19Leaves"
	crown_cards.mesh = crown_inputs.cards.mesh; smooth_tree.add_child(crown_cards)
	var alignment := Vector3(restored_inputs.pivot_bias.x-crown_inputs.pivot_bias.x,0,restored_inputs.pivot_bias.y-crown_inputs.pivot_bias.y)/16.0
	crown_wood.position = alignment; crown_cards.position = alignment
	var profile: Resource = load("res://content/terrain_materials/painted_light_grass.tres")
	crown_painted = PaintedBark.leaf_cards_material(restored_inputs.meshes.clouds,profile,true,CROWN_ART)
	crown_plain = crown_painted.duplicate() as ShaderMaterial
	crown_plain.set_shader_parameter("painted_leaf_card_coloured",false)
	crown_plain.set_shader_parameter("painted_leaf_card_plain",Color("61734c"))
	crown_build_ms = Time.get_ticks_msec()-started
	ready_for_crown = true; set_leaf_cards_mode(2)
	print("TREE_CROWN_READY branches=",crown_inputs.layout.size()," supports=",crown_inputs.structure.lines.size()," cards=",crown_inputs.cards.cards," triangles=",crown_inputs.cards.triangles," build_ms=",crown_build_ms)

func set_leaf_cards_mode(mode: int) -> void:
	if crown_wood == null:
		super.set_leaf_cards_mode(mode); return
	super.set_leaf_cards_mode(2)
	leaf_cards_mode = clampi(mode,0,2)
	branching_wood.visible = mode == 0
	branching_cards.visible = mode == 0 and leaves_visible
	crown_wood.visible = mode != 0
	crown_cards.visible = mode != 0 and leaves_visible
	crown_cards.material_override = crown_plain if mode == 1 else crown_painted
	card_label.text = CROWN_NAMES[leaf_cards_mode]+"\nОбъём и перекрытие масс · 19/seed7"
	if leaf_toggle != null: leaf_toggle.text = "Листва: видна / показать каркас" if leaves_visible else "Каркас: вернуть листву"

func set_crown_leaves_visible(value: bool) -> void:
	leaves_visible = value; set_leaf_cards_mode(leaf_cards_mode)

func _build_card_controls() -> void:
	super._build_card_controls()
	var column := card_label.get_parent()
	for i in 3: (column.get_child(i+1) as Button).text = CROWN_NAMES[i]
	leaf_toggle = Button.new(); column.add_child(leaf_toggle)
	leaf_toggle.pressed.connect(func(): set_crown_leaves_visible(not leaves_visible))

func _unhandled_input(event: InputEvent) -> void:
	if ready_for_crown and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_B:
		set_crown_leaves_visible(not leaves_visible); return
	super._unhandled_input(event)
