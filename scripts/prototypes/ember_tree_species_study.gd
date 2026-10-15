extends "res://scripts/prototypes/ember_tree_foliage21_study.gd"
const Species=preload("res://scripts/prototypes/ember_tree_species_fixture.gd")
const SpeciesProfiles=preload("res://scripts/ember_voxel_material_profiles.gd")
var species_inputs: Array[Dictionary]=[]
var species_roots: Array[Node3D]=[]
var birch_inputs: Dictionary
var birch_root: Node3D
var birch_wood: MeshInstance3D
var birch_leaves: MeshInstance3D
var birch_plain: ShaderMaterial
var birch_painted: ShaderMaterial
var birch_recipe_panel: VBoxContainer
var species_panel: PanelContainer
var species_label: Label
var species_ready:=false
var species_kind:=2
var birch_revision:=2
var species_mode:=2
var birch_build_ms:=0.0
var birch_baseline: Dictionary
var birch_controls_panel: PanelContainer
var birch_tabs: TabContainer
var birch_settings: Dictionary={"density":60.0,"depth":100.0,"receive":40.0,"wood_rim":45.0,"leaf_rim":18.0,"rim_on":1.0}
var birch_sliders: Dictionary={}
var birch_setting_labels: Dictionary={}
var birch_dragging: Dictionary={}
var birch_parts: OptionButton
var birch_selected_part:=-1
var birch_crown_groups: Dictionary={}
var birch_leaf_cache: Dictionary={}
var birch_density_builds:=0
var birch_rim_toggle: CheckButton
var birch_base_low:=0.448

# One controller for the species trials. Birch remains the default scene;
# subclasses supply only species identity/artwork/provider input.
func trial_kind() -> int:return 2
func trial_title() -> String:return "Берёза22"
func trial_short_title() -> String:return "Берёза"
func trial_inputs() -> Dictionary:return Species.birch()
func trial_art() -> String:return Species.BIRCH_ART
func trial_bark() -> String:return Species.BIRCH_BARK
func trial_card_size() -> float:return 0.64
func trial_card_options() -> Dictionary:return {"branch_growth":true,"size":trial_card_size()}
func trial_reset_caption() -> String:return "Вернуть принятый вид"
func trial_field_keys() -> Array[String]:return KEYS
func trial_recipe_directory() -> String:return "user://birch22-lab"

func prepare() -> void:
	await super.prepare()
	show_tree_leaf_trial(0.4);set_tree_leaf_shared_light(true);set_tree_rim(true)
	parametric_inputs.source.material=SpeciesProfiles.with_rim(parametric_inputs.source.material,"bark",true,0.45)
	parametric_inputs.source.material=SpeciesProfiles.with_rim(parametric_inputs.source.material,"foliage",true,0.18)
	apply_tree_material_rim(parametric_inputs.source)
	for kind in 5:
		var inputs:=Species.legacy(kind)
		species_inputs.append(inputs)
		var holder:=Node3D.new();holder.name="ExistingSpecies%d"%kind;smooth_tree.add_child(holder)
		holder.position=Vector3(restored_inputs.pivot_bias.x-inputs.pivot_bias.x,0,restored_inputs.pivot_bias.y-inputs.pivot_bias.y)/16.0
		var branch:=MeshInstance3D.new();branch.name="Wood";branch.mesh=PaintedBark.mesh(inputs.wood,inputs.structure,inputs.pivot_bias)
		var material:=PaintedBark.material(inputs.structure,inputs.pivot_bias,Species.BIRCH_BARK if kind==2 else OAK_CALM_BARK)
		if kind!=2:material.set_shader_parameter("painted_bark_enabled",false)
		material.set_shader_parameter("object_style_rim_enabled",true);material.set_shader_parameter("object_style_rim_strength",0.45)
		branch.material_override=material;holder.add_child(branch)
		var leaves:=MeshInstance3D.new();leaves.name="Leaves";leaves.mesh=inputs.leaves
		var leaf_material:=EmberVoxelPrefab.voxel_material().duplicate() as ShaderMaterial
		leaf_material.set_shader_parameter("surface_grain_scale",0.0)
		leaves.material_override=leaf_material;holder.add_child(leaves);holder.hide();species_roots.append(holder)
	_update_birch(trial_inputs())
	birch_baseline=birch_inputs
	var directory:=trial_recipe_directory()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var recipe:=Recipe.new();recipe.generator_id="large_tree";recipe.seed=7
	recipe.parameters=birch_inputs.parameters;recipe.structure=birch_inputs.structure
	assert(ResourceSaver.save(recipe,directory.path_join(birch_inputs.source.model_id+".tres"))==OK)
	for child in get_node("Instructions").get_children():
		if child is CanvasItem:child.hide()
	_build_species_controls(directory)
	species_ready=true;choose_species(trial_kind());set_species_view(1)
	print("SPECIES_READY ",trial_title()," branches=",birch_inputs.layout.size()," cards=",birch_inputs.leaves.cards)

func _build_species_controls(directory: String) -> void:
	species_panel=PanelContainer.new();species_panel.position=Vector2(18,18);get_node("Instructions").add_child(species_panel)
	var column:=VBoxContainer.new();column.custom_minimum_size.x=300;species_panel.add_child(column)
	species_label=Label.new();column.add_child(species_label)
	for kind in 5:
		var button:=Button.new();button.text=["Саванна · прежние массы","Дуб · принятая основа C","Берёза · сравнение","Клён · прежние массы","Ель · прежние массы"][kind]
		if kind==trial_kind():button.text=trial_short_title()+" · сравнение"
		column.add_child(button);button.pressed.connect(choose_species.bind(kind))
	for pair in [["A · "+Species.NAMES[trial_kind()]+" · прежние массы",0],["Б · новый силуэт без рисунка",1],["В · своя листва и кора",2]]:
		var button:=Button.new();button.text=pair[0];column.add_child(button);button.pressed.connect(set_birch_revision.bind(pair[1]))
	var bare:=Button.new();bare.text=trial_short_title()+" · показать ветви";column.add_child(bare)
	bare.pressed.connect(func():species_mode=2 if species_mode==0 else 0;set_birch_revision(2))
	for pair in [["Вечер",0],["День",1],["Ночь",2]]:
		var button:=Button.new();button.text=pair[0];column.add_child(button);button.pressed.connect(set_lighting_preset.bind(pair[1]))
	var pose:=Button.new();pose.text="Боковой / контровой свет";column.add_child(pose)
	pose.pressed.connect(func():set_sun_pose(0 if _sun_pose==1 else 1))
	for pair in [["Игровая камера",0],["Дерево целиком",1],["Слева",2],["Сзади",3]]:
		var button:=Button.new();button.text=pair[0];column.add_child(button);button.pressed.connect(set_species_view.bind(pair[1]))
	var hint:=Label.new();hint.text="1–3 · варианты   L/P · свет   F1 · UI";column.add_child(hint)
	var box:=PanelContainer.new();box.position=Vector2(get_viewport().get_visible_rect().size.x-335,18);box.custom_minimum_size=Vector2(317,500);get_node("Instructions").add_child(box)
	birch_controls_panel=box
	birch_tabs=TabContainer.new();birch_tabs.custom_minimum_size=Vector2(317,680);box.add_child(birch_tabs)
	birch_recipe_panel=RecipePanel.new();birch_recipe_panel.name="Ветви";birch_recipe_panel.recipe_directory=directory;birch_tabs.add_child(birch_recipe_panel)
	assert(birch_recipe_panel.open_source(birch_inputs.source,{"field_keys":trial_field_keys()}))
	birch_recipe_panel._save_mode.hide();birch_recipe_panel._variation_name.hide();birch_recipe_panel._save_button.hide()
	birch_recipe_panel.preview_changed.connect(_birch_recipe_preview)
	birch_recipe_panel._info.text=trial_short_title()+" · ветвление.\nПодготовь предпросмотр после правок."
	_build_birch_leaf_controls()

func _update_birch(inputs: Dictionary) -> void:
	var started:=Time.get_ticks_msec();birch_inputs=inputs
	if birch_root==null:
		birch_root=Node3D.new();birch_root.name="SpeciesTrial";smooth_tree.add_child(birch_root)
		birch_wood=MeshInstance3D.new();birch_wood.name="Wood";birch_root.add_child(birch_wood)
		birch_leaves=MeshInstance3D.new();birch_leaves.name="BranchAttachedLeaves";birch_root.add_child(birch_leaves)
	birch_root.position=Vector3(restored_inputs.pivot_bias.x-inputs.pivot_bias.x,0,restored_inputs.pivot_bias.y-inputs.pivot_bias.y)/16.0
	birch_wood.mesh=PaintedBark.mesh(inputs.wood,inputs.structure,inputs.pivot_bias)
	var bark_material:=PaintedBark.material(inputs.structure,inputs.pivot_bias,trial_bark())
	inputs.source.material=SpeciesProfiles.with_rim(inputs.source.material,"bark",true,0.45)
	inputs.source.material=SpeciesProfiles.with_rim(inputs.source.material,"foliage",true,0.18)
	SpeciesProfiles.apply_rim(bark_material,inputs.source.material);birch_wood.material_override=bark_material
	birch_leaves.mesh=inputs.leaves.mesh
	birch_painted=tree_leaf_shared_material.duplicate() as ShaderMaterial
	birch_painted.set_shader_parameter("painted_leaf_card_albedo",PaintedBark.artwork(trial_art(),true))
	SpeciesProfiles.apply_rim(birch_painted,inputs.source.material)
	birch_plain=birch_painted.duplicate() as ShaderMaterial
	birch_plain.set_shader_parameter("painted_leaf_card_coloured",false)
	birch_plain.set_shader_parameter("painted_leaf_card_plain",Color("659b42"))
	birch_leaves.material_override=birch_painted;birch_build_ms=Time.get_ticks_msec()-started
	birch_base_low=float(tree_leaf_shared_material.get_shader_parameter("painterly_grass_low"))
	birch_leaf_cache.clear();birch_crown_groups=Branching.crown_leaf_groups(inputs.full_leaves)
	birch_selected_part=-1
	for key: String in birch_settings.keys():
		if key.begins_with("part:"):birch_settings.erase(key)
	_sync_birch_parts();_apply_birch_settings()
	if species_ready:choose_species(trial_kind())

func _birch_recipe_preview(_packed: PackedScene,source: EmberVoxelModelResource) -> void:
	if source==null:_update_birch(birch_baseline)
	else:
		var prepared=birch_recipe_panel.creation
		var p: Dictionary=prepared.recipe.parameters
		var inputs:=Branching.from_built(prepared.report,p,prepared.recipe.seed)
		var offset:=Vector3(inputs.pivot_bias.x,0,inputs.pivot_bias.y)
		inputs["full_leaves"]=Branching.crown_cards(inputs.layout,inputs.structure,offset,16.0,prepared.recipe.seed,trial_card_options())
		inputs["leaves"]=Branching.thin_crown_cards(inputs.full_leaves,0.60)
		_update_birch(inputs)
	set_birch_revision(2)

func choose_species(kind: int) -> void:
	species_kind=clampi(kind,0,4)
	for node in [parametric_wood,foliage21_cards,network_wood,branching_wood,branching_cards,wood,card_visual]:node.hide()
	for node in species_roots:node.hide()
	birch_root.hide()
	if kind==1:
		parametric_wood.show();foliage21_cards.show();species_label.text="Дуб21 · B · кора C · 45%"
	elif kind==trial_kind() and birch_revision>0:
		birch_root.show();birch_leaves.visible=species_mode!=0 and birch_inputs.leaves.cards>0
		birch_leaves.material_override=birch_plain if birch_revision==1 else birch_painted
		species_label.text=trial_title()+" · %d ветвей\n%d плоскостей · просветы"%[birch_inputs.layout.size(),birch_inputs.leaves.cards]
	else:
		species_roots[kind].show();species_label.text=Species.NAMES[kind]+" · прежние опоры кроны"
	if birch_controls_panel!=null:birch_controls_panel.visible=kind==trial_kind()
	get_node("Map").refresh_style_rim()

func set_birch_revision(revision: int) -> void:
	birch_revision=clampi(revision,0,2);choose_species(trial_kind())
func set_species_view(view: int) -> void:
	set_network_view(view)

func _build_birch_leaf_controls() -> void:
	var column:=VBoxContainer.new();column.name="Листва и свет";birch_tabs.add_child(column)
	for row in [["density","Количество листвы"],["local","В выбранной части"],["depth","Глубина тёмных участков"],["receive","Приём теней"],["wood_rim","Кромка коры"],["leaf_rim","Кромка листвы"]]:
		if row[0]=="local":
			birch_parts=OptionButton.new();birch_parts.fit_to_longest_item=false;birch_parts.clip_text=true;column.add_child(birch_parts)
			birch_parts.item_selected.connect(func(index: int):birch_selected_part=int(birch_parts.get_item_metadata(index));_sync_birch_controls())
		var label:=Label.new();label.text=row[1];column.add_child(label);birch_setting_labels[row[0]]=label
		var slider:=HSlider.new();slider.min_value=0;slider.max_value=100;slider.step=5 if row[0] in ["density","local","depth","receive"] else 1
		column.add_child(slider);birch_sliders[row[0]]=slider
		slider.set_meta("caption",row[1]);birch_dragging[row[0]]=false
		slider.drag_started.connect(func():birch_dragging[row[0]]=true)
		slider.value_changed.connect(func(_value: float):
			birch_setting_labels[row[0]].text="%s · %d%%"%[row[1],slider.value]
			if not birch_dragging[row[0]]:_commit_birch_slider(row[0]))
		slider.drag_ended.connect(func(_changed: bool):birch_dragging[row[0]]=false;_commit_birch_slider(row[0]))
		slider.focus_exited.connect(func():
			if not birch_dragging[row[0]]:_commit_birch_slider(row[0]))
		slider.gui_input.connect(func(event: InputEvent):
			if event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER,KEY_KP_ENTER]:
				birch_dragging[row[0]]=false;_commit_birch_slider(row[0]))
	birch_rim_toggle=CheckButton.new();birch_rim_toggle.text="Световая кромка";column.add_child(birch_rim_toggle)
	birch_rim_toggle.toggled.connect(func(on: bool):set_birch_setting("rim_on",1.0 if on else 0.0))
	var reset:=Button.new();reset.text=trial_reset_caption();column.add_child(reset)
	reset.pressed.connect(reset_birch_settings)
	var hint:=Label.new();hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	hint.text="Ползунок: отпустить или Enter. Undo/Redo — вкладка Ветви. Приём теней меняет и внутреннее, и внешнее затенение. Настройки листвы пока только LAB.";column.add_child(hint)
	_sync_birch_parts();_sync_birch_controls()

func _sync_birch_parts() -> void:
	if birch_parts==null:return
	birch_parts.clear();birch_parts.add_item("Вся крона · выбери часть");birch_parts.set_item_metadata(0,-1)
	var ids:=birch_crown_groups.keys();ids.sort()
	for id: int in ids:
		birch_parts.add_item("Часть %d · ветвь %d"%[birch_parts.item_count,id]);birch_parts.set_item_metadata(birch_parts.item_count-1,id)
	birch_parts.select(0)

func _commit_birch_slider(key: String) -> void:
	if key=="local" and birch_selected_part<0:return
	set_birch_setting("part:%d"%birch_selected_part if key=="local" else key,birch_sliders[key].value)

func set_birch_setting(key: String,value: float) -> void:
	if not birch_settings.has(key) and not key.begins_with("part:"):return
	if key.begins_with("part:") and not birch_crown_groups.has(int(key.trim_prefix("part:"))):return
	value=clampf(value,0,100)
	if key=="rim_on":value=1.0 if value>0 else 0.0
	var before:=float(birch_settings.get(key,100.0))
	if is_equal_approx(value,before):return
	var history: UndoRedo=birch_recipe_panel.history
	history.create_action(trial_short_title()+" · настройки листвы")
	var source_id: int=birch_inputs.source.get_instance_id()
	history.add_do_method(_assign_birch_setting.bind(key,value,source_id));history.add_undo_method(_assign_birch_setting.bind(key,before,source_id));history.commit_action()

func _assign_birch_setting(key: String,value: float,source_id: int) -> void:
	if key.begins_with("part:") and source_id!=birch_inputs.source.get_instance_id():return
	if key.begins_with("part:") and not birch_crown_groups.has(int(key.trim_prefix("part:"))):return
	birch_settings[key]=value;_apply_birch_settings();_sync_birch_controls()
	if species_ready:choose_species(species_kind)

func _apply_birch_settings() -> void:
	var local: Dictionary={}
	for key: String in birch_settings:
		if key.begins_with("part:"):local[int(key.trim_prefix("part:"))]=float(birch_settings[key])/100.0
	var cache_key:=JSON.stringify([birch_settings.density,local])
	if not birch_leaf_cache.has(cache_key):
		if birch_leaf_cache.size()>=32:birch_leaf_cache.clear()
		birch_leaf_cache[cache_key]=Branching.thin_crown_cards(birch_inputs.full_leaves,birch_settings.density/100.0,local);birch_density_builds+=1
	birch_inputs.leaves=birch_leaf_cache[cache_key];birch_leaves.mesh=birch_inputs.leaves.mesh
	var low:=lerpf(1.0,birch_base_low,birch_settings.depth/100.0)
	for material: ShaderMaterial in [birch_plain,birch_painted]:
		material.set_shader_parameter("painterly_grass_low",low)
		material.set_shader_parameter("painted_leaf_shadow_strength",birch_settings.receive/100.0)
		material.set_shader_parameter("object_style_rim_enabled",birch_settings.rim_on>0)
	var profile:=SpeciesProfiles.with_rim(birch_inputs.source.material,"bark",birch_settings.rim_on>0,birch_settings.wood_rim/100.0)
	profile=SpeciesProfiles.with_rim(profile,"foliage",birch_settings.rim_on>0,birch_settings.leaf_rim/100.0)
	birch_inputs.source.material=profile
	for material: ShaderMaterial in [birch_plain,birch_painted,birch_wood.material_override]:SpeciesProfiles.apply_rim(material,profile)
	birch_leaves.visible=species_mode!=0 and birch_inputs.leaves.cards>0

func _sync_birch_controls() -> void:
	for key: String in birch_sliders:
		var value:=float(birch_settings.get("part:%d"%birch_selected_part,100)) if key=="local" else float(birch_settings[key])
		birch_sliders[key].set_value_no_signal(value)
		birch_setting_labels[key].text="%s · %d%%"%[birch_sliders[key].get_meta("caption"),value]
		if key=="local":birch_sliders[key].editable=birch_selected_part>=0
	if birch_rim_toggle!=null:birch_rim_toggle.set_pressed_no_signal(birch_settings.rim_on>0)

func reset_birch_settings() -> void:
	var history: UndoRedo=birch_recipe_panel.history
	history.create_action(trial_short_title()+" · исходный вид")
	history.add_do_method(_restore_birch_settings.bind({"density":60.0,"depth":100.0,"receive":40.0,"wood_rim":45.0,"leaf_rim":18.0,"rim_on":1.0}))
	history.add_undo_method(_restore_birch_settings.bind(birch_settings.duplicate(),birch_inputs.source.get_instance_id()));history.commit_action()

func _restore_birch_settings(settings: Dictionary,source_id:=0) -> void:
	birch_settings=settings.duplicate()
	if source_id!=birch_inputs.source.get_instance_id():
		for key: String in birch_settings.keys():
			if key.begins_with("part:"):birch_settings.erase(key)
	_apply_birch_settings();_sync_birch_controls();choose_species(species_kind)
func _unhandled_input(event: InputEvent) -> void:
	if species_ready and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_1,KEY_2,KEY_3]:set_birch_revision(event.keycode-KEY_1);return
		if event.keycode==KEY_L:set_lighting_preset(lighting_preset+1);return
		if event.keycode==KEY_P:set_sun_pose(_sun_pose+1);return
		if event.keycode==KEY_F1:get_node("Instructions").visible=not get_node("Instructions").visible;return
	super._unhandled_input(event)
