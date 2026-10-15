extends "res://scripts/prototypes/ember_tree_species_study.gd"
## Reuse the same recipe/foliage controls and accepted light response.
func trial_kind() -> int:return 3
func trial_title() -> String:return "Клён23"
func trial_short_title() -> String:return "Клён"
@export_enum("Широкая · сохранённая","Вытянутая · принятая основа") var maple_shape_variant:=0
func trial_inputs() -> Dictionary:return Species.maple(7,{"crown_shape":maple_shape_variant})
func trial_field_keys() -> Array[String]:return ["crown_shape","main_branch_count","branch_splits","branch_levels","branch_count_variation"]
func trial_art() -> String:return Species.MAPLE_ART
func trial_bark() -> String:return Species.MAPLE_BARK
func trial_card_size() -> float:return 0.82
func trial_reset_caption() -> String:return "Вернуть исходную пробу"
func trial_recipe_directory() -> String:return "user://maple23-lab"
var accepted_birch: Node3D
func prepare() -> void:
	await super.prepare()
	accepted_birch=accepted_reference(Species.birch(),Species.BIRCH_ART,Species.BIRCH_BARK,"AcceptedBirch22")
	choose_species(trial_kind())
func accepted_reference(inputs: Dictionary,art: String,bark: String,title: String) -> Node3D:
	var reference:=Node3D.new();reference.name=title;smooth_tree.add_child(reference)
	reference.position=Vector3(restored_inputs.pivot_bias.x-inputs.pivot_bias.x,0,restored_inputs.pivot_bias.y-inputs.pivot_bias.y)/16.0
	inputs.source.material=SpeciesProfiles.with_rim(inputs.source.material,"bark",true,0.45)
	inputs.source.material=SpeciesProfiles.with_rim(inputs.source.material,"foliage",true,0.18)
	var trunk:=MeshInstance3D.new();trunk.mesh=PaintedBark.mesh(inputs.wood,inputs.structure,inputs.pivot_bias)
	var material:=PaintedBark.material(inputs.structure,inputs.pivot_bias,bark)
	SpeciesProfiles.apply_rim(material,inputs.source.material);trunk.material_override=material;reference.add_child(trunk)
	var leaves:=MeshInstance3D.new();leaves.mesh=inputs.leaves.mesh
	var leaf_material:=tree_leaf_shared_material.duplicate() as ShaderMaterial
	leaf_material.set_shader_parameter("painted_leaf_card_albedo",PaintedBark.artwork(art,true))
	SpeciesProfiles.apply_rim(leaf_material,inputs.source.material);leaves.material_override=leaf_material;reference.add_child(leaves)
	reference.hide();return reference
func choose_species(kind: int) -> void:
	super.choose_species(kind)
	if accepted_birch!=null:
		accepted_birch.visible=kind==2
		if kind==2:species_roots[2].hide();species_label.text="Берёза22 · принятая основа · 388"
