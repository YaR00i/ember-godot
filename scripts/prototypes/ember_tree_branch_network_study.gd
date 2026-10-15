extends "res://scripts/prototypes/ember_tree_branching_study.gd"
const NETWORK_NAMES: Array[String] = ["А · прежние голые ветви18", "Б · новый каркас без текстуры", "В · новый каркас с корой"]
var network_inputs: Dictionary
var network_wood: MeshInstance3D
var network_plain: ShaderMaterial
var network_painted: ShaderMaterial
var network_build_ms := 0.0
var ready_for_network := false

func prepare() -> void:
	await super.prepare()
	var started := Time.get_ticks_msec()
	network_inputs = Branching.build(7,20)
	network_wood = MeshInstance3D.new(); network_wood.name = "BranchNetwork20"
	network_wood.mesh = PaintedBark.mesh(network_inputs.wood,network_inputs.structure,network_inputs.pivot_bias)
	network_painted = PaintedBark.material(network_inputs.structure,network_inputs.pivot_bias,PaintedBark.CALM_ART)
	network_plain = EmberVoxelPrefab.voxel_material().duplicate() as ShaderMaterial
	network_plain.set_shader_parameter("surface_grain_scale",0.0)
	smooth_tree.add_child(network_wood)
	network_wood.position = Vector3(restored_inputs.pivot_bias.x-network_inputs.pivot_bias.x,0,restored_inputs.pivot_bias.y-network_inputs.pivot_bias.y)/16.0
	network_build_ms = Time.get_ticks_msec()-started
	ready_for_network = true; set_leaf_cards_mode(2)
	set_network_view(1)
	print("TREE_NETWORK_READY branches=",network_inputs.layout.size()," supports=",network_inputs.structure.lines.size()," build_ms=",network_build_ms)

func set_leaf_cards_mode(mode: int) -> void:
	if network_wood == null:
		super.set_leaf_cards_mode(mode); return
	super.set_leaf_cards_mode(1)
	leaf_cards_mode = clampi(mode,0,2)
	branching_wood.visible = leaf_cards_mode==0
	branching_cards.hide(); card_visual.hide(); wood.hide()
	network_wood.visible = leaf_cards_mode!=0
	network_wood.material_override = network_plain if leaf_cards_mode==1 else network_painted
	card_label.text = NETWORK_NAMES[leaf_cards_mode]+"\nСтвол → крупные ветви → развилки → веточки → побеги · 20/seed7"

func _build_card_controls() -> void:
	super._build_card_controls()
	var column := card_label.get_parent()
	for i in 3: (column.get_child(i+1) as Button).text = NETWORK_NAMES[i]
	for pair in [["Игровая камера",0],["Каркас целиком",1],["Слева",2],["Сзади",3],["Развилки ближе",4]]:
		var button := Button.new(); button.text=pair[0]; column.add_child(button)
		button.pressed.connect(set_network_view.bind(pair[1]))

func set_network_view(view: int) -> void:
	if not ready_for_network: return
	follow_camera.set_process(view==0)
	if view==0:
		set_comparison(0); return
	var camera: Camera3D=follow_camera._cam
	var target := smooth_tree.global_position+Vector3(0,3.1,0)
	var offset: Vector3 = [Vector3(2,-0.4,11),Vector3(-11,-0.4,2),Vector3(-2,-0.4,-11),Vector3(1,0.1,3.1)][view-1]
	if view==4: target=smooth_tree.global_position+Vector3(0,2.9,0)
	camera.fov=40;camera.global_position=target+offset;camera.look_at(target)
