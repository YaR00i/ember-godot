extends SceneTree
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
	var original: EmberVoxelModelResource = Shapes.build("empty",Vector3i(16,8,16),16,Color.CORAL,"stamp_fixture","Stamp").source
	for index in [0,1,16]:
		original.voxels[index] = 1
	original.shine.resize(original.voxels.size())
	original.shine[1] = 70
	var captured := Stamp.capture(original,PackedInt32Array([0,1,16]),"Угол доски")
	check(not captured.has("error"),"capture")
	var preset: Resource = captured.preset
	var geometry_before: Dictionary = preset.geometry.to_definition()
	original.voxels[0] = 0
	check(preset.geometry.to_definition() == geometry_before,"stamp independent from source")
	var directory := "user://stamp_test_%d" % Time.get_ticks_usec()
	var saved := Stamp.save_new(preset,directory.path_join("presets"),directory.path_join("models"))
	check(saved.has("path"),"save library")
	check(Stamp.library(directory.path_join("presets")).size() == 1,"library reopen")
	var reopened := ResourceLoader.load(saved.path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(reopened.geometry.voxels == preset.geometry.voxels and reopened.geometry.shine == preset.geometry.shine,"preset external geometry roundtrip")
	var target: EmberVoxelModelResource = Shapes.build("empty",Vector3i(16,8,16),16,Color.BLUE,"target","Объект").source
	target.voxels[0] = 1
	target.voxels[17] = 1 # Empty corner in stamp must remain untouched.
	target.merge_parts = PackedStringArray(["Основа","Деталь"])
	target.voxel_part_ids.resize(target.voxels.size())
	target.voxel_part_ids[0] = 1
	target.voxel_part_ids[17] = 1
	var baseline := target.to_definition()
	var plan := Stamp.plan(target,preset,Vector3i.ZERO,1,0,-1,0,false,2)
	check(not plan.has("error") and target.to_definition() == baseline,"preview detached")
	var undo := UndoRedo.new()
	var actions := EmberVoxelSculptActions.new()
	actions.configure(undo)
	check(actions.apply_fragment(target,plan),"add stamp")
	check(target.palette[target.voxels[0]] == Color.BLUE and target.voxels[17] == 1,"add preserves occupied and empty stamp holes")
	check(target.shine[1] == 70 and target.voxel_part_ids[1] == 2,"channels and part assignment")
	undo.undo()
	check(target.to_definition() == baseline,"one Undo")
	undo.redo()
	check(target.shine[1] == 70,"Redo")
	undo.undo()
	plan = Stamp.plan(target,preset,Vector3i.ZERO,1,0,-1,0,true,2)
	check(actions.apply_fragment(target,plan),"replace stamp")
	check(target.palette[target.voxels[0]] == Color.CORAL and target.voxel_part_ids[0] == 1,"replace color retains old owner")
	check(target.voxels[17] == 1,"replace holes do not erase")
	undo.undo()
	plan = Stamp.plan(target,preset,Vector3i(4,0,4),1,1,0,1,false,0)
	check(not plan.has("error") and plan.selected.size() == 3,"rotate mirror anchor")
	check(Stamp.plan(target,preset,Vector3i(-2,0,0),1,0,-1,0,false,0).has("error"),"out of bounds atomic refusal")
	target.voxel_groups = [{"id":"locked","name":"Locked","indices":PackedInt32Array([1]),"locked":true}]
	check(Stamp.plan(target,preset,Vector3i.ZERO,1,0,-1,0,false,0).has("error"),"locked refusal")
	target.voxel_groups = []
	preset.geometry.voxels_per_block = 32
	check(Stamp.plan(target,preset,Vector3i.ZERO,1,0,-1,0,false,0).has("error"),"density refuses")
	preset.geometry.voxels_per_block = 16
	var crowded := target.duplicate(true) as EmberVoxelModelResource
	crowded.palette.resize(256)
	for i in range(1,256):
		crowded.palette[i] = Color(float(i)/256,0,0)
	check(Stamp.plan(crowded,preset,Vector3i(4,0,4),1,0,-1,0,false,0).has("error"),"palette overflow atomic refusal")
	var source_path: String = reopened.geometry.resource_path
	var edited := ResourceLoader.load(source_path,"",ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource
	edited.shine[1] = 90
	check(ResourceSaver.save(edited,source_path) == OK,"edit saved preset geometry")
	var fresh := ResourceLoader.load(saved.path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(fresh.geometry.shine[1] == 90,"preset loads updated dependency rather than stale cache")
	var large: EmberVoxelModelResource = Shapes.build("empty",Vector3i(64,32,64),16,Color.BLUE,"large_target","Large").source
	var large_piece: EmberVoxelModelResource = Shapes.build("block",Vector3i(16,32,32),16,Color.CORAL,"large_stamp","Large stamp").source
	var large_preset := Stamp.Preset.new()
	large_preset.geometry = large_piece
	var start := Time.get_ticks_usec()
	var large_plan := Stamp.plan(large,large_preset,Vector3i.ZERO,1,0,-1,0,false,0)
	print("Stamp 16384 / 131072 cells plan ms: ",(Time.get_ticks_usec()-start)/1000.0)
	check(not large_plan.has("error"),"bounded large stamp")
	await _ui(target,preset,undo,directory)
	undo.clear_history()
	undo.free()
	print("Voxel stamp: ","PASS" if errors == 0 else "FAIL %d" % errors)
	quit(0 if errors == 0 else 1)

func _ui(target: EmberVoxelModelResource, preset: Resource, undo: UndoRedo, directory: String) -> void:
	root.size = Vector2i(1280,900)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
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
	check(not workspace._stamp_panel._create_panel.visible,"new stamp form starts collapsed")
	check(workspace._stamp_panel._library_actions.get_parent() == workspace._stamp_panel,"library actions are pinned outside card scroll")
	var interaction: Control = workspace._selection_interaction
	var before := target.to_definition()
	interaction.begin_stamp(preset)
	for frame in 3:
		await process_frame
	check(interaction.transforming and not interaction._apply.disabled,"Canvas stamp preview with no selection")
	check(interaction._controls.get_parent() == workspace._operation_panel and interaction._controls.visible,"stamp controls stay visible above the library")
	check(not interaction._stamp_mode.visible and interaction._stamp_mode_buttons[0].visible,"stamp state dropdown is hidden behind direct mode choices")
	interaction._select_segment(interaction._stamp_mirror,1)
	await process_frame
	check(interaction._stamp_mirror.selected == 1 and interaction._stamp_mirror_buttons[1].button_pressed,"mirror segment synchronizes stamp plan state")
	check(workspace._sidebar_tabs.current_tab == 1 and workspace._stamp_tool_button.button_pressed,"stamp placement keeps the library context")
	check(workspace._workshop_context_label.text.contains(preset.display_name),"selected stamp is absent from workshop context")
	check(target.to_definition() == before,"UI preview unchanged")
	interaction._numbers[0].value = -100
	for frame in 2:
		await process_frame
	check(interaction._apply.disabled and interaction._hint.modulate.is_equal_approx(Color(1.0,0.45,0.40)),"invalid stamp state is not visibly distinct")
	interaction._numbers[0].value = 8
	for frame in 2:
		await process_frame
	check(not interaction._apply.disabled and not interaction._hint.modulate.is_equal_approx(Color(1.0,0.45,0.40)),"valid stamp state did not recover")
	if "--capture" in OS.get_cmdline_user_args():
		await create_timer(0.3).timeout
		root.get_texture().get_image().save_png("user://voxel_stamp.png")
	interaction.cancel_gesture()
	check(target.to_definition() == before,"UI cancel")
	interaction.begin_stamp(preset)
	for frame in 3:
		await process_frame
	var expected: PackedByteArray = interaction._plan.properties.voxels.duplicate()
	interaction.commit()
	check(target.voxels == expected and not interaction.transforming,"UI commit matches preview")
	check(workspace._save(),"target save")
	var reopened := ResourceLoader.load(directory.path_join("target.tres"),"",ResourceLoader.CACHE_MODE_IGNORE)
	check(reopened.voxels == expected,"target reopen")
	undo.undo()
	check(target.to_definition().model == before.model,"UI Undo")
	undo.redo()
	check(target.voxels == expected,"UI Redo")
	workspace._selection_panel.set_selection(PackedInt32Array([0,17]))
	for frame in 3:
		await process_frame
	workspace._stamp_panel._title.text = "Мой второй штамп"
	workspace._stamp_panel._save()
	check(workspace._stamp_panel._entries.size() == 2,"UI library save")
	check(workspace._stamp_panel._card_buttons.size() == 2,"UI library card grid")
	check(workspace._stamp_panel._card_buttons[0].icon != null,"UI library derived thumbnail")
	workspace._stamp_panel._edit()
	check(workspace._resource.tags.has("stamp"),"edit preset in same Canvas")
	var saved_voxels: PackedByteArray = workspace._resource.voxels.duplicate()
	workspace._resource.voxels.fill(0)
	workspace.discard_changes()
	check(workspace._resource.voxels == saved_voxels,"preset discard")
	workspace.free()
