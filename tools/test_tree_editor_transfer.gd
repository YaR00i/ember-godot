extends SceneTree
const Generator=preload("res://addons/ember_import/ember_voxel_generator.gd")
const Creation=preload("res://addons/ember_import/ember_voxel_tree_object_creation.gd")
const RecipePanel=preload("res://addons/ember_import/ember_voxel_generator_panel.gd")
const GenerationPanel=preload("res://addons/ember_import/ember_voxel_generation_panel.gd")
const Species=preload("res://scripts/ember_tree_species.gd")
const Geometry=preload("res://scripts/ember_tree_surface_geometry.gd")
const Surface=preload("res://scripts/ember_tree_surface.gd")
var errors: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:errors.append(message);push_error(message)
func run() -> void:
	if OS.get_cmdline_user_args().has("--paint-only"):
		var sample:=Creation.new();check(sample.prepare_recipe(Generator.creation_presets(Generator.LARGE_TREE)[2].recipe,"Paint"),"paint fixture")
		var sample_node:=sample.packed.instantiate()
		paint_checks(sample.source,sample_node.get_node("Mesh").mesh,"user://")
		sample_node.free();print("TREE_EDITOR_TRANSFER ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1);return
	var presets:=Generator.creation_presets(Generator.LARGE_TREE)
	check(presets.size()==5,"five ordinary creation presets")
	var expected: Array[String]=["b2c04fd021ae17c0bc30387743ff6803e1ff84ebcdead5f5b5a94ba8eeac8497","b6009b88304c8f92621b2d7b88f524fba5512da83d64aad5cf5113cc2d6115bf","eb98aaa7043c412e3ecdf9fc611fb32bbc261230d2c42a2f29be6c74bd2fffde","fc3b1683cb56bd32f6248e7303c0f6479f07c47f092cd4f19762af5130a305d8","4d4733cf999f18c7734801bce185a7a82809eebd83eb8f0694c005e251140249"]
	var counts: Array[int]=[382,885,388,730,1328]
	var directory:="user://tree-editor-transfer-%d"%Time.get_ticks_usec()
	var holder:=Node3D.new();root.add_child(holder)
	holder.name="TreeEditorFixture"
	var undo:=UndoRedo.new()
	for kind in 5:
		var recipe: Resource=presets[kind].recipe
		var creation:=Creation.new();creation.source_directory=directory.path_join("sources");creation.prefab_directory=directory.path_join("prefabs");creation.recipe_directory=directory.path_join("recipes")
		check(creation.prepare_recipe(recipe,Species.TITLES[kind]),"ordinary prepare "+str(kind))
		if creation.packed==null:continue
		check(creation.source.validation_errors().is_empty(),"published Source validates "+str(kind))
		check(creation.source.voxels.hex_encode().sha256_text()==expected[kind],"accepted physical/voxel Source preserved "+str(kind))
		var node:=creation.packed.instantiate();var mesh: ArrayMesh=node.get_node("Mesh").mesh
		check(mesh.get_surface_count()==2 and mesh.surface_get_name(0)=="tree_bark" and mesh.surface_get_name(1)=="tree_leaves","real prefab owns bark and leaves "+str(kind))
		check(int(mesh.get_meta("tree_leaf_cards"))==counts[kind],"accepted leaf density "+str(kind))
		check(node.get_node("Collision/Shape").shape!=null,"wood collision retained "+str(kind))
		var signature:=hash(mesh.surface_get_arrays(1))
		check(creation.save_to_library(holder,undo),"normal library publication "+str(kind))
		var published_path: String=creation.source_directory.path_join(creation.source.model_id+".tres")
		var published_bytes:=FileAccess.get_file_as_bytes(published_path)
		undo.undo();check(not FileAccess.file_exists(published_path),"library Undo removes only its publication")
		undo.redo();check(FileAccess.get_file_as_bytes(published_path)==published_bytes,"library Redo restores exact appearance Source")
		var saved: Resource=ResourceLoader.load(creation.source_directory.path_join(creation.source.model_id+".tres"),"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		check(same_values(saved.tree_surface,creation.source.tree_surface),"tree Source appearance roundtrip "+str(kind))
		var packed: PackedScene=ResourceLoader.load(creation.prefab_directory.path_join(creation.source.model_id+".tscn"),"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		var reopened:=packed.instantiate();var reopened_mesh: ArrayMesh=reopened.get_node("Mesh").mesh
		var source_path: String=creation.source_directory.path_join(creation.source.model_id+".tres")
		check(str(reopened.get_meta(EmberVoxelPrefab.SOURCE_SIGNATURE_META))==(EmberVoxelPrefab.source_render_contract(saved.to_definition().model)+":"+FileAccess.get_sha256(source_path)+":json-only").sha256_text(),"published prefab uses current render contract "+str(kind))
		check(hash(reopened_mesh.surface_get_arrays(1))==signature,"saved prefab leaf buffers exact "+str(kind))
		var rebuilt:=EmberVoxelPrefab.prepare_resource(saved);var restored:=rebuilt.instantiate()
		check(hash(restored.get_node("Mesh").mesh.surface_get_arrays(1))==signature,"runtime rebuild from Source without Recipe "+str(kind))
		var prop:=creation.commit(holder,holder,undo,Vector3(kind*10,0,0))
		check(prop!=null,"ordinary scene placement "+str(kind))
		undo.undo();check(prop.get_parent()==null,"scene creation Undo")
		undo.redo();check(prop.get_parent()==holder,"scene creation Redo")
		restored.free();reopened.free();node.free()
		var panel:=RecipePanel.new();holder.add_child(panel);panel.recipe_directory=creation.recipe_directory
		check(panel.open_source(saved,{"root":holder,"parent":holder,"undo":undo,"world_size":1.0,"position":Vector3.ZERO,"source_directory":creation.source_directory,"prefab_directory":creation.prefab_directory}),"ordinary recipe panel opens "+str(kind))
		check(panel.controls.has("tree_leaf_density") and panel.controls.has("tree_leaf_local"),"ordinary panel exposes appearance "+str(kind))
		panel.controls.tree_leaf_density.value=30;check(panel.creation==null,"draft does not remesh")
		panel.undo_parameters();check(panel.recipe.parameters.tree_leaf_density==recipe.parameters.tree_leaf_density,"density Undo")
		panel.redo_parameters();panel.prepare();check(panel.creation!=null,"appearance preview")
		var field=panel.controls.tree_leaf_local
		check(field.parts.item_count>1,"primary crown parts available")
		field.parts.select(1);field.parts.item_selected.emit(1);field.amount.value=50
		check(panel.recipe.parameters.tree_leaf_local.size()==1,"local density uses the real field signal")
		panel.undo_parameters();check(panel.recipe.parameters.tree_leaf_local.is_empty(),"local density Undo")
		panel.redo_parameters();check(panel.recipe.parameters.tree_leaf_local.size()==1,"local density Redo")
		panel.prepare();check(panel.creation!=null,"local density preview")
		if panel.creation!=null:
			var preview: Node=panel.creation.packed.instantiate()
			check(int(preview.get_node("Mesh").mesh.get_meta("tree_leaf_cards"))<counts[kind],"density reduces accepted crown")
			preview.free()
		if kind==2:
			panel._save_mode.select(1);panel._save_mode_changed(1);panel.prepare()
			check(panel.save_variant(),"existing variation update through ordinary panel: "+panel._info.text)
			var updated: Resource=ResourceLoader.load(source_path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
			check(updated.tree_surface.settings.tree_leaf_density==30 and updated.tree_surface.settings.tree_leaf_local.size()==1,"saved appearance and local controls")
			var after_signature:=hash(prop.get_node("Mesh").mesh.surface_get_arrays(1))
			check(after_signature!=signature,"existing placed instance updated")
			undo.undo();check(hash(prop.get_node("Mesh").mesh.surface_get_arrays(1))==signature,"variation scene Undo restores accepted tree")
			undo.redo();check(hash(prop.get_node("Mesh").mesh.surface_get_arrays(1))==after_signature,"variation scene Redo restores local density")
			paint_checks(saved,mesh,directory)
		panel.discard();check(panel.recipe.parameters.tree_leaf_density==recipe.parameters.tree_leaf_density,"appearance discard")
		panel.free();creation=null
	var workspace:=GenerationPanel.new();holder.add_child(workspace)
	for kind in 5:
		workspace._change_parameter("tree_type",kind)
		check(workspace.recipe.parameters.generation_version==[24,21,22,23,25][kind] and bool(workspace.recipe.parameters.painted_tree),"ordinary species switch stays on accepted form "+str(kind))
		check(workspace.controls.has("tree_leaf_density") and workspace.controls.has("main_branch_count"),"creation workspace has appearance and branching controls")
	workspace.free()
	var packed_map:=PackedScene.new();check(packed_map.pack(holder)==OK,"fixture map pack")
	var map_path:=directory.path_join("map.tscn")
	check(ResourceSaver.save(packed_map,map_path)==OK,"fixture map save")
	var map_again: PackedScene=ResourceLoader.load(map_path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var loaded_map:=map_again.instantiate()
	check(loaded_map.get_child_count()==5,"saved map reopens all five placed trees")
	for i in 5:
		check(hash(loaded_map.get_child(i).get_node("Mesh").mesh.surface_get_arrays(1))==hash(holder.get_child(i).get_node("Mesh").mesh.surface_get_arrays(1)),"map appearance roundtrip "+str(i))
	loaded_map.free()
	print("TREE_EDITOR_USER_DIR ",ProjectSettings.globalize_path("user://"))
	holder.free();undo.free()
	print("TREE_EDITOR_TRANSFER ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)

func paint_checks(source: EmberVoxelModelResource,mesh: ArrayMesh,directory: String) -> void:
	var edited:=source.duplicate_model();var old_colors=mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	for index in [1,2,3]:edited.palette[index]=Color("dd5533")
	check(Surface.active(edited.to_definition().model),"manual palette paint keeps the accepted branch surface")
	var painted:=EmberVoxelPrefab.prepare_resource(edited).instantiate()
	check(painted.get_node("Mesh").mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]!=old_colors,"manual bark paint affects the smooth surface")
	painted.free()
	var occupied:=edited.voxels.find(1)
	check(occupied>=0,"fixture bark voxel")
	if occupied>=0:edited.voxels[occupied]=2
	check(Surface.active(edited.to_definition().model),"individual voxel paint retains surface")
	var painted_path:=directory.path_join("manual-paint.tres")
	check(ResourceSaver.save(edited,painted_path)==OK,"manual paint saves")
	var reopened: Resource=ResourceLoader.load(painted_path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(reopened.voxels==edited.voxels and reopened.palette==edited.palette,"manual paint roundtrip")
	if occupied>=0:edited.voxels[occupied]=0
	check(not Surface.active(edited.to_definition().model),"manual sculpt uses authored voxel geometry instead of stale crown")
	var zero:=source.duplicate_model();zero.tree_surface.settings.tree_leaf_density=0
	var bare:=EmberVoxelPrefab.prepare_resource(zero).instantiate()
	check(bare.get_node("Mesh").mesh.get_surface_count()==1,"zero density removes every leaf")
	bare.free()
	for bad in [{"tree_leaf_density":101},{"tree_leaf_receive":NAN},{"tree_leaf_local":{"bad":20}},{"generation_version":21},{"tree_leaf_revision":"bad"}]:
		var invalid:=source.duplicate_model();invalid.tree_surface.settings.merge(bad,true)
		check(not invalid.validation_errors().is_empty(),"invalid published tree controls rejected "+str(bad.keys()))
	var stale:=Generator.default_recipe(Generator.LARGE_TREE);stale.parameters=source.tree_surface.settings.duplicate(true)
	stale.parameters.tree_leaf_local={"0":0};stale.parameters.tree_leaf_revision="0".repeat(64)
	var built:=Generator.build(stale,Color.WHITE,{},"Stale")
	check(not built.has("error") and built.geometry.tree_surface.settings.tree_leaf_local.is_empty(),"stale local selection cannot affect a different geometry")

func same_values(a: Variant,b: Variant) -> bool:
	if a is float and b is float:return absf(a-b)<=0.000001
	if a is Vector3 and b is Vector3:return a.distance_to(b)<=0.000001
	if a is Color and b is Color:return a.is_equal_approx(b)
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key in a:
			if not b.has(key) or not same_values(a[key],b[key]):return false
		return true
	if (a is Array or a is PackedColorArray) and (b is Array or b is PackedColorArray):
		if a.size()!=b.size():return false
		for index in a.size():
			if not same_values(a[index],b[index]):return false
		return true
	return a==b
