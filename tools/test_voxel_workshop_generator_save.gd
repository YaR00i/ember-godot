extends SceneTree

const Generator = preload("res://addons/ember_import/ember_voxel_generator.gd")
const Creation = preload("res://addons/ember_import/ember_voxel_tree_object_creation.gd")
const Workspace = preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")

class SaveSpy extends RefCounted:
	var calls := 0
	func save(_source: Resource) -> Dictionary:
		calls += 1
		return {"ok": false, "error": "unexpected sculpt save"}

var failures := 0
var directory := "user://workshop_generator_save_%d" % Time.get_ticks_usec()

func check(value: bool, message: String) -> void:
	if value: return
	failures += 1
	push_error(message)

func configure(creation: RefCounted) -> void:
	creation.source_directory = directory.path_join("sources")
	creation.prefab_directory = directory.path_join("prefabs")
	creation.recipe_directory = directory.path_join("recipes")

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	for folder in ["sources", "prefabs", "recipes"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory.path_join(folder)))
	var base: Resource = Generator.creation_presets(Generator.LARGE_TREE)[1].recipe.duplicate(true)
	base.parameters.height = 64
	base.parameters.crown_spread = 48
	base.seed = 371
	var original := Creation.new()
	configure(original)
	check(original.prepare_recipe(base, "Save fixture", "", "workshop_save_tree"), "fixture prepares")
	if original.source == null:
		quit(1)
		return
	var source_path: String = original.source_directory.path_join(original.source.model_id + ".tres")
	check(ResourceSaver.save(original.source, source_path) == OK, "fixture source saves")
	check(ResourceSaver.save(original.recipe, Creation.recipe_path(original.source.model_id, original.recipe_directory)) == OK, "fixture recipe saves")
	var scene := Node3D.new()
	root.add_child(scene)
	var undo := UndoRedo.new()
	var workspace := Workspace.new()
	root.add_child(workspace)
	root.size = Vector2i(1400, 900)
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	workspace.setup(null, undo)
	workspace.ensure_ui()
	var panel = workspace._generator_panel
	panel.recipe_directory = original.recipe_directory
	workspace.open_surface(original.source, source_path)
	workspace._sidebar_tabs.current_tab = 2
	var spy := SaveSpy.new()
	workspace._object_session = spy
	check(not workspace.save_changes() and spy.calls == 0, "missing preview refuses Save without sculpt fallback")
	check(workspace._status.text.contains("предпросмотр"), "missing preview explains required action")
	workspace._object_session = null
	for mode in [0, 2, 1]:
		workspace.open_surface(original.source, source_path)
		workspace._sidebar_tabs.current_tab = 2
		panel.context = {"root": scene, "parent": scene, "position": Vector3.ZERO, "world_size": 1.0, "undo": undo}
		check(panel.open_source(original.source, panel.context), "original recipe reopens between save modes")
		panel._save_mode.select(mode)
		panel._save_mode_changed(mode)
		if mode != 1: panel._variation_name.text = "Saved mode %d" % mode
		panel.set_parameter("foliage_style", 3 if mode == 2 else 1)
		panel.set_parameter("foliage_pattern_strength", 42 if mode == 2 else 25)
		panel.set_parameter("foliage_detail", 70)
		panel.prepare()
		# Inject fixture publication paths before preparation captures update hashes.
		var prepared := Creation.new()
		configure(prepared)
		check(prepared.prepare_recipe(panel.creation.recipe, panel.creation.source.display_name,
			original.source.model_id if mode == 1 else ""), "redirected exact preview prepares")
		panel.creation = prepared
		workspace._show_generator_preview(prepared.packed, prepared.source)
		var id: String = original.source.model_id if mode == 1 else prepared.source.model_id
		var expected: Dictionary = prepared.recipe.parameters.duplicate(true)
		var exact_voxels: PackedByteArray = prepared.source.voxels.duplicate()
		var exact_palette = prepared.source.palette.duplicate()
		if mode == 1:
			var saved_palette: PackedColorArray = workspace._saved_palette.duplicate()
			workspace._saved_palette = PackedColorArray()
			check(not workspace.save_changes() and panel.creation == prepared, "manual dirty update is refused and keeps preview")
			check(Creation.load_recipe(id, original.recipe_directory).parameters == original.recipe.parameters, "refused update leaves source recipe intact")
			workspace._saved_palette = saved_palette
		if "--capture" in OS.get_cmdline_user_args() and mode == 0:
			for frame in 12: await process_frame
			var capture := "user://workshop_generator_save_native.png"
			root.get_texture().get_image().save_png(capture)
			print("WORKSHOP_SAVE_CAPTURE ", ProjectSettings.globalize_path(capture))
		if mode == 2:
			var key := InputEventKey.new()
			key.keycode = KEY_S
			key.ctrl_pressed = true
			key.pressed = true
			workspace._input(key)
		else:
			var ok := workspace.save_changes()
			check(ok, "workshop Save succeeds in mode %d: %s" % [mode, panel._info.text])
		var saved: Resource = Creation.load_recipe(id, original.recipe_directory)
		var saved_source = ResourceLoader.load(original.source_directory.path_join(id + ".tres"), "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		check(saved != null and saved.parameters == expected, "all recipe parameters saved in mode %d" % mode)
		check(saved_source != null and saved_source.voxels == exact_voxels and saved_source.palette == exact_palette, "exact preview geometry/palette saved")
		check(panel.creation == null and workspace._generator_preview == null, "successful Save clears preview")
		undo.undo()
		if mode == 1:
			check(Creation.load_recipe(id, original.recipe_directory).parameters == original.recipe.parameters, "update Undo restores entire recipe")
			var restored = ResourceLoader.load(source_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
			check(restored.voxels == original.source.voxels and restored.palette == original.source.palette, "update Undo restores original geometry and palette")
		else:
			check(scene.get_child_count() == (1 if mode == 2 else 0), "new object Undo removes placement")
		undo.redo()
		check(Creation.load_recipe(id, original.recipe_directory).parameters == expected, "Redo keeps entire recipe")
		var redone = ResourceLoader.load(original.source_directory.path_join(id + ".tres"), "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		check(redone.voxels == exact_voxels and redone.palette == exact_palette, "Redo restores exact published geometry and palette")
		check(panel.open_source(saved_source), "saved source opens contextual recipe")
		check(panel.recipe.parameters == expected and panel.controls.foliage_pattern_strength.value == expected.foliage_pattern_strength, "reopen restores style and strength controls")
		panel.set_parameter("foliage_pattern_strength", 99)
		check(not workspace.save_changes(), "changed parameters require a fresh preview")
		check(Creation.load_recipe(id, original.recipe_directory).parameters == expected, "rejected Save leaves published recipe unchanged")
		panel.discard()
		check(panel.recipe.parameters == expected, "Discard restores saved settings")
		if mode != 1:
			check(Creation.load_recipe(original.source.model_id, original.recipe_directory).parameters == original.recipe.parameters, "new variation/standalone leaves original recipe intact")
	undo.clear_history()
	workspace.free()
	scene.free()
	undo.free()
	print("Voxel workshop generator save: ", "PASS" if failures == 0 else "FAIL %d" % failures)
	quit(0 if failures == 0 else 1)
