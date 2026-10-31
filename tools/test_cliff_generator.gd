extends SceneTree
## Landform-only Source/recipe/editor regression. All publication stays in user://.
const Generator = preload("res://addons/ember_import/ember_voxel_generator.gd")
const Creation = preload("res://addons/ember_import/ember_voxel_tree_object_creation.gd")
const Solid = preload("res://scripts/ember_voxel_solid_surface.gd")
var errors: Array[String]=[]
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok: errors.append(label); printerr("CLIFF_FAIL ",label)
func run() -> void:
	if DisplayServer.get_name()=="headless": printerr("Native Forward+ required");quit(2);return
	var scene:=Node3D.new();root.add_child(scene);current_scene=scene
	var directory:="user://ember-tests/cliff-%d"%OS.get_process_id()
	var history:=UndoRedo.new();var creation:=Creation.new()
	creation.source_directory=directory.path_join("sources");creation.prefab_directory=directory.path_join("prefabs");creation.recipe_directory=directory.path_join("recipes")
	var presets:=Generator.creation_presets(Generator.CLIFF)
	check(presets.size()==4,"three legacy presets and natural landform")
	for index in presets.size():
		if "--natural-only" in OS.get_cmdline_user_args() and index!=3:continue
		var built:=Generator.build(presets[index].recipe,Color.WHITE,{},"Уступ","cliff_%d"%index)
		check(not built.has("error"),str(built.get("error","build")))
		if built.has("error"):continue
		var source:EmberVoxelModelResource=built.geometry
		check(source.validation_errors().is_empty(),"source validates")
		check(source.voxels.count(1)>0 and source.voxels.count(2)>0 and source.voxels.count(3)>0,"stone, soil and grass volumes")
		check(source.merge_parts.size()==(3 if index==3 else (18 if index==2 else 9)),"mass ownership and legacy corner opening")
		var model:=EmberVoxelPrefab.model_of(source.to_definition())
		var slots:Dictionary={}
		for i in source.voxels.size():
			if source.voxels[i]>0: slots[int(source.voxel_part_ids[i])-1]=int(source.voxels[i])
		if index!=3:
			for face:Dictionary in Solid.hull_faces(model).faces:check(face.slot==slots[face.part],"each legacy layer keeps its material")
		else:
			var face_slots:Dictionary={}
			for face:Dictionary in Solid.hull_faces(model).faces:face_slots[face.slot]=true
			check(face_slots.has(3) and face_slots.has(2),"grass top and soil side published on the same mass")
			var painted_recipe:Resource=presets[index].recipe.duplicate(true)
			painted_recipe.parameters.soil_depth_m=0.5
			var painted:EmberVoxelModelResource=Generator.build(painted_recipe,Color.WHITE,{},"Уступ","painted").geometry
			check(Solid.occupancy_hash(painted.voxels)==Solid.occupancy_hash(source.voxels) and painted.voxel_part_ids==source.voxel_part_ids,"soil depth changes coverage only")
		var hull:=Solid.build(model)
		var voxel:=Solid.build_voxel_look(model)
		check(hull.get_surface_count()>0 and voxel.get_surface_count()>0,"hull and voxel shell exist")
		check(absf(hull.get_aabb().end.y-voxel.get_aabb().end.y)<=(1.0/source.voxels_per_block if index==3 else 0.001),"upper boundary stays within the source cell")
	var recipe:Resource=presets[3].recipe
	var repeated:=Generator.build(recipe,Color.WHITE,{},"Уступ","repeat")
	check(creation.prepare_recipe(recipe,"Уступ QA","","cliff_fixture"),creation.error)
	if creation.packed==null:quit(1);return
	var source:EmberVoxelModelResource=creation.source
	check(source.voxels==repeated.geometry.voxels and source.solid_surface==repeated.geometry.solid_surface,"seed reproducible")
	check(creation.save_to_library(scene,history),creation.error)
	var path:=creation.source_directory.path_join("cliff_fixture.tres")
	var bytes:=FileAccess.get_file_as_bytes(path)
	history.undo();check(not FileAccess.file_exists(path),"library Undo")
	history.redo();check(FileAccess.get_file_as_bytes(path)==bytes,"library Redo exact")
	var panel=load("res://addons/ember_import/ember_voxel_generator_panel.gd").new();root.add_child(panel)
	panel.recipe_directory=creation.recipe_directory
	var context:Dictionary={"root":scene,"parent":scene,"position":Vector3.ZERO,"world_size":16.0,"undo":history,"source_directory":creation.source_directory,"prefab_directory":creation.prefab_directory}
	check(panel.open_source(source,context),"existing generator editor opens cliff")
	panel.controls.height_m.value=2.5
	panel.undo_parameters();check(panel.recipe.parameters.height_m==1.75,"parameter Undo")
	panel.redo_parameters();check(panel.recipe.parameters.height_m==2.5,"parameter Redo")
	panel._save_mode.select(1);panel._save_mode.item_selected.emit(1);panel.prepare()
	check(panel.creation!=null and panel.creation.source.height_voxels>source.height_voxels,"preview has new height")
	check(FileAccess.get_file_as_bytes(path)==bytes,"preview leaves saved source intact")
	check(panel.save_variant(),"save variant: "+panel._info.text)
	var reopened:EmberVoxelModelResource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(reopened.validation_errors().is_empty() and reopened.height_voxels>source.height_voxels,"fresh Source reopen")
	check(Creation.load_recipe("cliff_fixture",creation.recipe_directory).parameters.height_m==2.5,"recipe reopen")
	history.undo();check(Creation.load_recipe("cliff_fixture",creation.recipe_directory).parameters.height_m==1.75,"saved update Undo")
	history.redo();check(Creation.load_recipe("cliff_fixture",creation.recipe_directory).parameters.height_m==2.5,"saved update Redo")
	var saved:=FileAccess.get_file_as_bytes(path)
	check(panel.open_source(reopened,context),"reopen editor")
	panel.controls.height_m.value=1.0;panel.discard()
	check(panel.recipe.parameters.height_m==2.5 and FileAccess.get_file_as_bytes(path)==saved,"discard keeps saved layers")
	context.manual_dirty=true;panel.context=context;panel.controls.height_m.value=1.0;panel._save_mode.select(1);panel._save_mode.item_selected.emit(1);panel.prepare()
	check(not panel.save_variant() and FileAccess.get_file_as_bytes(path)==saved,"manual sculpt protected")
	var workspace=load("res://addons/ember_import/ember_voxel_generation_panel.gd").new();root.add_child(workspace)
	workspace._select_provider(workspace.PROVIDERS.find(Generator.CLIFF))
	check(workspace.controls.has("shape") and workspace.controls.has("soil_depth_m"),"cliff in existing native workspace")
	workspace.controls.soil_depth_m.value=1.0
	check(workspace.recipe.parameters.soil_depth_m==1.0,"soil/stone share control")
	print("CLIFF_GENERATOR ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"presets":presets.size()}))
	workspace.free();panel.free();history.clear_history();scene.queue_free()
	await process_frame;quit(0 if errors.is_empty() else 1)
