extends SceneTree
const Fragment = preload("res://addons/ember_import/ember_voxel_fragment.gd")
const Stamp = preload("res://addons/ember_import/ember_voxel_stamp.gd")
const Pattern = preload("res://addons/ember_import/ember_voxel_pattern.gd")
const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
const Workspace = preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")
const Dialog = preload("res://addons/ember_import/ember_voxel_fragment_dialog.gd")
const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const Selection = preload("res://addons/ember_import/ember_voxel_selection.gd")
const Store = preload("res://addons/ember_import/ember_surface_editor_view_store.gd")
var errors := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		errors += 1
		push_error(label)

func _init() -> void:
	_run.call_deferred()

func fixture() -> EmberVoxelModelResource:
	var source: EmberVoxelModelResource = Shapes.build("empty",Vector3i(32,16,32),16,Color.BROWN,"boundary_fixture","Boundary").source
	source.merge_parts = PackedStringArray(["Board"])
	source.voxel_part_ids.resize(source.voxels.size())
	for channel in Fragment.CHANNELS:
		var bytes: PackedByteArray = source.get(channel)
		bytes.resize(source.voxels.size())
		for x in range(8,24):
			bytes[Model.index_of(Vector3i(x,8,8),source.grid_size())] = 1 if channel in ["voxels","collision_voxels"] else 30 + x
		source.set(channel,bytes)
	var members := PackedInt32Array()
	for x in range(8,24):
		var index := Model.index_of(Vector3i(x,8,8),source.grid_size())
		members.append(index)
		source.voxel_part_ids[index] = 1
	source.voxel_groups = [{"id":"board","name":"Board","indices":members}]
	return source

func complete(job: RefCounted) -> Dictionary:
	for iteration in 10000:
		job.step(8192,4000)
		if job.done:
			return job.result
	return {"error":"Job did not finish"}

func verify(source: EmberVoxelModelResource, plan: Dictionary, region := Rect2i(), height := -1) -> void:
	check(not plan.has("error"),"clipped plan succeeds: " + str(plan.get("error","")))
	if plan.has("error"):
		return
	var before := source.to_definition().duplicate(true)
	var undo := UndoRedo.new()
	var actions := EmberVoxelSculptActions.new()
	actions.configure(undo)
	check(actions.apply_fragment(source,plan),"apply clipped transaction")
	check(source.validation_errors().is_empty(),"clipped Resource valid: " + str(source.validation_errors()))
	for index in source.voxels.size():
		if Fragment._allowed(Selection.cell_of(index,source.grid_size()),source,region,height):
			continue
		for channel in Fragment.CHANNELS:
			check(source.get(channel)[index] == plan.before.get(channel,source.get(channel))[index],"context channel untouched")
		check(source.voxel_part_ids[index] == plan.before.get("voxel_part_ids",source.voxel_part_ids)[index],"context owner untouched")
	for index in plan.selected:
		check(Fragment._allowed(Selection.cell_of(index,source.grid_size()),source,region,height),"all output inside bounds")
	for group in plan.before.get("voxel_groups",[]):
		var after_members := {}
		for updated in source.voxel_groups:
			if updated.id == group.id:
				for index in updated.indices:
					after_members[index] = true
		for index in group.indices:
			if not Fragment._allowed(Selection.cell_of(index,source.grid_size()),source,region,height):
				check(after_members.has(index),"outside group membership untouched")
	var after := source.to_definition().duplicate(true)
	undo.undo()
	check(source.to_definition() == before and not undo.has_undo(),"one Undo restores cropped content")
	undo.redo()
	check(source.to_definition() == after,"Redo exact")
	var path := "user://boundary_clip_%d.tres" % Time.get_ticks_usec()
	check(ResourceSaver.save(source,path) == OK,"save clipped Resource")
	var reopened := ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource
	var reopened_def := reopened.to_definition()
	reopened_def.erase("_resourcePath")
	after.erase("_resourcePath")
	check(reopened_def == after,"save/reopen clipped channels, groups and owners")
	undo.clear_history()
	undo.free()
	source.emit_changed()

func _run() -> void:
	var source := fixture()
	var indices: PackedInt32Array = source.voxel_groups[0].indices
	var region := Rect2i(0,0,1,1)
	check(Fragment.plan(source,indices,Vector3i(24,0,0),1,0,false).has("error"),"strict canvas unchanged")
	check(Fragment.plan(source,indices,Vector3i(3,0,0),1,0,false,region).has("error"),"strict region unchanged")
	var plan := Fragment.plan(source,indices,Vector3i(3,0,0),1,0,false,region,-1,true)
	check(int(plan.get("clipped_voxels",0)) == 3,"partial move crops three source cells")
	verify(source,plan,region)
	source = fixture()
	verify(source,Fragment.plan(source,indices,Vector3i(24,0,0),1,0,false,Rect2i(),-1,true))
	source = fixture()
	plan = Fragment.plan(source,indices,Vector3i(32,0,0),1,0,false,region,-1,true)
	check(plan.has("selected") and plan.selected.is_empty(),"fully cropped move is a deletion, not invalid bounds")
	verify(source,plan,region)
	source = fixture()
	verify(source,Fragment.plan(source,indices,Vector3i(3,0,1),1,0,true,region,-1,true),region)
	source = fixture()
	verify(source,Fragment.plan(source,indices,Vector3i(0,0,4),1,1,false,region,-1,true),region)
	source = fixture()
	verify(source,Fragment.bend(source,indices,0,2,12,0,region,-1,true),region)
	source = fixture()
	verify(source,Fragment.plan(source,indices,Vector3i(0,2,0),1,0,false,Rect2i(),10,true),Rect2i(),10)
	source = fixture()
	check(complete(Fragment.start_grab(source,Vector3(15.5,8.5,8.5),4,Vector3(8,0,0),75,region)).has("error"),"Grab strict region")
	verify(source,complete(Fragment.start_grab(source,Vector3(15.5,8.5,8.5),4,Vector3(8,0,0),75,region,-1,true)),region)
	source = fixture()
	verify(source,complete(Fragment.start_grab(source,Vector3(16.5,8.5,8.5),12,Vector3(0,8,0),75,Rect2i(),10,true)),Rect2i(),10)
	source = fixture()
	verify(source,complete(Fragment.start_grab(source,Vector3(23.5,8.5,8.5),12,Vector3(12,0,0),75,Rect2i(),-1,true)))
	var last_cell: EmberVoxelModelResource = Shapes.build("empty",Vector3i(32,16,32),16,Color.BROWN,"last_cell","Last").source
	last_cell.voxels[Model.index_of(Vector3i(31,8,8),last_cell.grid_size())] = 1
	plan = complete(Fragment.start_grab(last_cell,Vector3(31.5,8.5,8.5),2,Vector3(4,0,0),75,Rect2i(),-1,true))
	check(plan.has("selected") and plan.selected.is_empty(),"fully cropped Grab finishes without invalid sampling extent")
	verify(last_cell,plan)
	source = fixture()
	source.voxel_groups[0].locked = true
	check(Fragment.plan(source,indices,Vector3i(32,0,0),1,0,false,region,-1,true).has("error"),"clipping never deletes locked source")
	check(complete(Fragment.start_grab(source,Vector3(15.5,8.5,8.5),4,Vector3(8,0,0),75,region,-1,true)).has("error"),"Grab keeps group protection")
	await _stamp_checks()
	await _workspace_checks()
	print("test_voxel_boundary_clip: ","PASS" if errors == 0 else "FAIL"," · ",errors)
	quit(errors)

func _stamp_checks() -> void:
	var small: EmberVoxelModelResource = Shapes.build("empty",Vector3i(16,8,16),16,Color.BROWN,"clip_stamp","Stamp").source
	small.voxels[0] = 1
	small.voxels[1] = 1
	var preset: Resource = Stamp.capture(small,PackedInt32Array([0,1]),"Clip").preset
	var source := fixture()
	check(Stamp.plan(source,preset,Vector3i(31,0,0),1,0,-1,0,false,1).has("error"),"strict stamp")
	var plan := Stamp.plan(source,preset,Vector3i(31,0,0),1,0,-1,0,false,1,Rect2i(),-1,Vector3i.ZERO,false,true)
	check(plan.get("clipped_voxels",0) == 1 and plan.get("selected",[]).size() == 1,"stamp partial crop")
	verify(source,plan)
	source = fixture()
	var placements: Array[Vector3i] = [Vector3i(15,9,8)]
	plan = Stamp.plan_scatter(source,preset,placements,Vector3i.UP,0,123,false,0,-1,0,false,1,Rect2i(0,0,1,1),-1,false,2,false,true)
	check(plan.get("clipped_voxels",0) > 0,"scatter propagates global clipping policy")
	verify(source,plan,Rect2i(0,0,1,1))
	source = fixture()
	plan = Stamp.plan(source,preset,Vector3i(15,8,8),1,0,-1,0,false,1,Rect2i(0,0,1,1),-1,Vector3i.UP,true,true)
	verify(source,plan,Rect2i(0,0,1,1))
	var pattern := Stamp.Preset.new()
	source = fixture()
	source.voxels[Model.index_of(Vector3i(31,8,8),source.grid_size())] = 1
	placements = [Vector3i(31,9,8)]
	plan = Stamp.plan_scatter(source,preset,placements,Vector3i.UP,0,123,false,0,-1,0,false,1,Rect2i(),-1,true,2,false,true)
	check(plan.get("clipped_voxels",0) == 1,"conformed scatter ignores missing surface outside canvas")
	verify(source,plan)
	pattern.display_name = "Boundary pattern"
	pattern.kind = Stamp.Preset.KIND_PATTERN
	pattern.pattern_size = Vector2i(2,1)
	pattern.pattern_depth = 1
	pattern.geometry = Pattern.build_geometry(Vector2i(2,1),PackedByteArray([1,1]),16,"Pattern").geometry
	source = fixture()
	check(Pattern.plan(source,pattern,Vector3i(31,0,0),Vector3i.UP,0,-1,0,false,1,1,1).has("error"),"strict pattern")
	plan = Pattern.plan(source,pattern,Vector3i(31,0,0),Vector3i.UP,0,-1,0,false,1,1,1,Rect2i(),-1,true)
	check(plan.get("clipped_voxels",0) == 1,"pattern partial crop")
	verify(source,plan)
	source = fixture()
	var lock_index := Model.index_of(Vector3i(31,0,0),source.grid_size())
	source.voxels[lock_index] = 1
	source.voxel_groups.append({"id":"locked","name":"Locked","indices":PackedInt32Array([lock_index]),"locked":true})
	check(Stamp.plan(source,preset,Vector3i(31,0,0),1,0,-1,0,true,1,Rect2i(),-1,Vector3i.ZERO,false,true).has("error"),"stamp protected destination")
	check(Pattern.plan(source,pattern,Vector3i(31,0,0),Vector3i.UP,0,-1,0,true,1,1,1,Rect2i(),-1,true).has("error"),"pattern protected removal")

func _workspace_checks() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280,720)
	var source := fixture()
	var before := source.to_definition().duplicate(true)
	var undo := UndoRedo.new()
	var workspace := Workspace.new()
	workspace.setup(null,undo)
	root.add_child(workspace)
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	workspace.open_surface(source,"user://boundary_canvas.tres")
	for frame in 6:
		await process_frame
	check(not workspace._clip_bounds and not workspace._clip_bounds_control.button_pressed,"global default strict")
	workspace._clip_bounds_control.button_pressed = true
	check(workspace._clip_bounds and source.to_definition() == before,"toggle changes only editor state")
	workspace._activate_tool_id(Model.TOOL_GRAB)
	workspace._activate_tool_id(Model.TOOL_PAINT)
	check(workspace._clip_bounds,"global mode survives switching tools")
	var data: Dictionary = workspace.export_editor_view_data()
	var store := Store.new()
	store.import_data(data)
	check(store.recall_clip_bounds(),"global editor state roundtrip")
	workspace.import_editor_view_data({"version":Store.VERSION})
	check(not workspace._clip_bounds,"old layouts default strict")
	workspace.import_editor_view_data(data)
	check(workspace._clip_bounds_control.button_pressed,"UI restores global flag")
	workspace._edit_region_blocks = Rect2i(0,0,1,1)
	workspace._toggle_voxel_selection()
	workspace._selection_panel.set_selection(source.voxel_groups[0].indices)
	for frame in 30:
		await process_frame
		if not workspace._selection_panel.busy():
			break
	var interaction: Control = workspace._selection_interaction
	interaction.begin_transform()
	check(interaction.transforming,"fragment transform starts after selection overlay is ready")
	interaction._offset = Vector3i(3,0,0)
	interaction._pending = true
	await process_frame
	await process_frame
	check(not interaction._plan.has("error") and interaction._ghost.multimesh != null and interaction._ghost.multimesh.instance_count == interaction._plan.get("selected",[]).size(),"fragment ghost shows only committed clipped result")
	check(source.to_definition() == before,"fragment clipping preview detached")
	workspace._clip_bounds_control.button_pressed = false
	await process_frame
	check(interaction._plan.has("error") and interaction._apply.disabled,"global toggle immediately recomputes active strict preview")
	workspace._clip_bounds_control.button_pressed = true
	await process_frame
	var fragment_draft := source.duplicate(true) as EmberVoxelModelResource
	for key in interaction._plan.get("properties",{}):
		fragment_draft.set(key,interaction._plan.properties[key])
	interaction.commit()
	check(source.to_definition() == fragment_draft.to_definition(),"fragment apply equals clipped preview")
	undo.undo()
	check(source.to_definition() == before,"fragment UI Undo restores original and outside context")
	interaction.cancel_gesture()
	var dialog := Dialog.new()
	root.add_child(dialog)
	dialog.open_bend(source,source.voxel_groups[0].indices,workspace._actions,Rect2i(0,0,1,1),-1,true)
	dialog._along.select(0)
	dialog._direction.select(2)
	dialog._amount.value = 12
	dialog._prepare()
	check(not dialog.result.has("error") and not dialog.get_ok_button().disabled,"Bend dialog uses clipping")
	check(source.to_definition() == before,"dialog preview detached")
	dialog.hide()
	dialog.queue_free()
	var empty_dialog := Dialog.new()
	root.add_child(empty_dialog)
	empty_dialog.open_for(source,source.voxel_groups[0].indices,workspace._actions,Rect2i(),-1,true)
	empty_dialog._numbers[0].value = 32
	empty_dialog._prepare()
	check(not empty_dialog.result.has("error") and not empty_dialog.get_ok_button().disabled,"fully cropped dialog can preview and apply empty geometry")
	empty_dialog.hide()
	empty_dialog.queue_free()
	workspace.queue_free()
	await process_frame
	undo.clear_history()
	undo.free()
