extends "res://scripts/prototypes/ember_tree_savanna_study.gd"
## Shape gate only. Needle artwork waits for approval of the near-camera form.
var shape_volumes: MeshInstance3D
var accepted_savanna: Node3D
var shape_mode:=2
func trial_kind() -> int:return 4
func trial_title() -> String:return "Ель · проба силуэта"
func trial_short_title() -> String:return "Ель"
func trial_inputs() -> Dictionary:return Species.spruce()
func trial_card_size() -> float:return 0.50
func trial_field_keys() -> Array[String]:return ["main_branch_count","branch_splits","branch_levels","branch_count_variation","crown_spread","branch_start"]
func trial_recipe_directory() -> String:return "user://spruce25-shape-lab"
func _update_birch(inputs: Dictionary) -> void:
	super._update_birch(inputs)
	if shape_volumes==null:
		shape_volumes=MeshInstance3D.new();shape_volumes.name="CrownBlockout";birch_root.add_child(shape_volumes)
	shape_volumes.mesh=Species.crown_blockout(inputs,0.0)
	var material:=EmberVoxelPrefab.voxel_material().duplicate() as ShaderMaterial
	material.set_shader_parameter("surface_grain_scale",0.0)
	SpeciesProfiles.apply_rim(material,inputs.source.material);shape_volumes.material_override=material
	birch_wood.material_override.set_shader_parameter("painted_bark_enabled",false)
	choose_species(trial_kind())
func prepare() -> void:
	await super.prepare()
	accepted_savanna=accepted_reference(Species.savanna_umbrella_foliage(),Species.SAVANNA_PATCH_ART,Species.SAVANNA_BARK,"AcceptedSavanna24")
	birch_tabs.set_tab_hidden(1,true)
	for child in species_panel.get_child(0).get_children():
		if not child is Button:continue
		var mode:=-1
		if child.text.begins_with("A ·"):mode=0;child.text="A · прежняя ель"
		elif child.text.begins_with("Б ·"):mode=1;child.text="Б · новый каркас"
		elif child.text.begins_with("В ·"):mode=2;child.text="В · новая форма без текстуры"
		elif child.text=="Ель · показать ветви":child.hide()
		elif child.text=="Саванна · прежние массы":child.text="Саванна · рабочая основа"
		if mode>=0:
			for connection: Dictionary in child.pressed.get_connections():child.pressed.disconnect(connection.callable)
			child.pressed.connect(set_shape_mode.bind(mode))
	choose_species(trial_kind())
func set_shape_mode(mode: int) -> void:
	shape_mode=clampi(mode,0,2);birch_revision=2;choose_species(trial_kind())
func set_birch_revision(revision: int) -> void:
	set_shape_mode(revision)
func choose_species(kind: int) -> void:
	if species_label==null:return
	super.choose_species(kind)
	if accepted_savanna!=null:
		accepted_savanna.visible=kind==0
		if kind==0:species_roots[0].hide();species_label.text="Саванна24 · рабочая основа"
	if shape_volumes==null:return
	shape_volumes.visible=kind==4 and shape_mode==2
	if kind==4:
		birch_root.visible=shape_mode!=0;species_roots[4].visible=shape_mode==0
		birch_leaves.hide();birch_wood.show()
		species_label.text="Ель · "+["прежняя форма","новый каркас","ярусная форма без хвои"][shape_mode]
