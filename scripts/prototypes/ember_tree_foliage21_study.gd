extends "res://scripts/prototypes/ember_tree_parametric_study.gd"
const FOLIAGE_ATLAS:="res://content/material_studies/trees/leaf_cluster_atlas_v2.png"
const QUIET_ATLAS:="res://content/material_studies/trees/leaf_cluster_atlas_v3_quiet.png"
const MINIMAL_ATLAS:="res://content/material_studies/trees/leaf_cluster_atlas_v6_one_tone_clean.png"
const TWO_TONE_ATLAS:="res://content/material_studies/trees/leaf_cluster_atlas_v5_two_tones.png"
const SOFT_BARK:="res://content/material_studies/trees/painterly_bark_v4_soft.png"
const OAK_PAINTED_BARK:="res://content/material_studies/trees/bark_species_v1/oak-v1.png"
const OAK_CALM_BARK:="res://content/material_studies/trees/bark_species_v1/oak-v2-calm.png"
@export_enum("Прежняя","Крупные борозды","Спокойные плоскости") var oak_bark_variant := 2
var oak_bark_trial: bool:
	get:return oak_bark_variant>0
var oak_bark_choice: OptionButton
const AIR_GAPS_ATLAS:="res://content/material_studies/trees/leaf_cluster_atlas_v7_air_gaps.png"
const SEPARATE_LEAVES_ATLAS:="res://content/material_studies/trees/leaf_cluster_atlas_v8_separate_leaves.png"
const OPTICS_NAMES: Array[String]=["До · прежняя фильтрация","Подготовленные прозрачные края","Края + насыщеннее цвет","Цвет + просвечивание + кромка","Просвечивание + кромка + просветы"]
const FOLIAGE_NAMES: Array[String]=["А · каркас без листвы","Б · крона одним цветом","В · крона с рисунком листьев"]
const MATERIAL_NAMES: Array[String]=["Прежний рисунок","Спокойная листва","Спокойная листва + мягкая кора","Листва · один тон","Листва · два близких тона","Проба · отдельные листья на дереве"]
var foliage21_inputs: Dictionary
var foliage21_cards: MeshInstance3D
var foliage21_plain: ShaderMaterial
var foliage21_painted: ShaderMaterial
var foliage21_quiet: ShaderMaterial
var foliage21_minimal: ShaderMaterial
var foliage21_two_tones: ShaderMaterial
var foliage21_soft_bark: ShaderMaterial
var material_revision:=3
var leaf_optics_mode:=4
var leaf_saturation:=1.18
var leaf_transmission:=0.28
var leaf_rim_strength:=0.23
var optical_materials: Array[ShaderMaterial]=[]
var optics_panel: PanelContainer
var branch_controls: Control
var optics_choice: OptionButton
var baseline_foliage: Dictionary
var ready_for_foliage21:=false
var leaf_samples: Node3D
var leaf_sample_materials: Array[ShaderMaterial]=[]
var leaf_sample_nodes: Array[MeshInstance3D]=[]
var leaf_sample_panel: PanelContainer
var leaf_sample_stage:=2
var leaf_sample_shadow_strength:=1.0
var leaf_sample_shadow_label: Label
var leaf_sample_shadow_slider: HSlider
var tree_leaf_trial_material: ShaderMaterial
var tree_leaf_trial_strength:=0.4
var tree_leaf_trial_panel: PanelContainer
var tree_leaf_trial_label: Label
var tree_leaf_density_percent:=45
var tree_leaf_density_inputs: Dictionary={}
var tree_leaf_density_cache: Dictionary={}
var tree_leaf_density_slider: HSlider
var tree_leaf_density_label: Label
var tree_leaf_density_dragging:=false
var tree_leaf_density_builds:=0
var tree_leaf_density_build_ms:=0.0
var tree_leaf_local_percent: Dictionary={}
var tree_leaf_groups: Dictionary={}
var tree_leaf_group_ids: Array[int]=[]
var tree_leaf_group_source_id:=0
var tree_leaf_selected_group: int=-1
var tree_leaf_group_choice: OptionButton
var tree_leaf_local_slider: HSlider
var tree_leaf_local_label: Label
var tree_leaf_local_dragging:=false
var tree_leaf_selection: MeshInstance3D
var tree_leaf_form_depth:=100.0
var tree_leaf_form_slider: HSlider
var tree_leaf_form_label: Label
var tree_leaf_shared_light := false
var tree_leaf_shared_material: ShaderMaterial
var tree_leaf_shared_button: Button
@export_group("Tree rim study")
@export var tree_rim_enabled := false
@export_range(0.0,1.0,0.01) var tree_rim_wood_strength := 0.45
@export_range(0.0,1.0,0.01) var tree_rim_leaf_strength := 0.18
var tree_rim_wood_material: ShaderMaterial
var tree_rim_wood_source: ShaderMaterial
var tree_rim_button: Button

func prepare() -> void:
	await super.prepare()
	var profile: Resource=load("res://content/terrain_materials/painted_light_grass.tres")
	foliage21_painted=PaintedBark.leaf_cards_material(restored_inputs.meshes.clouds,profile,true,FOLIAGE_ATLAS)
	foliage21_quiet=foliage21_painted.duplicate() as ShaderMaterial
	foliage21_quiet.set_shader_parameter("painted_leaf_card_albedo",PaintedBark.artwork(QUIET_ATLAS))
	foliage21_minimal=foliage21_painted.duplicate() as ShaderMaterial
	foliage21_minimal.set_shader_parameter("painted_leaf_card_albedo",PaintedBark.artwork(MINIMAL_ATLAS))
	foliage21_two_tones=foliage21_painted.duplicate() as ShaderMaterial
	foliage21_two_tones.set_shader_parameter("painted_leaf_card_albedo",PaintedBark.artwork(TWO_TONE_ATLAS))
	foliage21_plain=foliage21_painted.duplicate() as ShaderMaterial
	foliage21_plain.set_shader_parameter("painted_leaf_card_coloured",false)
	foliage21_plain.set_shader_parameter("painted_leaf_card_plain",Color("61734c"))
	for stage in OPTICS_NAMES.size():
		var material:=foliage21_minimal.duplicate() as ShaderMaterial
		if stage>0:
			material.set_shader_parameter("painted_leaf_card_albedo",PaintedBark.artwork(AIR_GAPS_ATLAS if stage==4 else MINIMAL_ATLAS,true))
		optical_materials.append(material)
	_refresh_optics_values()
	baseline_foliage=foliage21_inputs
	ready_for_foliage21=true;set_leaf_cards_mode(2)
	set_network_view(1)
	parameter_panel._info.text="Настройки ветвления меняют каркас и привязанную к нему листву.\nСобери предпросмотр после изменения чисел."
	_build_optics_controls()
	_build_leaf_samples()
	_build_tree_leaf_trial()
	if tree_rim_enabled:set_tree_rim(true)
	print("TREE_FOLIAGE21_READY cards=",foliage21_inputs.cards," triangles=",foliage21_inputs.triangles," guides=",foliage21_inputs.groups)

func _update_tree(inputs: Dictionary) -> void:
	super._update_tree(inputs)
	var offset:=Vector3(inputs.pivot_bias.x,0,inputs.pivot_bias.y)
	foliage21_inputs=Branching.crown_cards(inputs.layout,inputs.structure,offset,16.0,7,{"branch_growth":true,"size":0.96})
	tree_leaf_density_cache.clear();tree_leaf_density_inputs={}
	tree_leaf_local_percent.clear();tree_leaf_group_source_id=0;tree_leaf_selected_group=-1
	if foliage21_cards==null:
		foliage21_cards=MeshInstance3D.new();foliage21_cards.name="BranchRootedFoliage21";smooth_tree.add_child(foliage21_cards)
	foliage21_cards.mesh=foliage21_inputs.mesh;foliage21_cards.position=parametric_wood.position
	foliage21_cards.visible=ready_for_foliage21 and leaf_cards_mode!=0
	_refresh_soft_bark()

func _refresh_soft_bark() -> void:
	# Keep every projection/support/light setting; replace only the LAB albedo.
	foliage21_soft_bark=parametric_painted.duplicate() as ShaderMaterial
	foliage21_soft_bark.set_shader_parameter("painted_bark_albedo",PaintedBark.artwork([SOFT_BARK,OAK_PAINTED_BARK,OAK_CALM_BARK][oak_bark_variant]))

func _recipe_preview(packed: PackedScene,source: EmberVoxelModelResource) -> void:
	super._recipe_preview(packed,source)
	if source==null and not baseline_foliage.is_empty():
		foliage21_inputs=baseline_foliage;foliage21_cards.mesh=baseline_foliage.mesh;foliage21_cards.position=parametric_wood.position
		tree_leaf_density_cache.clear();tree_leaf_density_inputs={}
		tree_leaf_local_percent.clear();tree_leaf_group_source_id=0;tree_leaf_selected_group=-1
		_refresh_soft_bark()
	set_leaf_cards_mode(leaf_cards_mode)

func set_material_revision(revision: int) -> void:
	material_revision=clampi(revision,0,MATERIAL_NAMES.size()-1)
	if material_revision==5 and leaf_samples!=null:
		leaf_samples.hide();leaf_sample_panel.hide()
	set_leaf_cards_mode(2)

func set_leaf_cards_mode(mode: int) -> void:
	if not ready_for_foliage21:
		super.set_leaf_cards_mode(mode);return
	super.set_leaf_cards_mode(2)
	leaf_cards_mode=clampi(mode,0,2)
	var displayed:=_tree_leaf_density() if material_revision==5 else foliage21_inputs
	foliage21_cards.mesh=displayed.mesh
	foliage21_cards.visible=leaf_cards_mode!=0 and int(displayed.cards)>0
	var painted:=foliage21_painted
	match material_revision:
		1,2:painted=foliage21_quiet
		3:painted=optical_materials[leaf_optics_mode]
		4:painted=foliage21_two_tones
		5:painted=tree_leaf_shared_material if tree_leaf_shared_light else tree_leaf_trial_material
	foliage21_plain.set_shader_parameter("painted_leaf_card_albedo",painted.get_shader_parameter("painted_leaf_card_albedo"))
	foliage21_cards.material_override=foliage21_plain if leaf_cards_mode==1 else painted
	parametric_wood.material_override=foliage21_soft_bark if material_revision>=2 else parametric_painted
	card_label.text=FOLIAGE_NAMES[leaf_cards_mode]+"\n"+MATERIAL_NAMES[material_revision]+"\nТот же каркас21 · "+str(displayed.cards)+" листовых плоскостей"
	if material_revision==3:card_label.text+="\n"+OPTICS_NAMES[leaf_optics_mode]
	if material_revision==5:card_label.text+="\nТени на листьях · %d%%"%roundi(tree_leaf_trial_strength*100)
	if tree_leaf_trial_panel!=null and not leaf_samples.visible:
		tree_leaf_trial_panel.visible=material_revision==5
		optics_panel.visible=material_revision!=5
		if material_revision==5:branch_controls.hide()
	_sync_tree_leaf_selection()
	_sync_tree_rim()

func _refresh_optics_values() -> void:
	for stage in optical_materials.size():
		var material:=optical_materials[stage]
		material.set_shader_parameter("painted_leaf_saturation",leaf_saturation if stage>=2 else 1.0)
		material.set_shader_parameter("painted_leaf_transmission",leaf_transmission if stage>=3 else 0.0)
		material.set_shader_parameter("painted_leaf_rim_weight",1.0 if stage>=3 else 0.0)
		material.set_shader_parameter("painterly_rim_enabled",stage>=3)
		material.set_shader_parameter("painterly_rim_strength",leaf_rim_strength)

func set_leaf_optics_mode(mode: int) -> void:
	leaf_optics_mode=clampi(mode,0,OPTICS_NAMES.size()-1)
	if optics_choice!=null:optics_choice.select(leaf_optics_mode)
	set_material_revision(3)

func set_leaf_optics_value(key: String,value: float) -> void:
	match key:
		"saturation":leaf_saturation=clampf(value,1.0,1.4)
		"transmission":leaf_transmission=clampf(value,0.0,0.8)
		"rim":leaf_rim_strength=clampf(value,0.0,0.5)
	_refresh_optics_values();set_leaf_cards_mode(leaf_cards_mode)

func _optics_slider_changed(value: float,key: String) -> void:
	set_leaf_optics_value(key,value)

func _build_optics_controls() -> void:
	branch_controls=parameter_panel.get_parent().get_parent() as Control
	branch_controls.hide()
	optics_panel=PanelContainer.new();optics_panel.position=Vector2(get_viewport().get_visible_rect().size.x-375,18)
	get_node("Instructions").add_child(optics_panel)
	var column:=VBoxContainer.new();column.custom_minimum_size.x=357;optics_panel.add_child(column)
	var title:=Label.new();title.text="Свет листвы · форма прежняя";column.add_child(title)
	optics_choice=OptionButton.new();column.add_child(optics_choice)
	for name in OPTICS_NAMES:optics_choice.add_item(name)
	optics_choice.select(leaf_optics_mode);optics_choice.item_selected.connect(set_leaf_optics_mode)
	for row in [["saturation","Насыщенность",1.0,1.4,leaf_saturation],["transmission","Просвечивание",0.0,0.8,leaf_transmission],["rim","Общая световая кромка",0.0,0.5,leaf_rim_strength]]:
		var label:=Label.new();label.text=row[1];column.add_child(label)
		var slider:=HSlider.new();slider.min_value=row[2];slider.max_value=row[3];slider.step=0.01;slider.value=row[4];column.add_child(slider)
		slider.value_changed.connect(_optics_slider_changed.bind(row[0]))
	var hint:=Label.new();hint.text="Просвечивание следует солнцу.\nНастоящие тени и мягкая кора сохранены.\nПросветы — отдельный вариант текстуры.";column.add_child(hint)
	var branch_button:=Button.new();branch_button.text="Показать настройки ветвления";column.add_child(branch_button)
	branch_button.pressed.connect(func():optics_panel.hide();branch_controls.show())
	var return_button:=Button.new();return_button.text="Вернуться к свету листвы";parameter_panel.get_parent().add_child(return_button)
	return_button.pressed.connect(func():branch_controls.hide();optics_panel.show())
	var sample_button:=Button.new();sample_button.text="Плоскость и группа · новая листва";column.add_child(sample_button)
	sample_button.pressed.connect(show_leaf_samples)

func _build_leaf_samples() -> void:
	# Inspect the material on extracted existing cards. The live tree is untouched.
	leaf_samples=Node3D.new();leaf_samples.name="LeafMaterialSamples";add_child(leaf_samples)
	leaf_samples.position=Vector3(40,6,0);leaf_samples.hide()
	var group_ids: Array[int]=[]
	var first_branch: int=foliage21_inputs.roots[0].branch
	for i in foliage21_inputs.roots.size():
		if int(foliage21_inputs.roots[i].branch)==first_branch and group_ids.size()<6:group_ids.append(i)
	for ids in [[0],group_ids]:
		var selected: Array[int]=[];selected.assign(ids)
		var node:=MeshInstance3D.new();node.mesh=_leaf_sample_mesh(selected)
		node.position.x=-1.65 if leaf_sample_nodes.is_empty() else 1.65
		node.scale=Vector3.ONE*1.9
		var first_normal: Vector3=foliage21_cards.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL][0]
		node.quaternion=Quaternion(first_normal.normalized(),Vector3.BACK)
		leaf_samples.add_child(node);leaf_sample_nodes.append(node)
	for stage in 3:
		var material:=optical_materials[4].duplicate() as ShaderMaterial
		if stage>0:material.set_shader_parameter("painted_leaf_card_albedo",PaintedBark.artwork(SEPARATE_LEAVES_ATLAS,true))
		if stage==2:
			material.set_shader_parameter("painted_leaf_saturation",1.0)
			material.set_shader_parameter("painterly_grass_low",0.24)
			material.set_shader_parameter("painterly_grass_shadow_fill",0.025)
			material.set_shader_parameter("painted_leaf_transmission",0.14)
			material.set_shader_parameter("painterly_rim_strength",0.07)
		leaf_sample_materials.append(material)
	leaf_sample_panel=PanelContainer.new();leaf_sample_panel.position=optics_panel.position
	get_node("Instructions").add_child(leaf_sample_panel);leaf_sample_panel.hide()
	var column:=VBoxContainer.new();column.custom_minimum_size.x=357;leaf_sample_panel.add_child(column)
	var title:=Label.new();title.text="Плоскость слева · группа справа";column.add_child(title)
	for stage in 3:
		var button:=Button.new();button.text=["До · цельное пятно","Отдельные листья · прежний свет","Отдельные листья · новый свет"][stage]
		column.add_child(button);button.pressed.connect(set_leaf_sample_stage.bind(stage))
	leaf_sample_shadow_label=Label.new();column.add_child(leaf_sample_shadow_label)
	leaf_sample_shadow_slider=HSlider.new();leaf_sample_shadow_slider.min_value=0.0
	leaf_sample_shadow_slider.max_value=1.0;leaf_sample_shadow_slider.step=0.01
	leaf_sample_shadow_slider.value=leaf_sample_shadow_strength;column.add_child(leaf_sample_shadow_slider)
	leaf_sample_shadow_slider.value_changed.connect(set_leaf_sample_shadow_strength)
	var reset_shadow:=Button.new();reset_shadow.text="Вернуть прежние тени · 100%";column.add_child(reset_shadow)
	reset_shadow.pressed.connect(set_leaf_sample_shadow_strength.bind(1.0))
	var shadow_hint:=Label.new();shadow_hint.text="Тени на листьях: внутренние и внешние.\nТень на земле сохраняется.";column.add_child(shadow_hint)
	var hint:=Label.new();hint.text="Те же плоскости, другой рисунок.\nНа дерево пока не переносим.\nПресеты и направление солнца — слева.";column.add_child(hint)
	var back:=Button.new();back.text="Вернуться к дереву";column.add_child(back)
	back.pressed.connect(hide_leaf_samples)
	set_leaf_sample_stage(2)
	set_leaf_sample_shadow_strength(1.0)

func _leaf_sample_mesh(card_ids: Array[int]) -> ArrayMesh:
	var source:=foliage21_cards.mesh.surface_get_arrays(0)
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
	for channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_CUSTOM0,Mesh.ARRAY_CUSTOM1]:
		arrays[channel]=source[channel].slice(0,0)
	var indices:=PackedInt32Array()
	for id in card_ids:
		var start: int=int(foliage21_inputs.roots[id].vertex)-7
		var base: int=arrays[Mesh.ARRAY_VERTEX].size()
		for channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_CUSTOM0,Mesh.ARRAY_CUSTOM1]:
			var stride:=4 if channel in [Mesh.ARRAY_CUSTOM0,Mesh.ARRAY_CUSTOM1] else 1
			arrays[channel].append_array(source[channel].slice(start*stride,(start+12)*stride))
		for index in source[Mesh.ARRAY_INDEX].slice(id*36,(id+1)*36):indices.append(base+index-start)
	var low:=Vector3.ONE*INF;var high:=Vector3.ONE*-INF
	for p in arrays[Mesh.ARRAY_VERTEX]:low=low.min(p);high=high.max(p)
	for i in arrays[Mesh.ARRAY_VERTEX].size():arrays[Mesh.ARRAY_VERTEX][i]-=(low+high)*0.5
	arrays[Mesh.ARRAY_INDEX]=indices
	var result:=ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)|(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT))
	return result

func set_leaf_sample_stage(stage: int) -> void:
	leaf_sample_stage=clampi(stage,0,2)
	for node in leaf_sample_nodes:node.material_override=leaf_sample_materials[leaf_sample_stage]
	if leaf_sample_shadow_slider!=null:leaf_sample_shadow_slider.editable=leaf_sample_stage==2

func set_leaf_sample_shadow_strength(value: float) -> void:
	# The new-light sample owns this trial; historical stages and the tree remain
	# intact. This uniform changes receiving light, never alpha or shadow casting.
	leaf_sample_shadow_strength=clampf(value,0.0,1.0)
	leaf_sample_materials[2].set_shader_parameter("painted_leaf_shadow_strength",leaf_sample_shadow_strength)
	if leaf_sample_shadow_slider!=null:leaf_sample_shadow_slider.set_value_no_signal(leaf_sample_shadow_strength)
	if leaf_sample_shadow_label!=null:leaf_sample_shadow_label.text="Сила теней на листьях · %d%%"%roundi(leaf_sample_shadow_strength*100)

func show_leaf_samples() -> void:
	if tree_leaf_trial_panel!=null:tree_leaf_trial_panel.hide()
	leaf_samples.show();optics_panel.hide();branch_controls.hide();leaf_sample_panel.show()
	_sync_tree_leaf_selection()
	follow_camera.set_process(false)
	var camera: Camera3D=follow_camera._cam
	camera.fov=38;camera.global_position=leaf_samples.global_position+Vector3(0,0.3,7.2)
	camera.look_at(leaf_samples.global_position)

func hide_leaf_samples() -> void:
	leaf_samples.hide();leaf_sample_panel.hide();optics_panel.show();set_network_view(1)
	set_leaf_cards_mode(leaf_cards_mode)

func _build_tree_leaf_trial() -> void:
	# Clone the inspected sample response. The full tree keeps its original mesh,
	# card transforms, UVs and macro normals; historical materials stay available.
	tree_leaf_trial_material=leaf_sample_materials[2].duplicate() as ShaderMaterial
	tree_leaf_trial_material.set_shader_parameter("painted_leaf_shadow_strength",tree_leaf_trial_strength)
	tree_leaf_selection=MeshInstance3D.new();tree_leaf_selection.name="SelectedCanopyPart"
	tree_leaf_selection.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tree_leaf_selection.gi_mode=GeometryInstance3D.GI_MODE_DISABLED;foliage21_cards.add_child(tree_leaf_selection)
	var selection_material:=StandardMaterial3D.new();selection_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	selection_material.albedo_color=Color(1.0,0.76,0.18);selection_material.no_depth_test=true
	tree_leaf_selection.material_override=selection_material;tree_leaf_selection.hide()
	tree_leaf_trial_panel=PanelContainer.new();tree_leaf_trial_panel.position=optics_panel.position
	get_node("Instructions").add_child(tree_leaf_trial_panel);tree_leaf_trial_panel.hide()
	get_node("Instructions").visibility_changed.connect(_sync_tree_leaf_selection)
	tree_leaf_trial_panel.visibility_changed.connect(_sync_tree_leaf_selection)
	var column:=VBoxContainer.new();column.custom_minimum_size.x=357;tree_leaf_trial_panel.add_child(column)
	tree_leaf_trial_label=Label.new();tree_leaf_trial_label.text="Отдельные листья · тени40%";column.add_child(tree_leaf_trial_label)
	for value in [0.4,0.35,1.0]:
		var button:=Button.new();button.text="Сила теней · %d%%"%roundi(value*100);column.add_child(button)
		button.pressed.connect(set_tree_leaf_trial_strength.bind(value))
	tree_leaf_density_label=Label.new();column.add_child(tree_leaf_density_label)
	tree_leaf_density_slider=HSlider.new();tree_leaf_density_slider.min_value=0
	tree_leaf_density_slider.max_value=100;tree_leaf_density_slider.step=5
	tree_leaf_density_slider.value=tree_leaf_density_percent;column.add_child(tree_leaf_density_slider)
	tree_leaf_density_slider.drag_started.connect(func():tree_leaf_density_dragging=true)
	tree_leaf_density_slider.value_changed.connect(_tree_leaf_density_pending)
	tree_leaf_density_slider.drag_ended.connect(_tree_leaf_density_released)
	tree_leaf_density_slider.gui_input.connect(_tree_leaf_density_key)
	tree_leaf_density_slider.focus_exited.connect(_commit_tree_leaf_density)
	var density_row:=HBoxContainer.new();column.add_child(density_row)
	for percent in [45,100]:
		var density_button:=Button.new();density_button.text="Пучки · %d%%"%percent;density_row.add_child(density_button)
		density_button.pressed.connect(set_tree_leaf_density.bind(percent))
	_tree_leaf_density_pending(tree_leaf_density_percent)
	tree_leaf_group_choice=OptionButton.new();column.add_child(tree_leaf_group_choice)
	tree_leaf_group_choice.item_selected.connect(func(index: int):set_tree_leaf_group(int(tree_leaf_group_choice.get_item_metadata(index))))
	tree_leaf_local_label=Label.new();column.add_child(tree_leaf_local_label)
	tree_leaf_local_slider=HSlider.new();tree_leaf_local_slider.min_value=0;tree_leaf_local_slider.max_value=100
	tree_leaf_local_slider.step=5;tree_leaf_local_slider.value=100;column.add_child(tree_leaf_local_slider)
	tree_leaf_local_slider.drag_started.connect(func():tree_leaf_local_dragging=true)
	tree_leaf_local_slider.value_changed.connect(func(value: float):tree_leaf_local_label.text="Пучки в выбранной части · %d%%"%roundi(value))
	tree_leaf_local_slider.drag_ended.connect(func(changed: bool):
		tree_leaf_local_dragging=false
		if changed:_commit_tree_leaf_local())
	tree_leaf_local_slider.focus_exited.connect(_commit_tree_leaf_local)
	tree_leaf_local_slider.gui_input.connect(func(event: InputEvent):
		if event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER,KEY_KP_ENTER]:
			_commit_tree_leaf_local();tree_leaf_local_slider.accept_event())
	tree_leaf_form_label=Label.new();column.add_child(tree_leaf_form_label)
	tree_leaf_form_slider=HSlider.new();tree_leaf_form_slider.min_value=0;tree_leaf_form_slider.max_value=100
	tree_leaf_form_slider.step=1;tree_leaf_form_slider.value=tree_leaf_form_depth;column.add_child(tree_leaf_form_slider)
	tree_leaf_form_slider.value_changed.connect(set_tree_leaf_form_depth)
	var form_row:=HBoxContainer.new();column.add_child(form_row)
	for depth in [100,60,25]:
		var form_button:=Button.new();form_button.text=["Прежняя","Мягче","Почти ровно"][[100,60,25].find(depth)]
		form_row.add_child(form_button);form_button.pressed.connect(set_tree_leaf_form_depth.bind(depth))
	var history_row:=HBoxContainer.new();column.add_child(history_row)
	for pair in [["Отменить",parameter_panel.undo_parameters],["Повторить",parameter_panel.redo_parameters],["Сброс частей/света",reset_tree_leaf_local]]:
		var history_button:=Button.new();history_button.text=pair[0];history_row.add_child(history_button);history_button.pressed.connect(pair[1])
	_refresh_tree_leaf_groups();_assign_tree_leaf_form_depth(tree_leaf_form_depth)
	tree_leaf_shared_button=Button.new();tree_leaf_shared_button.text="Сравнение · свет как у травы"
	column.add_child(tree_leaf_shared_button);column.move_child(tree_leaf_shared_button,0)
	tree_leaf_shared_button.tooltip_text="B — фиксированный профиль света. Изменение силы теней или глубины ниже возвращает A. Геометрия общая."
	tree_leaf_shared_button.pressed.connect(func():set_tree_leaf_shared_light(not tree_leaf_shared_light))
	tree_rim_button=Button.new();tree_rim_button.text="Световая кромка дерева · выкл"
	column.add_child(tree_rim_button);column.move_child(tree_rim_button,1)
	tree_rim_button.pressed.connect(func():set_tree_rim(not tree_rim_enabled))
	for spec in [["tree_rim_wood_strength","Кромка коры",tree_rim_wood_strength],["tree_rim_leaf_strength","Кромка кроны",tree_rim_leaf_strength]]:
		var row:=HBoxContainer.new();column.add_child(row);column.move_child(row,2 if spec[0]=="tree_rim_wood_strength" else 3)
		var label:=Label.new();label.text=spec[1];row.add_child(label)
		var slider:=HSlider.new();slider.min_value=0;slider.max_value=1;slider.step=0.01;slider.value=spec[2]
		slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(slider)
		slider.value_changed.connect(func(value: float):set(spec[0],value);set_tree_rim(true))
	oak_bark_choice=OptionButton.new()
	oak_bark_choice.add_item("Кора дуба · прежняя")
	oak_bark_choice.add_item("Кора дуба · крупные борозды")
	oak_bark_choice.add_item("Кора дуба · спокойные плоскости")
	oak_bark_choice.select(oak_bark_variant)
	oak_bark_choice.clip_text=true;oak_bark_choice.fit_to_longest_item=false
	oak_bark_choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	oak_bark_choice.item_selected.connect(set_oak_bark_variant)
	column.add_child(oak_bark_choice);column.move_child(oak_bark_choice,4)
	var previous:=Button.new();previous.text="Вернуть прежний материал дерева";column.add_child(previous)
	previous.pressed.connect(set_material_revision.bind(3))
	var hint:=Label.new();hint.text="Пучки остаются на прежних местах.\nПолзунок: отпустить или Enter.\nF1 — скрыть панели для осмотра.";column.add_child(hint)
	var sample_column:=leaf_sample_panel.get_child(0)
	var tree_button:=Button.new();tree_button.text="Посмотреть на дереве · тени40%";sample_column.add_child(tree_button)
	tree_button.pressed.connect(show_tree_leaf_trial.bind(0.4))

func set_tree_leaf_shared_light(enabled: bool) -> void:
	# A reversible LAB material override. Do not mutate the inspected Sol variant,
	# its controls, atlas, mesh, density, source paint or ground material.
	if enabled and tree_leaf_shared_material==null:
		tree_leaf_shared_material=tree_leaf_trial_material.duplicate() as ShaderMaterial
		var profile: Resource=load("res://content/terrain_materials/painted_light_grass.tres")
		for pair in [["low","low"],["cool","cool"],["warm","warm"],["tint_strength","tint_strength"],["shadow_color","shadow_color"],["shadow_fill","shadow_fill"]]:
			tree_leaf_shared_material.set_shader_parameter("painterly_grass_"+pair[0],profile.get("grass_light_"+pair[1]))
		# A crown has a visible underside: keep the common bands, with a deeper
		# low tone than the almost horizontal grass carpet (.64 -> .448).
		tree_leaf_shared_material.set_shader_parameter("painterly_grass_low",profile.grass_light_low*0.7)
		# New mesh pigment becomes the reference; retain deviations from that paint
		# instead of inheriting a colour multiplier from the old solid canopy.
		var colours: PackedColorArray=foliage21_inputs.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		var mean:=Vector3.ZERO
		for colour in colours:
			var linear:=colour.srgb_to_linear();mean+=Vector3(linear.r,linear.g,linear.b)
		mean/=maxi(colours.size(),1)
		tree_leaf_shared_material.set_shader_parameter("painted_foliage_paint_reference",mean)
		tree_leaf_shared_material.set_shader_parameter("painted_leaf_card_plain",profile.base_color)
		tree_leaf_shared_material.set_shader_parameter("painted_leaf_artwork_strength",0.18)
		tree_leaf_shared_material.set_shader_parameter("painted_leaf_saturation",1.0)
		tree_leaf_shared_material.set_shader_parameter("painted_leaf_transmission",0.06)
		tree_leaf_shared_material.set_shader_parameter("painterly_rim_strength",0.05)
	tree_leaf_shared_light=enabled
	if not enabled:tree_rim_enabled=false
	if tree_leaf_shared_button!=null:
		tree_leaf_shared_button.text="B · общий свет травы / вернуть A" if enabled else "A · прежняя листва / показать B"
	if tree_leaf_form_label!=null:
		tree_leaf_form_label.text="B · тёмный тон как у травы" if enabled else "Глубина тёмных участков · %d%%"%roundi(tree_leaf_form_depth)
	set_leaf_cards_mode(leaf_cards_mode)

func set_tree_rim(enabled: bool) -> void:
	# Both endpoints use the accepted leaf/grass look; no texture or form changes.
	if not tree_leaf_shared_light:set_tree_leaf_shared_light(true)
	tree_rim_enabled=enabled
	set_leaf_cards_mode(leaf_cards_mode)

func set_oak_bark_trial(enabled: bool) -> void:
	set_oak_bark_variant(2 if enabled else 0)

func set_oak_bark_variant(index: int) -> void:
	# Albedo only. Do not resync the tree/leaf controls or discard a Source rim binding.
	oak_bark_variant=clampi(index,0,2)
	var texture:=PaintedBark.artwork([SOFT_BARK,OAK_PAINTED_BARK,OAK_CALM_BARK][oak_bark_variant])
	for material in [foliage21_soft_bark,tree_rim_wood_material]:
		if material!=null:material.set_shader_parameter("painted_bark_albedo",texture)
	if oak_bark_choice!=null:oak_bark_choice.select(oak_bark_variant)

func _sync_tree_rim() -> void:
	if tree_leaf_shared_material==null or parametric_wood==null:return
	var active:=tree_rim_enabled and tree_leaf_shared_light and material_revision==5 and leaf_cards_mode==2
	# LAB controls remain temporary comparisons; Source binding is applied explicitly
	# after this hook and never leaks into a historical variant or legacy slider.
	tree_leaf_shared_material.set_shader_parameter("object_style_rim_profiles_enabled",false)
	if tree_rim_wood_material!=null:tree_rim_wood_material.set_shader_parameter("object_style_rim_profiles_enabled",false)
	tree_leaf_shared_material.set_shader_parameter("object_style_rim_enabled",active)
	tree_leaf_shared_material.set_shader_parameter("object_style_rim_strength",tree_rim_leaf_strength)
	if active:
		# set_leaf_cards_mode restores the base wood material before this hook.
		var source:=parametric_wood.material_override as ShaderMaterial
		if tree_rim_wood_source!=source:
			tree_rim_wood_source=source;tree_rim_wood_material=source.duplicate() as ShaderMaterial
		tree_rim_wood_material.set_shader_parameter("object_style_rim_enabled",true)
		tree_rim_wood_material.set_shader_parameter("object_style_rim_strength",tree_rim_wood_strength)
		parametric_wood.material_override=tree_rim_wood_material
	if tree_rim_button!=null:tree_rim_button.text="Световая кромка дерева · вкл" if active else "Световая кромка дерева · выкл"

func set_tree_leaf_trial_strength(value: float) -> void:
	if tree_leaf_trial_material==null:return
	if tree_leaf_shared_light:set_tree_leaf_shared_light(false)
	tree_leaf_trial_strength=clampf(value,0.0,1.0)
	tree_leaf_trial_material.set_shader_parameter("painted_leaf_shadow_strength",tree_leaf_trial_strength)
	if tree_leaf_trial_label!=null:tree_leaf_trial_label.text="Отдельные листья · тени%d%%"%roundi(tree_leaf_trial_strength*100)
	set_material_revision(5)

func show_tree_leaf_trial(strength:=0.4) -> void:
	set_tree_leaf_trial_strength(strength);set_network_view(1)

func _tree_leaf_density() -> Dictionary:
	_refresh_tree_leaf_groups()
	var local_key:="";var factors: Dictionary={}
	for owner in tree_leaf_group_ids:
		if tree_leaf_local_percent.has(owner):
			local_key+="%d=%d;"%[owner,tree_leaf_local_percent[owner]];factors[owner]=float(tree_leaf_local_percent[owner])/100.0
	var key: String="%d:%d:%s"%[foliage21_inputs.mesh.get_instance_id(),tree_leaf_density_percent,local_key]
	if not tree_leaf_density_cache.has(key):
		var started:=Time.get_ticks_usec()
		tree_leaf_density_cache[key]=Branching.thin_crown_cards(foliage21_inputs,float(tree_leaf_density_percent)/100.0,factors)
		tree_leaf_density_build_ms=float(Time.get_ticks_usec()-started)/1000.0
		tree_leaf_density_builds+=1
	tree_leaf_density_inputs=tree_leaf_density_cache[key]
	return tree_leaf_density_inputs

func set_tree_leaf_density(percent: float) -> void:
	tree_leaf_density_percent=clampi(roundi(percent),0,100)
	if tree_leaf_density_slider!=null:tree_leaf_density_slider.set_value_no_signal(tree_leaf_density_percent)
	set_material_revision(5)
	if tree_leaf_density_label!=null:
		var puffs: int=tree_leaf_density_inputs.get("puffs",Branching.crown_puff_count(foliage21_inputs))
		tree_leaf_density_label.text="Количество пучков · %d%% · %d"%[tree_leaf_density_percent,puffs]

func _tree_leaf_density_pending(percent: float) -> void:
	if tree_leaf_density_label!=null:tree_leaf_density_label.text="Количество пучков · %d%%"%roundi(percent)

func _tree_leaf_density_released(changed: bool) -> void:
	tree_leaf_density_dragging=false
	if changed:_commit_tree_leaf_density()

func _tree_leaf_density_key(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER,KEY_KP_ENTER]:
		_commit_tree_leaf_density();tree_leaf_density_slider.accept_event()

func _commit_tree_leaf_density() -> void:
	if not tree_leaf_density_dragging and tree_leaf_density_slider!=null:
		set_tree_leaf_density(tree_leaf_density_slider.value)

func _refresh_tree_leaf_groups() -> void:
	var source_id: int=foliage21_inputs.mesh.get_instance_id()
	if tree_leaf_group_source_id==source_id:return
	tree_leaf_group_source_id=source_id;tree_leaf_groups=Branching.crown_leaf_groups(foliage21_inputs)
	tree_leaf_group_ids.clear()
	for owner: int in tree_leaf_groups:tree_leaf_group_ids.append(owner)
	tree_leaf_group_ids.sort_custom(func(a: int,b: int):return (tree_leaf_groups[a].low.x+tree_leaf_groups[a].high.x)<(tree_leaf_groups[b].low.x+tree_leaf_groups[b].high.x))
	if tree_leaf_group_choice!=null:
		tree_leaf_group_choice.clear();tree_leaf_group_choice.add_item("Часть кроны · без выделения")
		tree_leaf_group_choice.set_item_metadata(0,-1)
		for i in tree_leaf_group_ids.size():
			tree_leaf_group_choice.add_item("Часть %d · выбрать рамкой"%[i+1]);tree_leaf_group_choice.set_item_metadata(i+1,tree_leaf_group_ids[i])
		set_tree_leaf_group(-1)

func set_tree_leaf_group(owner: int) -> void:
	tree_leaf_selected_group=owner if tree_leaf_groups.has(owner) else -1
	if tree_leaf_group_choice!=null:
		for i in tree_leaf_group_choice.item_count:
			if int(tree_leaf_group_choice.get_item_metadata(i))==tree_leaf_selected_group:tree_leaf_group_choice.select(i);break
	var valid:=tree_leaf_selected_group>=0
	if tree_leaf_local_slider!=null:
		tree_leaf_local_slider.editable=valid;tree_leaf_local_slider.set_value_no_signal(tree_leaf_local_percent.get(owner,100))
	if tree_leaf_local_label!=null:tree_leaf_local_label.text="Пучки в выбранной части · %d%%"%tree_leaf_local_percent.get(owner,100) if valid else "Выбери часть кроны для прореживания"
	if tree_leaf_selection!=null and valid:
		var group: Dictionary=tree_leaf_groups[owner]
		var box:=AABB(group.low,(group.high as Vector3)-(group.low as Vector3)).grow(0.08)
		var wire:=ImmediateMesh.new();wire.surface_begin(Mesh.PRIMITIVE_LINES)
		for pair in [[0,1],[0,2],[0,4],[1,3],[1,5],[2,3],[2,6],[3,7],[4,5],[4,6],[5,7],[6,7]]:
			wire.surface_add_vertex(box.get_endpoint(pair[0]));wire.surface_add_vertex(box.get_endpoint(pair[1]))
		wire.surface_end();tree_leaf_selection.mesh=wire
	_sync_tree_leaf_selection()

func _sync_tree_leaf_selection() -> void:
	if tree_leaf_selection!=null:
		tree_leaf_selection.visible=material_revision==5 and tree_leaf_selected_group>=0 and tree_leaf_trial_panel!=null and tree_leaf_trial_panel.is_visible_in_tree() and not leaf_samples.visible

func _commit_tree_leaf_local() -> void:
	if not tree_leaf_local_dragging and tree_leaf_selected_group>=0:set_tree_leaf_local_percent(tree_leaf_selected_group,tree_leaf_local_slider.value)

func set_tree_leaf_local_percent(owner: int,percent: float) -> void:
	if not tree_leaf_groups.has(owner):return
	var value:=clampi(roundi(percent),0,100);var before: int=tree_leaf_local_percent.get(owner,100)
	if value==before:return
	parameter_panel.history.create_action("Пучки выбранной части кроны")
	parameter_panel.history.add_do_method(_assign_tree_leaf_local.bind(owner,value))
	parameter_panel.history.add_undo_method(_assign_tree_leaf_local.bind(owner,before));parameter_panel.history.commit_action()

func _assign_tree_leaf_local(owner: int,percent: int) -> void:
	if percent==100:tree_leaf_local_percent.erase(owner)
	else:tree_leaf_local_percent[owner]=percent
	set_tree_leaf_density(tree_leaf_density_percent);set_tree_leaf_group(tree_leaf_selected_group)

func set_tree_leaf_form_depth(depth: float) -> void:
	if tree_leaf_shared_light:set_tree_leaf_shared_light(false)
	var value:=clampf(depth,0,100)
	if is_equal_approx(value,tree_leaf_form_depth):return
	parameter_panel.history.create_action("Глубина тёмных участков",UndoRedo.MERGE_ENDS)
	parameter_panel.history.add_do_method(_assign_tree_leaf_form_depth.bind(value))
	parameter_panel.history.add_undo_method(_assign_tree_leaf_form_depth.bind(tree_leaf_form_depth));parameter_panel.history.commit_action()

func _assign_tree_leaf_form_depth(depth: float) -> void:
	if tree_leaf_shared_light:set_tree_leaf_shared_light(false)
	tree_leaf_form_depth=depth
	tree_leaf_trial_material.set_shader_parameter("painterly_grass_low",lerpf(1.0,0.24,depth/100.0))
	if tree_leaf_form_slider!=null:tree_leaf_form_slider.set_value_no_signal(depth)
	if tree_leaf_form_label!=null:tree_leaf_form_label.text="Глубина тёмных участков · %d%%"%roundi(depth)
	set_material_revision(5)

func reset_tree_leaf_local() -> void:
	parameter_panel.history.create_action("Сброс локальной листвы и света")
	parameter_panel.history.add_do_method(_restore_tree_leaf_local.bind({},100.0))
	parameter_panel.history.add_undo_method(_restore_tree_leaf_local.bind(tree_leaf_local_percent.duplicate(),tree_leaf_form_depth));parameter_panel.history.commit_action()

func _restore_tree_leaf_local(local: Dictionary,depth: float) -> void:
	tree_leaf_local_percent=local.duplicate();_assign_tree_leaf_form_depth(depth)
	set_tree_leaf_density(tree_leaf_density_percent);set_tree_leaf_group(tree_leaf_selected_group)

func _build_card_controls() -> void:
	super._build_card_controls()
	var column:=card_label.get_parent()
	for i in 3:(column.get_child(i+1) as Button).text=FOLIAGE_NAMES[i]
	var heading:=Label.new();heading.text="Рисунок материалов · форма прежняя";column.add_child(heading)
	for i in MATERIAL_NAMES.size():
		var button:=Button.new();button.text=MATERIAL_NAMES[i];column.add_child(button)
		button.pressed.connect(set_material_revision.bind(i))

func set_network_view(view: int) -> void:
	if not ready_for_foliage21 or view in [0,4]:
		super.set_network_view(view);return
	follow_camera.set_process(false)
	var camera: Camera3D=follow_camera._cam
	var target:=smooth_tree.global_position+Vector3(0,3.5,0)
	var offset: Vector3=[Vector3(2,-0.4,13),Vector3(-13,-0.4,2),Vector3(-2,-0.4,-13)][view-1]
	camera.fov=40;camera.global_position=target+offset;camera.look_at(target)


func apply_tree_material_rim(source: EmberVoxelModelResource) -> void:
	if source==null:return
	if not tree_leaf_shared_light:set_tree_leaf_shared_light(true)
	# Refresh the existing clones before binding the saved profile; keep artwork,
	# light response B, normals, geometry and softened receiving shadows intact.
	set_tree_rim(true)
	var profiles=preload("res://scripts/ember_voxel_material_profiles.gd")
	profiles.apply_rim(tree_leaf_shared_material,source.material)
	profiles.apply_rim(tree_rim_wood_material,source.material)
	get_node("Map").refresh_style_rim()
