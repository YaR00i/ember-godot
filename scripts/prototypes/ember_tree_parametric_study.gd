extends "res://scripts/prototypes/ember_tree_branch_network_study.gd"
const RecipePanel=preload("res://addons/ember_import/ember_voxel_generator_panel.gd")
const Recipe=preload("res://addons/ember_import/ember_voxel_generator_recipe.gd")
const KEYS: Array[String]=["main_branch_count","branch_splits","branch_levels","branch_count_variation"]
const PRESETS: Array[Dictionary]=[
	{"main_branch_count":4,"branch_splits":2,"branch_levels":3,"branch_count_variation":25},
	{"main_branch_count":8,"branch_splits":3,"branch_levels":4,"branch_count_variation":40},
	{"main_branch_count":10,"branch_splits":3,"branch_levels":4,"branch_count_variation":15}]
const PARAMETRIC_NAMES: Array[String]=["А · прежний каркас20","Б · настраиваемый каркас без рисунка","В · настраиваемый каркас с корой"]
var parametric_inputs: Dictionary
var parametric_wood: MeshInstance3D
var parametric_painted: ShaderMaterial
var parameter_panel: VBoxContainer
var ready_for_parametric:=false
var parametric_build_ms:=0.0
var baseline_inputs: Dictionary
var baseline_mesh: ArrayMesh
var baseline_painted: ShaderMaterial

func prepare() -> void:
	await super.prepare()
	var started:=Time.get_ticks_msec()
	parametric_inputs=Branching.build(7,21,PRESETS[1])
	_update_tree(parametric_inputs)
	baseline_inputs=parametric_inputs;baseline_mesh=parametric_wood.mesh;baseline_painted=parametric_painted
	parametric_build_ms=Time.get_ticks_msec()-started
	var recipe:=Recipe.new();recipe.generator_id="large_tree";recipe.seed=7
	recipe.parameters=parametric_inputs.parameters;recipe.structure=parametric_inputs.structure
	var directory:="user://tree-parametric-lab"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	assert(ResourceSaver.save(recipe,directory.path_join(parametric_inputs.source.model_id+".tres"))==OK)
	_build_parameter_controls(directory)
	ready_for_parametric=true;set_leaf_cards_mode(2)
	print("TREE_PARAMETRIC_READY branches=",parametric_inputs.layout.size()," supports=",parametric_inputs.structure.lines.size()," build_ms=",parametric_build_ms)

func _build_parameter_controls(directory: String) -> void:
	var box:=PanelContainer.new()
	box.position=Vector2(get_viewport().get_visible_rect().size.x-375,18);box.size=Vector2(357,770)
	get_node("Instructions").add_child(box)
	var column:=VBoxContainer.new();column.custom_minimum_size=Vector2(357,770);box.add_child(column)
	var label:=Label.new();label.text="Настройки ветвления";column.add_child(label)
	var row:=HBoxContainer.new();column.add_child(row)
	for i in 3:
		var button:=Button.new();button.text=["Редко","Обычно","Густо"][i];row.add_child(button)
		button.pressed.connect(apply_branch_preset.bind(i))
	parameter_panel=RecipePanel.new();parameter_panel.recipe_directory=directory;column.add_child(parameter_panel)
	assert(parameter_panel.open_source(parametric_inputs.source,{"field_keys":KEYS}))
	parameter_panel._save_mode.hide();parameter_panel._variation_name.hide();parameter_panel._save_button.hide()
	parameter_panel._variation_name.text="Каркас дерева"
	parameter_panel.preview_changed.connect(_recipe_preview)
	parameter_panel._info.text="Выбери количество ветвей и собери предпросмотр.\nСначала оцениваем дерево без листвы."

func apply_branch_preset(index: int) -> void:
	if parameter_panel==null:return
	parameter_panel.history.create_action("Набор ветвления")
	for key in KEYS:
		parameter_panel.history.add_do_method(parameter_panel._assign.bind(key,PRESETS[index][key]))
		parameter_panel.history.add_undo_method(parameter_panel._assign.bind(key,parameter_panel.recipe.parameters[key]))
	parameter_panel.history.commit_action()
	parameter_panel.prepare()

func _recipe_preview(_packed: PackedScene,source: EmberVoxelModelResource) -> void:
	if source==null:
		parametric_inputs=baseline_inputs;parametric_wood.mesh=baseline_mesh;parametric_painted=baseline_painted
		parametric_wood.position=Vector3(restored_inputs.pivot_bias.x-baseline_inputs.pivot_bias.x,0,restored_inputs.pivot_bias.y-baseline_inputs.pivot_bias.y)/16.0
		set_leaf_cards_mode(leaf_cards_mode);return
	var started:=Time.get_ticks_msec()
	var prepared=parameter_panel.creation
	var inputs:=Branching.from_built(prepared.report,prepared.recipe.parameters,prepared.recipe.seed)
	_update_tree(inputs);parametric_inputs=inputs;parametric_build_ms=Time.get_ticks_msec()-started
	set_leaf_cards_mode(leaf_cards_mode)

func _update_tree(inputs: Dictionary) -> void:
	var mapped:=PaintedBark.mesh(inputs.wood,inputs.structure,inputs.pivot_bias)
	parametric_painted=PaintedBark.material(inputs.structure,inputs.pivot_bias,PaintedBark.CALM_ART)
	if parametric_wood==null:
		parametric_wood=MeshInstance3D.new();parametric_wood.name="RecursiveBranches21";smooth_tree.add_child(parametric_wood)
	parametric_wood.mesh=mapped
	parametric_wood.position=Vector3(restored_inputs.pivot_bias.x-inputs.pivot_bias.x,0,restored_inputs.pivot_bias.y-inputs.pivot_bias.y)/16.0
	parametric_wood.material_override=parametric_painted

func set_leaf_cards_mode(mode: int) -> void:
	if parametric_wood==null:
		super.set_leaf_cards_mode(mode);return
	super.set_leaf_cards_mode(2)
	leaf_cards_mode=clampi(mode,0,2)
	network_wood.visible=leaf_cards_mode==0
	parametric_wood.visible=leaf_cards_mode!=0
	parametric_wood.material_override=network_plain if leaf_cards_mode==1 else parametric_painted
	card_label.text=PARAMETRIC_NAMES[leaf_cards_mode]+"\nВетви: "+str(parametric_inputs.layout.size())+" · 21/seed7 · без листвы"

func _build_card_controls() -> void:
	super._build_card_controls()
	var column:=card_label.get_parent()
	for i in 3:(column.get_child(i+1) as Button).text=PARAMETRIC_NAMES[i]
	for child in column.get_children():
		if child is Label and child!=card_label:child.text="1–3 — вид · L/P — свет · F1 — панель\nРакурсы ниже — осмотр дерева\nИгровая камера — обычное управление"
