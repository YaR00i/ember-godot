extends SceneTree
const Plan=preload("res://scripts/ember_terrain_plan_resource.gd")
const Terrain=preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Editor=preload("res://addons/ember_import/ember_world_editor.gd")
const PlanPanel=preload("res://addons/ember_import/ember_terrain_plan_dialog.gd")
var errors:Array[String]=[]
var world:Node
var map:EmberMapLoader
var camera:Camera3D
var history:=UndoRedo.new()
var frame:Node3D
var dir:="user://ember-tests/plan-controls-%d"%OS.get_process_id()
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("PLAN_CONTROLS_FAIL ",label)
func mouse(pixel:Vector2,pressed:bool)->InputEventMouseButton:
	var event:=InputEventMouseButton.new();event.position=pixel;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;return event
func mode(value:String)->void:
	world._plan_panel._buttons["point_"+value].pressed.emit()
func drag(a:Vector2,b:Vector2,cancel:=false)->void:
	var start:Vector2=world._plan_point_pixel(a);var end:Vector2=world._plan_point_pixel(b)
	check(start.is_finite() and end.is_finite(),"handles project")
	var before:Resource=Plan.read(map).working_copy();var count:=history.get_history_count()
	var revision:int=map._visual_surface_projection.column_revision()
	world.forward_input(camera,mouse(start,true));check(not world._plan_drag.is_empty(),"upper input starts drag")
	for i in 5:
		var event:=InputEventMouseMotion.new();event.position=start.lerp(end,float(i+1)/5);event.button_mask=MOUSE_BUTTON_MASK_LEFT;world.forward_input(camera,event)
	check(Plan.same(Plan.read(map),before) and history.get_history_count()==count,"ghost never writes plan/history")
	check(map._visual_surface_projection.column_revision()==revision,"ghost never rebuilds terrain")
	if cancel:
		var escape:=InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.pressed=true;world.forward_input(camera,escape)
		check(Plan.same(Plan.read(map),before) and world._plan_drag.is_empty(),"Escape discards ghost")
	else:world.forward_input(camera,mouse(end,false))
func region(kind:String)->Dictionary:
	var bounds:=Rect2i(4,4,12,12)
	var values:Dictionary=Plan.Math.DEFAULTS.duplicate() if kind=="generation" else Plan.Influence.mountain_defaults(bounds) if kind=="mountain" else Plan.Influence.LAKE_DEFAULTS.duplicate() if kind=="lake" else Plan.Influence.COAST_DEFAULTS.duplicate() if kind=="coast" else Plan.Influence.ROAD_DEFAULTS.duplicate() if kind=="road" else Plan.Influence.RIVER_DEFAULTS.duplicate() if kind=="river" else Plan.Influence.GROVE_DEFAULTS.duplicate() if kind=="grove" else Plan.Influence.PLACEMENT_DEFAULTS.duplicate() if kind=="placement" else Plan.Influence.DEFAULTS.duplicate()
	var result:Dictionary={"id":kind,"name":kind,"kind":kind,"bounds":bounds,"parameters":values,"enabled":true}
	if Plan.Influence.plan_is_path(result):
		result.points_m=PackedVector2Array([Vector2(5,5),Vector2(9,6),Vector2(13,13)])
		result.bounds=world._plan_path_bounds(result,values,Vector2i(24,24))
	return result
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var source:=Terrain.new();source.width=384;source.depth=384;source.height_limit=192;source.origin_y=-32
	source.palette=PackedColorArray([Color.TRANSPARENT,Color.GREEN,Color.SADDLE_BROWN]);source.palette_surface_roles=PackedStringArray(["","grass","soil"]);source.palette_material_ids=PackedStringArray(["","cartoon_grass","cartoon_soil"])
	for channel in Terrain.Sections.CHANNELS:
		var data:Variant=PackedInt32Array() if channel in ["heights","water_levels"] else PackedByteArray();data.resize(source.width*source.depth);data.fill(32 if channel=="heights" else 1 if channel in ["top_materials","base_materials"] else 3 if channel=="cap_depths" else 0);source.set(channel,data)
	ResourceSaver.save(source,dir.path_join("terrain.res"))
	var vp:=SubViewport.new();vp.size=Vector2i(700,700);root.add_child(vp)
	frame=Node3D.new();frame.scene_file_path=dir.path_join("map.tscn");vp.add_child(frame)
	map=EmberMapLoader.new();map.name="Map";map.compact_terrain=ResourceLoader.load(dir.path_join("terrain.res"));map.world_look=2;map.compact_ground_style=0;frame.add_child(map);map.owner=frame
	camera=Camera3D.new();frame.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=580;camera.far=2000;camera.look_at_from_position(Vector3(192,700,450),Vector3(192,0,192));camera.make_current()
	var deadline:=Time.get_ticks_msec()+20000
	while map._visual_surface_projection.pending_tile_count()>0 and Time.get_ticks_msec()<deadline:await process_frame
	world=Editor.new();root.add_child(world);world.scene=frame;world.map=map;world.camera=camera;world.active=true
	world.sessions.configure(history,func()->int:
		var packed:=PackedScene.new();var code:=packed.pack(frame)
		return ResourceSaver.save(packed,frame.scene_file_path) if code==OK else code)
	world.sessions.recovery_directory=dir.path_join("recovery");world.entry=world.sessions.open_map(map,frame)
	world._terrain_workspace=VBoxContainer.new();root.add_child(world._terrain_workspace)
	world._tools_workspace=VBoxContainer.new();root.add_child(world._tools_workspace)
	world._workspace_tools_button=Button.new();world._tools_workspace.add_child(world._workspace_tools_button)
	world._workspace_terrain_button=Button.new();world._tools_workspace.add_child(world._workspace_terrain_button)
	world._plan_panel=PlanPanel.new();world._terrain_workspace.add_child(world._plan_panel);world._plan_target=weakref(map)
	world._plan_panel.action_requested.connect(world._terrain_plan_action);world._plan_panel.selection_changed.connect(world._select_plan_region)
	var source_hash:=FileAccess.get_sha256(dir.path_join("terrain.res"))
	for kind in ["generation","plateau","lake","mountain","grove","placement","coast","river","road"]:
		var plan:=Plan.new();plan.upgrade_local_layers();plan.regions=[region(kind)]
		check(world.commit_terrain_plan(map,plan).is_empty(),"valid fixture "+kind)
		if kind=="coast":world._generation_panel._profile.select(3) # A previous plains generator must not leak its fields.
		world._plan_panel._picker.item_selected.emit(0)
		check(world._plan_parameters_active() and world._generation_context.plan_id==kind,"shared parameter context "+kind)
		check(world._plan_panel.get_index()<world._generation_panel.get_index(),"selector stays above parameters "+kind)
		if kind=="coast":check(not world._generation_panel._plains_grid.visible and world._generation_panel._plan_save_button.visible,"coast shows only its parameters and common save")
		check(world._plan_panel._buttons.point_insert.visible==Plan.Influence.plan_is_path(plan.regions[0]),"shape-aware tools "+kind)
		mode("translate")
		var anchor:Vector2=Plan.Influence.plan_anchor(plan.regions[0]);var count:=history.get_history_count()
		await drag(anchor,anchor+Vector2.ONE)
		var moved:Resource=Plan.read(map).working_copy()
		check(not Plan.same(moved,plan) and history.get_history_count()==count+1,"one move Undo "+kind)
		history.undo();check(Plan.same(Plan.read(map),plan),"move Undo "+kind)
		history.redo();check(Plan.same(Plan.read(map),moved),"move Redo "+kind)
		mode("move")
		var point:Vector2=Plan.Influence.plan_controls(moved.regions[0])[0]
		await drag(point,point+(Vector2(0.5,0) if Plan.Influence.plan_is_path(moved.regions[0]) else -Vector2.ONE))
		var shaped:Resource=Plan.read(map).working_copy()
		check(not Plan.same(shaped,moved),"point/corner changes shape "+kind)
		check(shaped.regions[0].parameters==moved.regions[0].parameters,"shape retains parameters "+kind)
		point=Plan.Influence.plan_controls(shaped.regions[0])[0];await drag(point,point+Vector2.ONE,true)
		check(world._generation_context.area==shaped.regions[0].bounds,"parameter area follows geometry "+kind)
		if kind=="coast":
			world._generation_panel._coast_fields.shore_m.value=2.5
			await drag(point,point+Vector2(0.5,0))
			check(world._generation_panel._coast_fields.shore_m.value==2.5,"geometry retains pending parameter input")
			var old_shore:float=Plan.read(map).regions[0].parameters.shore_m
			world._generation_panel._plan_save_button.pressed.emit()
			check(Plan.read(map).regions[0].parameters.shore_m==2.5,"common save publishes coast parameters")
			history.undo();check(world._generation_panel._coast_fields.shore_m.value==old_shore,"parameter Undo refreshes fields")
			history.redo();check(world._generation_panel._coast_fields.shore_m.value==2.5,"parameter Redo refreshes fields")
		if Plan.Influence.plan_is_path(shaped.regions[0]):
			mode("insert");var curve:=Plan.Influence.path_curve(Plan.read(map).regions[0].points_m)
			var middle:float=(curve.get_closest_offset(Plan.read(map).regions[0].points_m[1])+curve.get_baked_length())*0.5
			world.forward_input(camera,mouse(world._plan_point_pixel(curve.sample_baked(middle)),true))
			check(Plan.read(map).regions[0].points_m.size()==4,"insert point "+kind)
			var key:=InputEventKey.new();key.keycode=KEY_DELETE;key.pressed=true;world.forward_input(camera,key)
			check(Plan.read(map).regions[0].points_m.size()==3,"remove point "+kind)
	check(world._plan_point_pixel(Vector2(24,24)).is_finite(),"map-edge corner remains visible")
	var final:Resource=Plan.read(map).working_copy();final.regions.append(region("plateau"))
	check(world.commit_terrain_plan(map,final).is_empty(),"second shape added")
	world._plan_panel._picker.item_selected.emit(1)
	check(world._plan_point_mode=="move" and world._plan_panel._buttons.point_move.button_pressed,"line insert mode normalizes for corners")
	var count:=history.get_history_count();var before:Resource=Plan.read(map).working_copy()
	check(not world.commit_plan_points(map,"road",PackedVector2Array([Vector2(-1,6),Vector2(10,7)])).is_empty(),"out-of-map edit rejected")
	check(Plan.same(Plan.read(map),before) and history.get_history_count()==count,"invalid edit leaves document/history intact")
	var original_terrain:Resource=world.entry.resource.working_copy()
	world._generation_panel._preview_button.pressed.emit()
	deadline=Time.get_ticks_msec()+30000
	while world._generation_panel.get_apply_button().disabled and Time.get_ticks_msec()<deadline:
		if world._generation_job==null and not is_instance_valid(world._generation_preview):break
		world._process_terrain_generation();await process_frame
	check(world._generation_context.has("candidate") and not world._generation_panel.get_apply_button().disabled,"edited area reaches the existing ready preview: "+world._generation_panel._status.text)
	check(world.entry.resource.same_terrain_data(original_terrain),"ready preview leaves source unchanged")
	world._close_generation_panel()
	check(not world._generation_context.has("candidate") and world.entry.resource.same_terrain_data(original_terrain),"preview Cancel returns to the same source")
	check(world.sessions.save_all(frame),"save shared plan")
	var saved:Resource=Plan.read(map).working_copy()
	var reopened:Node=ResourceLoader.load(frame.scene_file_path,"",ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	check(Plan.same(Plan.read(reopened.get_node("Map")),saved),"fresh saved Plan exact");reopened.free()
	check(world.commit_plan_points(map,"road",PackedVector2Array([Vector2(6,6),Vector2(10,7),Vector2(14,14)])).is_empty(),"unsaved edit")
	world.sessions.discard(frame);check(Plan.same(Plan.read(map),saved),"Discard exact")
	check(FileAccess.get_sha256(dir.path_join("terrain.res"))==source_hash,"plan controls never write terrain")
	print("PLAN_CONTROLS ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"kinds":9}))
	history.clear_history();world.sessions.entries.clear();world.sessions.save_scene=Callable();world._terrain_workspace.free();world._tools_workspace.free();world.free();history.free();vp.free();await process_frame;quit(0 if errors.is_empty() else 1)
