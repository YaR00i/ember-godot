@tool
extends "res://tools/editor_test_voxel_generation.gd"
## The normal library button and generator in an isolated native editor copy.
func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("ember-tree-quiet-materials/project"):
		push_error("Painted tree editor gate requires its disposable project");return
	await frames(15);await settle()
	var fixture:=Node3D.new();fixture.name="PaintedTreeEditorFixture"
	var packed:=PackedScene.new();check(packed.pack(fixture)==OK,"fixture pack")
	check(ResourceSaver.save(packed,"res://scenes/painted_tree_editor_fixture.tscn")==OK,"fixture save");fixture.free()
	preload("res://addons/ember_import/ember_editor_filesystem.gd").request();await frames(15);await settle()
	EditorInterface.open_scene_from_path("res://scenes/painted_tree_editor_fixture.tscn");await frames(15)
	var create:=EditorInterface.get_base_control().find_child("VoxelLibraryNewLargeTree",true,false) as Button
	check(create!=null,"ordinary library tree button")
	if create==null:get_tree().quit(1);return
	create.pressed.emit();await frames(20)
	var panel=EditorInterface.get_base_control().find_child("EmberGenerationWorkspace",true,false)
	check(panel!=null,"ordinary generator opens")
	if panel==null:get_tree().quit(1);return
	var ids: Array[String]=[]
	for kind in 5:
		panel.controls.tree_type.select(kind);panel.controls.tree_type.item_selected.emit(kind)
		check(panel.recipe.parameters.generation_version==[24,21,22,23,25][kind],"native species selects accepted algorithm")
		check(panel.controls.has("tree_leaf_density") and panel.controls.has("tree_leaf_local") and panel.controls.has("main_branch_count"),"native controls include structure/local density/light")
		panel._count.value=1;panel._seed.value=7;panel.context.world_size=1.0
		panel._generate.pressed.emit();await work(panel)
		var candidate: Dictionary=panel.session.candidates.back()
		check(is_instance_valid(candidate.node),"native placed candidate")
		if not is_instance_valid(candidate.node):continue
		var mesh: ArrayMesh=candidate.node.get_node("Mesh").mesh
		check(mesh.get_surface_count()==2 and mesh.surface_get_name(1)=="tree_leaves","native candidate has accepted artwork")
		panel._select_preview(candidate);await frames(5)
		check(panel.candidate_controls.has("tree_leaf_local"),"native individual controls")
		panel._choose(candidate,true);panel._save.pressed.emit();await work(panel)
		check(candidate.saved,"native save best publishes tree")
		var id: String=candidate.creation.source.model_id;ids.append(id)
		var source: Resource=ResourceLoader.load("res://content/voxel_models/"+id+".tres","",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		check(source!=null and not source.tree_surface.is_empty(),"ordinary library Source keeps full appearance")
		await frames(5)
	await settle();await frames(10)
	var shot:=EditorInterface.get_base_control().get_viewport().get_texture().get_image()
	check(shot.save_png(OS.get_cmdline_user_args()[0].path_join("native-editor.png"))==OK,"native editor capture")
	panel.edit_requested.emit(ids[2]);await frames(12)
	var save_button:=EditorInterface.get_base_control().find_child("SaveVoxelSurfacePilot",true,false)
	check(save_button!=null,"saved library tree opens in the existing workshop")
	if save_button!=null:
		var workspace: Node=save_button
		while workspace!=null:
			if workspace.get_script()!=null and workspace.get_script().resource_path.ends_with("ember_voxel_sculpt_workspace.gd"):break
			workspace=workspace.get_parent()
		check(workspace!=null,"ordinary workshop owner")
		if workspace!=null:
			workspace._sidebar_tabs.current_tab=2
			var recipe_panel=workspace._generator_panel
			check(recipe_panel.controls.has("tree_leaf_local"),"saved tree reopens with editable local density")
			recipe_panel.controls.tree_leaf_density.value=35;recipe_panel._preview_button.pressed.emit();await frames(8)
			check(recipe_panel.creation!=null,"workshop renders the real tree variation preview")
			recipe_panel.discard();await frames(3)
			check(EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0].path_join("native-workshop.png"))==OK,"workshop capture")
	var manifest:=FileAccess.open(OS.get_cmdline_user_args()[0].path_join("editor-library.var"),FileAccess.WRITE);manifest.store_var(ids);manifest.close()
	for message in errors:push_error(message)
	# Tear down the tested plugin while the editor tree is still alive. The
	# project's separate late-shutdown get_node warning is not a test failure.
	EditorInterface.set_plugin_enabled("ember_surface_canvas",false)
	EditorInterface.set_plugin_enabled("ember_import",false);await frames(5)
	print("PAINTED_TREE_EDITOR ","PASS" if errors.is_empty() else "FAIL")
	get_tree().quit(0 if errors.is_empty() else 1)
