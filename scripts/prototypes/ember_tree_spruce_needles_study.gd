extends "res://scripts/prototypes/ember_tree_savanna_study.gd"
## Needle art trial on the provisional spruce scaffold; same Recipe/light owner.
var shape_reference: Node3D
var accepted_savanna: Node3D
var patch_sample: MeshInstance3D
func trial_kind() -> int:return 4
func trial_title() -> String:return "Ель · хвойные пучки"
func trial_short_title() -> String:return "Ель"
func trial_inputs() -> Dictionary:return Species.spruce_needles()
func trial_art() -> String:return Species.SPRUCE_ART
func trial_bark() -> String:return Species.SPRUCE_BARK
func trial_card_size() -> float:return Species.SPRUCE_CARD_SIZE
func trial_card_options() -> Dictionary:return {"branch_growth":true,"size":trial_card_size(),"needle_sprays":true}
func trial_field_keys() -> Array[String]:return ["main_branch_count","branch_splits","branch_levels","branch_count_variation","crown_spread","branch_start"]
func trial_recipe_directory() -> String:return "user://spruce25-needles-lab"
func prepare() -> void:
	await super.prepare()
	accepted_savanna=accepted_reference(Species.savanna_umbrella_foliage(),Species.SAVANNA_PATCH_ART,Species.SAVANNA_BARK,"AcceptedSavanna24")
	var inputs:=Species.spruce()
	shape_reference=accepted_reference(inputs,Species.SPRUCE_ART,Species.SPRUCE_BARK,"ProvisionalShape")
	shape_reference.get_child(0).material_override.set_shader_parameter("painted_bark_enabled",false)
	shape_reference.get_child(1).mesh=Species.crown_blockout(inputs,0.0)
	var material:=EmberVoxelPrefab.voxel_material().duplicate() as ShaderMaterial
	material.set_shader_parameter("surface_grain_scale",0.0);SpeciesProfiles.apply_rim(material,inputs.source.material)
	shape_reference.get_child(1).material_override=material
	patch_sample=MeshInstance3D.new();patch_sample.name="NeedleSample";smooth_tree.add_child(patch_sample);patch_sample.hide()
	var column:=species_panel.get_child(0)
	for child in column.get_children():
		if not child is Button:continue
		if child.text.begins_with("A ·"):
			child.text="A · пробный объём"
			for connection: Dictionary in child.pressed.get_connections():child.pressed.disconnect(connection.callable)
			child.pressed.connect(show_canopy_reference)
		elif child.text.begins_with("Б ·"):child.text="Б · хвоя без рисунка"
		elif child.text.begins_with("В ·"):child.text="В · хвоя и кора"
		elif child.text=="Саванна · прежние массы":child.text="Саванна · рабочая основа"
	for count in [1,6]:
		var button:=Button.new();button.text="Одна хвойная плоскость" if count==1 else "Группа · 6 плоскостей"
		column.add_child(button);column.move_child(button,10 if count==1 else 11);button.pressed.connect(show_leaf_sample.bind(count))
	choose_species(trial_kind())
func choose_species(kind: int) -> void:
	super.choose_species(kind)
	if shape_reference!=null:shape_reference.hide()
	if patch_sample!=null:patch_sample.hide()
	if accepted_savanna!=null:
		accepted_savanna.visible=kind==0
		if kind==0:species_roots[0].hide();species_label.text="Саванна24 · рабочая основа"
func set_birch_revision(revision: int) -> void:
	if revision==0 and shape_reference!=null:show_canopy_reference()
	else:super.set_birch_revision(revision)
func show_canopy_reference() -> void:
	choose_species(trial_kind());birch_root.hide();shape_reference.show();set_species_view(1)
	species_label.text="Ель · пробная форма с выступами · без хвои"
func show_leaf_sample(count: int) -> void:
	choose_species(trial_kind());birch_root.hide()
	var start_card:=0
	for i in birch_inputs.full_leaves.roots.size():
		if birch_inputs.layout[birch_inputs.full_leaves.roots[i].branch].order==1:start_card=i;break
	patch_sample.mesh=Branching.crown_card_sample(birch_inputs.full_leaves,count,start_card)
	patch_sample.position=birch_root.position+Vector3(25,0,0);patch_sample.material_override=birch_painted;patch_sample.show()
	var centre: Vector3=patch_sample.global_transform*patch_sample.mesh.get_aabb().get_center()
	var normal: Vector3=patch_sample.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL][0]
	var distance:=maxf(patch_sample.mesh.get_aabb().size.length()*1.5,1.2)
	var camera: Camera3D=follow_camera._cam;camera.global_position=centre+normal*distance;camera.fov=40
	camera.look_at(centre,Vector3.FORWARD if absf(normal.dot(Vector3.UP))>0.95 else Vector3.UP)
	species_label.text="Одна хвойная плоскость" if count==1 else "Группа · 6 плоскостей"
