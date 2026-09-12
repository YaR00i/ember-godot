extends SceneTree

const Pattern = preload("res://addons/ember_import/ember_voxel_pattern.gd")
const PatternEditor = preload("res://addons/ember_import/ember_voxel_pattern_editor.gd")
const Stamp = preload("res://addons/ember_import/ember_voxel_stamp.gd")
const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
const Workspace = preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")

var errors := 0


func check(ok: bool, label: String) -> void:
	if not ok:
		errors += 1
		push_error(label)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var mask := PackedByteArray([1,0,1,0,1,0])
	var built := Pattern.build_geometry(Vector2i(3,2),mask,16,"Зубцы")
	check(not built.has("error"),"build flat geometry")
	var preset := Stamp.Preset.new()
	preset.display_name = "Зубцы"
	preset.kind = Stamp.Preset.KIND_PATTERN
	preset.pattern_size = Vector2i(3,2)
	preset.pattern_depth = 3
	preset.anchor = 1
	preset.geometry = built.geometry
	check(Pattern.validation_errors(preset).is_empty(),"pattern validation")
	check(Pattern.mask_from_preset(preset) == mask,"editable mask roundtrip")
	var target: EmberVoxelModelResource = Shapes.build("empty",Vector3i(16,8,16),16,Color.ROYAL_BLUE,"pattern_target","Target").source
	target.merge_parts = PackedStringArray(["Основа","Деталь"])
	target.voxel_part_ids.resize(target.voxels.size())
	var before := target.to_definition()
	var add := Pattern.plan(target,preset,Vector3i(8,1,8),Vector3i.UP,0,-1,1,false,3,1,2)
	check(not add.has("error") and add.selected.size() == 9,"add extrudes mask by exact depth")
	check(target.to_definition() == before,"pattern preview detached")
	var undo := UndoRedo.new()
	var actions := EmberVoxelSculptActions.new()
	actions.configure(undo)
	check(actions.apply_fragment(target,add),"apply pattern")
	check(target.voxels.count(0) == target.voxels.size()-9,"pattern add cells")
	check(target.palette[target.voxels[add.selected[0]]] == Color.ROYAL_BLUE,"pattern add uses target palette color")
	for index in add.selected:
		check(target.voxel_part_ids[index] == 2,"pattern active part")
	undo.undo()
	check(target.to_definition() == before,"pattern one Undo")
	undo.redo()
	var remove := Pattern.plan(target,preset,Vector3i(8,3,8),Vector3i.UP,0,-1,1,true,3,1,2)
	check(not remove.has("error") and remove.selected.size() == 9,"remove cuts inward")
	check(actions.apply_fragment(target,remove),"apply pattern cut")
	check(target.to_definition() == before,"cut removes exact added volume")
	undo.undo()
	undo.undo()
	check(target.to_definition() == before,"two operations undo to baseline")
	var repeated_points: Array[Vector3i] = [Vector3i(4,1,8),Vector3i(8,1,8),Vector3i(12,1,8)]
	var repeated := Pattern.plan_many(target,preset,repeated_points,Vector3i.UP,0,-1,1,false,2,1,0)
	check(not repeated.has("error") and repeated.selected.size() == 18 and repeated.placements == repeated_points,"pattern line placements share one fixed plane")
	check(target.to_definition() == before,"repeated pattern preview detached")
	var overlap_points: Array[Vector3i] = [Vector3i(8,1,8),Vector3i(8,1,8)]
	var overlap := Pattern.plan_many(target,preset,overlap_points,Vector3i.UP,0,-1,1,false,2,1,0)
	check(not overlap.has("error") and overlap.selected.size() == 6,"overlapping patterns deduplicate cells")
	var path_points := Stamp.sample_path([Vector3i(4,1,4),Vector3i(10,1,4),Vector3i(10,1,10)],3)
	var path_plan := Pattern.plan_many(target,preset,path_points,Vector3i.UP,0,-1,1,false,2,1,0)
	check(not path_plan.has("error") and path_plan.placements == path_points,"pattern path uses shared spacing sampler")
	check(actions.apply_fragment(target,repeated),"apply repeated pattern once")
	undo.undo()
	check(target.to_definition() == before,"repeated pattern one Undo")
	var rotated := Pattern.plan(target,preset,Vector3i(8,1,8),Vector3i.RIGHT,1,2,0,false,2,1,0)
	check(not rotated.has("error") and rotated.selected.size() == 6,"rotation mirror and side face")
	for normal in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.UP,Vector3i.DOWN,Vector3i.FORWARD,Vector3i.BACK]:
		var faced := Pattern.plan(target,preset,Vector3i(8,4,8),normal,0,-1,1,false,2,1,0)
		check(not faced.has("error") and faced.selected.size() == 6,"pattern supports face %s" % normal)
	var built_32 := Pattern.build_geometry(Vector2i(3,2),mask,32,"Зубцы 32")
	var preset_32 := Stamp.Preset.new()
	preset_32.display_name = "Зубцы 32"
	preset_32.kind = Stamp.Preset.KIND_PATTERN
	preset_32.pattern_size = Vector2i(3,2)
	preset_32.pattern_depth = 2
	preset_32.geometry = built_32.geometry
	var target_32: EmberVoxelModelResource = Shapes.build("empty",Vector3i(32,8,32),32,Color.ROYAL_BLUE,"pattern_target_32","Target 32").source
	check(not Pattern.plan(target_32,preset_32,Vector3i(16,1,16),Vector3i.UP,0,-1,1,false,2,1,0).has("error"),"matching density 32")
	check(Pattern.plan(target,preset_32,Vector3i(8,1,8),Vector3i.UP,0,-1,1,false,2,1,0).has("error"),"density mismatch refuses conversion")
	var dense_mask := PackedByteArray()
	dense_mask.resize(Pattern.MAX_SIZE*Pattern.MAX_SIZE)
	dense_mask.fill(1)
	var dense_preset := Stamp.Preset.new()
	dense_preset.display_name = "Dense pattern"
	dense_preset.kind = Stamp.Preset.KIND_PATTERN
	dense_preset.pattern_size = Vector2i(Pattern.MAX_SIZE,Pattern.MAX_SIZE)
	dense_preset.pattern_depth = 32
	dense_preset.geometry = Pattern.build_geometry(dense_preset.pattern_size,dense_mask,16,"Dense pattern").geometry
	var large_target: EmberVoxelModelResource = Shapes.build("empty",Vector3i(64,32,64),16,Color.ROYAL_BLUE,"pattern_large","Large").source
	var pattern_start := Time.get_ticks_usec()
	var dense_plan := Pattern.plan(large_target,dense_preset,Vector3i(32,0,32),Vector3i.UP,0,-1,1,false,32,1,0)
	print("Pattern 16x16 depth-32 / 131072 cells plan ms: ",(Time.get_ticks_usec()-pattern_start)/1000.0)
	check(not dense_plan.has("error") and dense_plan.selected.size() == 8192,"bounded maximum pattern")
	var excessive_points: Array[Vector3i] = []
	for index in 17:
		excessive_points.append(Vector3i(32,0,32))
	check(Pattern.plan_many(large_target,dense_preset,excessive_points,Vector3i.UP,0,-1,1,false,32,1,0).has("error"),"repeated pattern candidate limit")
	check(Pattern.plan(target,preset,Vector3i.ZERO,Vector3i.LEFT,0,-1,1,false,3,1,0).has("error"),"out of bounds atomic refusal")
	target.voxel_groups = [{"id":"locked","name":"Locked","indices":PackedInt32Array([add.selected[0]]),"locked":true}]
	check(Pattern.plan(target,preset,Vector3i(8,1,8),Vector3i.UP,0,-1,1,false,3,1,0).has("error"),"locked group refusal")
	target.voxel_groups = []
	var directory := "user://pattern_test_%d" % Time.get_ticks_usec()
	var saved := Stamp.save_new(preset,directory.path_join("presets"),directory.path_join("models"))
	check(saved.has("path"),"pattern save new")
	var entries := Stamp.library(directory.path_join("presets"))
	check(entries.size() == 1 and entries[0].kind == Stamp.Preset.KIND_PATTERN and entries[0].pattern_depth == 3,"pattern library metadata")
	var reopened := ResourceLoader.load(saved.path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(Pattern.mask_from_preset(reopened) == mask,"pattern reopen")
	var edited_mask := PackedByteArray([1,1,1,0,1,0])
	var edited_geometry: EmberVoxelModelResource = Pattern.build_geometry(Vector2i(3,2),edited_mask,16,"Зубцы").geometry
	reopened.geometry = edited_geometry
	reopened.pattern_depth = 4
	var source_path: String = ResourceLoader.load(saved.path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP).geometry.resource_path
	check(Stamp.save_existing(reopened,saved.path,source_path).has("path"),"pattern edit existing")
	var edited := ResourceLoader.load(saved.path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(edited.pattern_depth == 4 and Pattern.mask_from_preset(edited) == edited_mask,"pattern edit reopen")
	for x in range(4,12):
		for z in range(4,12):
			target.voxels[Pattern.Model.index_of(Vector3i(x,0,z),target.grid_size())] = 1
	await _ui(target,edited,undo,directory)
	undo.clear_history()
	undo.free()
	print("Voxel pattern: ","PASS" if errors == 0 else "FAIL %d" % errors)
	quit(errors)


func _ui(target: EmberVoxelModelResource, preset: Resource, undo: UndoRedo, directory: String) -> void:
	root.size = Vector2i(1280,720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	var editor := PatternEditor.new()
	root.add_child(editor)
	editor.size = Vector2(160,160)
	editor.set_pattern_size(Vector2i(4,4))
	editor.paint_at(Vector2(20,20),1)
	check(editor.mask().count(1) == 1,"pixel editor draw")
	editor.drawing = false
	editor.paint_at(Vector2(20,20),0)
	check(editor.mask().count(1) == 0,"pixel editor erase")
	editor.queue_free()
	var workspace := Workspace.new()
	workspace.setup(null,undo)
	root.add_child(workspace)
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	workspace.open_surface(target,directory.path_join("target.tres"))
	workspace._stamp_panel.directory = directory.path_join("presets")
	workspace._stamp_panel.sources = directory.path_join("models")
	workspace._stamp_panel.refresh_library()
	for frame in 4:
		await process_frame
	var interaction: Control = workspace._selection_interaction
	var before := target.to_definition()
	interaction.begin_stamp(preset)
	interaction._stamp_normal = Vector3i.UP
	interaction._set_stamp_position(Vector3i(8,1,8))
	for frame in 3:
		await process_frame
	check(interaction._is_pattern() and interaction._stamp_depth_row.visible and interaction._stamp_application_buttons[0].get_parent().visible and interaction._stamp_spacing_row.visible,"pattern repeated-placement controls")
	check(interaction._stamp_mode_buttons[0].visible and interaction._stamp_mode_buttons[1].visible and not interaction._stamp_mode_buttons[2].visible,"volume indent leaked into flat pattern modes")
	check(workspace._palette.visible and not workspace._radius.visible and not workspace._depth.visible and not workspace._application_mode.visible,"pattern context did not keep only its relevant palette control")
	check(not interaction._plan.has("error") and target.to_definition() == before,"pattern UI preview detached")
	if "--capture" in OS.get_cmdline_user_args():
		for frame in 4:
			await process_frame
		root.get_texture().get_image().save_png("user://voxel_pattern_preview.png")
		print("PATTERN_PREVIEW_CAPTURE ",ProjectSettings.globalize_path("user://voxel_pattern_preview.png"))
	var expected: PackedByteArray = interaction._plan.properties.voxels.duplicate()
	interaction.commit()
	check(target.voxels == expected,"pattern UI commit")
	undo.undo()
	check(target.to_definition() == before,"pattern UI one Undo")
	interaction.begin_stamp(preset)
	interaction._select_segment(interaction._stamp_application,2)
	interaction._stamp_spacing.value = 3
	interaction._stamp_normal = Vector3i.UP
	interaction._stamp_line_start = Vector3i(4,1,4)
	interaction._stamp_line_started = true
	interaction._set_stamp_position(Vector3i(10,1,4))
	interaction._stamp_draft_ready = true
	interaction._stamp_draft_visible_count = interaction._all_stamp_placements().size()
	interaction._pending = true
	for frame in 3:
		await process_frame
	var expected_line: Array[Vector3i] = Stamp.sample_line(Vector3i(4,1,4),Vector3i(10,1,4),3)
	check(not interaction._plan.has("error") and interaction._plan.placements == expected_line and interaction._stamp_normal == Vector3i.UP,"pattern line preview uses spacing and fixed first face")
	check(target.to_definition() == before,"pattern line preview detached")
	interaction.commit()
	check(target.to_definition() != before,"pattern line commit")
	undo.undo()
	check(target.to_definition() == before,"pattern line one Undo")
	interaction.begin_stamp(preset)
	interaction._select_segment(interaction._stamp_application,1)
	interaction._stamp_spacing.value = 2
	var path_event := InputEventMouseButton.new()
	path_event.button_index = MOUSE_BUTTON_LEFT
	path_event.pressed = true
	path_event.position = interaction._screen(Vector3(5.5,1.01,5.5)/target.normalized_density())
	workspace._on_viewport_input(path_event)
	var path_motion := InputEventMouseMotion.new()
	path_motion.position = interaction._screen(Vector3(10.5,1.01,5.5)/target.normalized_density())
	workspace._on_viewport_input(path_motion)
	path_event.pressed = false
	path_event.position = path_motion.position
	workspace._on_viewport_input(path_event)
	for frame in 6:
		await process_frame
	check(interaction.transforming and interaction._stamp_draft_ready and target.to_definition() == before,"pointer pattern path release did not keep a detached draft")
	var pattern_count: int = interaction._stamp_placements().size()
	var draft_undo := InputEventKey.new()
	draft_undo.keycode = KEY_Z
	draft_undo.pressed = true
	draft_undo.ctrl_pressed = true
	check(interaction.handle(draft_undo),"pattern draft Undo was not consumed")
	await process_frame
	check(interaction._stamp_placements().size() == pattern_count-1 and target.to_definition() == before,"pattern draft Undo changed the Resource or missed one preview step")
	var apply_draft := InputEventKey.new()
	apply_draft.keycode = KEY_ENTER
	apply_draft.pressed = true
	check(interaction.handle(apply_draft),"pattern path Enter was not consumed")
	check(interaction.transforming and target.to_definition() != before,"pointer pattern path did not commit and keep the pattern selected on Enter")
	undo.undo()
	check(target.to_definition() == before,"pointer pattern path one Undo")
	interaction.begin_stamp(preset)
	interaction._select_segment(interaction._stamp_application,0)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = interaction._screen(Vector3(8.5,1.01,8.5)/target.normalized_density())
	workspace._on_viewport_input(click)
	click.pressed = false
	workspace._on_viewport_input(click)
	for frame in 3:
		await process_frame
	check(interaction._stamp_normal == Vector3i.UP and not interaction._plan.has("error") and target.to_definition() == before,"pointer pattern picks support face without mutation")
	interaction.commit()
	check(target.to_definition() != before,"pointer pattern commit")
	var committed := target.voxels.duplicate()
	check(workspace._save(),"pattern target save")
	var reopened_target := ResourceLoader.load(directory.path_join("target.tres"),"",ResourceLoader.CACHE_MODE_IGNORE)
	check(reopened_target.voxels == committed,"pattern target reopen")
	undo.undo()
	check(target.to_definition().model == before.model,"pointer pattern one Undo")
	interaction.cancel_gesture()
	var panel: VBoxContainer = workspace._stamp_panel
	panel._set_create_expanded(true)
	panel._select_create_kind(1)
	panel._title.text = "Рамка"
	panel._pattern_width.value = 4
	panel._pattern_height.value = 4
	panel._pattern_depth.value = 2
	panel._pattern_editor.set_mask(PackedByteArray([1,1,1,1,1,0,0,1,1,0,0,1,1,1,1,1]))
	panel._save_pattern()
	for frame in 3:
		await process_frame
	check(panel._entries.size() == 2 and panel._entries[panel._library.selected].kind == Stamp.Preset.KIND_PATTERN,"pattern created from editor into shared library")
	panel._edit()
	check(panel._create_panel.visible and panel._create_kind == 1 and not panel._editing_path.is_empty(),"pattern library edit lifecycle")
	for frame in 3:
		await process_frame
	var pattern_save := panel.find_child("VoxelWorkshopSavePattern",true,false) as Button
	check(panel._create_panel.get_combined_minimum_size().x <= panel._create_scroll.size.x,"compact pattern editor has no horizontal clipping")
	check(panel._create_scroll.get_v_scroll_bar().visible and pattern_save != null,"compact pattern editor is scrollable")
	if "--capture" in OS.get_cmdline_user_args():
		root.get_texture().get_image().save_png("user://voxel_pattern_editor.png")
		print("PATTERN_CAPTURE ",ProjectSettings.globalize_path("user://voxel_pattern_editor.png"))
	panel._create_scroll.ensure_control_visible(pattern_save)
	for frame in 5:
		await process_frame
	var visible_save: Rect2 = panel._create_scroll.get_global_rect().intersection(pattern_save.get_global_rect())
	check(visible_save.size.y >= pattern_save.size.y-1.0,"compact pattern save action is reachable")
	if "--capture" in OS.get_cmdline_user_args():
		root.get_texture().get_image().save_png("user://voxel_pattern_editor_actions.png")
		print("PATTERN_ACTIONS_CAPTURE ",ProjectSettings.globalize_path("user://voxel_pattern_editor_actions.png"))
	workspace.free()
