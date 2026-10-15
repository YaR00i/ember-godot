extends "res://scripts/prototypes/ember_tree_leaf_cards_study.gd"
const Branching = preload("res://scripts/prototypes/ember_tree_branching_fixture.gd")
const BRANCH_NAMES: Array[String] = ["А · прежний каркас и листья", "Б · новый каркас без листьев", "В · новый каркас с листвой"]
var branching_inputs: Dictionary
var branching_wood: MeshInstance3D
var branching_cards: MeshInstance3D
var branching_build_ms := 0.0
var ready_for_branching := false

func prepare() -> void:
	await super.prepare()
	var started := Time.get_ticks_msec()
	branching_inputs = Branching.build()
	branching_wood = MeshInstance3D.new(); branching_wood.name = "HierarchicalBranches"
	branching_wood.mesh = PaintedBark.mesh(branching_inputs.wood, branching_inputs.structure, branching_inputs.pivot_bias)
	branching_wood.material_override = PaintedBark.material(branching_inputs.structure, branching_inputs.pivot_bias, PaintedBark.CALM_ART)
	smooth_tree.add_child(branching_wood)
	branching_cards = MeshInstance3D.new(); branching_cards.name = "TwigRootedLeafCards"
	branching_cards.mesh = branching_inputs.cards.mesh; branching_cards.material_override = card_painted
	smooth_tree.add_child(branching_cards)
	var alignment := Vector3(restored_inputs.pivot_bias.x - branching_inputs.pivot_bias.x, 0, restored_inputs.pivot_bias.y - branching_inputs.pivot_bias.y) / 16.0
	branching_wood.position = alignment; branching_cards.position = alignment
	branching_build_ms = Time.get_ticks_msec() - started
	ready_for_branching = true; set_leaf_cards_mode(2)
	print("TREE_BRANCHING_READY branches=", branching_inputs.layout.size(), " supports=", branching_inputs.structure.lines.size(), " cards=", branching_inputs.cards.cards, " build_ms=", branching_build_ms)

func set_leaf_cards_mode(mode: int) -> void:
	if branching_wood == null:
		super.set_leaf_cards_mode(mode); return
	super.set_leaf_cards_mode(2)
	leaf_cards_mode = clampi(mode, 0, 2)
	wood.visible = mode == 0; card_visual.visible = mode == 0
	branching_wood.visible = mode != 0; branching_cards.visible = mode == 2
	card_label.text = BRANCH_NAMES[leaf_cards_mode] + "\nСтвол → ветви → веточки → листва · 18/seed7"

func _build_card_controls() -> void:
	super._build_card_controls()
	var column := card_label.get_parent()
	for i in 3:
		(column.get_child(i + 1) as Button).text = BRANCH_NAMES[i]
