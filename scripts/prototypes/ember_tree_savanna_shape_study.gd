extends "res://scripts/prototypes/ember_tree_savanna_study.gd"
## First art gate: source scaffold and untextured provider crown volumes.
## The accepted species and rejected savanna remain exact references.
var shape_volumes: MeshInstance3D
var rejected_tree: Node3D
var shape_mode:=2
func trial_title() -> String:return "Саванна · проба силуэта"
func trial_inputs() -> Dictionary:return Species.savanna_umbrella()
func trial_recipe_directory() -> String:return "user://savanna24-shape-lab"
func _update_birch(inputs: Dictionary) -> void:
	super._update_birch(inputs)
	if shape_volumes==null:
		shape_volumes=MeshInstance3D.new();shape_volumes.name="CrownBlockout";birch_root.add_child(shape_volumes)
	shape_volumes.mesh=Species.crown_blockout(inputs)
	var material:=EmberVoxelPrefab.voxel_material().duplicate() as ShaderMaterial
	material.set_shader_parameter("surface_grain_scale",0.0)
	SpeciesProfiles.apply_rim(material,inputs.source.material);shape_volumes.material_override=material
	birch_wood.material_override.set_shader_parameter("painted_bark_enabled",false)
	choose_species(trial_kind())
func prepare() -> void:
	await super.prepare()
	rejected_tree=accepted_reference(Species.savanna(),Species.SAVANNA_ART,Species.SAVANNA_BARK,"RejectedSavanna24")
	# Existing Recipe controls stay active. Final-leaf controls wait for the next gate.
	birch_tabs.set_tab_hidden(1,true)
	for child in species_panel.get_child(0).get_children():
		if not child is Button:continue
		var mode:=-1
		if child.text.begins_with("A ·"):mode=0;child.text="A · отклонённая проба"
		elif child.text.begins_with("Б ·"):mode=1;child.text="Б · новый каркас"
		elif child.text.begins_with("В ·"):mode=2;child.text="В · объёмы без текстуры"
		elif child.text=="Саванна · показать ветви":child.hide()
		if mode>=0:
			for connection: Dictionary in child.pressed.get_connections():child.pressed.disconnect(connection.callable)
			child.pressed.connect(set_shape_mode.bind(mode))
	choose_species(trial_kind())
func set_shape_mode(mode: int) -> void:
	shape_mode=clampi(mode,0,2);birch_revision=2;choose_species(trial_kind())
func choose_species(kind: int) -> void:
	if species_label==null:return
	super.choose_species(kind)
	if rejected_tree!=null:rejected_tree.visible=kind==0 and shape_mode==0
	if shape_volumes==null:return
	shape_volumes.visible=kind==0 and shape_mode==2
	if kind==0:
		birch_leaves.hide();birch_wood.visible=shape_mode!=0
		species_label.text="Саванна · "+["отклонённая проба","новый каркас","объёмы без текстуры"][shape_mode]
