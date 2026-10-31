extends SceneTree
## House-only recipe/editor/persistence regression; all writes use user://.
const Generator=preload("res://addons/ember_import/ember_voxel_generator.gd")
const Creation=preload("res://addons/ember_import/ember_voxel_tree_object_creation.gd")
const Solid=preload("res://scripts/ember_voxel_solid_surface.gd")
var errors:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("FAIL ",label)
func run()->void:
	if DisplayServer.get_name()=="headless":printerr("Native Forward+ required");quit(2);return
	var scene:=Node3D.new();root.add_child(scene);current_scene=scene
	var directory:="user://ember-tests/building-%d"%OS.get_process_id()
	var history:=UndoRedo.new();var creation:=Creation.new()
	creation.source_directory=directory.path_join("sources");creation.prefab_directory=directory.path_join("prefabs");creation.recipe_directory=directory.path_join("recipes")
	var recipe=Generator.default_recipe(Generator.BUILDING)
	var started:=Time.get_ticks_msec()
	check(creation.prepare_recipe(recipe,"Дом QA","","building_fixture"),creation.error)
	if creation.packed==null:quit(1);return
	var source:EmberVoxelModelResource=creation.source
	check(source.validation_errors().is_empty(),"source validates")
	var repeat:Dictionary=Generator.build(recipe,Color.WHITE,{},"Дом QA","building_fixture")
	check(repeat.geometry.voxels==source.voxels and repeat.geometry.solid_surface==source.solid_surface,"deterministic source and guides")
	# A part's support corner must not take the neighbouring roof/window colour.
	var model:Dictionary=EmberVoxelPrefab.model_of(source.to_definition())
	var owner_slots:Dictionary={}
	for i in source.voxels.size():
		if source.voxels[i]!=0:owner_slots[int(source.voxel_part_ids[i])-1]=int(source.voxels[i])
	for face:Dictionary in Solid.hull_faces(model).faces:
		check(face.slot==owner_slots[face.part],"convex part retains its own palette slot")
	check(creation.save_to_library(scene,history),creation.error)
	var path:=creation.source_directory.path_join("building_fixture.tres")
	var bytes:=FileAccess.get_file_as_bytes(path)
	history.undo();check(not FileAccess.file_exists(path),"library Undo")
	history.redo();check(FileAccess.get_file_as_bytes(path)==bytes,"library Redo exact bytes")
	var panel=load("res://addons/ember_import/ember_voxel_generator_panel.gd").new();root.add_child(panel)
	panel.recipe_directory=creation.recipe_directory
	var context:Dictionary={"root":scene,"parent":scene,"position":Vector3.ZERO,"world_size":16.0,"undo":history,"source_directory":creation.source_directory,"prefab_directory":creation.prefab_directory}
	check(panel.open_source(source,context),"existing recipe editor")
	check(panel.controls.floor_height_m.get_line_edit().text.contains("2.75"),"metres display exact quarter steps")
	panel.controls.width_m.value=4.75
	check(panel.recipe.parameters.width_m==4.75,"fractional metre input")
	panel.undo_parameters();check(panel.recipe.parameters.width_m==4.5,"parameter Undo")
	panel.redo_parameters();check(panel.recipe.parameters.width_m==4.75,"parameter Redo")
	panel.controls.floors.value=2
	panel._save_mode.select(1);panel.prepare()
	check(panel.creation!=null and panel.creation.source.height_voxels>source.height_voxels,"two-storey exact preview")
	check(FileAccess.get_file_as_bytes(path)==bytes,"preview does not write source")
	check(panel.save_variant(),"update variant: "+panel._info.text)
	var saved:=FileAccess.get_file_as_bytes(path)
	var reopened:EmberVoxelModelResource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(reopened.validation_errors().is_empty() and reopened.height_voxels>source.height_voxels,"source fresh reopen")
	check(Creation.load_recipe("building_fixture",creation.recipe_directory).parameters.floors==2,"recipe fresh reopen")
	history.undo()
	var undone:EmberVoxelModelResource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(undone.voxels==source.voxels and Creation.load_recipe("building_fixture",creation.recipe_directory).parameters.floors==1,"saved update Undo")
	history.redo()
	var redone:EmberVoxelModelResource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(redone.voxels==reopened.voxels and Creation.load_recipe("building_fixture",creation.recipe_directory).parameters.floors==2,"saved update Redo")
	saved=FileAccess.get_file_as_bytes(path)
	check(panel.open_source(reopened,context),"reopen controls")
	panel.controls.floors.value=1;panel.discard()
	check(panel.recipe.parameters.floors==2 and FileAccess.get_file_as_bytes(path)==saved,"discard preserves saved house")
	context.manual_dirty=true;panel.context=context;panel.controls.floors.value=1;panel._save_mode.select(1);panel.prepare()
	check(not panel.save_variant() and FileAccess.get_file_as_bytes(path)==saved,"manual edits protected")
	var workspace=load("res://addons/ember_import/ember_voxel_generation_panel.gd").new();root.add_child(workspace)
	workspace._select_provider(workspace.PROVIDERS.find(Generator.BUILDING))
	check(workspace.recipe.generator_id==Generator.BUILDING and workspace.controls.has("width_m"),"building in existing creation workspace")
	workspace.controls.overhang_m.value=0.375
	check(workspace.recipe.parameters.overhang_m==0.375,"creation fractional metre field")
	workspace._select_provider(workspace.PROVIDERS.find(Generator.ROCK))
	workspace.controls.roughness.value=42
	check(workspace.recipe.parameters.roughness==42 and workspace.controls.roughness.step==1.0,"existing integer generator controls unchanged")
	print("HOUSE_TEST ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"elapsed_ms":Time.get_ticks_msec()-started}))
	workspace.queue_free();panel.queue_free();scene.queue_free();history.clear_history()
	for frame in 4:await process_frame
	quit(0 if errors.is_empty() else 1)
