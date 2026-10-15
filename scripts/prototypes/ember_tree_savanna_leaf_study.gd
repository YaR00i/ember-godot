extends "res://scripts/prototypes/ember_tree_savanna_study.gd"
var canopy_reference: Node3D
var patch_sample: MeshInstance3D
func trial_title() -> String:return "Саванна · мелкая листва"
func trial_inputs() -> Dictionary:return Species.savanna_umbrella_foliage()
func trial_art() -> String:return Species.SAVANNA_PATCH_ART
func trial_card_size() -> float:return 1.05
func trial_card_options() -> Dictionary:return {"branch_growth":true,"size":trial_card_size(),"canopy_envelope":true}
func trial_recipe_directory() -> String:return "user://savanna24-leaf-patches-lab"
func prepare() -> void:
	await super.prepare()
	var inputs:=Species.savanna_umbrella()
	canopy_reference=accepted_reference(inputs,Species.SAVANNA_ART,Species.SAVANNA_BARK,"AcceptedCanopy")
	canopy_reference.get_child(0).material_override.set_shader_parameter("painted_bark_enabled",false)
	canopy_reference.get_child(1).mesh=Species.crown_blockout(inputs)
	var material:=EmberVoxelPrefab.voxel_material().duplicate() as ShaderMaterial
	material.set_shader_parameter("surface_grain_scale",0.0);SpeciesProfiles.apply_rim(material,inputs.source.material)
	canopy_reference.get_child(1).material_override=material
	patch_sample=MeshInstance3D.new();patch_sample.name="LeafPatchSample";smooth_tree.add_child(patch_sample);patch_sample.hide()
	var column:=species_panel.get_child(0)
	for child in column.get_children():
		if not child is Button:continue
		if child.text.begins_with("A ·"):
			child.text="A · принятый объём"
			for connection: Dictionary in child.pressed.get_connections():child.pressed.disconnect(connection.callable)
			child.pressed.connect(show_canopy_reference)
		elif child.text.begins_with("Б ·"):child.text="Б · листва без рисунка"
		elif child.text.begins_with("В ·"):child.text="В · мелкая листва"
		elif child.text=="Клён · прежние массы":child.text="Клён · принятая основа"
	for count in [1,6]:
		var button:=Button.new();button.text="Одна плоскость" if count==1 else "Группа · 6 плоскостей"
		column.add_child(button);column.move_child(button,10 if count==1 else 11);button.pressed.connect(show_leaf_sample.bind(count))
	choose_species(trial_kind())
func choose_species(kind: int) -> void:
	super.choose_species(kind)
	if canopy_reference!=null:canopy_reference.hide()
	if patch_sample!=null:patch_sample.hide()
func show_canopy_reference() -> void:
	choose_species(trial_kind());birch_root.hide();canopy_reference.show();set_species_view(1)
	species_label.text="Саванна · принятая общая форма"
func show_leaf_sample(count: int) -> void:
	choose_species(trial_kind());birch_root.hide()
	patch_sample.mesh=Branching.crown_card_sample(birch_inputs.full_leaves,count)
	# Display the unchanged sample away from the grass island for a clear backdrop.
	patch_sample.position=birch_root.position+Vector3(25,0,0);patch_sample.material_override=birch_painted;patch_sample.show()
	var centre: Vector3=patch_sample.global_transform*patch_sample.mesh.get_aabb().get_center()
	var normal: Vector3=patch_sample.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL][0]
	var distance:=maxf(patch_sample.mesh.get_aabb().size.length()*1.5,1.2)
	var camera: Camera3D=follow_camera._cam;camera.global_position=centre+normal*distance;camera.fov=40
	camera.look_at(centre,Vector3.FORWARD if absf(normal.dot(Vector3.UP))>0.95 else Vector3.UP)
	species_label.text="Одна плоскость" if count==1 else "Пучок · 6 плоскостей"
